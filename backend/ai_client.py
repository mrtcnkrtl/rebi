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
from typing import Optional

from config import GEMINI_API_KEY, get_logger

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
