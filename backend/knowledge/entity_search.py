from __future__ import annotations

from dataclasses import dataclass
from typing import Optional

from config import get_logger
from knowledge.db import pg_conn

log = get_logger("knowledge.entity_search")


@dataclass
class EntityChunk:
    entity_name: str
    entity_kind: str
    chunk_id: str
    document_id: str
    chunk_text: str


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


def find_chunks_by_entity(
    *,
    user_id: str,
    folder_slug: Optional[str],
    q: str,
    k: int = 10,
    kind: Optional[str] = None,
) -> list[EntityChunk]:
    query = (q or "").strip().lower()
    if not query:
        return []

    folder_id = None
    if folder_slug:
        folder_id = _folder_id(user_id, folder_slug)
        if not folder_id:
            return []

    with pg_conn(autocommit=True) as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                select
                  e.name,
                  e.kind,
                  c.id as chunk_id,
                  c.document_id,
                  c.chunk_text
                from public.knowledge_entities e
                join public.knowledge_chunk_entities ce on ce.entity_id = e.id
                join public.knowledge_chunks c on c.id = ce.chunk_id
                where e.user_id = %s
                  and (%s::uuid is null or e.folder_id = %s::uuid)
                  and (%s is null or e.kind = %s)
                  and e.name like %s
                order by c.created_at asc
                limit %s
                """,
                (user_id, folder_id, folder_id, kind, kind, f"%{query}%", max(int(k), 1)),
                prepare=False,
            )
            rows = cur.fetchall() or []

    out: list[EntityChunk] = []
    for r in rows:
        out.append(
            EntityChunk(
                entity_name=str(r[0]),
                entity_kind=str(r[1] or "ingredient"),
                chunk_id=str(r[2]),
                document_id=str(r[3]),
                chunk_text=str(r[4] or ""),
            )
        )
    return out


def list_entities(
    *,
    user_id: str,
    folder_slug: Optional[str],
    q: Optional[str] = None,
    k: int = 50,
) -> list[dict]:
    folder_id = None
    if folder_slug:
        folder_id = _folder_id(user_id, folder_slug)
        if not folder_id:
            return []
    qq = (q or "").strip().lower()
    like = f"%{qq}%" if qq else "%"

    with pg_conn(autocommit=True) as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                select e.name, e.kind, count(*) as chunk_count
                from public.knowledge_entities e
                join public.knowledge_chunk_entities ce on ce.entity_id = e.id
                where e.user_id = %s
                  and (%s::uuid is null or e.folder_id = %s::uuid)
                  and e.name like %s
                group by e.name, e.kind
                order by chunk_count desc, e.name asc
                limit %s
                """,
                (user_id, folder_id, folder_id, like, max(int(k), 1)),
                prepare=False,
            )
            rows = cur.fetchall() or []
    return [{"name": str(r[0]), "kind": str(r[1] or "ingredient"), "chunk_count": int(r[2] or 0)} for r in rows]

