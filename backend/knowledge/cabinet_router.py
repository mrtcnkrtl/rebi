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


# ── Routine integration (Faz 0/1/2) ────────────────────────────────────────
# Bridge between flow_engine's coarse concern slugs and the canonical concern ids
# so the routine pipeline can reuse the same evidence chains as free chat.
CONCERN_SLUG_TO_CANONICAL: dict[str, list[str]] = {
    "acne": ["acne_vulgaris", "comedones_open_closed", "post_inflammatory_hyperpigmentation"],
    "aging": ["photoaging_premature_aging", "skin_laxity"],
    "pigmentation": ["hyperpigmentation_melasma", "post_inflammatory_hyperpigmentation"],
    "dryness": ["dry_skin_xerosis"],
    "sensitivity": ["rosacea", "atopic_dermatitis"],
    "pores": ["enlarged_pores"],
    "oiliness": ["oily_skin_seborrhea"],
    "general": [],
}


def concern_ids_for_slug(concern_slug: str) -> list[str]:
    """Map a flow_engine concern slug to canonical concern ids (primary first)."""
    return list(CONCERN_SLUG_TO_CANONICAL.get((concern_slug or "").strip().lower(), []))


def _format_chain_line(link: dict) -> str:
    ing_tr = link.get("ingredient_tr") or link.get("ingredient_id")
    eff = link.get("effect_status") or "supports"
    note = (link.get("notes_tr") or "").strip()
    tod = (link.get("time_of_day") or "").strip()
    pr = link.get("priority")
    conc = ""
    if link.get("min_conc_recommended") or link.get("max_conc_recommended"):
        conc = f" ({link.get('min_conc_recommended') or ''}-{link.get('max_conc_recommended') or ''})"
    tail = f" {note[:180]}" if note else ""
    tags = []
    if pr:
        tags.append(f"öncelik {pr}")
    if tod:
        tags.append(tod)
    tagstr = f" [{', '.join(tags)}]" if tags else ""
    return f"- {ing_tr} → {eff}{conc}.{tail}{tagstr}"


def format_routine_expert_block(concern_slug: str, *, max_chars: int = 1800) -> tuple[str, dict[str, Any]]:
    """
    Evidence block for the routine polish step: the canonical ingredient chain for
    the user's concern + a few raw literature passages. Returns (text, meta) with
    the resolved concern/ingredient ids so callers can tag or trace.
    """
    meta: dict[str, Any] = {"concern_ids": [], "ingredient_ids": []}
    cnd_ids = concern_ids_for_slug(concern_slug)
    if not cnd_ids:
        return "", meta
    meta["concern_ids"] = cnd_ids
    links = _fetch_links_by_concern(cnd_ids, limit=8)
    if not links:
        return "", meta

    ing_ids: list[str] = []
    for link in links:
        iid = str(link.get("ingredient_id") or "").strip()
        if iid and iid not in ing_ids:
            ing_ids.append(iid)
    meta["ingredient_ids"] = ing_ids

    lines = ["[Katalog — kanıta dayalı içerik zinciri (öncelik sırasıyla)]"]
    for link in links[:8]:
        lines.append(_format_chain_line(link))
    text = "\n".join(lines)

    try:
        from knowledge.literature import format_literature_block

        lit = format_literature_block(ing_ids[:4], limit=3, max_chars=900)
        if lit:
            text += "\n\n" + lit
    except Exception as e:  # pragma: no cover - literature is best-effort
        log.warning("routine literature block skipped: %s", e)

    if len(text) > max_chars:
        text = text[: max_chars - 1].rstrip() + "…"
    return text, meta


def chain_actives_for_concern(concern_slug: str, *, limit: int = 8) -> list[dict[str, Any]]:
    """
    Structured, priority-ordered recommended actives for a concern slug.
    Used by the routine coverage report (shadow validation for Faz 3): compare
    what the deterministic engine picked against the canonical chain.
    """
    cnd_ids = concern_ids_for_slug(concern_slug)
    if not cnd_ids:
        return []
    out: list[dict[str, Any]] = []
    seen: set[str] = set()
    for link in _fetch_links_by_concern(cnd_ids, limit=limit):
        iid = str(link.get("ingredient_id") or "").strip()
        if not iid or iid in seen:
            continue
        seen.add(iid)
        out.append(
            {
                "ingredient_id": iid,
                "name_tr": link.get("ingredient_tr") or iid,
                "priority": link.get("priority"),
                "time_of_day": link.get("time_of_day"),
                "effect_status": link.get("effect_status") or "supports",
            }
        )
    return out


def _ingredient_phrase_index(min_len: int = 4) -> list[tuple[str, set[str]]]:
    """(ingredient_id, {normalized phrases}) from the cached catalog for tagging."""
    _load_catalog()
    idx: list[tuple[str, set[str]]] = []
    for ing in _CACHE.get("ingredients") or []:
        iid = (ing.get("ingredient_id") or "").strip()
        if not iid:
            continue
        phrases: set[str] = set()
        for field in ("name_tr", "name_en", "slug"):
            v = (ing.get(field) or "").strip()
            if v:
                phrases.add(_norm(v))
        for a in _aliases_list(ing.get("aliases")):
            na = _norm(a)
            if na:
                phrases.add(na)
        phrases = {p for p in phrases if len(p) >= min_len}
        if phrases:
            idx.append((iid, phrases))
    return idx


def tag_items_with_canonical_ids(items: list[dict]) -> int:
    """
    Attach `canonical_ingredient_ids[]` to each routine item whose action/detail
    text mentions a canonical ingredient (name/alias/slug). Uses the cached
    catalog (no extra DB round-trips). Returns the number of tagged items.
    """
    if not items:
        return 0
    idx = _ingredient_phrase_index()
    if not idx:
        return 0
    tagged = 0
    for it in items:
        if not isinstance(it, dict):
            continue
        text = _norm(f"{it.get('action', '')} {it.get('detail', '')}")
        if len(text) < 3:
            continue
        found: list[str] = []
        for iid, phrases in idx:
            if any(p in text for p in phrases):
                found.append(iid)
        if not found:
            continue
        existing = [str(x) for x in (it.get("canonical_ingredient_ids") or [])]
        it["canonical_ingredient_ids"] = list(dict.fromkeys([*existing, *found]))
        tagged += 1
    return tagged


def invalidate_catalog_cache() -> None:
    _CACHE["loaded"] = False
    _CACHE["ingredients"] = []
    _CACHE["concerns"] = []
