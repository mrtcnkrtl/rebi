"""
Literature fetch: the "literature/" section of an ingredient/concern box.

Pulls raw passages (any source: master_veri / pdf / graph) that were tagged with
a canonical id, via the GIN indexes on knowledge_chunks. This is how the cabinet
surfaces real evidence text once boxes are populated.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Optional

from config import get_logger
from knowledge.db import pg_conn

log = get_logger("knowledge.literature")


@dataclass
class Passage:
    text: str
    source_kind: Optional[str]
    source_ref: Optional[str]


def _exec(cur, sql: str, params=None):
    if params is None:
        return cur.execute(sql, prepare=False)
    return cur.execute(sql, params, prepare=False)


def fetch_passages_by_ingredient(
    ingredient_ids: list[str],
    *,
    limit: int = 6,
    max_chars: int = 1600,
) -> list[Passage]:
    """Raw passages tagged to any of the given canonical ingredient ids."""
    ids = [i for i in (ingredient_ids or []) if i]
    if not ids:
        return []
    try:
        with pg_conn(autocommit=True) as conn:
            with conn.cursor() as cur:
                _exec(
                    cur,
                    """
                    select chunk_text, source_kind, source_ref
                    from public.knowledge_chunks
                    where canonical_ingredient_ids && %s
                      and chunk_text is not null
                    order by (source_kind = 'master_veri') desc, char_length(chunk_text) asc
                    limit %s
                    """,
                    (ids, int(limit)),
                )
                rows = cur.fetchall() or []
    except Exception as e:
        log.warning("fetch_passages_by_ingredient failed: %s", e)
        return []
    out: list[Passage] = []
    for text, kind, ref in rows:
        t = (text or "").strip()
        if t:
            out.append(Passage(t[:max_chars], kind, ref))
    return out


def format_literature_block(
    ingredient_ids: list[str],
    *,
    limit: int = 4,
    max_chars: int = 1400,
) -> str:
    """Compact literature block for the evidence bundle (raw cited passages)."""
    passages = fetch_passages_by_ingredient(ingredient_ids, limit=limit)
    if not passages:
        return ""
    parts = ["İlgili literatür (ham pasajlar):"]
    total = 0
    for p in passages:
        seg = p.text.strip()
        if not seg:
            continue
        if total + len(seg) > max_chars:
            seg = seg[: max(0, max_chars - total)]
        if not seg:
            break
        parts.append(f"- {seg}")
        total += len(seg)
        if total >= max_chars:
            break
    return "\n".join(parts).strip()
