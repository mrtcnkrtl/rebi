"""Sohbet kotası: çağrıdan önce atomik rezerve, başarısız turda iade (ücretsiz günlük + Plus aylık; bellek + Redis)."""

from __future__ import annotations

import asyncio
import logging
import threading
from collections import defaultdict, deque
from datetime import date as real_date

import httpx
import jwt
import pytest

import chat_quota
import free_chat_quota
import main
import plus_chat_quota
import rag_service
import rate_limit
from chat_quota import QuotaHold, reserve_chat_turn
from free_chat_quota import _MemoryDailyQuota, _RedisDailyQuota
from plus_chat_quota import _MemoryMonthlyQuota, _RedisMonthlyQuota

USER_ID = "99999999-9999-4999-8999-999999999999"
SECRET = "test-secret-at-least-32-bytes-long"


class FakeRedis:
    """Redis'in INCR/DECR/EXPIRE/GET'inin atomikliğini taklit eder (gerçek Redis'te bu işlemler atomiktir)."""

    def __init__(self):
        self.data: dict[str, int] = {}
        self.ttl: dict[str, int] = {}
        self._lock = threading.Lock()

    def incr(self, key):
        with self._lock:
            self.data[key] = int(self.data.get(key, 0)) + 1
            return self.data[key]

    def decr(self, key):
        with self._lock:
            self.data[key] = int(self.data.get(key, 0)) - 1
            return self.data[key]

    def get(self, key):
        value = self.data.get(key)
        return None if value is None else str(value)

    def expire(self, key, seconds):
        self.ttl[key] = seconds


@pytest.fixture
def redis_daily(monkeypatch):
    import redis

    fake = FakeRedis()
    monkeypatch.setattr(redis, "from_url", lambda *a, **k: fake)
    return _RedisDailyQuota("redis://x"), fake


@pytest.fixture
def redis_monthly(monkeypatch):
    import redis

    fake = FakeRedis()
    monkeypatch.setattr(redis, "from_url", lambda *a, **k: fake)
    return _RedisMonthlyQuota("redis://x"), fake


def _hammer(fn, workers=16, per_worker=40):
    """`fn()` bir hak almaya çalışır; kaç tanesinin başarılı olduğunu döner."""
    results: list = []

    def run():
        for _ in range(per_worker):
            results.append(fn())

    threads = [threading.Thread(target=run) for _ in range(workers)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    return results


# ── Ücretsiz günlük: bellek ──────────────────────────────────────────────────────────────────────

def test_daily_memory_reserves_up_to_the_limit_and_no_further():
    q = _MemoryDailyQuota()
    tickets = [q.reserve("u", 3) for _ in range(5)]
    assert [t is not None for t in tickets] == [True, True, True, False, False]
    assert q.count_today("u") == 3, "reddedilen istekler hiçbir şey harcamaz"


def test_daily_memory_release_gives_one_back_and_never_goes_negative():
    q = _MemoryDailyQuota()
    ticket = q.reserve("u", 3)
    q.release("u", ticket)
    assert q.count_today("u") == 0
    q.release("u", ticket)  # fazladan iade
    assert q.count_today("u") == 0


def test_daily_memory_is_exact_under_parallel_requests():
    q = _MemoryDailyQuota()
    results = _hammer(lambda: q.reserve("u", 25))
    assert sum(r is not None for r in results) == 25
    assert q.count_today("u") == 25


def test_daily_memory_users_are_independent():
    q = _MemoryDailyQuota()
    assert q.reserve("a", 1) and q.reserve("b", 1)
    assert q.reserve("a", 1) is None


def test_daily_memory_release_after_midnight_does_not_touch_the_new_day(monkeypatch):
    days = ["2026-10-26"]

    class _Date(real_date):
        @classmethod
        def today(cls):
            return real_date.fromisoformat(days[0])

    monkeypatch.setattr(free_chat_quota, "date", _Date)
    q = _MemoryDailyQuota()
    old_ticket = q.reserve("u", 5)
    days[0] = "2026-10-27"
    assert q.reserve("u", 5) is not None  # yeni günün ilk hakkı
    q.release("u", old_ticket)  # dünün bileti: bugünün sayacına dokunmaz
    assert q.count_today("u") == 1


# ── Ücretsiz günlük: Redis ───────────────────────────────────────────────────────────────────────

def test_daily_redis_never_grants_more_than_the_limit_under_parallel_requests(redis_daily):
    q, fake = redis_daily
    results = _hammer(lambda: q.reserve("u", 25))
    assert sum(r is not None for r in results) == 25
    assert q.count_today("u") == 25, "aşan INCR'ler geri alınır; sayaç sınırda kalır"
    assert list(fake.data.values()) == [25]


def test_daily_redis_sets_expiry_on_first_reserve_and_release_restores(redis_daily):
    q, fake = redis_daily
    ticket = q.reserve("u", 3)
    key = next(iter(fake.data))
    assert fake.ttl[key] == 172800
    q.release("u", ticket)
    assert q.count_today("u") == 0
    q.release("u", ticket)  # sayaç sıfırın altına inmez
    assert q.count_today("u") == 0 and fake.data[key] == 0


def test_daily_redis_release_targets_the_reservation_day(redis_daily):
    q, fake = redis_daily
    q.reserve("u", 5)
    q.release("u", "2000-01-01")  # başka günün bileti: bugünün sayacı korunur
    assert q.count_today("u") == 1


# ── Plus aylık ───────────────────────────────────────────────────────────────────────────────────

def test_monthly_memory_reserve_release_and_parallel_exactness():
    q = _MemoryMonthlyQuota()
    assert [q.reserve("u", "2026-10", 2) for _ in range(4)] == [True, True, False, False]
    q.release("u", "2026-10")
    assert q.count_month("u", "2026-10") == 1
    q.release("u", "2026-10")
    q.release("u", "2026-10")
    assert q.count_month("u", "2026-10") == 0

    results = _hammer(lambda: q.reserve("p", "2026-10", 100))
    assert sum(results) == 100 and q.count_month("p", "2026-10") == 100


def test_monthly_redis_never_grants_more_than_the_cap(redis_monthly):
    q, fake = redis_monthly
    results = _hammer(lambda: q.reserve("u", "2026-10", 100))
    assert sum(results) == 100
    assert q.count_month("u", "2026-10") == 100
    assert fake.ttl[next(iter(fake.data))] == 2678400
    q.release("u", "2026-10")
    assert q.count_month("u", "2026-10") == 99


def test_monthly_release_goes_to_the_month_it_was_reserved_in(monkeypatch):
    months = ["2026-10"]
    monkeypatch.setattr(plus_chat_quota, "_month_key", lambda: months[0])
    monkeypatch.setattr(plus_chat_quota, "_backend", _MemoryMonthlyQuota())
    monkeypatch.setenv("PLUS_CHAT_MONTHLY_CAP", "10")

    ticket = plus_chat_quota.plus_chat_reserve("u")
    assert ticket == "2026-10"
    months[0] = "2026-11"
    assert plus_chat_quota.plus_chat_reserve("u") == "2026-11"
    plus_chat_quota.plus_chat_release("u", ticket)  # ekim hakkı ekime iade edilir
    assert plus_chat_quota._backend.count_month("u", "2026-10") == 0
    assert plus_chat_quota._backend.count_month("u", "2026-11") == 1


def test_public_helpers_report_remaining_and_exceeded(monkeypatch):
    monkeypatch.setattr(free_chat_quota, "_backend", _MemoryDailyQuota())
    monkeypatch.setenv("FREE_CHAT_DAILY_LIMIT", "2")
    assert free_chat_quota.free_chat_remaining("u") == 2
    t = free_chat_quota.free_chat_reserve("u")
    assert free_chat_quota.free_chat_remaining("u") == 1 and not free_chat_quota.free_chat_quota_exceeded("u")
    free_chat_quota.free_chat_reserve("u")
    assert free_chat_quota.free_chat_quota_exceeded("u")
    assert free_chat_quota.free_chat_reserve("u") is None
    free_chat_quota.free_chat_release("u", t)
    assert free_chat_quota.free_chat_remaining("u") == 1


# ── Rezervasyon arayüzü ──────────────────────────────────────────────────────────────────────────

@pytest.fixture
def fresh_backends(monkeypatch):
    monkeypatch.setattr(free_chat_quota, "_backend", _MemoryDailyQuota())
    monkeypatch.setattr(plus_chat_quota, "_backend", _MemoryMonthlyQuota())
    monkeypatch.setenv("FREE_CHAT_DAILY_LIMIT", "2")
    monkeypatch.setenv("PLUS_CHAT_MONTHLY_CAP", "10")


def test_reserve_chat_turn_routes_by_plan(fresh_backends):
    free = reserve_chat_turn("u", plus=False, plus_capped=False)
    assert free.hold is not None and free.exceeded is None
    assert free_chat_quota.free_chat_remaining("u") == 1

    capped = reserve_chat_turn("c", plus=True, plus_capped=True)
    assert capped.hold is not None
    assert plus_chat_quota.plus_chat_remaining("c") == 9

    unlimited = reserve_chat_turn("p", plus=True, plus_capped=False)
    assert unlimited.hold is None and unlimited.exceeded is None


def test_reserve_chat_turn_reports_exhaustion_without_spending(fresh_backends):
    reserve_chat_turn("u", plus=False, plus_capped=False)
    reserve_chat_turn("u", plus=False, plus_capped=False)
    third = reserve_chat_turn("u", plus=False, plus_capped=False)
    assert third.exceeded == "free_daily" and third.hold is None
    assert free_chat_quota.free_chat_remaining("u") == 0

    for _ in range(10):
        reserve_chat_turn("c", plus=True, plus_capped=True)
    assert reserve_chat_turn("c", plus=True, plus_capped=True).exceeded == "plus_monthly"
    assert plus_chat_quota.plus_chat_remaining("c") == 0


def test_hold_release_is_idempotent(fresh_backends):
    hold = reserve_chat_turn("u", plus=False, plus_capped=False).hold
    hold.release()
    hold.release()
    assert hold.released
    assert free_chat_quota.free_chat_remaining("u") == 2, "iki kez çağrılsa da bir hak iade edilir"


def test_hold_as_context_manager_refunds_only_on_exception(fresh_backends):
    kept = reserve_chat_turn("u", plus=False, plus_capped=False).hold
    with kept:
        pass
    assert free_chat_quota.free_chat_remaining("u") == 1, "başarıyla biten tur hakkı tüketir"

    failed = reserve_chat_turn("u", plus=False, plus_capped=False).hold
    with pytest.raises(RuntimeError):
        with failed:
            raise RuntimeError("model çöktü")
    assert free_chat_quota.free_chat_remaining("u") == 1, "istisnada hak iade edilir"


def test_a_failing_refund_never_masks_the_original_error(caplog):
    def broken():
        raise ConnectionError("redis yok")

    hold = QuotaHold(broken)
    with caplog.at_level(logging.ERROR, logger="chat_quota"):
        with pytest.raises(ValueError):
            with hold:
                raise ValueError("asıl hata")
    assert any("Kota iadesi yapılamadı" in r.getMessage() for r in caplog.records)


# ── Uç noktalar ──────────────────────────────────────────────────────────────────────────────────

@pytest.fixture
def api(monkeypatch, fresh_backends):
    """JWT açık, kota arka uçları taze, hız sınırı sıfır; model ve DB sahte."""
    monkeypatch.setenv("SUPABASE_JWT_SECRET", SECRET)
    monkeypatch.delenv("API_ALLOW_INSECURE_AUTH", raising=False)
    monkeypatch.setenv("FREE_CHAT_DAILY_LIMIT", "3")
    monkeypatch.setattr(rate_limit.LIMIT_CHAT_ASSESSMENT, "_hits", defaultdict(deque))
    monkeypatch.setattr(main, "get_supabase", lambda: None)
    monkeypatch.setattr(main, "_require_privacy_permission", lambda *a, **k: None)
    monkeypatch.setattr(main, "_persist_chat_turn", lambda *a, **k: None)
    token = jwt.encode({"sub": USER_ID, "aud": "authenticated"}, SECRET, algorithm="HS256")
    return {"Authorization": f"Bearer {token}"}


def _post_general(client, headers, msg="SPF?"):
    return client.post("/chat_general", json={"user_id": USER_ID, "message": msg, "history": []}, headers=headers)


def test_free_user_successful_turns_consume_quota_and_report_it(monkeypatch, client, api):
    async def ok(**kwargs):
        return "Cevap."

    monkeypatch.setattr(rag_service, "chat_general", ok)
    first = _post_general(client, api).json()
    assert first["usage_kind"] == "free_daily" and first["usage_remaining"] == 2 and not first["chat_quota_exceeded"]
    _post_general(client, api)
    third = _post_general(client, api).json()
    assert third["usage_remaining"] == 0

    fourth = _post_general(client, api).json()
    assert fourth["chat_quota_exceeded"] is True and "hakkın doldu" in fourth["reply"]
    assert free_chat_quota.free_chat_remaining(USER_ID) == 0


def test_failed_model_reply_does_not_cost_the_user_a_turn(monkeypatch, client, api):
    async def overloaded(**kwargs):
        return "Şu an çok yoğunuz, biraz sonra tekrar dene."

    monkeypatch.setattr(rag_service, "chat_general", overloaded)
    body = _post_general(client, api).json()
    assert body["usage_remaining"] == 3, "hata yanıtı hakkı düşürmez"
    assert free_chat_quota.free_chat_remaining(USER_ID) == 3


def test_server_error_during_a_turn_refunds_the_reservation(monkeypatch, api):
    from fastapi.testclient import TestClient

    async def crash(**kwargs):
        raise RuntimeError("beklenmeyen")

    monkeypatch.setattr(rag_service, "chat_general", crash)
    r = _post_general(TestClient(main.app, raise_server_exceptions=False), api)
    assert r.status_code == 500
    assert free_chat_quota.free_chat_remaining(USER_ID) == 3


def _parallel(app_call, n):
    async def run():
        transport = httpx.ASGITransport(app=main.app)
        async with httpx.AsyncClient(transport=transport, base_url="http://t", timeout=30) as c:
            return await asyncio.gather(*(app_call(c) for _ in range(n)))

    return asyncio.run(run())


def test_parallel_requests_cannot_exceed_the_daily_limit(monkeypatch, api):
    """Eski "kontrol et, sonra artır" akışında 12 paralel istek de kontrolden geçerdi."""

    async def slow(**kwargs):
        await asyncio.sleep(0.15)  # tüm istekler birbirine bindirilsin
        return "Cevap."

    monkeypatch.setattr(rag_service, "chat_general", slow)
    responses = _parallel(
        lambda c: c.post("/chat_general", json={"user_id": USER_ID, "message": "x", "history": []}, headers=api), 12
    )
    bodies = [r.json() for r in responses]
    assert all(r.status_code == 200 for r in responses)
    assert sum(not b["chat_quota_exceeded"] for b in bodies) == 3
    assert sum(b["chat_quota_exceeded"] for b in bodies) == 9
    assert free_chat_quota.free_chat_remaining(USER_ID) == 0


def test_parallel_failures_free_their_slots_for_later_requests(monkeypatch, api):
    state = {"fail": True}

    async def flaky(**kwargs):
        await asyncio.sleep(0.05)
        return "Bağlantı kurulamadı." if state["fail"] else "Cevap."

    monkeypatch.setattr(rag_service, "chat_general", flaky)
    call = lambda c: c.post("/chat_general", json={"user_id": USER_ID, "message": "x", "history": []}, headers=api)
    _parallel(call, 6)  # hepsi hata yanıtı: hak harcanmamalı (rezerve edilen iade edildi)
    assert free_chat_quota.free_chat_remaining(USER_ID) == 3

    state["fail"] = False
    bodies = [r.json() for r in _parallel(call, 5)]
    assert sum(not b["chat_quota_exceeded"] for b in bodies) == 3


def test_capped_plus_user_is_limited_monthly_and_refunded_on_failure(monkeypatch, client, api):
    monkeypatch.setattr(main, "user_is_rebi_plus", lambda *a, **k: True)
    monkeypatch.setattr(main, "user_plus_chat_is_monthly_capped", lambda *a, **k: True)
    monkeypatch.setenv("PLUS_CHAT_MONTHLY_CAP", "10")
    replies = iter(["Bağlantı kurulamadı."] + ["Cevap."] * 12)

    async def scripted(**kwargs):
        return next(replies)

    monkeypatch.setattr(rag_service, "chat_general", scripted)
    assert _post_general(client, api).json()["usage_remaining"] == 10, "hata yanıtı aylık hakkı düşürmez"
    bodies = [_post_general(client, api).json() for _ in range(11)]
    assert [b["chat_quota_exceeded"] for b in bodies] == [False] * 10 + [True]
    assert bodies[-1]["usage_kind"] == "plus_monthly" and "Plus sohbet kotan doldu" in bodies[-1]["reply"]


def test_unlimited_plus_is_never_counted(monkeypatch, client, api):
    monkeypatch.setattr(main, "user_is_rebi_plus", lambda *a, **k: True)
    monkeypatch.setattr(main, "user_plus_chat_is_monthly_capped", lambda *a, **k: False)

    async def ok(**kwargs):
        return "Cevap."

    monkeypatch.setattr(rag_service, "chat_general", ok)
    for _ in range(6):
        body = _post_general(client, api).json()
        assert not body["chat_quota_exceeded"] and body["usage_kind"] == "plus_unlimited"
    assert free_chat_quota.free_chat_remaining(USER_ID) == 3


def _post_assessment(client, headers, mode="free_chat"):
    return client.post(
        "/chat_assessment",
        json={"user_id": USER_ID, "message": "merhaba", "history": [], "user_profile": {"mode": mode}},
        headers=headers,
    )


def test_assessment_chat_uses_the_same_reservation_model(monkeypatch, client, api):
    replies = iter(
        [{"reply": "Şu an kısa bir yanıt üretilemedi."}]  # hata: iade
        + [{"reply": "Anlıyorum.", "is_complete": False}] * 5
    )

    async def scripted(**kwargs):
        return next(replies)

    monkeypatch.setattr(rag_service, "assessment_chat", scripted)
    first = _post_assessment(client, api).json()
    assert first["free_chat_remaining"] == 3, "hata yanıtı hakkı düşürmez"
    bodies = [_post_assessment(client, api).json() for _ in range(4)]
    assert [b["chat_quota_exceeded"] for b in bodies] == [False, False, False, True]
    assert bodies[2]["free_chat_remaining"] == 0 and bodies[3]["free_chat_remaining"] == 0


def test_routine_assessment_mode_is_not_quota_limited(monkeypatch, client, api):
    async def ok(**kwargs):
        return {"reply": "Peki.", "is_complete": False}

    monkeypatch.setattr(rag_service, "assessment_chat", ok)
    for _ in range(6):
        body = _post_assessment(client, api, mode="assessment").json()
        assert body["chat_quota_exceeded"] is False and body["free_chat_remaining"] is None
    assert free_chat_quota.free_chat_remaining(USER_ID) == 3


def test_parallel_assessment_requests_cannot_exceed_the_limit(monkeypatch, api):
    async def slow(**kwargs):
        await asyncio.sleep(0.15)
        return {"reply": "Peki.", "is_complete": False}

    monkeypatch.setattr(rag_service, "assessment_chat", slow)
    body = {"user_id": USER_ID, "message": "x", "history": [], "user_profile": {"mode": "free_chat"}}
    responses = _parallel(lambda c: c.post("/chat_assessment", json=body, headers=api), 10)
    assert sum(not r.json()["chat_quota_exceeded"] for r in responses) == 3


def test_old_racy_api_is_gone():
    for name in ("free_chat_record_successful_turn", "plus_chat_record_successful_turn"):
        assert not hasattr(free_chat_quota, name) and not hasattr(plus_chat_quota, name)
    assert chat_quota.reserve_chat_turn is reserve_chat_turn
