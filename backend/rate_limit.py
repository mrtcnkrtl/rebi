"""
IP tabanlı rate limit. REDIS_URL tanımlıysa tüm worker'lar arasında sabit pencere kotası;
yoksa bellek içi kayan pencere (tek süreç için).
"""

from __future__ import annotations

import os
import time
from collections import defaultdict, deque
from typing import Deque, Dict, Protocol

from fastapi import HTTPException, Request


def get_client_ip(request: Request) -> str:
    forwarded = request.headers.get("X-Forwarded-For") or request.headers.get("x-forwarded-for")
    if forwarded:
        return forwarded.split(",")[0].strip() or "unknown"
    if request.client:
        return request.client.host
    return "unknown"


class SupportsRateLimit(Protocol):
    def allow(self, key: str) -> bool: ...


class SlidingWindowLimiter:
    """Tek süreç: monotonic kayan pencere."""

    def __init__(self, max_requests: int, window_seconds: float) -> None:
        self.max_requests = max(1, max_requests)
        self.window_seconds = float(window_seconds)
        self._hits: Dict[str, Deque[float]] = defaultdict(deque)

    def allow(self, key: str) -> bool:
        now = time.monotonic()
        dq = self._hits[key]
        cutoff = now - self.window_seconds
        while dq and dq[0] < cutoff:
            dq.popleft()
        if len(dq) >= self.max_requests:
            return False
        dq.append(now)
        return True


class RedisFixedWindowLimiter:
    """Çok süreç: Redis INCR ile sabit zaman dilimi (epoch / pencere)."""

    def __init__(
        self,
        max_requests: int,
        window_seconds: float,
        redis_url: str,
        name: str,
    ) -> None:
        import redis

        self.max_requests = max(1, max_requests)
        self.window_seconds = max(1, int(round(window_seconds)))
        self._prefix = f"rebi:rl:{name}:"
        self._r = redis.from_url(redis_url, decode_responses=True)

    def allow(self, key: str) -> bool:
        now = time.time()
        bucket = int(now // self.window_seconds)
        rk = f"{self._prefix}{key}:{bucket}"
        n = self._r.incr(rk)
        if n == 1:
            self._r.expire(rk, self.window_seconds + 1)
        return n <= self.max_requests


def _make_limiter(max_requests: int, window_seconds: float, name: str) -> SupportsRateLimit:
    url = os.getenv("REDIS_URL", "").strip()
    if url:
        return RedisFixedWindowLimiter(max_requests, window_seconds, url, name)
    return SlidingWindowLimiter(max_requests, window_seconds)


def rate_limit_dependency(limiter: SupportsRateLimit):
    def _check(request: Request) -> None:
        ip = get_client_ip(request)
        if not limiter.allow(ip):
            raise HTTPException(
                status_code=429,
                detail="Çok fazla istek. Lütfen kısa süre sonra tekrar deneyin.",
            )

    return _check


LIMIT_DAILY_TRACKING_INGEST = _make_limiter(120, 60.0, "daily_ingest")
LIMIT_DAILY_TRACKING_TODAY = _make_limiter(90, 60.0, "daily_today")
LIMIT_CHAT_ASSESSMENT = _make_limiter(35, 60.0, "chat_assessment")
LIMIT_DAILY_CHECKIN = _make_limiter(12, 3600.0, "daily_checkin")
LIMIT_DAILY_CHECKIN_STATUS = _make_limiter(90, 60.0, "daily_checkin_status")
LIMIT_GENERATE_ROUTINE = _make_limiter(25, 3600.0, "generate_routine")
LIMIT_CHAT = _make_limiter(45, 60.0, "chat")
LIMIT_UPLOAD_PHOTO = _make_limiter(40, 3600.0, "upload_photo")
LIMIT_ACCOUNT_DELETE = _make_limiter(3, 3600.0, "account_delete")


def rate_limit_backend_label() -> str:
    return "redis" if os.getenv("REDIS_URL", "").strip() else "memory"
