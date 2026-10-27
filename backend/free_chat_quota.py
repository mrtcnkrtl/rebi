"""
Günlük ücretsiz Rebi AI (free_chat) mesaj kotası — kullanıcı bazlı.
REDIS_URL varsa Redis, yoksa tek süreç bellek (geliştirme).

Kota "kontrol et, yanıttan sonra artır" ile değil, çağrıdan ÖNCE atomik olarak rezerve edilir
(`free_chat_reserve`) ve tur başarısız olursa geri verilir (`free_chat_release`). Kontrol ile artırma
arasında boşluk olsaydı, aynı kullanıcının paralel istekleri hepsi "hakkım var" görüp sınırı aşardı.
"""

from __future__ import annotations

import os
import threading
from datetime import date
from typing import Optional, Protocol

from redis_client import FallbackProxy, get_redis


def _limit() -> int:
    try:
        return max(1, int(os.getenv("FREE_CHAT_DAILY_LIMIT", "25")))
    except ValueError:
        return 25


class _DailyQuotaBackend(Protocol):
    def count_today(self, user_id: str) -> int: ...

    def reserve(self, user_id: str, limit: int) -> Optional[str]:
        """Bir hakkı atomik olarak alır; dönen bilet (gün) iade için gerekir. Hak kalmadıysa None, hiçbir şey alınmaz."""
        ...

    def release(self, user_id: str, ticket: str) -> None:
        """Rezerve edilmiş hakkı, rezervasyon gününün sayacına geri verir."""
        ...


class _MemoryDailyQuota:
    def __init__(self) -> None:
        self._day: str = ""
        self._counts: dict[str, int] = {}
        self._lock = threading.Lock()

    def _roll(self) -> None:
        today = date.today().isoformat()
        if self._day != today:
            self._counts.clear()
            self._day = today

    def _key(self, user_id: str) -> str:
        return f"{user_id.strip()}|{date.today().isoformat()}"

    def count_today(self, user_id: str) -> int:
        with self._lock:
            self._roll()
            return self._counts.get(self._key(user_id), 0)

    def reserve(self, user_id: str, limit: int) -> Optional[str]:
        with self._lock:
            self._roll()
            k = self._key(user_id)
            used = self._counts.get(k, 0)
            if used >= limit:
                return None
            self._counts[k] = used + 1
            return self._day

    def release(self, user_id: str, ticket: str) -> None:
        with self._lock:
            self._roll()
            if ticket != self._day:
                return  # gün döndü: eski günün sayacı zaten temizlendi
            k = self._key(user_id)
            if self._counts.get(k, 0) > 0:
                self._counts[k] -= 1


class _RedisDailyQuota:
    def __init__(self, redis_url: str, client=None) -> None:
        if client is None:
            import redis

            client = redis.from_url(redis_url, decode_responses=True)
        self._r = client
        self._prefix = "rebi:freechat:v1:"

    def _key(self, user_id: str, day: str) -> str:
        return f"{self._prefix}{user_id.strip()}:{day}"

    def count_today(self, user_id: str) -> int:
        v = self._r.get(self._key(user_id, date.today().isoformat()))
        return int(v or 0)

    def reserve(self, user_id: str, limit: int) -> Optional[str]:
        # INCR atomiktir: her çağıran kendi sırasını görür. Sınırı aşan, aldığını geri bırakır.
        # Verilen hak sayısı hiçbir an `limit`'i aşmaz (aşan kısa süreli artışlar yalnızca reddedilenlerindir).
        day = date.today().isoformat()
        k = self._key(user_id, day)
        n = int(self._r.incr(k))
        if n == 1:
            self._r.expire(k, 172800)
        if n > limit:
            self._r.decr(k)
            return None
        return day

    def release(self, user_id: str, ticket: str) -> None:
        k = self._key(user_id, ticket)
        if int(self._r.decr(k)) < 0:
            self._r.incr(k)  # sayaç sıfırın altına inmesin


_backend: Optional[_DailyQuotaBackend] = None


def _get_backend() -> _DailyQuotaBackend:
    global _backend
    if _backend is not None:
        return _backend
    url = os.getenv("REDIS_URL", "").strip()
    if url:
        # Redis kapanırsa sohbet durmasın: süreç içi sayaca düşülür (kota o süre boyunca süreç başınadır).
        _backend = FallbackProxy(_RedisDailyQuota(url, client=get_redis()), _MemoryDailyQuota(), "ücretsiz sohbet kotası")
    else:
        _backend = _MemoryDailyQuota()
    return _backend


def free_chat_limit() -> int:
    return _limit()


def free_chat_remaining(user_id: str) -> int:
    used = _get_backend().count_today(user_id)
    return max(0, _limit() - used)


def free_chat_quota_exceeded(user_id: str) -> bool:
    """Yalnızca okuma (göstergeler için). Kotayı harcamak için `free_chat_reserve` kullanılır."""
    return _get_backend().count_today(user_id) >= _limit()


def free_chat_reserve(user_id: str) -> Optional[str]:
    """Bugünün kotasından bir hakkı atomik olarak alır. Dönen bilet iade için gerekir; hak kalmadıysa None."""
    return _get_backend().reserve(user_id, _limit())


def free_chat_release(user_id: str, ticket: str) -> None:
    """Başarısız turun hakkını geri verir."""
    _get_backend().release(user_id, ticket)
