from __future__ import annotations

import os
from dataclasses import dataclass
from typing import Any, Optional

from config import get_logger

log = get_logger("active_rules")


def _postgres_dsn() -> str | None:
    return (os.getenv("SUPABASE_DATABASE_URL") or os.getenv("DATABASE_URL") or "").strip() or None


@dataclass
class ActiveRule:
    active_key: str
    family: str | None
    role: str | None
    priority: int
    rule: dict


def load_active_rules() -> list[ActiveRule]:
    dsn = _postgres_dsn()
    if not dsn:
        return []
    try:
        import psycopg  # type: ignore
    except Exception:
        return []

    try:
        with psycopg.connect(dsn, autocommit=True) as conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    select active_key, family, role, priority, rule
                    from public.active_rules
                    where enabled is true
                    order by priority asc, active_key asc
                    """
                )
                rows = cur.fetchall() or []
    except Exception as e:
        log.warning("active_rules read failed (ignored): %s", e)
        return []

    out: list[ActiveRule] = []
    for r in rows:
        try:
            out.append(
                ActiveRule(
                    active_key=str(r[0]),
                    family=(str(r[1]) if r[1] is not None else None),
                    role=(str(r[2]) if r[2] is not None else None),
                    priority=int(r[3] or 100),
                    rule=(r[4] if isinstance(r[4], dict) else dict(r[4] or {})),
                )
            )
        except Exception:
            continue
    return out


def _ctx_in(ctx: dict, key: str, values: list[str]) -> bool:
    v = ctx.get(key)
    if v is None:
        return False
    return str(v) in {str(x) for x in (values or [])}


def _match_condition(ctx: dict, cond: dict) -> bool:
    """
    Minimal matcher for rule JSON.
    Supported:
      - <key>_in: list
      - <key>_not_in: list
      - <key>_gte / <key>_lte: numeric or ordinal comparisons (risk_level, severity_level)
    """
    risk_rank = {"normal": 0, "moderate": 1, "high": 2, "crisis": 3}
    sev_rank = {"hafif": 0, "orta": 1, "şiddetli": 2}

    def _to_rank(key: str, value) -> float | None:
        if value is None:
            return None
        s = str(value).strip().lower()
        if key in ("risk_level", "risk"):
            return float(risk_rank.get(s)) if s in risk_rank else None
        if key in ("severity_level", "severity"):
            return float(sev_rank.get(s)) if s in sev_rank else None
        try:
            return float(s)
        except Exception:
            return None

    for k, v in (cond or {}).items():
        if k.endswith("_in"):
            base = k[: -len("_in")]
            if not _ctx_in(ctx, base, list(v or [])):
                return False
        elif k.endswith("_not_in"):
            base = k[: -len("_not_in")]
            if _ctx_in(ctx, base, list(v or [])):
                return False
        elif k.endswith("_gte") or k.endswith("_lte"):
            op = "gte" if k.endswith("_gte") else "lte"
            base = k[: -len("_gte")] if op == "gte" else k[: -len("_lte")]
            a = _to_rank(base, ctx.get(base))
            b = _to_rank(base, v)
            if a is None or b is None:
                return False
            if op == "gte" and not (a >= b):
                return False
            if op == "lte" and not (a <= b):
                return False
        else:
            # equality fallback
            if str(ctx.get(k)) != str(v):
                return False
    return True


def _any_match(ctx: dict, conds: list[dict]) -> bool:
    for c in conds or []:
        if _match_condition(ctx, c):
            return True
    return False


def _pick_concentration(rule: dict, ctx: dict) -> Any:
    c = rule.get("concentration")
    if c is None:
        return None
    if isinstance(c, dict):
        # Dynamic: derive range from a ctx numeric percent.
        # Example:
        #   { "from_ctx_pct": "niacinamide_start_pct", "min": 2, "max": 10, "spread": 3 }
        if "from_ctx_pct" in c:
            key = str(c.get("from_ctx_pct") or "").strip()
            raw = ctx.get(key)
            try:
                base = float(raw)
            except Exception:
                base = None
            if base is not None:
                mn = float(c.get("min", base))
                mx = float(c.get("max", base))
                spread = float(c.get("spread", 0))
                start = max(mn, min(base, mx))
                high = max(start, min(mx, start + max(0.0, spread)))
                # return as % strings to match existing API style
                def _fmt(x: float) -> str:
                    if float(x).is_integer():
                        return f"%{int(x)}"
                    return f"%{x}"
                return {"start": _fmt(start), "range": f"{_fmt(start)}-{_fmt(high)}"}

        # default_range + overrides[{if, range}]
        picked = c.get("default_range")
        for ov in c.get("overrides") or []:
            try:
                if _match_condition(ctx, (ov or {}).get("if") or {}):
                    picked = (ov or {}).get("range") or picked
            except Exception:
                continue
        if picked is None:
            return c
        return {"range": picked}
    return c


def _pick_frequency(rule: dict, ctx: dict) -> Any:
    """
    Supports:
      - direct object, e.g. {"per_week":"2-4"}
      - object with overrides:
          {"per_week":"2-4","overrides":[{"if":{...},"per_week":"1-2"}]}
    """
    f = rule.get("frequency")
    if f is None:
        return None
    if isinstance(f, dict):
        out = dict(f)
        for ov in f.get("overrides") or []:
            try:
                if _match_condition(ctx, (ov or {}).get("if") or {}):
                    if (ov or {}).get("per_week") is not None:
                        out["per_week"] = (ov or {}).get("per_week")
            except Exception:
                continue
        out.pop("overrides", None)
        return out
    return f


def evaluate_rule(ar: ActiveRule, ctx: dict) -> Optional[dict]:
    """
    Returns an active_plan item dict if recommended.
    """
    rule = ar.rule or {}

    # tolerate gates: if the family-specific tol is "bad", skip
    if ar.family:
        tol_key = f"tol_{ar.family}"
        if str(ctx.get(tol_key) or "").lower() == "bad":
            return None

    recommended = rule.get("recommended")
    if recommended is True:
        ok = True
    else:
        ok = True
        if isinstance(rule.get("recommended_if"), dict):
            ok = _match_condition(ctx, rule["recommended_if"])
        if ok and isinstance(rule.get("recommended_if_any"), list):
            ok = _any_match(ctx, rule["recommended_if_any"])
    if not ok:
        return None

    # Safety gates based on standardized constraints
    constraints = rule.get("constraints") or {}
    if isinstance(constraints, dict):
        if bool(constraints.get("avoid_in_pregnancy")) and bool(ctx.get("is_pregnant")):
            return None
        if bool(constraints.get("avoid_if_sensitive")) and (
            str(ctx.get("skin_type") or "").lower() == "sensitive" or bool(ctx.get("stings_with_products"))
        ):
            return None

    out = {
        "active": ar.active_key,
        "family": ar.family,
        "role": ar.role or rule.get("role"),
        "recommended": True,
        "when": rule.get("when"),
        "concentration": _pick_concentration(rule, ctx),
        "frequency": _pick_frequency(rule, ctx),
        "constraints": constraints if isinstance(constraints, dict) else {},
    }

    copy = rule.get("copy") or {}
    if isinstance(copy, dict):
        out.update(copy)

    return out


def build_active_plan_from_rules(ctx: dict) -> list[dict]:
    rules = load_active_rules()
    if not rules:
        return []
    items: list[dict] = []
    for r in rules:
        it = evaluate_rule(r, ctx)
        if it:
            items.append(it)
    return items

