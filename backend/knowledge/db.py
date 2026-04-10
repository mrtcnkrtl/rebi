from __future__ import annotations

import os
import re
from contextlib import contextmanager
from urllib.parse import quote_plus


def resolve_postgres_dsn() -> str | None:
    """
    Önce tam URI; yoksa SUPABASE_URL + SUPABASE_DB_PASSWORD (db_bootstrap / ingest ile aynı kural).
    SUPABASE_URL yalnızca REST API adresidir; Postgres için URI veya şifre gerekir.
    """
    u = (os.getenv("SUPABASE_DATABASE_URL") or os.getenv("DATABASE_URL") or "").strip()
    if u:
        return u
    pw = (os.getenv("SUPABASE_DB_PASSWORD") or "").strip()
    base = (os.getenv("SUPABASE_URL") or "").strip()
    if pw and base:
        m = re.search(r"https?://([^.]+)\.supabase\.co", base.rstrip("/"), re.I)
        ref = m.group(1) if m else None
        if ref:
            return f"postgresql://postgres:{quote_plus(pw)}@db.{ref}.supabase.co:5432/postgres"
    return None


def postgres_dsn() -> str:
    dsn = resolve_postgres_dsn()
    if not dsn:
        raise RuntimeError(
            "Postgres için SUPABASE_DATABASE_URL veya DATABASE_URL tanımlayın; "
            "veya SUPABASE_DB_PASSWORD ile birlikte SUPABASE_URL (Dashboard → Settings → Database)."
        )
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

