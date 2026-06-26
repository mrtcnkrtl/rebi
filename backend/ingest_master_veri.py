#!/usr/bin/env python3
"""
Ingest the cleaned Master Veri inventory into knowledge_chunks as canonical-tagged
literature: each ingredient box's claims become chunks tagged with
source_kind='master_veri' and canonical_ingredient_ids=[resolved id].

This is the bridge that fills the "literature/" section of each ingredient box
with raw, cited evidence — so chat can pull real passages, not just structure.

Requires migrations (auto-applied at API startup):
  - 20260504120000_data_catalog_cabinet.sql
  - 20260504160000_chunk_canonical_links.sql
Requires env: SUPABASE_DATABASE_URL / DATABASE_URL (+ GEMINI_API_KEY for embeds).

Usage:
  cd backend && python3 ingest_master_veri.py
  python3 ingest_master_veri.py --no-embed         # write chunks, skip embeddings
  python3 ingest_master_veri.py --from-db          # resolve against canonical_ingredients in DB
  python3 ingest_master_veri.py --dry-run          # report only, no DB writes
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from config import KNOWLEDGE_CATALOG_USER_ID, get_logger

log = get_logger("ingest_master_veri")

DEFAULT_USER = (KNOWLEDGE_CATALOG_USER_ID or "").strip() or "00000000-0000-4000-8000-000000000001"
FOLDER_SLUG = "data-pdfs"
FOLDER_TITLE = "Rebi katalog"
DEFAULT_XLSX = (
    Path(__file__).resolve().parent / "documents" / "Dermatolojik_Veri_Analizi_Master.xlsx"
)


def pack_claims_into_chunks(box: dict, *, max_chars: int = 1300) -> list[str]:
    """
    Group a box's claim texts into chunk strings (<= max_chars), prefixed with the
    box name + subcategory so each chunk is self-describing for vector search.
    Pure function (no DB), testable.
    """
    name = (box.get("name") or "").strip()
    claims = box.get("claims") or []
    chunks: list[str] = []
    buf: list[str] = []
    size = 0
    for c in claims:
        alt = (c.get("alt") or "").strip()
        text = (c.get("text") or "").strip()
        if not text:
            continue
        line = f"[{alt}] {text}" if alt else text
        if size + len(line) + 1 > max_chars and buf:
            chunks.append(f"{name}:\n" + "\n".join(buf))
            buf, size = [], 0
        buf.append(line)
        size += len(line) + 1
    if buf:
        chunks.append(f"{name}:\n" + "\n".join(buf))
    return chunks


def build_box_records(inventory: dict, resolver) -> tuple[list[dict], dict]:
    """
    Resolve each ingredient/oil/extract box to a canonical id and pack chunks.
    Returns (records, stats). Each record: {name, ingredient_id, slug, chunks[]}.
    Topic boxes (mechanisms/conditions) are skipped here (concern mapping is a
    separate step) but counted in stats.
    """
    records: list[dict] = []
    stats = {"resolved": 0, "candidate": 0, "topic_skipped": 0, "chunks": 0}
    for box in inventory.get("boxes") or []:
        kind = box.get("kind")
        if kind == "topic":
            stats["topic_skipped"] += 1
            continue
        res = resolver.resolve(box.get("name") or "")
        chunks = pack_claims_into_chunks(box)
        if not chunks:
            continue
        ingredient_id = res.ingredient_id or res.suggested_slug
        if res.is_candidate:
            stats["candidate"] += 1
        else:
            stats["resolved"] += 1
        stats["chunks"] += len(chunks)
        records.append(
            {
                "name": box.get("name"),
                "ingredient_id": ingredient_id,
                "is_candidate": res.is_candidate,
                "slug": res.suggested_slug,
                "chunks": chunks,
            }
        )
    return records, stats


def _write_records(records: list[dict], *, user_id: str, embed: bool, embed_model: str) -> dict:
    import psycopg  # type: ignore

    from knowledge.db import resolve_postgres_dsn
    from knowledge.ingest import _pg_vector_literal, _sanitize_text_for_pg, embed_texts_google

    dsn = resolve_postgres_dsn()
    if not dsn:
        raise SystemExit("Postgres DSN yok: SUPABASE_DATABASE_URL / DATABASE_URL ayarla.")

    inserted_docs = 0
    inserted_chunks = 0
    embedded = 0
    failed = 0

    with psycopg.connect(dsn, autocommit=True, prepare_threshold=0) as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                insert into public.knowledge_folders (user_id, slug, title)
                values (%s, %s, %s)
                on conflict (user_id, slug) do update set title = excluded.title
                returning id
                """,
                (user_id, FOLDER_SLUG, FOLDER_TITLE),
            )
            folder_id = cur.fetchone()[0]

            for rec in records:
                source_url = f"master_veri://{rec['slug']}"
                # Idempotent: replace existing master_veri doc for this box.
                cur.execute(
                    "select id from public.knowledge_documents where user_id=%s and folder_id=%s and source_url=%s limit 1",
                    (user_id, folder_id, source_url),
                )
                row = cur.fetchone()
                if row:
                    cur.execute("delete from public.knowledge_documents where id=%s", (row[0],))

                cur.execute(
                    """
                    insert into public.knowledge_documents
                      (user_id, folder_id, source_type, title, source_url)
                    values (%s, %s, %s, %s, %s)
                    returning id
                    """,
                    (user_id, folder_id, "master_veri", rec["name"], source_url),
                )
                doc_id = cur.fetchone()[0]
                inserted_docs += 1

                canon_ids = [] if rec["is_candidate"] else [rec["ingredient_id"]]
                chunks = [_sanitize_text_for_pg(c) for c in rec["chunks"]]
                for idx, ch in enumerate(chunks):
                    cur.execute(
                        """
                        insert into public.knowledge_chunks
                          (user_id, folder_id, document_id, chunk_index, chunk_text,
                           embed_model, embed_ok, source_kind, source_ref, canonical_ingredient_ids)
                        values (%s,%s,%s,%s,%s,%s,false,'master_veri',%s,%s)
                        """,
                        (user_id, folder_id, doc_id, idx, ch, embed_model, source_url, canon_ids),
                    )
                inserted_chunks += len(chunks)

                if embed and chunks:
                    for i in range(0, len(chunks), 16):
                        batch = chunks[i : i + 16]
                        try:
                            vecs = embed_texts_google(batch, model=embed_model, output_dimensionality=768)
                            for j, v in enumerate(vecs):
                                cur.execute(
                                    """
                                    update public.knowledge_chunks
                                    set embedding=%s::vector, embed_ok=true, embed_error=null
                                    where document_id=%s and chunk_index=%s
                                    """,
                                    (_pg_vector_literal(v), doc_id, i + j),
                                )
                            embedded += len(batch)
                        except Exception as e:
                            failed += len(batch)
                            log.warning("embed batch failed: %s", str(e)[:200])

    return {
        "documents": inserted_docs,
        "chunks": inserted_chunks,
        "embedded": embedded,
        "failed": failed,
    }


def main() -> None:
    ap = argparse.ArgumentParser(description="Ingest Master Veri as canonical-tagged literature")
    ap.add_argument("--file", default=str(DEFAULT_XLSX))
    ap.add_argument("--user", default=DEFAULT_USER)
    ap.add_argument("--from-db", action="store_true", help="resolve against canonical_ingredients in DB")
    ap.add_argument("--no-embed", action="store_true")
    ap.add_argument("--dry-run", action="store_true", help="report only, no DB writes")
    args = ap.parse_args()

    from clean_master_veri import build_inventory
    from knowledge.entity_resolver import build_resolver

    inv = build_inventory(Path(args.file))
    resolver = build_resolver(load_from_db=args.from_db)
    records, stats = build_box_records(inv, resolver)

    print(json.dumps({"inventory_boxes": inv["box_count"], **stats}, ensure_ascii=False, indent=2))
    print("\nÇözümlenen kutular:")
    for rec in records:
        tag = "ADAY" if rec["is_candidate"] else rec["ingredient_id"]
        print(f"  - {rec['name']:30s} -> {tag}  ({len(rec['chunks'])} chunk)")

    if args.dry_run:
        print("\n[dry-run] DB'ye yazılmadı.")
        return

    result = _write_records(records, user_id=args.user, embed=not args.no_embed, embed_model="gemini-embedding-001")
    print("\nYazım sonucu:", json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
