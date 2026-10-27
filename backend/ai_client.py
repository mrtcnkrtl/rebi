"""
Gemini istemcisi: paylaşılan örnek, zaman aşımı ve token kullanım günlüğü.

- İstemci süreç başına bir kez kurulur (her çağrıda yeni istemci = yeni bağlantı).
- Zaman aşımı olmayan bir çağrı, takıldığında isteği (ve bir iş parçacığını) dakikalarca tutar.
  Varsayılan 20 sn; toplu embedding (ingest) için ayrı, uzun zaman aşımlı bir istemci var.
- Her üretim çağrısı bir `gemini_usage` satırı yazar: etiket, model, giriş/çıkış/düşünme token'ı,
  süre ve tahmini maliyet. Böylece gerçek harcama günlüklerden ölçülür (tahmin değil).
"""

from __future__ import annotations

import os
import threading
from datetime import date
from typing import Optional

from config import GEMINI_API_KEY, get_logger
from redis_client import FallbackProxy, get_redis, redis_url

log = get_logger("ai_client")


def _float_env(name: str, default: float) -> float:
    try:
        return float(os.getenv(name, "") or default)
    except ValueError:
        return default


# Yanıt üretimi: kullanıcı bekliyor, uzun sürerse zarif yedeğe (KB özeti) düşmek daha iyi.
REQUEST_TIMEOUT_SECONDS = max(3.0, _float_env("GEMINI_TIMEOUT_SECONDS", 20.0))
# Toplu embedding (ingest betikleri): büyük gruplar daha uzun sürebilir.
BATCH_TIMEOUT_SECONDS = max(REQUEST_TIMEOUT_SECONDS, _float_env("GEMINI_BATCH_TIMEOUT_SECONDS", 120.0))

# Tahmini maliyet için birim fiyatlar (USD / 1M token). Fiyat değişirse ortam değişkeniyle güncellenir;
# varsayılanlar gemini-2.5-flash standart ücretli katmanıdır.
PRICE_INPUT_PER_M = _float_env("GEMINI_PRICE_INPUT_PER_M", 0.30)
PRICE_OUTPUT_PER_M = _float_env("GEMINI_PRICE_OUTPUT_PER_M", 2.50)

_clients: dict[float, object] = {}
_lock = threading.Lock()


def _build(timeout_seconds: float):
    if not GEMINI_API_KEY:
        return None
    from google import genai
    from google.genai import types

    return genai.Client(
        api_key=GEMINI_API_KEY,
        http_options=types.HttpOptions(timeout=int(timeout_seconds * 1000)),
    )


def get_client(batch: bool = False):
    """Paylaşılan istemci (GEMINI_API_KEY yoksa None). `batch=True` uzun zaman aşımlı olanı verir."""
    timeout = BATCH_TIMEOUT_SECONDS if batch else REQUEST_TIMEOUT_SECONDS
    client = _clients.get(timeout)
    if client is None and GEMINI_API_KEY:
        with _lock:
            client = _clients.get(timeout)
            if client is None:
                client = _build(timeout)
                _clients[timeout] = client
    return client


# ── Günlük bütçe kesicisi ────────────────────────────────────────────────────────────────────────
# GEMINI_DAILY_BUDGET_USD tanımlıysa (0 / boş = kapalı), tahmini günlük harcama bu değere ulaşınca yeni Gemini
# çağrıları yapılmaz. Sohbet çökmez: çağıranlar zaten model hatasında bilgi tabanı özetine düşer. Böylece
# kullanıcı sayısı, sahte hesaplar ya da bir hata ne olursa olsun günlük fatura üst sınırı olur.
# Harcama Redis'te tutulur (varsa; çok işçi/yeniden başlatma boyunca sürer), yoksa süreç belleğinde.


class GeminiBudgetExceeded(Exception):
    """Günlük yapay zekâ bütçesi doldu; çağrı yapılmadı."""


def daily_budget_usd() -> float:
    try:
        return max(0.0, float(os.getenv("GEMINI_DAILY_BUDGET_USD") or 0))
    except ValueError:
        return 0.0


class _SpendMemory:
    def __init__(self) -> None:
        self._micro: dict[str, int] = {}
        self._lock = threading.Lock()

    def add(self, day: str, micro: int) -> int:
        with self._lock:
            self._micro = {day: self._micro.get(day, 0) + micro}  # yalnızca bugünün sayacı tutulur
            return self._micro[day]

    def get(self, day: str) -> int:
        with self._lock:
            return self._micro.get(day, 0)


class _SpendRedis:
    def __init__(self, client) -> None:
        self._r = client

    def add(self, day: str, micro: int) -> int:
        key = f"rebi:gemini:spend:{day}"
        total = int(self._r.incrby(key, micro))
        if total == micro:
            self._r.expire(key, 172800)
        return total

    def get(self, day: str) -> int:
        return int(self._r.get(f"rebi:gemini:spend:{day}") or 0)


_spend_backend = None
_spend_lock = threading.Lock()
_warned: dict[str, set] = {}


def _spend():
    global _spend_backend
    if _spend_backend is None:
        with _spend_lock:
            if _spend_backend is None:
                memory = _SpendMemory()
                _spend_backend = FallbackProxy(_SpendRedis(get_redis()), memory, "Gemini günlük harcama") if redis_url() else memory
    return _spend_backend


def spent_today_usd() -> float:
    return _spend().get(date.today().isoformat()) / 1_000_000


def check_budget() -> None:
    """Bütçe tanımlı ve dolmuşsa GeminiBudgetExceeded yükseltir. Okuma hata verirse çağrıya izin verilir (bütçe yardımcıdır)."""
    limit = daily_budget_usd()
    if limit <= 0:
        return
    try:
        spent = spent_today_usd()
    except Exception:
        return
    if spent >= limit:
        _warn_once("limit", spent, limit)
        raise GeminiBudgetExceeded(f"günlük yapay zekâ bütçesi doldu ({spent:.2f}/{limit:.2f} USD)")


def _warn_once(kind: str, spent: float, limit: float) -> None:
    day = date.today().isoformat()
    done = _warned.setdefault(day, set())
    if kind in done:
        return
    done.add(kind)
    for old in [d for d in _warned if d != day]:
        _warned.pop(old, None)
    if kind == "limit":
        log.error("gemini_budget DOLDU spent_usd=%.2f limit_usd=%.2f: yeni Gemini çağrıları bugün durduruldu", spent, limit)
    else:
        log.warning("gemini_budget %%80 spent_usd=%.2f limit_usd=%.2f", spent, limit)


def _add_spend(cost_usd: float) -> None:
    """Çağrı maliyetini günlük sayaca ekler (hata verirse yok sayılır) ve %80 eşiğinde uyarır."""
    limit = daily_budget_usd()
    if limit <= 0 or cost_usd <= 0:
        return
    try:
        total = _spend().add(date.today().isoformat(), int(round(cost_usd * 1_000_000))) / 1_000_000
    except Exception:
        return
    if total >= limit * 0.8:
        _warn_once("80", total, limit)


def reset_budget() -> None:
    """Testler için."""
    global _spend_backend
    with _spend_lock:
        _spend_backend = None
    _warned.clear()


# ── Kullanım günlüğü ─────────────────────────────────────────────────────────────────────────────

_totals: dict[str, dict[str, float]] = {}
_totals_lock = threading.Lock()


def _int(value) -> int:
    try:
        return int(value or 0)
    except (TypeError, ValueError):
        return 0


def estimate_cost_usd(tokens_in: int, tokens_out: int) -> float:
    return (tokens_in * PRICE_INPUT_PER_M + tokens_out * PRICE_OUTPUT_PER_M) / 1_000_000


def record_usage(label: str, model: Optional[str], response, elapsed_seconds: float) -> dict:
    """
    Bir üretim yanıtının token kullanımını günlüğe yazar ve toplamlara ekler.
    `usage_metadata` yoksa (sahte/bozuk yanıt) sıfırlarla yazar; çağıranı asla düşürmez.
    Düşünme token'ları çıkış fiyatından faturalandığı için çıkışa dahil edilir.
    """
    meta = getattr(response, "usage_metadata", None)
    tokens_in = _int(getattr(meta, "prompt_token_count", 0))
    tokens_out = _int(getattr(meta, "candidates_token_count", 0))
    thoughts = _int(getattr(meta, "thoughts_token_count", 0))
    cost = estimate_cost_usd(tokens_in, tokens_out + thoughts)
    _add_spend(cost)
    with _totals_lock:
        t = _totals.setdefault(label, {"calls": 0, "errors": 0, "in": 0, "out": 0, "cost_usd": 0.0})
        t["calls"] += 1
        t["in"] += tokens_in
        t["out"] += tokens_out + thoughts
        t["cost_usd"] += cost
    log.info(
        "gemini_usage label=%s model=%s in=%d out=%d thoughts=%d ms=%d cost_usd=%.6f",
        label, model or "-", tokens_in, tokens_out, thoughts, int(elapsed_seconds * 1000), cost,
    )
    return {"in": tokens_in, "out": tokens_out, "thoughts": thoughts, "cost_usd": cost}


def record_error(label: str, error: Exception, elapsed_seconds: float) -> None:
    """Başarısız/zaman aşımına uğrayan çağrıyı günlüğe yazar (hata türü; metin değil)."""
    with _totals_lock:
        t = _totals.setdefault(label, {"calls": 0, "errors": 0, "in": 0, "out": 0, "cost_usd": 0.0})
        t["errors"] += 1
    log.warning("gemini_error label=%s kind=%s ms=%d", label, type(error).__name__, int(elapsed_seconds * 1000))


def record_embedding(label: str, texts: list[str], elapsed_seconds: float) -> None:
    """Embedding yanıtı token sayısı vermez; karakter sayısı ve süre yazılır (fiyat ihmal edilebilir düzeyde)."""
    chars = sum(len(t or "") for t in texts)
    with _totals_lock:
        t = _totals.setdefault(label, {"calls": 0, "errors": 0, "in": 0, "out": 0, "cost_usd": 0.0})
        t["calls"] += 1
        t["in"] += chars // 3  # kabaca: Türkçe için ~3 karakter / token
    log.info("gemini_embed label=%s texts=%d chars=%d ms=%d", label, len(texts), chars, int(elapsed_seconds * 1000))


def usage_snapshot() -> dict[str, dict[str, float]]:
    """Süreç başlangıcından beri etiket başına toplamlar (testler ve ileride bir yönetici ucu için)."""
    with _totals_lock:
        return {k: dict(v) for k, v in _totals.items()}


def reset_usage() -> None:
    with _totals_lock:
        _totals.clear()
