from __future__ import annotations

import os
import re
import threading
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


# Varsayılan, API isteği yolunda ulaşılamayan bir veritabanı iş parçacığını dakikalarca tutmasın diye
# kısa. Uzun classify/ingest koşuları POSTGRES_CONNECT_TIMEOUT ile (en fazla 900 sn) yükseltir.
_DEFAULT_CONNECT_TIMEOUT_SEC = 20


def _connect_timeout_sec() -> int:
    raw = (os.getenv("POSTGRES_CONNECT_TIMEOUT") or str(_DEFAULT_CONNECT_TIMEOUT_SEC)).strip()
    try:
        v = int(raw)
    except ValueError:
        v = _DEFAULT_CONNECT_TIMEOUT_SEC
    return max(5, min(v, 900))


def _max_concurrent_connections() -> int:
    try:
        return max(1, int(os.getenv("POSTGRES_MAX_CONCURRENT") or 16))
    except ValueError:
        return 16


def _workers() -> int:
    try:
        return max(1, int(os.getenv("WEB_CONCURRENCY") or 1))
    except ValueError:
        return 1


def pool_max_size() -> int:
    """
    Bu süreçteki havuzun üst sınırı. POSTGRES_MAX_CONCURRENT TÜM işçilerin toplam bütçesidir (Supabase'in bağlantı
    sınırı süreç başına değil proje başınadır); işçi sayısına bölünür, işçi başına en az 2.
    """
    total = _max_concurrent_connections()
    return max(2, -(-total // _workers()))


def pool_enabled() -> bool:
    """POSTGRES_POOL=0 ile kapatılır (eski davranış: her çağrıda yeni bağlantı)."""
    if (os.getenv("POSTGRES_POOL") or "1").strip().lower() in {"0", "false", "no", "off"}:
        return False
    try:
        import psycopg_pool  # noqa: F401
    except Exception:
        return False
    return True


# Havuzsuz yol (betikler, autocommit=False işler ve havuz kapalıyken): her pg_conn yeni bir bağlantı açar.
# Eşzamanlı sohbetler iş parçacığı havuzundan aynı anda onlarca bağlantı açıp Supabase'in bağlantı sınırını
# (doğrudan ~60, pooler ~200) zorlamasın diye aynı anda açık bağlantı sayısı sınırlanır; fazlası sırada bekler.
_conn_slots = threading.BoundedSemaphore(_max_concurrent_connections())

# İstek yolu (autocommit=True) süreç başına bir bağlantı havuzu kullanır: her sorguda yeni TCP + TLS + kimlik
# doğrulaması (Supabase'e ~100-300 ms) yerine açık bağlantı yeniden kullanılır. Boşta kalan bağlantılar 60 sn sonra
# kapanır (Supavisor oturum kipinde boş bağlantı da yer tutar), en az bağlantı sayısı 0'dır.
_pool = None
_pool_lock = threading.Lock()


def _configure_conn(conn) -> None:
    try:
        # Pooler, sunucu tarafında hazırlanmış ifade bırakmış bir bağlantıyı yeniden verebilir.
        conn.execute("DEALLOCATE ALL")
    except Exception:
        pass


def _get_pool():
    global _pool
    if _pool is None:
        with _pool_lock:
            if _pool is None:
                from psycopg_pool import ConnectionPool

                timeout = _connect_timeout_sec()
                _pool = ConnectionPool(
                    postgres_dsn(),
                    min_size=0,
                    max_size=pool_max_size(),
                    kwargs={
                        "autocommit": True,
                        # None: hazırlanmış ifade hiç kullanılmaz (0 her sorguyu hazırlar; işlem kipindeki
                        # pooler'da "prepared statement already exists" hatası verir).
                        "prepare_threshold": None,
                        "connect_timeout": timeout,
                    },
                    configure=_configure_conn,
                    # Ödünç verirken bağlantıyı yokla: Supavisor/ağ kapattığı bağlantı isteğe hata olarak dönmesin.
                    check=ConnectionPool.check_connection,
                    timeout=float(timeout),
                    max_idle=60.0,
                    max_lifetime=1800.0,
                    name="rebi-pg",
                    open=True,
                )
    return _pool


def close_pool() -> None:
    """Süreç kapanırken / testlerde."""
    global _pool
    with _pool_lock:
        pool, _pool = _pool, None
    if pool is not None:
        try:
            pool.close(timeout=5)
        except Exception:
            pass


@contextmanager
def pg_conn(autocommit: bool = True):
    try:
        import psycopg  # type: ignore
    except Exception as e:
        raise RuntimeError("psycopg is required; install psycopg[binary]") from e
    if autocommit and pool_enabled():
        from psycopg_pool import PoolTimeout

        try:
            with _get_pool().connection() as conn:
                yield conn
        except PoolTimeout as e:
            raise RuntimeError("Postgres bağlantı sırası dolu (zaman aşımı)") from e
        return
    if not _conn_slots.acquire(timeout=_connect_timeout_sec()):
        raise RuntimeError("Postgres bağlantı sırası dolu (zaman aşımı)")
    try:
        with psycopg.connect(
            postgres_dsn(),
            autocommit=autocommit,
            prepare_threshold=None,
            connect_timeout=_connect_timeout_sec(),
        ) as conn:
            _configure_conn(conn)
            yield conn
    finally:
        _conn_slots.release()
