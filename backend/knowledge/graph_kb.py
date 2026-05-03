"""
Skincare Graph KB: Postgres catalog (ingredient_profiles, relationships, safety_rules)
merged into free-chat evidence as a short deterministic block.

Tables are created by supabase/migrations/20260503140000_skincare_graph_kb.sql
and filled by backend/ingest_graph_kb.py.
"""

from __future__ import annotations

import re
import unicodedata
from typing import Any

from config import get_logger
from knowledge.db import pg_conn

log = get_logger("knowledge.graph_kb")

_RELATION_LABEL_TR: dict[str, str] = {
    "conflicts_with": "çakışma",
    "contraindicated": "kontrendike",
    "synergy_with": "sinerji",
    "treats": "hedef",
    "requires_ph": "pH koşulu",
    "apply_before": "önce uygula",
    "boosts": "destekler",
}


def _exec(cur, sql: str, params=None):
    if params is None:
        return cur.execute(sql, prepare=False)
    return cur.execute(sql, params, prepare=False)


def _norm(s: str) -> str:
    t = unicodedata.normalize("NFKC", (s or "").strip()).casefold()
    # Drop combining marks (e.g. Turkish İ → i + U+0307) for stable substring match.
    t = "".join(ch for ch in t if unicodedata.category(ch) != "Mn")
    t = re.sub(r"\s+", " ", t)
    tr = str.maketrans("ığüşöçâêîôû", "igusocaeiou")
    return t.translate(tr)


def _words(s: str) -> list[str]:
    return [w for w in re.split(r"[^\w]+", _norm(s)) if len(w) >= 3]


def _condition_match_phrases(condition_tr: str) -> list[str]:
    base = (condition_tr or "").split("/")[0].strip()
    if not base:
        return []
    phrases = [_norm(base)]
    for w in _words(base):
        if len(w) >= 4:
            phrases.append(w)
    return list(dict.fromkeys(phrases))


def _load_profiles(cur) -> list[dict[str, Any]]:
    _exec(cur, "select ingredient_id, ingredient_tr, ingredient_en from public.ingredient_profiles")
    rows = cur.fetchall() or []
    cols = [d[0] for d in cur.description]
    return [dict(zip(cols, r)) for r in rows]


def _load_conditions(cur) -> list[dict[str, Any]]:
    _exec(cur, "select condition_id, condition_tr, condition_en from public.skin_conditions")
    rows = cur.fetchall() or []
    cols = [d[0] for d in cur.description]
    return [dict(zip(cols, r)) for r in rows]


def _match_ingredient_ids(qnorm: str, profiles: list[dict[str, Any]]) -> list[str]:
    ids: list[str] = []
    for p in profiles:
        iid = (p.get("ingredient_id") or "").strip()
        tr = (p.get("ingredient_tr") or "").strip()
        en = (p.get("ingredient_en") or "").strip()
        if not iid:
            continue
        candidates = [_norm(tr), _norm(en)] + _words(tr) + _words(en)
        hit = False
        for c in candidates:
            if len(c) < 3:
                continue
            if c in qnorm:
                hit = True
                break
        if hit and iid not in ids:
            ids.append(iid)
    return ids


def _match_condition_ids(qnorm: str, conditions: list[dict[str, Any]]) -> list[str]:
    ids: list[str] = []
    for cnd in conditions:
        cid = (cnd.get("condition_id") or "").strip()
        tr = (cnd.get("condition_tr") or "").strip()
        en = (cnd.get("condition_en") or "").strip()
        if not cid:
            continue
        phrases = _condition_match_phrases(tr) + _condition_match_phrases(en)
        hit = any(len(ph) >= 4 and ph in qnorm for ph in phrases)
        if hit and cid not in ids:
            ids.append(cid)
    return ids


def _fetch_edges(cur, ing_ids: list[str]) -> list[dict[str, Any]]:
    if not ing_ids:
        return []
    _exec(
        cur,
        """
        select relation_id, entity_a_tr, relation_type, entity_b_tr, condition_note, safety_critical
        from public.ingredient_relationships
        where entity_a_id = any(%s) or entity_b_id = any(%s)
        order by safety_critical desc nulls last, relation_id
        limit 24
        """,
        (ing_ids, ing_ids),
    )
    rows = cur.fetchall() or []
    cols = [d[0] for d in cur.description]
    return [dict(zip(cols, r)) for r in rows]


def _fetch_maps(cur, cond_ids: list[str], ing_ids: list[str]) -> list[dict[str, Any]]:
    if not cond_ids and not ing_ids:
        return []
    if cond_ids and ing_ids:
        _exec(
            cur,
            """
            select map_id, condition_tr, ingredient_tr, priority, time_of_day, notes_tr
            from public.condition_ingredient_map
            where condition_id = any(%s) and ingredient_id = any(%s)
            order by priority nulls last, map_id
            limit 16
            """,
            (cond_ids, ing_ids),
        )
    elif cond_ids:
        _exec(
            cur,
            """
            select map_id, condition_tr, ingredient_tr, priority, time_of_day, notes_tr
            from public.condition_ingredient_map
            where condition_id = any(%s)
            order by priority nulls last, map_id
            limit 16
            """,
            (cond_ids,),
        )
    else:
        _exec(
            cur,
            """
            select map_id, condition_tr, ingredient_tr, priority, time_of_day, notes_tr
            from public.condition_ingredient_map
            where ingredient_id = any(%s)
            order by priority nulls last, map_id
            limit 16
            """,
            (ing_ids,),
        )
    rows = cur.fetchall() or []
    cols = [d[0] for d in cur.description]
    return [dict(zip(cols, r)) for r in rows]


def _fetch_profiles_detail(cur, ing_ids: list[str]) -> list[dict[str, Any]]:
    if not ing_ids:
        return []
    _exec(
        cur,
        """
        select ingredient_tr, min_conc_pct, max_conc_pct, effective_conc_pct,
               ph_min, ph_max, pregnancy_safe, evidence_level
        from public.ingredient_profiles
        where ingredient_id = any(%s)
        """,
        (ing_ids,),
    )
    rows = cur.fetchall() or []
    cols = [d[0] for d in cur.description]
    return [dict(zip(cols, r)) for r in rows]


def _fetch_safety(cur, qnorm: str, matched_trs: list[str]) -> list[dict[str, Any]]:
    rules: dict[str, dict[str, Any]] = {}
    preg_hit = any(x in qnorm for x in ("hamile", "gebe", "gebelik", "emzir", "laktasyon"))
    iso_hit = "isotretinoin" in qnorm or "roaccutane" in qnorm or "aknetrent" in qnorm

    def add_rows(rows: list[dict[str, Any]]) -> None:
        for r in rows:
            rid = (r.get("rule_id") or "").strip()
            if rid:
                rules[rid] = r

    if preg_hit:
        _exec(
            cur,
            """
            select rule_id, severity, user_message_tr, blocked_ingredient, safe_alternative
            from public.safety_rules
            where rule_category ilike %s
            order by case severity when 'KRİTİK' then 0 when 'YÜKSEK' then 1 when 'ORTA' then 2 else 3 end, rule_id
            limit 8
            """,
            ("%Hamile%",),
        )
        cols = [d[0] for d in cur.description]
        add_rows([dict(zip(cols, r)) for r in (cur.fetchall() or [])])

    if iso_hit:
        _exec(
            cur,
            """
            select rule_id, severity, user_message_tr, blocked_ingredient, safe_alternative
            from public.safety_rules
            where rule_category ilike %s
            order by case severity when 'KRİTİK' then 0 when 'YÜKSEK' then 1 when 'ORTA' then 2 else 3 end, rule_id
            limit 6
            """,
            ("%İlaç%",),
        )
        cols = [d[0] for d in cur.description]
        add_rows([dict(zip(cols, r)) for r in (cur.fetchall() or [])])

    for tr in matched_trs:
        if len(tr) < 3:
            continue
        _exec(
            cur,
            """
            select rule_id, severity, user_message_tr, blocked_ingredient, safe_alternative
            from public.safety_rules
            where blocked_ingredient ilike %s
            order by case severity when 'KRİTİK' then 0 when 'YÜKSEK' then 1 when 'ORTA' then 2 else 3 end, rule_id
            limit 4
            """,
            (f"%{tr}%",),
        )
        cols = [d[0] for d in cur.description]
        add_rows([dict(zip(cols, r)) for r in (cur.fetchall() or [])])

    out = list(rules.values())
    out.sort(
        key=lambda r: (
            {"KRİTİK": 0, "YÜKSEK": 1, "ORTA": 2, "DÜŞÜK": 3}.get((r.get("severity") or "").upper(), 9),
            r.get("rule_id") or "",
        )
    )
    return out[:10]


def _format_edges(edges: list[dict[str, Any]], max_lines: int) -> list[str]:
    lines: list[str] = []
    for e in edges:
        if len(lines) >= max_lines:
            break
        a = (e.get("entity_a_tr") or "").strip()
        b = (e.get("entity_b_tr") or "").strip()
        rt = (e.get("relation_type") or "").strip()
        note = (e.get("condition_note") or "").strip()
        lbl = _RELATION_LABEL_TR.get(rt, rt)
        crit = " (!) " if e.get("safety_critical") is True else ""
        tail = f" ({note})" if note and len(note) < 120 else ""
        if a and b:
            lines.append(f"- {a} — {lbl} — {b}{crit}{tail}")
    return lines


def _format_profiles(rows: list[dict[str, Any]], max_lines: int) -> list[str]:
    lines: list[str] = []
    for r in rows:
        if len(lines) >= max_lines:
            break
        tr = (r.get("ingredient_tr") or "").strip()
        if not tr:
            continue
        lo = r.get("min_conc_pct")
        hi = r.get("max_conc_pct")
        eff = r.get("effective_conc_pct")
        conc = ""
        if lo is not None and hi is not None:
            conc = f" tipik %{lo:g}-{hi:g}"
            if eff is not None:
                conc += f" (etkili ~%{eff:g})"
        ph = ""
        pmin, pmax = r.get("ph_min"), r.get("ph_max")
        if pmin is not None and pmax is not None:
            ph = f"; pH ~{pmin:g}-{pmax:g}"
        preg = r.get("pregnancy_safe")
        ps = ""
        if preg is True:
            ps = "; hamilelik: genelde uygun kabul (yine de doktor)"
        elif preg is False:
            ps = "; hamilelik: dikkat / genelde kaçınılır"
        ev = (r.get("evidence_level") or "").strip()
        evs = f" [{ev}]" if ev else ""
        lines.append(f"- {tr}{conc}{ph}{ps}{evs}")
    return lines


def format_graph_evidence_block(user_message: str, *, max_chars: int = 950) -> str:
    """
    Build a compact Turkish block for RAG context from Graph KB tables.
    Returns empty string if tables are empty, DB unreachable, or no matches.
    """
    um = (user_message or "").strip()
    if len(um) < 4:
        return ""
    qnorm = _norm(um)
    try:
        with pg_conn(autocommit=True) as conn:
            with conn.cursor() as cur:
                profiles = _load_profiles(cur)
                if not profiles:
                    return ""
                conditions = _load_conditions(cur)
                ing_ids = _match_ingredient_ids(qnorm, profiles)
                cond_ids = _match_condition_ids(qnorm, conditions)
                preg_q = any(x in qnorm for x in ("hamile", "gebe", "gebelik", "emzir", "laktasyon"))
                iso_q = "isotretinoin" in qnorm or "roaccutane" in qnorm or "aknetrent" in qnorm
                if not ing_ids and not cond_ids and not preg_q and not iso_q:
                    return ""
                edges = _fetch_edges(cur, ing_ids)
                maps = _fetch_maps(cur, cond_ids, ing_ids)
                prof_rows = _fetch_profiles_detail(cur, ing_ids)
                trs = [str(p.get("ingredient_tr") or "") for p in prof_rows]
                safety = _fetch_safety(cur, qnorm, trs)
    except Exception as e:
        log.warning("graph_kb fetch skipped: %s", e)
        return ""

    chunks: list[str] = []
    if prof_rows:
        lines = _format_profiles(prof_rows, max_lines=6)
        if lines:
            chunks.append("Etken özet:\n" + "\n".join(lines))
    if edges:
        lines = _format_edges(edges, max_lines=10)
        if lines:
            chunks.append("Bilinen ilişkiler:\n" + "\n".join(lines))
    if maps:
        mlines = []
        for m in maps[:8]:
            ct = (m.get("condition_tr") or "").strip()
            it = (m.get("ingredient_tr") or "").strip()
            pr = m.get("priority")
            tod = (m.get("time_of_day") or "").strip()
            note = (m.get("notes_tr") or "").strip()
            tail = f" — {note[:100]}" if note else ""
            mlines.append(f"- {ct} → {it} (öncelik {pr}, {tod}){tail}")
        chunks.append("Sorun–etken eşlemesi:\n" + "\n".join(mlines))
    if safety:
        slines = []
        for s in safety[:5]:
            sev = (s.get("severity") or "").strip()
            msg = (s.get("user_message_tr") or "").strip()
            if msg:
                slines.append(f"- [{sev}] {msg[:220]}")
        if slines:
            chunks.append("Güvenlik:\n" + "\n".join(slines))

    text = "\n\n".join(chunks).strip()
    if len(text) > max_chars:
        text = text[: max_chars - 1].rstrip() + "…"
    return text


def format_graph_context_for_prompt(user_message: str, *, max_chars: int = 950) -> str:
    """Alias for tests / external callers."""
    return format_graph_evidence_block(user_message, max_chars=max_chars)
