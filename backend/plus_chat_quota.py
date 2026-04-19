"""
Rebi Plus (1000’lik paket) için aylık sohbet mesaj kotası — kullanıcı bazlı, takvim ayı.
Sınırsız Plus bu modülü kullanmaz.
"""

from __future__ import annotations

import os
from datetime import date
from typing import Optional, Protocol


def plus_chat_monthly_cap() -> int:
    try:
        return max(10, int(os.getenv("PLUS_CHAT_MONTHLY_CAP", "1000")))
    except ValueError:
        return 1000


class _MonthlyQuotaBackend(Protocol):
    def count_month(self, user_id: str, month_key: str) -> int: ...
    def increment_month(self, user_id: str, month_key: str) -> int: ...


class _MemoryMonthlyQuota:
    def __init__(self) -> None:
        self._counts: dict[str, int] = {}

    def _key(self, user_id: str, month_key: str) -> str:
        return f"{user_id.strip()}|{month_key}"

    def count_month(self, user_id: str, month_key: str) -> int:
        return self._counts.get(self._key(user_id, month_key), 0)

    def increment_month(self, user_id: str, month_key: str) -> int:
        k = self._key(user_id, month_key)
        self._counts[k] = self._counts.get(k, 0) + 1
        return self._counts[k]


class _RedisMonthlyQuota:
    def __init__(self, redis_url: str) -> None:
        import redis

        self._r = redis.from_url(redis_url, decode_responses=True)
        self._prefix = "rebi:pluschat:v1:"

    def _key(self, user_id: str, month_key: str) -> str:
        return f"{self._prefix}{user_id.strip()}:{month_key}"

    def count_month(self, user_id: str, month_key: str) -> int:
        v = self._r.get(self._key(user_id, month_key))
        return int(v or 0)

    def increment_month(self, user_id: str, month_key: str) -> int:
        k = self._key(user_id, month_key)
        n = self._r.incr(k)
        if n == 1:
            self._r.expire(k, 2678400)  # ~31 gün
        return int(n)


_backend: Optional[_MonthlyQuotaBackend] = None


def _month_key() -> str:
    return date.today().strftime("%Y-%m")


def _get_backend() -> _MonthlyQuotaBackend:
    global _backend
    if _backend is not None:
        return _backend
    url = os.getenv("REDIS_URL", "").strip()
    if url:
        _backend = _RedisMonthlyQuota(url)
    else:
        _backend = _MemoryMonthlyQuota()
    return _backend


def plus_chat_remaining(user_id: str) -> int:
    used = _get_backend().count_month(user_id, _month_key())
    return max(0, plus_chat_monthly_cap() - used)


def plus_chat_quota_exceeded(user_id: str) -> bool:
    return _get_backend().count_month(user_id, _month_key()) >= plus_chat_monthly_cap()


def plus_chat_record_successful_turn(user_id: str) -> int:
    return _get_backend().increment_month(user_id, _month_key())
