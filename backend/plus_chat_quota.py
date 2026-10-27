"""
Rebi Plus (1000’lik paket) için aylık sohbet mesaj kotası — kullanıcı bazlı, takvim ayı.
Sınırsız Plus bu modülü kullanmaz.

Ücretsiz günlük kotayla aynı model: çağrıdan önce atomik rezerve (`plus_chat_reserve`), başarısız turda
iade (`plus_chat_release`); bkz. free_chat_quota.py.
"""

from __future__ import annotations

import os
import threading
from datetime import date
from typing import Optional, Protocol

from redis_client import FallbackProxy, get_redis


def plus_chat_monthly_cap() -> int:
    try:
        return max(10, int(os.getenv("PLUS_CHAT_MONTHLY_CAP", "1000")))
    except ValueError:
        return 1000


class _MonthlyQuotaBackend(Protocol):
    def count_month(self, user_id: str, month_key: str) -> int: ...

    def reserve(self, user_id: str, month_key: str, limit: int) -> bool:
        """Bir hakkı atomik olarak alır; hak kalmadıysa False, hiçbir şey alınmaz."""
        ...

    def release(self, user_id: str, month_key: str) -> None: ...


class _MemoryMonthlyQuota:
    def __init__(self) -> None:
        self._counts: dict[str, int] = {}
        self._lock = threading.Lock()

    def _key(self, user_id: str, month_key: str) -> str:
        return f"{user_id.strip()}|{month_key}"

    def count_month(self, user_id: str, month_key: str) -> int:
        with self._lock:
            return self._counts.get(self._key(user_id, month_key), 0)

    def reserve(self, user_id: str, month_key: str, limit: int) -> bool:
        k = self._key(user_id, month_key)
        with self._lock:
            used = self._counts.get(k, 0)
            if used >= limit:
                return False
            self._counts[k] = used + 1
            return True

    def release(self, user_id: str, month_key: str) -> None:
        k = self._key(user_id, month_key)
        with self._lock:
            if self._counts.get(k, 0) > 0:
                self._counts[k] -= 1


class _RedisMonthlyQuota:
    def __init__(self, redis_url: str, client=None) -> None:
        if client is None:
            import redis

            client = redis.from_url(redis_url, decode_responses=True)
        self._r = client
        self._prefix = "rebi:pluschat:v1:"

    def _key(self, user_id: str, month_key: str) -> str:
        return f"{self._prefix}{user_id.strip()}:{month_key}"

    def count_month(self, user_id: str, month_key: str) -> int:
        v = self._r.get(self._key(user_id, month_key))
        return int(v or 0)

    def reserve(self, user_id: str, month_key: str, limit: int) -> bool:
        k = self._key(user_id, month_key)
        n = int(self._r.incr(k))
        if n == 1:
            self._r.expire(k, 2678400)  # ~31 gün
        if n > limit:
            self._r.decr(k)
            return False
        return True

    def release(self, user_id: str, month_key: str) -> None:
        k = self._key(user_id, month_key)
        if int(self._r.decr(k)) < 0:
            self._r.incr(k)  # sayaç sıfırın altına inmesin


_backend: Optional[_MonthlyQuotaBackend] = None


def _month_key() -> str:
    return date.today().strftime("%Y-%m")


def _get_backend() -> _MonthlyQuotaBackend:
    global _backend
    if _backend is not None:
        return _backend
    url = os.getenv("REDIS_URL", "").strip()
    if url:
        # Redis kapanırsa sohbet durmasın: süreç içi sayaca düşülür (kota o süre boyunca süreç başınadır).
        _backend = FallbackProxy(_RedisMonthlyQuota(url, client=get_redis()), _MemoryMonthlyQuota(), "Plus aylık kotası")
    else:
        _backend = _MemoryMonthlyQuota()
    return _backend


def plus_chat_remaining(user_id: str) -> int:
    used = _get_backend().count_month(user_id, _month_key())
    return max(0, plus_chat_monthly_cap() - used)


def plus_chat_quota_exceeded(user_id: str) -> bool:
    """Yalnızca okuma (göstergeler için). Kotayı harcamak için `plus_chat_reserve` kullanılır."""
    return _get_backend().count_month(user_id, _month_key()) >= plus_chat_monthly_cap()


def plus_chat_reserve(user_id: str) -> Optional[str]:
    """Bu ayın kotasından bir hakkı atomik olarak alır. Dönen bilet (ay) iade için gerekir; hak kalmadıysa None."""
    month = _month_key()
    return month if _get_backend().reserve(user_id, month, plus_chat_monthly_cap()) else None


def plus_chat_release(user_id: str, ticket: str) -> None:
    """Başarısız turun hakkını, rezerve edildiği ayın sayacına geri verir."""
    _get_backend().release(user_id, ticket)
