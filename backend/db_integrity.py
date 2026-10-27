"""
Canlı veritabanı öz-denetimi (yalnızca okur): beklenen indeksler, fonksiyonlar ve retention cron'u var mı?

Neden: migration'lar elle uygulanıyorsa (SUPABASE_DATABASE_URL yoksa açılışta "skipped" olur) eksik bir indeks
sessizce veri bozar. Örneğin `daily_events_user_client_event_idx` yoksa olay yazımındaki `ON CONFLICT` hata verir.
Bu modül sorunu `/health` ve günlükte görünür kılar; asla istisna fırlatmaz, bağlanamazsa "unknown" döner.
"""

from __future__ import annotations

import threading
import time
from typing import Optional

from config import get_logger

log = get_logger("db_integrity")

RETENTION_JOB = "rebi-data-retention-daily"

# Eksikse veri yanlış davranır: olay idempotansı, bildirim defteri, vektör araması, retention fonksiyonu.
CRITICAL_INDEXES = {
    "daily_events_user_client_event_idx": "olay yazımı (ON CONFLICT user_id,client_event_id) çalışmaz",
}
CRITICAL_FUNCTIONS = {
    "match_knowledge_chunks": "sohbetin vektör araması çalışmaz",
    "purge_expired_rebi_data": "retention temizliği çalışmaz",
}
# Eksikse yalnızca yavaşlar (kullanıcı sayısı büyüdükçe sorgular tabloyu taramaya başlar).
PERFORMANCE_INDEXES = (
    "daily_events_user_date_idx",
    "daily_events_user_type_time_idx",
    "chat_history_user_seq_idx",
    "assessments_user_created_idx",
    "routines_user_active_idx",
    "daily_logs_user_date_idx",
    "device_tokens_enabled_seen_idx",
    "knowledge_chunks_embedding_idx",
)

_TTL_SECONDS = 600.0
_cache: dict = {"at": 0.0, "value": None}
_lock = threading.Lock()


def _push_sends_unique(indexdefs: dict[str, str]) -> bool:
    """`push_sends` üzerinde (user_id, reminder_id, log_date, slot) benzersiz indeksi (toplu defter yazımı buna dayanır)."""
    for definition in indexdefs.values():
        d = definition.lower()
        if "push_sends" in d and "unique" in d and all(c in d for c in ("user_id", "reminder_id", "log_date", "slot")):
            return True
    return False


def _classify(indexdefs: dict[str, str], functions: set[str]) -> tuple[list[str], list[str]]:
    critical = [f"{name}: {why}" for name, why in CRITICAL_INDEXES.items() if name not in indexdefs]
    critical += [f"{name}(): {why}" for name, why in CRITICAL_FUNCTIONS.items() if name not in functions]
    if not _push_sends_unique(indexdefs):
        critical.append("push_sends(user_id,reminder_id,log_date,slot) benzersiz indeksi: bildirim defteri çalışmaz")
    slow = [name for name in PERFORMANCE_INDEXES if name not in indexdefs]
    return critical, slow


def _retention(cur) -> str:
    """'pg_cron' (iş aktif), 'no_cron_job' (eklenti var, iş yok), 'no_pg_cron' (eklenti yok), 'unknown'."""
    try:
        cur.execute("select to_regclass('cron.job') is not null", prepare=False)
        if not cur.fetchone()[0]:
            return "no_pg_cron"
        cur.execute("select count(*) from cron.job where jobname = %s and active", (RETENTION_JOB,), prepare=False)
        return "pg_cron" if int(cur.fetchone()[0]) > 0 else "no_cron_job"
    except Exception:
        return "unknown"


def inspect_integrity() -> dict:
    """
    {"status": "ok" | "slow" | "degraded" | "unknown", "retention": ..., "missing_critical": [...], "missing_performance": [...]}
    degraded: kritik eksik (veri bozulabilir), slow: yalnızca performans indeksi eksik, unknown: bağlanılamadı.
    """
    try:
        from knowledge.db import pg_conn

        with pg_conn(autocommit=True) as conn:
            with conn.cursor() as cur:
                cur.execute("select indexname, indexdef from pg_indexes where schemaname = 'public'", prepare=False)
                indexdefs = {str(r[0]): str(r[1]) for r in cur.fetchall() or []}
                cur.execute(
                    "select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public'",
                    prepare=False,
                )
                functions = {str(r[0]) for r in cur.fetchall() or []}
                retention = _retention(cur)
    except Exception as e:
        return {"status": "unknown", "retention": "unknown", "missing_critical": [], "missing_performance": [], "reason": type(e).__name__}

    critical, slow = _classify(indexdefs, functions)
    status = "degraded" if critical else ("slow" if slow else "ok")
    return {"status": status, "retention": retention, "missing_critical": critical, "missing_performance": slow}


def get_integrity(force: bool = False) -> dict:
    """Önbellekli sonuç (10 dk): sağlık yoklaması veritabanını yormaz. Sorun varsa günlüğe adlarıyla yazılır."""
    now = time.monotonic()
    with _lock:
        cached = _cache["value"]
        if not force and cached is not None and now - _cache["at"] < _TTL_SECONDS:
            return cached
    result = inspect_integrity()
    with _lock:
        _cache.update(at=now, value=result)
    if result["status"] == "degraded":
        log.error("DB eksik/bozuk (veri güvenliği riski): %s", "; ".join(result["missing_critical"]))
    elif result["status"] == "slow":
        log.warning("DB'de performans indeksleri eksik: %s", ", ".join(result["missing_performance"]))
    if result.get("retention") in ("no_pg_cron", "no_cron_job"):
        log.warning(
            "Retention temizliği zamanlanmamış (%s): süresi dolan veriler silinmez. pg_cron'u açın ya da "
            "RETENTION_PURGE_DAILY=1 verin (docs/DEPLOY.md).", result["retention"],
        )
    return result


_refreshing = False


def refresh_in_background(force: bool = False) -> None:
    """Denetimi arka plan iş parçacığında yeniler (aynı anda en fazla bir tane); çağıranı hiç bekletmez."""
    global _refreshing
    with _lock:
        fresh = _cache["value"] is not None and time.monotonic() - _cache["at"] < _TTL_SECONDS
        if _refreshing or (fresh and not force):
            return
        _refreshing = True

    def run() -> None:
        global _refreshing
        try:
            get_integrity(force=True)
        except Exception as e:  # denetim asla uygulamayı düşürmez
            log.warning("DB öz-denetimi çalışmadı: %s", type(e).__name__)
        finally:
            with _lock:
                _refreshing = False

    threading.Thread(target=run, name="db-integrity", daemon=True).start()


def summary_nowait() -> dict:
    """
    `/health` için: önbellekteki özeti HEMEN döner, bayatsa arka planda yeniler. Veritabanı yavaş ya da kapalıyken
    sağlık yoklaması beklemez (Docker sağlık denetimi zaman aşımına düşüp konteyneri "unhealthy" yapmasın).
    """
    with _lock:
        cached = _cache["value"]
    refresh_in_background()
    if cached is None:
        return {"status": "unknown", "retention": "unknown", "missing_critical": 0, "missing_performance": 0, "pending": True}
    return public_summary(cached)


def public_summary(result: Optional[dict] = None) -> dict:
    """`/health` için herkese açık özet: durum ve sayılar; indeks/fonksiyon adları yalnızca günlükte."""
    r = result if result is not None else get_integrity()
    return {
        "status": r.get("status", "unknown"),
        "retention": r.get("retention", "unknown"),
        "missing_critical": len(r.get("missing_critical") or []),
        "missing_performance": len(r.get("missing_performance") or []),
    }


def reset_cache() -> None:
    """Testler için."""
    global _refreshing
    with _lock:
        _cache.update(at=0.0, value=None)
        _refreshing = False
