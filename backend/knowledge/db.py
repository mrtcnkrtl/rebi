from __future__ import annotations

import os
from contextlib import contextmanager


def postgres_dsn() -> str:
    dsn = (os.getenv("SUPABASE_DATABASE_URL") or os.getenv("DATABASE_URL") or "").strip()
    if not dsn:
        raise RuntimeError("SUPABASE_DATABASE_URL or DATABASE_URL is required")
    return dsn


@contextmanager
def pg_conn(autocommit: bool = True):
    try:
        import psycopg  # type: ignore
    except Exception as e:
        raise RuntimeError("psycopg is required; install psycopg[binary]") from e
    # Supabase pooler (PgBouncer) can break psycopg prepared statement caching.
    # Disable automatic prepared statements; also deallocate any server-side statements
    # that might remain from a reused pooled connection.
    with psycopg.connect(
        postgres_dsn(),
        autocommit=autocommit,
        prepare_threshold=0,
    ) as conn:
        try:
            # Pooler can reuse server connections that already have prepared statements.
            # Clearing is safe and helps avoid name collisions.
            conn.execute("DEALLOCATE ALL")
        except Exception:
            pass
        yield conn

