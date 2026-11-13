"""
Paylaşılan Redis istemcisi ve "Redis kapanırsa uygulama kapanmasın" sarmalayıcısı.

Redis yalnızca yardımcı bir sistemdir (hız sınırı, sohbet kotası sayaçları). Erişilemezse API'nin tamamının
500 vermesi yerine istek, süreç içi (bellek) yedeğe düşer: sayaçlar o süre boyunca süreç başınadır ve süreç
yeniden başlayınca sıfırlanır; yani kota/hız sınırı gevşer ama kullanıcılar sohbet etmeye devam eder.

Zaman aşımsız bir Redis çağrısı, Redis takıldığında iş parçacığını sonsuza dek tutar; bu yüzden bağlantı ve
okuma zaman aşımları kısadır (varsayılan 1 sn).
"""

from __future__ import annotations

import os
import threading
import time
from typing import Any, Optional

from config import get_logger

log = get_logger("redis_client")

_client: Any = None
_client_url = ""
_lock = threading.Lock()


def redis_url() -> str:
    return os.getenv("REDIS_URL", "").strip()


def _timeout_seconds() -> float:
    try:
        return max(0.1, float(os.getenv("REDIS_TIMEOUT_SECONDS") or 1.0))
    except ValueError:
        return 1.0


def get_redis():
    """Paylaşılan istemci; REDIS_URL tanımlı değilse None. Bağlantı havuzu iş parçacıkları arasında paylaşılır."""
    global _client, _client_url
    url = redis_url()
    if not url:
        return None
    if _client is None or _client_url != url:
        with _lock:
            if _client is None or _client_url != url:
                import redis

                timeout = _timeout_seconds()
                _client = redis.from_url(
                    url,
                    decode_responses=True,
                    socket_connect_timeout=timeout,
                    socket_timeout=timeout,
                    health_check_interval=30,
                )
                _client_url = url
    return _client


def reset_redis() -> None:
    """Testler için: bir sonraki çağrıda istemci yeniden kurulur."""
    global _client, _client_url
    with _lock:
        _client, _client_url = None, ""
    _status_cache.update(at=0.0, value="off")


class FallbackProxy:
    """
    `primary` (Redis arka ucu) hata verirse aynı yöntemi `fallback` (bellek arka ucu) üzerinde çağırır.
    Hata günlüğü dakikada bir yazılır: Redis kapalıyken her istek günlüğü doldurmasın.
    """

    _LOG_EVERY_SECONDS = 60.0

    def __init__(self, primary, fallback, name: str) -> None:
        self._primary = primary
        self._fallback = fallback
        self._name = name
        self._last_log = 0.0

    def __getattr__(self, method: str):
        def call(*args, **kwargs):
            try:
                return getattr(self._primary, method)(*args, **kwargs)
            except Exception as e:
                self._note(e)
                return getattr(self._fallback, method)(*args, **kwargs)

        return call

    def _note(self, error: Exception) -> None:
        now = time.monotonic()
        if now - self._last_log >= self._LOG_EVERY_SECONDS:
            self._last_log = now
            log.warning("Redis kullanılamıyor (%s), bellek yedeğine düşüldü: %s", self._name, type(error).__name__)


# ── Sağlık durumu ────────────────────────────────────────────────────────────────────────────────

_STATUS_TTL_SECONDS = 10.0
_status_cache: dict = {"at": 0.0, "value": "off"}


def redis_status() -> str:
    """'off' (tanımlı değil), 'ok' ya da 'down'. Sonuç 10 sn önbelleklenir: sağlık yoklaması Redis'i dövmesin."""
    if not redis_url():
        return "off"
    now = time.monotonic()
    if now - _status_cache["at"] < _STATUS_TTL_SECONDS and _status_cache["at"] > 0:
        return _status_cache["value"]
    try:
        value: Optional[str] = "ok" if get_redis().ping() else "down"
    except Exception:
        value = "down"
    _status_cache.update(at=now, value=value)
    return value
