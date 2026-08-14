from __future__ import annotations

import os
import re
from contextlib import contextmanager
from urllib.parse import quote_plus


def project_ref() -> str | None:
    """Supabase project ref from SUPABASE_URL (the REST endpoint)."""
    base = (os.getenv("SUPABASE_URL") or "").strip()
    if not base:
        return None
    m = re.search(r"https?://([^.]+)\.supabase\.co", base.rstrip("/"), re.I)
    return m.group(1) if m else None


def resolve_postgres_dsn() -> str | None:
    """
    Önce tam URI; yoksa SUPABASE_URL + SUPABASE_DB_PASSWORD (db_bootstrap / ingest ile aynı kural).
    SUPABASE_URL yalnızca REST API adresidir; Postgres için URI veya şifre gerekir.

    Supabase, doğrudan bağlantı host'u (db.<ref>.supabase.co) için IPv4'ü kaldırdı;
    yalnızca AAAA kaydı var. IPv6 rotası olmayan ortamlarda (Docker varsayılanı,
    birçok ofis/ev ağı) bu host'a hiç ulaşılamaz. Böyle ortamlar için IPv4 sunan
    Supavisor pooler host'u SUPABASE_DB_POOLER_HOST ile verilebilir; pooler'da
    kullanıcı adı "postgres.<ref>" biçimindedir.
    """
    u = (os.getenv("SUPABASE_DATABASE_URL") or os.getenv("DATABASE_URL") or "").strip()
    if u:
        return u
    pw = (os.getenv("SUPABASE_DB_PASSWORD") or "").strip()
    ref = project_ref()
    if not (pw and ref):
        return None

    pooler = (os.getenv("SUPABASE_DB_POOLER_HOST") or "").strip()
    if pooler:
        port = (os.getenv("SUPABASE_DB_POOLER_PORT") or "5432").strip() or "5432"
        return f"postgresql://postgres.{ref}:{quote_plus(pw)}@{pooler}:{port}/postgres"

    return f"postgresql://postgres:{quote_plus(pw)}@db.{ref}.supabase.co:5432/postgres"


def postgres_dsn() -> str:
    dsn = resolve_postgres_dsn()
    if not dsn:
        raise RuntimeError(
            "Postgres için SUPABASE_DATABASE_URL veya DATABASE_URL tanımlayın; "
            "veya SUPABASE_DB_PASSWORD ile birlikte SUPABASE_URL (Dashboard → Settings → Database). "
            "IPv6 rotası olmayan ortamlarda ayrıca SUPABASE_DB_POOLER_HOST gerekir."
        )
    return dsn


def _connect_timeout_sec() -> int:
    raw = (os.getenv("POSTGRES_CONNECT_TIMEOUT") or "240").strip() or "240"
    try:
        v = int(raw)
    except ValueError:
        v = 240
    return max(15, min(v, 900))


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
        connect_timeout=_connect_timeout_sec(),
    ) as conn:
        try:
            # Pooler can reuse server connections that already have prepared statements.
            # Clearing is safe and helps avoid name collisions.
            conn.execute("DEALLOCATE ALL")
        except Exception:
            pass
        yield conn

