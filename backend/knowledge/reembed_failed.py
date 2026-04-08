from __future__ import annotations

import json
from typing import Optional

from config import get_logger
from knowledge.db import pg_conn
from knowledge.ingest import embed_texts_google, _pg_vector_literal

log = get_logger("knowledge.reembed")


def reembed_failed(
    *,
    user_id: str,
    folder_slug: Optional[str] = None,
    embed_model: str = "gemini-embedding-001",
    limit: int = 500,
    batch_size: int = 16,
) -> dict:
    """
    Re-embeds chunks where embed_ok=false OR embedding is null.
    Writes embed_ok/embed_error accordingly.
    """
    updated_ok = 0
    updated_fail = 0
    stopped_due_to_quota = False

    with pg_conn(autocommit=True) as conn:
        with conn.cursor() as cur:
            folder_id = None
            if folder_slug:
                cur.execute(
                    "select id from public.knowledge_folders where user_id=%s and slug=%s",
                    (user_id, folder_slug),
                )
                row = cur.fetchone()
                folder_id = row[0] if row else None
                if not folder_id:
                    raise RuntimeError(f"Folder not found for slug={folder_slug}")

            cur.execute(
                """
                select id, document_id, chunk_index, chunk_text
                from public.knowledge_chunks
                where user_id = %s
                  and (%s::uuid is null or folder_id = %s::uuid)
                  and (embed_ok is false or embedding is null)
                order by created_at asc
                limit %s
                """,
                (user_id, folder_id, folder_id, max(int(limit), 1)),
            )
            rows = cur.fetchall() or []

            log.info("Found %d chunks to re-embed", len(rows))

            for i in range(0, len(rows), batch_size):
                batch = rows[i : i + batch_size]
                texts = [r[3] for r in batch]
                try:
                    vecs = embed_texts_google(texts, model=embed_model, output_dimensionality=768)
                    if len(vecs) != len(batch):
                        raise RuntimeError("Embedding count mismatch")
                    for (chunk_id, _doc_id, _chunk_index, _), v in zip(batch, vecs):
                        cur.execute(
                            """
                            update public.knowledge_chunks
                            set embedding = %s::vector,
                                embed_ok = true,
                                embed_error = null,
                                embed_model = %s
                            where id = %s
                            """,
                            (_pg_vector_literal(v), embed_model, chunk_id),
                        )
                        updated_ok += 1
                except Exception as e:
                    err = str(e)[:500]
                    if "RESOURCE_EXHAUSTED" in err or "429" in err:
                        stopped_due_to_quota = True
                    for (chunk_id, _doc_id, _chunk_index, _) in batch:
                        cur.execute(
                            """
                            update public.knowledge_chunks
                            set embed_ok = false,
                                embed_error = %s,
                                embed_model = %s
                            where id = %s
                            """,
                            (err, embed_model, chunk_id),
                        )
                        updated_fail += 1
                    log.error("Batch re-embed failed (%d..%d): %s", i, i + len(batch) - 1, err)
                    if stopped_due_to_quota:
                        break

    return {
        "user_id": user_id,
        "folder_slug": folder_slug,
        "embed_model": embed_model,
        "attempted": updated_ok + updated_fail,
        "updated_ok": updated_ok,
        "updated_fail": updated_fail,
        "stopped_due_to_quota": stopped_due_to_quota,
    }


if __name__ == "__main__":
    import argparse

    ap = argparse.ArgumentParser()
    ap.add_argument("--user", required=True, help="supabase auth user uuid")
    ap.add_argument("--folder", default=None, help="folder slug (optional)")
    ap.add_argument("--model", default="gemini-embedding-001")
    ap.add_argument("--limit", type=int, default=500)
    ap.add_argument("--batch", type=int, default=16)
    args = ap.parse_args()

    result = reembed_failed(
        user_id=args.user,
        folder_slug=args.folder,
        embed_model=args.model,
        limit=args.limit,
        batch_size=args.batch,
    )
    print(json.dumps(result, indent=2, ensure_ascii=False))

