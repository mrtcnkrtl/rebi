"""
Literature fetch: the "literature/" section of an ingredient/concern box.

Pulls raw passages (any source: master_veri / pdf / graph) that were tagged with
a canonical id, via the GIN indexes on knowledge_chunks. This is how the cabinet
surfaces real evidence text once boxes are populated.

Quality matters: PDF extraction often yields fragmented lines ("Niasina mid
Niacinamid e Aktif"). We clean whitespace, drop low-quality fragments, and rank
clean curated sources (master_veri/graph) above raw PDF text.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Optional

from config import get_logger
from knowledge.db import pg_conn

log = get_logger("knowledge.literature")

# Lower number = higher priority in the literature block.
_SOURCE_PRIORITY = {"master_veri": 0, "graph": 1, "chat_guide": 2, "pdf": 3}
_MIN_PASSAGE_CHARS = 120


@dataclass
class Passage:
    text: str
    source_kind: Optional[str]
    source_ref: Optional[str]


def clean_text(raw: str) -> str:
    """Collapse PDF line-break noise into a single clean line. Pure."""
    t = (raw or "").replace("\x00", " ")
    t = re.sub(r"\s+", " ", t)
    return t.strip()


def quality_ok(text: str, *, min_chars: int = _MIN_PASSAGE_CHARS) -> bool:
    """Reject fragmented / low-signal passages (typical bad PDF extraction). Pure."""
    t = clean_text(text)
    if len(t) < min_chars:
        return False
    letters = sum(ch.isalpha() for ch in t)
    if letters / max(len(t), 1) < 0.55:
        return False
    tokens = [w for w in t.split(" ") if w]
    if len(tokens) < 8:
        return False
    short = sum(1 for w in tokens if len(w) <= 2)
    if short / len(tokens) > 0.32:
        return False
    avg_len = sum(len(w) for w in tokens) / len(tokens)
    if avg_len < 3.2:
        return False
    return True


def _source_rank(kind: Optional[str]) -> int:
    return _SOURCE_PRIORITY.get((kind or "").strip(), 5)


def rank_passages(passages: list[Passage], *, limit: int) -> list[Passage]:
    """Filter to quality passages and rank: curated source first, then longer. Pure."""
    seen: set[str] = set()
    good: list[Passage] = []
    for p in passages:
        ct = clean_text(p.text)
        if not quality_ok(ct):
            continue
        key = ct[:160].lower()
        if key in seen:
            continue
        seen.add(key)
        good.append(Passage(ct, p.source_kind, p.source_ref))
    good.sort(key=lambda p: (_source_rank(p.source_kind), -min(len(p.text), 1200)))
    return good[:limit]


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
    """Raw quality passages tagged to any of the given canonical ingredient ids."""
    ids = [i for i in (ingredient_ids or []) if i]
    if not ids:
        return []
    # Pull a candidate pool, then rank/filter in Python for quality control.
    pool = max(limit * 8, 40)
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
                    order by (source_kind = 'master_veri') desc,
                             (source_kind = 'graph') desc,
                             char_length(chunk_text) desc
                    limit %s
                    """,
                    (ids, int(pool)),
                )
                rows = cur.fetchall() or []
    except Exception as e:
        log.warning("fetch_passages_by_ingredient failed: %s", e)
        return []
    candidates = [Passage(t or "", k, r) for t, k, r in rows]
    ranked = rank_passages(candidates, limit=limit)
    return [Passage(p.text[:max_chars], p.source_kind, p.source_ref) for p in ranked]


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
        tag = (p.source_kind or "kaynak").strip()
        parts.append(f"- [{tag}] {seg}")
        total += len(seg)
        if total >= max_chars:
            break
    return "\n".join(parts).strip()
