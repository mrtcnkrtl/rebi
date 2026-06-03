"""
Build unified data catalog (canonical ingredients/concerns + links) from:
  - Graph KB tables (ingredient_profiles, skin_conditions, condition_ingredient_map)
  - INGREDIENT_DB (ingredient_db.py)
  - backend/knowledge/data_catalog_seeds.json (oils, hair concerns, manual rows)
  - knowledge_entities promoted from PDFs (oils / extracts / actives folders)

Requires migrations:
  - 20260503140000_skincare_graph_kb.sql
  - 20260504120000_data_catalog_cabinet.sql

Usage:
  cd backend && python3 merge_data_catalog.py
  python3 merge_data_catalog.py --inventory-only
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

from config import get_logger
from knowledge.db import pg_conn

log = get_logger("merge_data_catalog")

SEEDS_PATH = Path(__file__).resolve().parent / "knowledge" / "data_catalog_seeds.json"


def _slugify(s: str) -> str:
    t = (s or "").strip().lower()
    t = re.sub(r"[^a-z0-9]+", "_", t)
    return t.strip("_")[:80] or "unknown"


def _exec(cur, sql: str, params=None):
    if params is None:
        return cur.execute(sql, prepare=False)
    return cur.execute(sql, params, prepare=False)


def inventory(cur) -> dict:
    out: dict = {}
    for table in (
        "ingredient_profiles",
        "skin_conditions",
        "ingredient_relationships",
        "condition_ingredient_map",
        "safety_rules",
        "canonical_ingredients",
        "canonical_concerns",
        "ingredient_concern_links",
    ):
        try:
            _exec(cur, f"select count(*) from public.{table}")
            out[table] = int(cur.fetchone()[0])
        except Exception as e:
            out[table] = f"error: {e}"
    try:
        from ingredient_db import INGREDIENT_DB, SCENARIO_PROTOCOLS

        out["ingredient_db_keys"] = len(INGREDIENT_DB or {})
        out["scenario_protocol_keys"] = len(SCENARIO_PROTOCOLS or {})
    except Exception as e:
        out["ingredient_db_keys"] = f"error: {e}"
    try:
        _exec(
            cur,
            """
            select count(*) from public.knowledge_entities
            where kind = 'ingredient'
            """,
        )
        out["knowledge_entities_ingredient"] = int(cur.fetchone()[0])
    except Exception:
        out["knowledge_entities_ingredient"] = 0
    try:
        _exec(cur, "select count(*) from public.knowledge_chunks")
        out["knowledge_chunks"] = int(cur.fetchone()[0])
    except Exception:
        out["knowledge_chunks"] = 0
    return out


def _upsert_ingredient(cur, row: dict) -> None:
    _exec(
        cur,
        """
        insert into public.canonical_ingredients (
          ingredient_id, slug, name_tr, name_en, kind, folder_slug, aliases,
          summary_tr, graph_ingredient_id, ingredient_db_key, sources
        ) values (%s,%s,%s,%s,%s,%s,%s::jsonb,%s,%s,%s,%s::jsonb)
        on conflict (ingredient_id) do update set
          slug = excluded.slug,
          name_tr = excluded.name_tr,
          name_en = excluded.name_en,
          kind = excluded.kind,
          folder_slug = excluded.folder_slug,
          aliases = excluded.aliases,
          summary_tr = coalesce(excluded.summary_tr, canonical_ingredients.summary_tr),
          graph_ingredient_id = coalesce(excluded.graph_ingredient_id, canonical_ingredients.graph_ingredient_id),
          ingredient_db_key = coalesce(excluded.ingredient_db_key, canonical_ingredients.ingredient_db_key),
          sources = canonical_ingredients.sources || excluded.sources,
          updated_at = now()
        """,
        (
            row["ingredient_id"],
            row.get("slug") or row["ingredient_id"],
            row["name_tr"],
            row.get("name_en"),
            row.get("kind") or "active",
            row.get("folder_slug") or "ingredients/actives",
            json.dumps(row.get("aliases") or [], ensure_ascii=False),
            row.get("summary_tr"),
            row.get("graph_ingredient_id"),
            row.get("ingredient_db_key"),
            json.dumps(row.get("sources") or ["merge"], ensure_ascii=False),
        ),
    )


def _upsert_concern(cur, row: dict) -> None:
    _exec(
        cur,
        """
        insert into public.canonical_concerns (
          concern_id, slug, name_tr, name_en, body_area, folder_slug, aliases, graph_condition_id
        ) values (%s,%s,%s,%s,%s,%s,%s::jsonb,%s)
        on conflict (concern_id) do update set
          slug = excluded.slug,
          name_tr = excluded.name_tr,
          name_en = excluded.name_en,
          body_area = excluded.body_area,
          folder_slug = excluded.folder_slug,
          aliases = excluded.aliases,
          graph_condition_id = coalesce(excluded.graph_condition_id, canonical_concerns.graph_condition_id),
          updated_at = now()
        """,
        (
            row["concern_id"],
            row.get("slug") or row["concern_id"],
            row["name_tr"],
            row.get("name_en"),
            row.get("body_area") or "face",
            row.get("folder_slug") or "concerns/skin",
            json.dumps(row.get("aliases") or [], ensure_ascii=False),
            row.get("graph_condition_id"),
        ),
    )


def _upsert_link(cur, row: dict) -> None:
    link_id = row.get("link_id") or f"{row['ingredient_id']}__{row['concern_id']}"
    _exec(
        cur,
        """
        insert into public.ingredient_concern_links (
          link_id, ingredient_id, concern_id, effect_status, priority,
          notes_tr, min_conc_recommended, max_conc_recommended, time_of_day, source, confidence
        ) values (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
        on conflict (ingredient_id, concern_id) do update set
          effect_status = excluded.effect_status,
          priority = excluded.priority,
          notes_tr = excluded.notes_tr,
          min_conc_recommended = excluded.min_conc_recommended,
          max_conc_recommended = excluded.max_conc_recommended,
          time_of_day = excluded.time_of_day,
          source = excluded.source,
          confidence = excluded.confidence,
          updated_at = now()
        """,
        (
            link_id,
            row["ingredient_id"],
            row["concern_id"],
            row.get("effect_status") or "supports",
            row.get("priority"),
            row.get("notes_tr"),
            row.get("min_conc_recommended"),
            row.get("max_conc_recommended"),
            row.get("time_of_day"),
            row.get("source") or "merge",
            row.get("confidence"),
        ),
    )


def merge_from_graph(cur) -> dict:
    counts = {"ingredients": 0, "concerns": 0, "links": 0}
    _exec(cur, "select ingredient_id, ingredient_tr, ingredient_en, category from public.ingredient_profiles")
    cols = [d[0] for d in cur.description]
    graph_ing_by_tr: dict[str, str] = {}
    for r in cur.fetchall() or []:
        row = dict(zip(cols, r))
        gid = row["ingredient_id"]
        slug = _slugify(row.get("ingredient_en") or row.get("ingredient_tr") or gid)
        ing_id = slug
        graph_ing_by_tr[(row.get("ingredient_tr") or "").strip().lower()] = ing_id
        graph_ing_by_tr[gid] = ing_id
        kind = "active"
        cat = (row.get("category") or "").lower()
        if "oil" in cat or "lipid" in cat:
            kind = "oil"
        _upsert_ingredient(
            cur,
            {
                "ingredient_id": ing_id,
                "slug": slug,
                "name_tr": row.get("ingredient_tr") or ing_id,
                "name_en": row.get("ingredient_en"),
                "kind": kind,
                "folder_slug": "ingredients/oils-botanicals" if kind == "oil" else "ingredients/actives",
                "aliases": [row.get("ingredient_tr"), row.get("ingredient_en")],
                "graph_ingredient_id": gid,
                "sources": ["graph_kb"],
            },
        )
        counts["ingredients"] += 1

    _exec(cur, "select condition_id, condition_tr, condition_en, category from public.skin_conditions")
    cols = [d[0] for d in cur.description]
    graph_cnd_by_id: dict[str, str] = {}
    for r in cur.fetchall() or []:
        row = dict(zip(cols, r))
        cid_graph = row["condition_id"]
        slug = _slugify(row.get("condition_en") or row.get("condition_tr") or cid_graph)
        cnd_id = slug
        graph_cnd_by_id[cid_graph] = cnd_id
        _upsert_concern(
            cur,
            {
                "concern_id": cnd_id,
                "slug": slug,
                "name_tr": row.get("condition_tr") or cnd_id,
                "name_en": row.get("condition_en"),
                "body_area": "face",
                "folder_slug": "concerns/skin",
                "aliases": [row.get("condition_tr"), row.get("condition_en")],
                "graph_condition_id": cid_graph,
            },
        )
        counts["concerns"] += 1

    _exec(
        cur,
        """
        select map_id, condition_id, ingredient_id, ingredient_tr, condition_tr,
               priority, min_conc_recommended, max_conc_recommended, time_of_day, notes_tr
        from public.condition_ingredient_map
        """,
    )
    cols = [d[0] for d in cur.description]
    for r in cur.fetchall() or []:
        row = dict(zip(cols, r))
        i_graph = row.get("ingredient_id") or ""
        c_graph = row.get("condition_id") or ""
        ing_id = graph_ing_by_tr.get(i_graph) or _slugify(row.get("ingredient_tr") or i_graph)
        cnd_id = graph_cnd_by_id.get(c_graph) or _slugify(row.get("condition_tr") or c_graph)
        if not ing_id or not cnd_id:
            continue
        _upsert_ingredient(
            cur,
            {
                "ingredient_id": ing_id,
                "slug": ing_id,
                "name_tr": row.get("ingredient_tr") or ing_id,
                "kind": "active",
                "graph_ingredient_id": i_graph if i_graph.startswith("ING") else None,
                "sources": ["graph_kb_map"],
            },
        )
        _upsert_concern(
            cur,
            {
                "concern_id": cnd_id,
                "slug": cnd_id,
                "name_tr": row.get("condition_tr") or cnd_id,
                "graph_condition_id": c_graph if c_graph.startswith("SKN") else None,
            },
        )
        _upsert_link(
            cur,
            {
                "link_id": row.get("map_id"),
                "ingredient_id": ing_id,
                "concern_id": cnd_id,
                "effect_status": "supports",
                "priority": row.get("priority"),
                "notes_tr": row.get("notes_tr"),
                "min_conc_recommended": row.get("min_conc_recommended"),
                "max_conc_recommended": row.get("max_conc_recommended"),
                "time_of_day": row.get("time_of_day"),
                "source": "condition_ingredient_map",
                "confidence": 0.85,
            },
        )
        counts["links"] += 1
    return counts


def _find_canonical_ingredient_id(cur, key: str, name: str) -> str | None:
    _exec(cur, "select ingredient_id from public.canonical_ingredients where ingredient_db_key = %s limit 1", (key,))
    row = cur.fetchone()
    if row:
        return str(row[0])
    slug = _slugify(key)
    _exec(cur, "select ingredient_id from public.canonical_ingredients where slug = %s limit 1", (slug,))
    row = cur.fetchone()
    if row:
        return str(row[0])
    _exec(
        cur,
        """
        select ingredient_id from public.canonical_ingredients
        where aliases::text ilike %s
        limit 1
        """,
        (f"%{key}%",),
    )
    row = cur.fetchone()
    if row:
        return str(row[0])
    if name:
        _exec(
            cur,
            "select ingredient_id from public.canonical_ingredients where lower(name_tr) = lower(%s) limit 1",
            (name[:120],),
        )
        row = cur.fetchone()
        if row:
            return str(row[0])
    return None


def merge_from_ingredient_db(cur) -> int:
    from ingredient_db import INGREDIENT_DB

    n = 0
    for key, item in (INGREDIENT_DB or {}).items():
        if not isinstance(item, dict):
            continue
        name = (item.get("name") or key).strip()
        existing = _find_canonical_ingredient_id(cur, key, name)
        ing_id = existing or key
        _upsert_ingredient(
            cur,
            {
                "ingredient_id": ing_id,
                "slug": _slugify(key) if not existing else ing_id,
                "name_tr": name,
                "name_en": key.replace("_", " "),
                "kind": "active",
                "folder_slug": "ingredients/actives",
                "aliases": [key, name],
                "summary_tr": (item.get("mechanism") or item.get("clinical_efficacy") or "")[:500] or None,
                "ingredient_db_key": key,
                "sources": ["ingredient_db"],
            },
        )
        n += 1
    return n


def merge_from_seeds(cur) -> dict:
    if not SEEDS_PATH.is_file():
        return {"ingredients": 0, "concerns": 0, "links": 0}
    data = json.loads(SEEDS_PATH.read_text(encoding="utf-8"))
    ni, nc, nl = 0, 0, 0
    for row in data.get("ingredients") or []:
        _upsert_ingredient(cur, row)
        ni += 1
    for row in data.get("concerns") or []:
        _upsert_concern(cur, row)
        nc += 1
    for row in data.get("links") or []:
        _upsert_link(cur, row)
        nl += 1
    return {"ingredients": ni, "concerns": nc, "links": nl}


_PROMOTE_STOP = {
    "oil", "yag", "yagi", "extract", "ekstrakt", "ekstre", "ozu", "ozut",
    "acid", "asit", "skin", "cilt", "hair", "sac", "water", "su", "vitamin",
    "complex", "kompleks", "serum", "krem", "cream", "active", "aktif",
}

_OIL_HINTS = ("oil", "yag", "butter", "yagi", "butyrospermum", "oleum")
_EXTRACT_HINTS = (
    "extract", "ekstrakt", "ekstre", "ozu", "ferment", "mucin", "leaf",
    "root", "flower", "bark", "seed", "fruit", "kabugu", "yapragi", "koku",
    "cicegi", "venom", "honey", "bal ", "propolis",
)


def _classify_entity_folder(name: str) -> tuple[str, str]:
    """Guess kind + folder slug for a free-text PDF entity name."""
    n = (name or "").lower()
    if any(w in n for w in _OIL_HINTS):
        return "oil", "ingredients/oils-botanicals"
    if any(w in n for w in _EXTRACT_HINTS):
        return "extract", "ingredients/extracts"
    return "active", "ingredients/actives"


def promote_entities_to_catalog(cur, min_count: int = 2, limit: int = 500) -> int:
    """
    Promote frequent PDF-extracted entities (knowledge_entities) that are not yet
    in canonical_ingredients into new catalog rows, routed to oils/extracts/actives.
    This is what makes "PDF'de çok daha fazla yağ/ekstrakt" actually land in the cabinet.
    """
    try:
        _exec(
            cur,
            """
            select lower(name) as name, count(*) as c
            from public.knowledge_entities
            where kind = 'ingredient' and length(trim(name)) >= 3
            group by lower(name)
            having count(*) >= %s
            order by c desc
            limit %s
            """,
            (int(min_count), int(limit)),
        )
    except Exception as e:
        log.warning("promote_entities_to_catalog skipped: %s", e)
        return 0

    added = 0
    for name, _c in cur.fetchall() or []:
        nm = (name or "").strip()
        if len(nm) < 3 or nm in _PROMOTE_STOP:
            continue
        if _find_canonical_ingredient_id(cur, nm, nm):
            continue
        kind, folder = _classify_entity_folder(nm)
        _upsert_ingredient(
            cur,
            {
                "ingredient_id": _slugify(nm),
                "slug": _slugify(nm),
                "name_tr": nm,
                "name_en": nm,
                "kind": kind,
                "folder_slug": folder,
                "aliases": [nm],
                "sources": ["pdf_entity"],
            },
        )
        added += 1
    return added


def merge_entity_aliases(cur, limit: int = 400) -> int:
    """Attach frequent knowledge_entities names as aliases on existing canonical rows (best-effort)."""
    try:
        _exec(
            cur,
            """
            select lower(name) as name, count(*) as c
            from public.knowledge_entities
            where kind = 'ingredient' and length(trim(name)) >= 3
            group by lower(name)
            order by c desc
            limit %s
            """,
            (limit,),
        )
    except Exception:
        return 0
    added = 0
    for name, _c in cur.fetchall() or []:
        nm = (name or "").strip().lower()
        if len(nm) < 3:
            continue
        _exec(
            cur,
            """
            update public.canonical_ingredients
            set aliases = aliases || %s::jsonb,
                updated_at = now()
            where lower(name_tr) = %s
               or lower(name_en) = %s
               or slug = %s
            """,
            (json.dumps([nm], ensure_ascii=False), nm, nm, _slugify(nm)),
        )
        if cur.rowcount:
            added += 1
    return added


def main() -> None:
    ap = argparse.ArgumentParser(description="Merge all Rebi data sources into canonical catalog")
    ap.add_argument("--inventory-only", action="store_true")
    ap.add_argument(
        "--no-promote",
        action="store_true",
        help="Skip promoting frequent PDF entities into the catalog (oils/extracts/actives).",
    )
    ap.add_argument(
        "--promote-min-count",
        type=int,
        default=2,
        help="Minimum chunk frequency for a PDF entity to be promoted (default: 2).",
    )
    args = ap.parse_args()

    with pg_conn(autocommit=False) as conn:
        with conn.cursor() as cur:
            inv = inventory(cur)
            log.info("Inventory: %s", inv)
            print(json.dumps(inv, indent=2, ensure_ascii=False))
            if args.inventory_only:
                conn.commit()
                return

            summary = {
                "seeds": merge_from_seeds(cur),
                "ingredient_db": merge_from_ingredient_db(cur),
                "graph": merge_from_graph(cur),
                "promoted_pdf_entities": (
                    0
                    if args.no_promote
                    else promote_entities_to_catalog(cur, min_count=args.promote_min_count)
                ),
                "entity_alias_updates": merge_entity_aliases(cur),
            }
            inv2 = inventory(cur)
            summary["inventory_after"] = inv2
        conn.commit()

    log.info("Merge done: %s", summary)
    print(json.dumps(summary, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
