"""
IP tabanlı rate limit. REDIS_URL tanımlıysa tüm worker'lar arasında sabit pencere kotası;
yoksa bellek içi kayan pencere (tek süreç için).
"""

from __future__ import annotations

import os
import threading
import time
from collections import defaultdict, deque
from typing import Deque, Dict, Protocol

from fastapi import HTTPException, Request

from redis_client import FallbackProxy, get_redis


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
        self._lock = threading.Lock()

    def allow(self, key: str) -> bool:
        now = time.monotonic()
        with self._lock:
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
        client=None,
    ) -> None:
        self.max_requests = max(1, max_requests)
        self.window_seconds = max(1, int(round(window_seconds)))
        self._prefix = f"rebi:rl:{name}:"
        if client is None:
            import redis

            client = redis.from_url(redis_url, decode_responses=True)
        self._r = client

    def allow(self, key: str) -> bool:
        now = time.time()
        bucket = int(now // self.window_seconds)
        rk = f"{self._prefix}{key}:{bucket}"
        # Tek gidiş-dönüşte artır + süre koy (pencere kovası zamana bağlı olduğundan her çağrıda koymak zararsız).
        pipe = self._r.pipeline()
        pipe.incr(rk)
        pipe.expire(rk, self.window_seconds + 1)
        n = pipe.execute()[0]
        return n <= self.max_requests


def ip_multiplier() -> float:
    """
    IP başına sınırların çarpanı (RATE_LIMIT_IP_MULTIPLIER, varsayılan 4). Türkiye'de mobil operatörler çok sayıda
    kullanıcıyı tek IP'ye toplar (CGNAT): sabah uygulama açılışlarında ya da akşam check-in'lerinde aynı IP'den
    yüzlerce meşru istek gelir ve dar bir IP sınırı onları kilitler. Gerçek koruma kullanıcı başınadır (yapay zekâ
    bütçesi, olay yazımı); IP sınırı yalnızca kaba bir üst sınırdır. 1 = eski, sıkı değerler.
    """
    try:
        return max(1.0, float(os.getenv("RATE_LIMIT_IP_MULTIPLIER") or 4.0))
    except ValueError:
        return 4.0


def _make_limiter(max_requests: int, window_seconds: float, name: str, scale: bool = True) -> SupportsRateLimit:
    """`scale=False`: çarpan uygulanmaz (kullanıcı başına ya da güvenlik amaçlı sıkı sınırlar)."""
    if scale:
        max_requests = max(1, int(round(max_requests * ip_multiplier())))
    url = os.getenv("REDIS_URL", "").strip()
    if url:
        # Redis takılırsa ya da kapanırsa istekler 500 vermesin: süreç içi sınırlayıcıya düşülür.
        return FallbackProxy(
            RedisFixedWindowLimiter(max_requests, window_seconds, url, name, client=get_redis()),
            SlidingWindowLimiter(max_requests, window_seconds),
            f"hız sınırı:{name}",
        )
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
LIMIT_ROUTINE_ACTIVE = _make_limiter(90, 60.0, "routine_active")
LIMIT_TODAY_PLAN = _make_limiter(60, 60.0, "today_plan")
LIMIT_CHAT_ASSESSMENT = _make_limiter(35, 60.0, "chat_assessment")
LIMIT_DAILY_CHECKIN = _make_limiter(12, 3600.0, "daily_checkin")
LIMIT_DAILY_CHECKIN_STATUS = _make_limiter(90, 60.0, "daily_checkin_status")
LIMIT_GENERATE_ROUTINE = _make_limiter(25, 3600.0, "generate_routine")
LIMIT_CHAT = _make_limiter(45, 60.0, "chat")
LIMIT_CHAT_HISTORY = _make_limiter(90, 60.0, "chat_history")
LIMIT_CHAT_HISTORY_CLEAR = _make_limiter(20, 3600.0, "chat_history_clear")
LIMIT_CHAT_HISTORY_IMPORT = _make_limiter(10, 3600.0, "chat_history_import")
LIMIT_USER_DATA = _make_limiter(90, 60.0, "user_data")
LIMIT_USER_PROFILE_WRITE = _make_limiter(30, 3600.0, "user_profile_write")
LIMIT_DEVICE_REGISTER = _make_limiter(120, 60.0, "device_register")
LIMIT_PUSH_DISPATCH = _make_limiter(30, 60.0, "push_dispatch", scale=False)
LIMIT_PUSH_RESPOND = _make_limiter(60, 60.0, "push_respond")
LIMIT_UPLOAD_PHOTO = _make_limiter(40, 3600.0, "upload_photo")
LIMIT_ACCOUNT_DELETE = _make_limiter(3, 3600.0, "account_delete", scale=False)
LIMIT_INTRO_SEEN = _make_limiter(60, 60.0, "intro_seen", scale=False)


def _int_env(name: str, default: int) -> int:
    try:
        return max(1, int(os.getenv(name, "") or default))
    except ValueError:
        return default


# Yapay zekâ uçları için KULLANICI başına bütçe (IP'den bağımsız: IP değiştirerek aşılamaz). Gerçek bir
# sohbet dakikada birkaç mesajı geçmez; sınırsız Plus kullanıcısının tek hesapla model bütçesini tüketmesini
# bu sınır engeller. Sohbet, çeviri, rutin üretimi ve check-in aynı bütçeyi paylaşır.
LIMIT_AI_USER_MINUTE = _make_limiter(_int_env("AI_USER_LIMIT_PER_MINUTE", 20), 60.0, "ai_user_min", scale=False)
LIMIT_AI_USER_HOUR = _make_limiter(_int_env("AI_USER_LIMIT_PER_HOUR", 200), 3600.0, "ai_user_hour", scale=False)

# Olay yazımı için kullanıcı başına üst sınır: IP sınırı gevşetildiği için tek bir yetkili hesabın veritabanını
# olayla doldurması başka türlü engellenmezdi. Gerçek kullanım dakikada onlarcadır; çevrimdışı kuyruğun toplu
# gönderimi bile (en fazla 200 olay) bu sınırın altında kalır.
LIMIT_INGEST_USER = _make_limiter(_int_env("INGEST_USER_LIMIT_PER_MINUTE", 300), 60.0, "ingest_user", scale=False)


def enforce_ingest_user_limit(user_id: str) -> None:
    """Kullanıcı başına olay yazım sınırı; aşılırsa 429 (mobil bunu "yeniden dene" sayıp kuyrukta tutar)."""
    uid = (user_id or "").strip()
    if uid and not LIMIT_INGEST_USER.allow(uid):
        raise HTTPException(
            status_code=429,
            detail="Çok fazla kayıt gönderildi. Kısa süre sonra yeniden denenecek.",
            headers={"Retry-After": "15"},
        )


def enforce_ai_user_limit(user_id: str) -> None:
    """Kullanıcının yapay zekâ bütçesi dolmuşsa 429 yükseltir. Kota ve model çağrısından ÖNCE çağrılır."""
    uid = (user_id or "").strip()
    if not uid:
        return
    # Dakikalık sınır reddederse saatlik sayaç artmaz (reddedilen istek bütçeden düşmesin).
    if not LIMIT_AI_USER_MINUTE.allow(uid) or not LIMIT_AI_USER_HOUR.allow(uid):
        raise HTTPException(
            status_code=429,
            detail="Çok hızlı mesaj gönderiyorsun. Birkaç saniye bekleyip tekrar dene.",
            headers={"Retry-After": "30"},
        )


def rate_limit_backend_label() -> str:
    return "redis" if os.getenv("REDIS_URL", "").strip() else "memory"
