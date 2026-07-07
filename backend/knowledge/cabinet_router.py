"""
Cabinet router: lookup-before-LLM using canonical_ingredients / canonical_concerns / links.

Answers structured questions: "ingredient X for concern Y" by checking the map first.
"""

from __future__ import annotations

import json
import re
import unicodedata
from typing import Any

from config import get_logger
from knowledge.db import pg_conn

log = get_logger("knowledge.cabinet_router")

_CACHE: dict[str, Any] = {"loaded": False, "ingredients": [], "concerns": []}


def _exec(cur, sql: str, params=None):
    if params is None:
        return cur.execute(sql, prepare=False)
    return cur.execute(sql, params, prepare=False)


def _norm(s: str) -> str:
    t = unicodedata.normalize("NFKC", (s or "").strip()).casefold()
    t = "".join(ch for ch in t if unicodedata.category(ch) != "Mn")
    t = re.sub(r"\s+", " ", t)
    tr = str.maketrans("ığüşöç", "igusoc")
    return t.translate(tr)


def _aliases_list(val) -> list[str]:
    if isinstance(val, list):
        return [str(x).strip() for x in val if str(x).strip()]
    if isinstance(val, str):
        try:
            return _aliases_list(json.loads(val))
        except Exception:
            return [val] if val.strip() else []
    return []


def _load_catalog() -> None:
    if _CACHE.get("loaded"):
        return
    try:
        with pg_conn(autocommit=True) as conn:
            with conn.cursor() as cur:
                _exec(
                    cur,
                    """
                    select ingredient_id, slug, name_tr, name_en, kind, folder_slug,
                           aliases, summary_tr, graph_ingredient_id, ingredient_db_key
                    from public.canonical_ingredients
                    """,
                )
                icols = [d[0] for d in cur.description]
                _CACHE["ingredients"] = [dict(zip(icols, r)) for r in (cur.fetchall() or [])]

                _exec(
                    cur,
                    """
                    select concern_id, slug, name_tr, name_en, body_area, folder_slug,
                           aliases, graph_condition_id
                    from public.canonical_concerns
                    """,
                )
                ccols = [d[0] for d in cur.description]
                _CACHE["concerns"] = [dict(zip(ccols, r)) for r in (cur.fetchall() or [])]
        _CACHE["loaded"] = True
    except Exception as e:
        log.warning("cabinet catalog load failed: %s", e)
        _CACHE["ingredients"] = []
        _CACHE["concerns"] = []
        _CACHE["loaded"] = True


def _phrase_matches(ph: str, qnorm: str, qtokens: set[str], min_token: int) -> bool:
    """Match a phrase either as a contiguous substring, or (for multi-word
    phrases) when all of its significant tokens appear in the query. The token
    path makes matching robust to inserted/inflected words, e.g. the alias
    'yagli cilt' still matches 'yagli cildim var'."""
    if len(ph) < min_token:
        return False
    if ph in qnorm:
        return True
    toks = [t for t in ph.split(" ") if len(t) >= 3]
    if len(toks) >= 2 and all(any(t in qt for qt in qtokens) for t in toks):
        return True
    return False


def _match_rows(qnorm: str, rows: list[dict], id_key: str, min_token: int = 3) -> list[dict]:
    hits: list[dict] = []
    seen: set[str] = set()
    qtokens = {t for t in qnorm.split(" ") if t}
    for row in rows:
        rid = (row.get(id_key) or "").strip()
        if not rid or rid in seen:
            continue
        phrases: list[str] = []
        for field in ("name_tr", "name_en", "slug"):
            v = (row.get(field) or "").strip()
            if v:
                phrases.append(_norm(v))
        phrases.extend(_norm(a) for a in _aliases_list(row.get("aliases")))
        for ph in phrases:
            if _phrase_matches(ph, qnorm, qtokens, min_token):
                hits.append(row)
                seen.add(rid)
                break
    return hits


def resolve_query(user_message: str) -> dict[str, Any]:
    """
    Returns matched canonical ingredients/concerns from user text.
    """
    _load_catalog()
    um = (user_message or "").strip()
    if len(um) < 4:
        return {"ingredients": [], "concerns": [], "qnorm": ""}
    qnorm = _norm(um)
    return {
        "qnorm": qnorm,
        "ingredients": _match_rows(qnorm, _CACHE["ingredients"], "ingredient_id"),
        "concerns": _match_rows(qnorm, _CACHE["concerns"], "concern_id", min_token=4),
    }


def _fetch_links(ingredient_ids: list[str], concern_ids: list[str]) -> list[dict[str, Any]]:
    if not ingredient_ids or not concern_ids:
        return []
    try:
        with pg_conn(autocommit=True) as conn:
            with conn.cursor() as cur:
                _exec(
                    cur,
                    """
                    select l.link_id, l.ingredient_id, l.concern_id, l.effect_status, l.priority,
                           l.notes_tr, l.min_conc_recommended, l.max_conc_recommended, l.time_of_day,
                           l.source, l.confidence,
                           i.name_tr as ingredient_tr, c.name_tr as concern_tr
                    from public.ingredient_concern_links l
                    join public.canonical_ingredients i on i.ingredient_id = l.ingredient_id
                    join public.canonical_concerns c on c.concern_id = l.concern_id
                    where l.ingredient_id = any(%s) and l.concern_id = any(%s)
                    order by l.priority nulls last, l.link_id
                    limit 12
                    """,
                    (ingredient_ids, concern_ids),
                )
                cols = [d[0] for d in cur.description]
                return [dict(zip(cols, r)) for r in (cur.fetchall() or [])]
    except Exception as e:
        log.warning("cabinet link fetch failed: %s", e)
        return []


def _fetch_links_by_concern(concern_ids: list[str], limit: int = 8) -> list[dict[str, Any]]:
    """Top recommended ingredients (the roadmap chain) for a concern-only query."""
    if not concern_ids:
        return []
    try:
        with pg_conn(autocommit=True) as conn:
            with conn.cursor() as cur:
                _exec(
                    cur,
                    """
                    select l.link_id, l.ingredient_id, l.concern_id, l.effect_status, l.priority,
                           l.notes_tr, l.min_conc_recommended, l.max_conc_recommended, l.time_of_day,
                           l.source, l.confidence,
                           i.name_tr as ingredient_tr, c.name_tr as concern_tr
                    from public.ingredient_concern_links l
                    join public.canonical_ingredients i on i.ingredient_id = l.ingredient_id
                    join public.canonical_concerns c on c.concern_id = l.concern_id
                    where l.concern_id = any(%s)
                    order by (l.effect_status = 'supports') desc,
                             l.priority nulls last, l.confidence desc nulls last, l.link_id
                    limit %s
                    """,
                    (concern_ids, int(limit)),
                )
                cols = [d[0] for d in cur.description]
                return [dict(zip(cols, r)) for r in (cur.fetchall() or [])]
    except Exception as e:
        log.warning("cabinet concern-chain fetch failed: %s", e)
        return []


def _fetch_links_by_ingredient(ingredient_ids: list[str], limit: int = 8) -> list[dict[str, Any]]:
    """Concerns this ingredient is recommended for (ingredient-only query)."""
    if not ingredient_ids:
        return []
    try:
        with pg_conn(autocommit=True) as conn:
            with conn.cursor() as cur:
                _exec(
                    cur,
                    """
                    select l.link_id, l.ingredient_id, l.concern_id, l.effect_status, l.priority,
                           l.notes_tr, l.min_conc_recommended, l.max_conc_recommended, l.time_of_day,
                           l.source, l.confidence,
                           i.name_tr as ingredient_tr, c.name_tr as concern_tr
                    from public.ingredient_concern_links l
                    join public.canonical_ingredients i on i.ingredient_id = l.ingredient_id
                    join public.canonical_concerns c on c.concern_id = l.concern_id
                    where l.ingredient_id = any(%s)
                    order by (l.effect_status = 'supports') desc,
                             l.priority nulls last, l.confidence desc nulls last, l.link_id
                    limit %s
                    """,
                    (ingredient_ids, int(limit)),
                )
                cols = [d[0] for d in cur.description]
                return [dict(zip(cols, r)) for r in (cur.fetchall() or [])]
    except Exception as e:
        log.warning("cabinet ingredient-chain fetch failed: %s", e)
        return []


def lookup(user_message: str) -> dict[str, Any]:
    """
    Full cabinet lookup with status:
      - hit: ingredient+concern with link rows
      - partial_no_link: both known, no direct link
      - concern_chain: only a concern matched -> surface its recommended ingredients
      - ingredient_chain: only an ingredient matched -> surface concerns it treats
      - partial_single: single match with no chain rows
      - miss: no canonical match
    """
    resolved = resolve_query(user_message)
    ings = resolved.get("ingredients") or []
    cnds = resolved.get("concerns") or []
    ing_ids = [str(i.get("ingredient_id")) for i in ings if i.get("ingredient_id")]
    cnd_ids = [str(c.get("concern_id")) for c in cnds if c.get("concern_id")]

    if ing_ids and cnd_ids:
        links = _fetch_links(ing_ids, cnd_ids)
        status = "hit" if links else "partial_no_link"
    elif cnd_ids:
        links = _fetch_links_by_concern(cnd_ids)
        status = "concern_chain" if links else "partial_single"
    elif ing_ids:
        links = _fetch_links_by_ingredient(ing_ids)
        status = "ingredient_chain" if links else "partial_single"
    else:
        links = []
        status = "miss"

    return {
        "status": status,
        "ingredients": ings,
        "concerns": cnds,
        "links": links,
    }


def format_cabinet_evidence_block(user_message: str, *, max_chars: int = 1500) -> tuple[str, dict[str, Any]]:
    """
    Structured catalog block for RAG / deterministic hints.
    Returns (text, meta) where meta includes cabinet_status.
    """
    result = lookup(user_message)
    status = result.get("status") or "miss"
    ings = result.get("ingredients") or []
    cnds = result.get("concerns") or []
    ing_ids = [str(i.get("ingredient_id")) for i in ings if i.get("ingredient_id")]
    cnd_ids = [str(c.get("concern_id")) for c in cnds if c.get("concern_id")]
    # For a concern-only chain, expose the recommended ingredients so the
    # literature block can surface their raw passages too.
    chain_ids = [str(l.get("ingredient_id")) for l in (result.get("links") or []) if l.get("ingredient_id")]
    lit_ids = ing_ids + [i for i in chain_ids if i not in ing_ids]
    meta = {
        "cabinet_status": status,
        "cabinet_ingredient_ids": lit_ids,
        "cabinet_concern_ids": cnd_ids,
        "cabinet_link_count": len(result.get("links") or []),
    }
    if status == "miss":
        return "", meta

    lines: list[str] = []

    for ing in ings[:2]:
        folder = (ing.get("folder_slug") or "ingredients").strip()
        summary = (ing.get("summary_tr") or "").strip()
        line = f"- Madde [{folder}]: {ing.get('name_tr') or ing.get('ingredient_id')}"
        if summary:
            line += f" — {summary[:280]}"
        lines.append(line)

    for cnd in cnds[:2]:
        folder = (cnd.get("folder_slug") or "concerns").strip()
        lines.append(f"- Şikâyet [{folder}]: {cnd.get('name_tr') or cnd.get('concern_id')}")

    links = result.get("links") or []
    if status == "concern_chain" and cnds:
        cnd_name = cnds[0].get("name_tr") or cnds[0].get("concern_id")
        lines.append(f"- Öneri zinciri — {cnd_name} için öncelik sırasıyla etken maddeler:")
    elif status == "ingredient_chain" and ings:
        ing_name = ings[0].get("name_tr") or ings[0].get("ingredient_id")
        lines.append(f"- Öneri zinciri — {ing_name} hangi şikâyetlerde önerilir:")

    for link in links[:6]:
        ing_tr = link.get("ingredient_tr") or link.get("ingredient_id")
        cnd_tr = link.get("concern_tr") or link.get("concern_id")
        eff = link.get("effect_status") or "supports"
        note = (link.get("notes_tr") or "").strip()
        tod = (link.get("time_of_day") or "").strip()
        pr = link.get("priority")
        conc = ""
        if link.get("min_conc_recommended") or link.get("max_conc_recommended"):
            conc = f" ({link.get('min_conc_recommended') or ''}-{link.get('max_conc_recommended') or ''})"
        tail = f" {note[:200]}" if note else ""
        tags = []
        if pr:
            tags.append(f"öncelik {pr}")
        if tod:
            tags.append(tod)
        tagstr = f" [{', '.join(tags)}]" if tags else ""
        if status == "concern_chain":
            lines.append(f"- {ing_tr} → {eff}{conc}.{tail}{tagstr}")
        elif status == "ingredient_chain":
            lines.append(f"- {cnd_tr} → {eff}{conc}.{tail}{tagstr}")
        else:
            lines.append(f"- Eşleme: {ing_tr} + {cnd_tr} → {eff}{conc}.{tail}{tagstr}")

    if status == "partial_no_link" and ing_ids and cnd_ids:
        ing_names = ", ".join((i.get("name_tr") or i.get("ingredient_id") for i in ings[:2]))
        cnd_names = ", ".join((c.get("name_tr") or c.get("concern_id") for c in cnds[:2]))
        lines.append(
            f"- Katalog: {ing_names} ve {cnd_names} için kayıtlı madde–şikâyet eşlemesi yok; "
            "genel pasajlara veya uzman görüşüne güvenmek gerekir."
        )

    if not lines:
        return "", meta

    text = "[Katalog — yapılandırılmış dolaplar]\n" + "\n".join(lines)
    if len(text) > max_chars:
        text = text[: max_chars - 1].rstrip() + "…"
    return text, meta


def invalidate_catalog_cache() -> None:
    _CACHE["loaded"] = False
    _CACHE["ingredients"] = []
    _CACHE["concerns"] = []
