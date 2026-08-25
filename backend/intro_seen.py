"""Mark the cinematic intro as shown once per client IP (hashed, not stored raw)."""

from __future__ import annotations

import hashlib

from knowledge.db import pg_conn

_mem: set[str] = set()
_table_ready = False


def hash_ip(ip: str) -> str:
    return hashlib.sha256(f"rebi-intro-v1|{(ip or '').strip()}".encode("utf-8")).hexdigest()


def _ensure_table(cur) -> None:
    global _table_ready
    if _table_ready:
        return
    cur.execute(
        """
        create table if not exists public.intro_seen_ips (
          ip_hash text primary key,
          seen_at timestamptz not null default now()
        )
        """,
        prepare=False,
    )
    _table_ready = True


def intro_already_seen(ip: str) -> bool:
    h = hash_ip(ip)
    if not h or h in _mem:
        return h in _mem
    try:
        with pg_conn(autocommit=True) as conn:
            with conn.cursor() as cur:
                _ensure_table(cur)
                cur.execute(
                    "select 1 from public.intro_seen_ips where ip_hash = %s",
                    (h,),
                    prepare=False,
                )
                if cur.fetchone():
                    _mem.add(h)
                    return True
    except Exception:
        return h in _mem
    return False


def mark_intro_seen(ip: str) -> None:
    h = hash_ip(ip)
    if not h:
        return
    _mem.add(h)
    try:
        with pg_conn(autocommit=True) as conn:
            with conn.cursor() as cur:
                _ensure_table(cur)
                cur.execute(
                    """
                    insert into public.intro_seen_ips (ip_hash)
                    values (%s)
                    on conflict (ip_hash) do nothing
                    """,
                    (h,),
                    prepare=False,
                )
    except Exception:
        pass
