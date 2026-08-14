#!/usr/bin/env python3
"""
Clean up the knowledge chunk store: drop byte-identical duplicate passages and
backfill the missing source_kind tags.

Why duplicates exist: the same PDF was ingested more than once under slightly
different filenames ("... olarak ...", "... oltttarak ...", "... (1)"). Only the
passages that are byte-identical are removed, so nothing unique is lost -- the
three files genuinely differ outside those shared passages.

Keeper rule per duplicate group (in order):
  1. most canonical tags (the copy that is wired into ingredient/concern boxes)
  2. best source_kind (master_veri > graph > chat_guide > pdf > unknown)
  3. oldest row, then lowest id for a stable tie-break

source_kind backfill matters for retrieval quality: knowledge/literature.py
ranks passages by source_kind, and NULL sorts as unknown/last.

Usage:
  python3 dedupe_chunks.py            # dry run (default, no writes)
  python3 dedupe_chunks.py --apply    # perform the cleanup
"""

from __future__ import annotations

import argparse

import config  # noqa: F401  (loads backend/.env)
from knowledge.db import pg_conn

# Lower number = preferred keeper.
SOURCE_PRIORITY = {"master_veri": 0, "graph": 1, "chat_guide": 2, "pdf": 3}

# folder slug -> source_kind for rows ingested before the column existed.
FOLDER_SOURCE_KIND = {"data-pdfs": "pdf", "chat-guides": "chat_guide"}


def _exec(cur, sql, params=None):
    return cur.execute(sql, params, prepare=False) if params else cur.execute(sql, prepare=False)


def keeper_sort_key(row: dict) -> tuple:
    """Pure ordering helper: first element of the sorted list is the keeper."""
    return (
        -int(row.get("tag_count") or 0),
        SOURCE_PRIORITY.get((row.get("source_kind") or "").strip(), 99),
        str(row.get("created_at") or ""),
        str(row.get("id") or ""),
    )


def plan_duplicates(cur) -> list[dict]:
    """Duplicate groups with the keeper resolved and the ids to delete."""
    _exec(
        cur,
        """
        with dup as (
          select md5(chunk_text) as h
          from public.knowledge_chunks
          group by 1
          having count(*) > 1
        )
        select c.id, c.document_id, c.source_kind, c.created_at,
               md5(c.chunk_text) as h,
               cardinality(c.canonical_ingredient_ids)
                 + cardinality(c.canonical_concern_ids) as tag_count
        from public.knowledge_chunks c
        join dup on md5(c.chunk_text) = dup.h
        """,
    )
    cols = [d[0] for d in cur.description]
    groups: dict[str, list[dict]] = {}
    for r in cur.fetchall() or []:
        row = dict(zip(cols, r))
        groups.setdefault(row["h"], []).append(row)

    out: list[dict] = []
    for h, rows in groups.items():
        rows.sort(key=keeper_sort_key)
        out.append(
            {
                "hash": h,
                "keep": rows[0]["id"],
                "delete": [r["id"] for r in rows[1:]],
                "copies": len(rows),
            }
        )
    return out


def redundant_empty_documents(cur) -> list[tuple[str, str]]:
    """
    Document rows left with zero chunks *and* sharing a title with a document
    that still has chunks. Those are proven re-ingests of the same file; a
    zero-chunk row with a unique title could be a genuine mid-ingest document,
    so it is deliberately left alone.
    """
    _exec(
        cur,
        """
        select d.id, d.title
        from public.knowledge_documents d
        where not exists (
                select 1 from public.knowledge_chunks c where c.document_id = d.id
              )
          and exists (
                select 1
                from public.knowledge_documents o
                join public.knowledge_chunks oc on oc.document_id = o.id
                where o.title = d.title and o.id <> d.id
              )
        """,
    )
    return [(str(r[0]), str(r[1])) for r in cur.fetchall() or []]


def count_missing_source_kind(cur) -> list[tuple[str, int]]:
    _exec(
        cur,
        """
        select coalesce(f.slug, '(klasorsuz)') as slug, count(*)
        from public.knowledge_chunks c
        left join public.knowledge_folders f on f.id = c.folder_id
        where c.source_kind is null
        group by 1
        order by 2 desc
        """,
    )
    return [(str(r[0]), int(r[1])) for r in cur.fetchall() or []]


def main() -> int:
    ap = argparse.ArgumentParser(description="Dedupe knowledge chunks + backfill source_kind")
    ap.add_argument("--apply", action="store_true", help="write changes (default: dry run)")
    args = ap.parse_args()

    with pg_conn(autocommit=True) as conn:
        with conn.cursor() as cur:
            _exec(cur, "select count(*) from public.knowledge_chunks")
            total_before = int(cur.fetchone()[0])

            groups = plan_duplicates(cur)
            to_delete = [cid for g in groups for cid in g["delete"]]
            missing = count_missing_source_kind(cur)
            empty_docs = redundant_empty_documents(cur)

            print(f"Mevcut chunk sayisi      : {total_before}")
            print(f"Mukerrer grup            : {len(groups)}")
            print(f"Silinecek kopya          : {len(to_delete)}")
            print(f"Temizlik sonrasi         : {total_before - len(to_delete)}")
            print(f"Bos mukerrer belge       : {len(empty_docs)}")
            for _, title in empty_docs:
                print(f"  - {title}")
            print("source_kind bos satirlar :")
            for slug, n in missing:
                print(f"  {slug:16} {n:5}  -> {FOLDER_SOURCE_KIND.get(slug) or '(eslesme yok)'}")

            if not args.apply:
                print("\nDRY RUN — hicbir sey yazilmadi. Uygulamak icin: --apply")
                return 0

            deleted = 0
            if to_delete:
                _exec(
                    cur,
                    "delete from public.knowledge_chunks where id = any(%s::uuid[])",
                    (to_delete,),
                )
                deleted = cur.rowcount or 0

            filled = 0
            for slug, kind in FOLDER_SOURCE_KIND.items():
                _exec(
                    cur,
                    """
                    update public.knowledge_chunks c
                    set source_kind = %s
                    from public.knowledge_folders f
                    where f.id = c.folder_id
                      and f.slug = %s
                      and c.source_kind is null
                    """,
                    (kind, slug),
                )
                filled += cur.rowcount or 0

            docs_removed = 0
            if empty_docs:
                _exec(
                    cur,
                    "delete from public.knowledge_documents where id = any(%s::uuid[])",
                    ([d for d, _ in empty_docs],),
                )
                docs_removed = cur.rowcount or 0

            _exec(cur, "select count(*) from public.knowledge_chunks")
            total_after = int(cur.fetchone()[0])

            print(f"\nSilinen kopya            : {deleted}")
            print(f"source_kind dolduruldu   : {filled}")
            print(f"Silinen bos belge        : {docs_removed}")
            print(f"Yeni chunk sayisi        : {total_after}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
