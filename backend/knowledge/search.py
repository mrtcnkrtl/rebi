from __future__ import annotations

from dataclasses import dataclass
from typing import Optional, Sequence

from config import get_logger
from knowledge.db import pg_conn
from knowledge.ingest import embed_texts_google, _pg_vector_literal

log = get_logger("knowledge.search")


@dataclass
class ChunkMatch:
    chunk_id: str
    document_id: str
    chunk_text: str
    similarity: float


def _folder_id(user_id: str, folder_slug: str) -> str | None:
    with pg_conn(autocommit=True) as conn:
        with conn.cursor() as cur:
            cur.execute(
                "select id from public.knowledge_folders where user_id=%s and slug=%s",
                (user_id, folder_slug),
                prepare=False,
            )
            row = cur.fetchone()
            return str(row[0]) if row else None


def search_chunks(
    *,
    user_id: str,
    folder_slug: Optional[str],
    query: str,
    k: int = 6,
    embed_model: str = "gemini-embedding-001",
    klass_topics: Optional[Sequence[str]] = None,
) -> list[ChunkMatch]:
    q = (query or "").strip()
    if not q:
        return []

    folder_id = None
    if folder_slug:
        folder_id = _folder_id(user_id, folder_slug)
        if not folder_id:
            return []

    vec = embed_texts_google([q], model=embed_model, output_dimensionality=768)[0]
    vec_lit = _pg_vector_literal(vec)
    topics = None
    if klass_topics:
        topics = [str(x).strip().lower() for x in klass_topics if str(x).strip()]
        if not topics:
            topics = None

    with pg_conn(autocommit=True) as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                select chunk_id, document_id, chunk_text, similarity
                from public.match_knowledge_chunks(%s::uuid, %s::vector, %s, %s::uuid, %s::text[])
                """,
                (user_id, vec_lit, max(int(k), 1), folder_id, topics),
                prepare=False,
            )
            rows = cur.fetchall() or []

    out: list[ChunkMatch] = []
    for r in rows:
        out.append(
            ChunkMatch(
                chunk_id=str(r[0]),
                document_id=str(r[1]),
                chunk_text=str(r[2] or ""),
                similarity=float(r[3] or 0.0),
            )
        )
    return out

