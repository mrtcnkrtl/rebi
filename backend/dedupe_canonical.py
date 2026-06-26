#!/usr/bin/env python3
"""
Merge duplicate canonical ingredient boxes into a single survivor.

Root cause: merge_data_catalog created two rows per concept — one from
INGREDIENT_DB (ingredient_db_key, e.g. 'seramidler') and one from the Graph KB
(graph_ingredient_id, e.g. 'ceramide'). Literature + links end up split across
both. This consolidates them onto the INGREDIENT_DB id (it carries the curated
profile and is also the resolver's offline key), preserving the graph link.

For each survivor<-dup:
  * repoint ingredient_concern_links (drop colliding dups via UNIQUE)
  * re-tag knowledge_chunks.canonical_ingredient_ids (replace dup -> survivor)
  * merge graph_ingredient_id / name_en / aliases / sources onto survivor
  * delete the dup canonical_ingredients row

Idempotent: missing dup rows are skipped.

Usage:
  cd backend && python3 dedupe_canonical.py --dry-run
  python3 dedupe_canonical.py
"""

from __future__ import annotations

import argparse
import json

import config  # noqa: F401  (loads backend/.env so DB DSN resolves)

# survivor (INGREDIENT_DB id) <- [graph duplicate ids]
MERGE_MAP: dict[str, list[str]] = {
    "niacinamid": ["niacinamide"],
    "seramidler": ["ceramide"],
    "hyaluronik_asit": ["hyaluronic_acid"],
    "salisilik_asit": ["salicylic_acid"],
    "azelaik_asit": ["azelaic_acid"],
    "benzoil_peroksit": ["benzoyl_peroxide"],
    "traneksamik_asit": ["tranexamic_acid"],
    "vitamin_c": ["ascorbic_acid"],
    "alfa_arbutin": ["alpha_arbutin"],
}


def plan_pairs(merge_map: dict[str, list[str]]) -> list[tuple[str, str]]:
    """Flatten the merge map into (survivor, dup) pairs. Pure (testable)."""
    pairs: list[tuple[str, str]] = []
    for survivor, dups in merge_map.items():
        for dup in dups:
            if dup and survivor and dup != survivor:
                pairs.append((survivor, dup))
    return pairs


def _as_list(v) -> list[str]:
    if isinstance(v, list):
        return [str(x) for x in v if x is not None]
    return []


def merge_jsonb_list(*vals) -> list[str]:
    """Union of jsonb-array values + extra scalars, de-duped, order-stable. Pure."""
    out: list[str] = []
    seen: set[str] = set()
    for v in vals:
        items = _as_list(v) if isinstance(v, list) else ([v] if v else [])
        for it in items:
            s = str(it).strip()
            if s and s not in seen:
                seen.add(s)
                out.append(s)
    return out


def _fetch_row(cur, iid: str):
    cur.execute(
        """select graph_ingredient_id, name_en, ingredient_db_key, name_tr, slug, aliases, sources
           from public.canonical_ingredients where ingredient_id = %s""",
        (iid,),
        prepare=False,
    )
    return cur.fetchone()


def _merge_one(cur, survivor: str, dup: str) -> dict:
    from psycopg.types.json import Json

    dp = _fetch_row(cur, dup)
    if not dp:
        return {"survivor": survivor, "dup": dup, "skipped": "dup_missing"}
    sv = _fetch_row(cur, survivor)
    if not sv:
        return {"survivor": survivor, "dup": dup, "skipped": "survivor_missing"}

    sv_graph, sv_en, sv_dbk, sv_tr, sv_slug, sv_aliases, sv_sources = sv
    dp_graph, dp_en, dp_dbk, dp_tr, dp_slug, dp_aliases, dp_sources = dp

    # 1) drop links that would collide on UNIQUE(ingredient_id, concern_id)
    cur.execute(
        """
        delete from public.ingredient_concern_links d
        where d.ingredient_id = %s
          and exists (
            select 1 from public.ingredient_concern_links s
            where s.ingredient_id = %s and s.concern_id = d.concern_id
          )
        """,
        (dup, survivor),
        prepare=False,
    )
    dropped_links = cur.rowcount or 0
    # 1b) repoint the rest
    cur.execute(
        "update public.ingredient_concern_links set ingredient_id = %s where ingredient_id = %s",
        (survivor, dup),
        prepare=False,
    )
    moved_links = cur.rowcount or 0

    # 2) re-tag chunks: replace dup id with survivor id, dedupe
    cur.execute(
        """
        update public.knowledge_chunks
        set canonical_ingredient_ids =
            (select array(select distinct unnest(array_replace(canonical_ingredient_ids, %s, %s))))
        where %s = any(canonical_ingredient_ids)
        """,
        (dup, survivor, dup),
        prepare=False,
    )
    retagged_chunks = cur.rowcount or 0

    # 3) merge fields onto survivor (jsonb arrays merged in Python)
    merged_aliases = merge_jsonb_list(sv_aliases, dp_aliases, dp_en, dp_tr, dp_slug, dup)
    merged_sources = merge_jsonb_list(sv_sources, dp_sources)
    cur.execute(
        """
        update public.canonical_ingredients set
          graph_ingredient_id = coalesce(graph_ingredient_id, %s),
          name_en = coalesce(name_en, %s),
          ingredient_db_key = coalesce(ingredient_db_key, %s),
          aliases = %s,
          sources = %s,
          updated_at = now()
        where ingredient_id = %s
        """,
        (dp_graph, dp_en, dp_dbk, Json(merged_aliases), Json(merged_sources), survivor),
        prepare=False,
    )

    # 4) delete dup
    cur.execute(
        "delete from public.canonical_ingredients where ingredient_id = %s",
        (dup,),
        prepare=False,
    )

    return {
        "survivor": survivor,
        "dup": dup,
        "dropped_links": dropped_links,
        "moved_links": moved_links,
        "retagged_chunks": retagged_chunks,
        "merged": True,
    }


def main() -> None:
    ap = argparse.ArgumentParser(description="Merge duplicate canonical ingredient boxes")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    pairs = plan_pairs(MERGE_MAP)
    print(f"Planlanan birleştirme: {len(pairs)} çift")
    for sv, dp in pairs:
        print(f"  {dp:18s} -> {sv}")

    if args.dry_run:
        print("\n[dry-run] DB güncellenmedi.")
        return

    from knowledge.db import pg_conn

    results: list[dict] = []
    with pg_conn(autocommit=False) as conn:
        with conn.cursor() as cur:
            for sv, dp in pairs:
                results.append(_merge_one(cur, sv, dp))
        conn.commit()

    print("\nSonuç:")
    print(json.dumps(results, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
