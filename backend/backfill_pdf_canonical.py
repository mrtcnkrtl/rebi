#!/usr/bin/env python3
"""
Backfill canonical box tags onto existing PDF chunks.

PDF ingest + classify already populate knowledge_entities (free-text ingredient
names) linked to chunks. This script resolves those names to canonical
ingredient_ids and writes them into knowledge_chunks.canonical_ingredient_ids
(+ source_kind='pdf'), so PDF passages flow into each ingredient box's
literature/ section like graph + master_veri do.

Requires migrations (20260504160000) + a populated catalog (merge_data_catalog).

Usage:
  cd backend && python3 backfill_pdf_canonical.py --dry-run
  python3 backfill_pdf_canonical.py --from-db
"""

from __future__ import annotations

import argparse
import json

from config import KNOWLEDGE_CATALOG_USER_ID, get_logger

log = get_logger("backfill_pdf_canonical")

DEFAULT_USER = (KNOWLEDGE_CATALOG_USER_ID or "").strip() or "00000000-0000-4000-8000-000000000001"
FOLDER_SLUG = "data-pdfs"


def resolve_entity_names(names: list[str], resolver) -> tuple[dict[str, str], list[str]]:
    """
    Map entity names -> canonical ingredient_id (only confident, non-candidate).
    Returns (resolved_map, unresolved[]). Pure function (testable).
    """
    resolved: dict[str, str] = {}
    unresolved: list[str] = []
    for name in names:
        nm = (name or "").strip()
        if not nm:
            continue
        res = resolver.resolve(nm)
        if res.is_candidate or not res.ingredient_id:
            unresolved.append(nm)
        else:
            resolved[nm] = res.ingredient_id
    return resolved, unresolved


def _fetch_entity_names(cur, user_id: str) -> list[str]:
    cur.execute(
        """
        select distinct e.name
        from public.knowledge_entities e
        where e.user_id = %s and e.kind = 'ingredient'
          and length(trim(e.name)) >= 3
        """,
        (user_id,),
        prepare=False,
    )
    return [r[0] for r in (cur.fetchall() or [])]


def _apply_backfill(user_id: str, resolved: dict[str, str]) -> dict:
    from knowledge.db import pg_conn

    updated_chunks = 0
    tagged_pairs = 0
    with pg_conn(autocommit=False) as conn:
        with conn.cursor() as cur:
            for name, iid in resolved.items():
                # Append canonical id to all chunks linked to this entity name,
                # avoiding duplicates; also set source_kind='pdf' when missing.
                cur.execute(
                    """
                    update public.knowledge_chunks kc
                    set canonical_ingredient_ids =
                          (select array(select distinct unnest(kc.canonical_ingredient_ids || array[%s::text]))),
                        source_kind = coalesce(kc.source_kind, 'pdf')
                    from public.knowledge_chunk_entities ce
                    join public.knowledge_entities e on e.id = ce.entity_id
                    where ce.chunk_id = kc.id
                      and e.user_id = %s
                      and lower(e.name) = lower(%s)
                      and not (%s = any(kc.canonical_ingredient_ids))
                    """,
                    (iid, user_id, name, iid),
                    prepare=False,
                )
                if cur.rowcount and cur.rowcount > 0:
                    updated_chunks += cur.rowcount
                    tagged_pairs += 1
        conn.commit()
    return {"updated_chunks": updated_chunks, "tagged_entities": tagged_pairs}


def main() -> None:
    ap = argparse.ArgumentParser(description="Backfill canonical ids onto PDF chunks")
    ap.add_argument("--user", default=DEFAULT_USER)
    ap.add_argument("--from-db", action="store_true", help="resolve against canonical_ingredients in DB")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    from knowledge.db import pg_conn
    from knowledge.entity_resolver import build_resolver

    resolver = build_resolver(load_from_db=args.from_db)

    with pg_conn(autocommit=True) as conn:
        with conn.cursor() as cur:
            names = _fetch_entity_names(cur, args.user)

    resolved, unresolved = resolve_entity_names(names, resolver)
    print(
        json.dumps(
            {"entities": len(names), "resolved": len(resolved), "unresolved": len(unresolved)},
            ensure_ascii=False,
            indent=2,
        )
    )
    print("\nÇözümlenen (PDF entity -> kutu):")
    for n, i in sorted(resolved.items()):
        print(f"  ✓ {n:30s} -> {i}")
    if unresolved:
        print(f"\nÇözümlenemeyen ({len(unresolved)}) — aday kutu olabilir:")
        for n in sorted(unresolved)[:40]:
            print(f"  + {n}")

    if args.dry_run:
        print("\n[dry-run] DB güncellenmedi.")
        return
    result = _apply_backfill(args.user, resolved)
    print("\nBackfill sonucu:", json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
