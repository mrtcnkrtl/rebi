"""
Supabase Postgres üzerinde gerekli tabloları otomatik oluşturur (CREATE IF NOT EXISTS).

Kullanım:
  - Tercih: SUPABASE_DATABASE_URL veya DATABASE_URL (URI, Dashboard → Database → Connection string)
  - Alternatif: SUPABASE_URL + SUPABASE_DB_PASSWORD (Database şifresi — Settings → Database)

Servis rolü anahtarı Postgres şifresi değildir; doğrudan SQL için yukarıdakilerden biri gerekir.
"""

from __future__ import annotations

import logging
import os
import re
from typing import Literal
from pathlib import Path
from urllib.parse import quote_plus

log = logging.getLogger("db_bootstrap")

_MIGRATIONS_DIR = Path(__file__).resolve().parent.parent / "supabase" / "migrations"


def _migration_sql_files() -> list[Path]:
    if not _MIGRATIONS_DIR.is_dir():
        return []
    return sorted(_MIGRATIONS_DIR.glob("*.sql"))


def _supabase_ref_from_url(url: str) -> str | None:
    if not url:
        return None
    m = re.search(r"https?://([^.]+)\.supabase\.co", url.strip().rstrip("/"), re.I)
    return m.group(1) if m else None


def _postgres_dsn() -> str | None:
    u = (os.getenv("SUPABASE_DATABASE_URL") or os.getenv("DATABASE_URL") or "").strip()
    if u:
        return u
    pw = (os.getenv("SUPABASE_DB_PASSWORD") or "").strip()
    ref = _supabase_ref_from_url(os.getenv("SUPABASE_URL", "") or "")
    if pw and ref:
        return f"postgresql://postgres:{quote_plus(pw)}@db.{ref}.supabase.co:5432/postgres"
    return None


def _split_sql_statements(sql: str) -> list[str]:
    lines = []
    for line in sql.splitlines():
        s = line.strip()
        if s.startswith("--"):
            continue
        lines.append(line)
    text = "\n".join(lines)
    parts: list[str] = []
    for chunk in text.split(";"):
        c = chunk.strip()
        if c:
            parts.append(c)
    return parts


def ensure_daily_events_schema() -> Literal["skipped", "ok", "error"]:
    """
    supabase/migrations/*.sql dosyalarını ada göre sırayla uygular (CREATE IF NOT EXISTS, RLS vb.).
    skipped: URI/şifre yok; error: dosya/psycopg/SQL hatası.
    """
    dsn = _postgres_dsn()
    if not dsn:
        log.info(
            "DB bootstrap atlandı: SUPABASE_DATABASE_URL, DATABASE_URL veya "
            "SUPABASE_DB_PASSWORD + SUPABASE_URL tanımlı değil."
        )
        return "skipped"
    files = _migration_sql_files()
    if not files:
        log.warning("Migration klasöründe .sql yok: %s", _MIGRATIONS_DIR)
        return "error"
    try:
        import psycopg
    except ImportError:
        log.warning("psycopg yüklü değil; pip install 'psycopg[binary]' gerekir.")
        return "error"

    try:
        with psycopg.connect(dsn, autocommit=True) as conn:
            with conn.cursor() as cur:
                for path in files:
                    sql = path.read_text(encoding="utf-8")
                    statements = _split_sql_statements(sql)
                    if not statements:
                        log.warning("Migration atlandı (boş/yorum): %s", path.name)
                        continue
                    for stmt in statements:
                        cur.execute(stmt)
                    log.info("Migration uygulandı: %s", path.name)
        log.info("DB bootstrap tamam: %d migration dosyası.", len(files))
        return "ok"
    except Exception as e:
        log.error("DB bootstrap hatası: %s", e)
        return "error"


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    r = ensure_daily_events_schema()
    raise SystemExit(0 if r != "error" else 1)
