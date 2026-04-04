"""
Günlük ücretsiz Rebi AI (free_chat) mesaj kotası — kullanıcı bazlı.
REDIS_URL varsa Redis, yoksa tek süreç bellek (geliştirme).
"""

from __future__ import annotations

import os
from datetime import date
from typing import Optional, Protocol


def _limit() -> int:
    try:
        return max(1, int(os.getenv("FREE_CHAT_DAILY_LIMIT", "25")))
    except ValueError:
        return 25


class _DailyQuotaBackend(Protocol):
    def count_today(self, user_id: str) -> int: ...
    def increment_today(self, user_id: str) -> int: ...


class _MemoryDailyQuota:
    def __init__(self) -> None:
        self._day: str = ""
        self._counts: dict[str, int] = {}

    def _roll(self) -> None:
        today = date.today().isoformat()
        if self._day != today:
            self._counts.clear()
            self._day = today

    def _key(self, user_id: str) -> str:
        return f"{user_id.strip()}|{date.today().isoformat()}"

    def count_today(self, user_id: str) -> int:
        self._roll()
        return self._counts.get(self._key(user_id), 0)

    def increment_today(self, user_id: str) -> int:
        self._roll()
        k = self._key(user_id)
        self._counts[k] = self._counts.get(k, 0) + 1
        return self._counts[k]


class _RedisDailyQuota:
    def __init__(self, redis_url: str) -> None:
        import redis

        self._r = redis.from_url(redis_url, decode_responses=True)
        self._prefix = "rebi:freechat:v1:"

    def _key(self, user_id: str) -> str:
        return f"{self._prefix}{user_id.strip()}:{date.today().isoformat()}"

    def count_today(self, user_id: str) -> int:
        v = self._r.get(self._key(user_id))
        return int(v or 0)

    def increment_today(self, user_id: str) -> int:
        k = self._key(user_id)
        n = self._r.incr(k)
        if n == 1:
            self._r.expire(k, 172800)
        return int(n)


_backend: Optional[_DailyQuotaBackend] = None


def _get_backend() -> _DailyQuotaBackend:
    global _backend
    if _backend is not None:
        return _backend
    url = os.getenv("REDIS_URL", "").strip()
    if url:
        _backend = _RedisDailyQuota(url)
    else:
        _backend = _MemoryDailyQuota()
    return _backend


def free_chat_limit() -> int:
    return _limit()


def free_chat_remaining(user_id: str) -> int:
    used = _get_backend().count_today(user_id)
    return max(0, _limit() - used)


def free_chat_quota_exceeded(user_id: str) -> bool:
    return _get_backend().count_today(user_id) >= _limit()


def free_chat_record_successful_turn(user_id: str) -> int:
    """Başarılı bir free_chat yanıtından sonra çağır; yeni toplam sayıyı döner."""
    return _get_backend().increment_today(user_id)
