"""Yapay zekâ uçlarında kullanıcı başına bütçe: IP'den bağımsız, kota ve modelden önce, sınırsız Plus dahil."""

from __future__ import annotations

import inspect

import jwt
import pytest
from fastapi import HTTPException

import free_chat_quota
import main
import rag_service
import rate_limit
from free_chat_quota import _MemoryDailyQuota
from plus_chat_quota import _MemoryMonthlyQuota
import plus_chat_quota

USER_A = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
USER_B = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
SECRET = "test-secret-at-least-32-bytes-long"


def _limiters(monkeypatch, per_minute: int, per_hour: int):
    monkeypatch.setattr(rate_limit, "LIMIT_AI_USER_MINUTE", rate_limit.SlidingWindowLimiter(per_minute, 60))
    monkeypatch.setattr(rate_limit, "LIMIT_AI_USER_HOUR", rate_limit.SlidingWindowLimiter(per_hour, 3600))


# ── Sınırlayıcı ──────────────────────────────────────────────────────────────────────────────────

def test_user_gets_the_minute_budget_then_a_429_with_retry_after(monkeypatch):
    _limiters(monkeypatch, 3, 100)
    for _ in range(3):
        rate_limit.enforce_ai_user_limit(USER_A)

    with pytest.raises(HTTPException) as err:
        rate_limit.enforce_ai_user_limit(USER_A)

    assert err.value.status_code == 429
    assert err.value.headers == {"Retry-After": "30"}
    assert "bekleyip tekrar dene" in err.value.detail


def test_the_hourly_budget_applies_even_when_the_minute_budget_is_fine(monkeypatch):
    _limiters(monkeypatch, 100, 5)
    for _ in range(5):
        rate_limit.enforce_ai_user_limit(USER_A)
    with pytest.raises(HTTPException) as err:
        rate_limit.enforce_ai_user_limit(USER_A)
    assert err.value.status_code == 429


def test_users_have_independent_budgets(monkeypatch):
    _limiters(monkeypatch, 2, 100)
    rate_limit.enforce_ai_user_limit(USER_A)
    rate_limit.enforce_ai_user_limit(USER_A)
    rate_limit.enforce_ai_user_limit(USER_B)  # B'nin bütçesi A'dan etkilenmez
    with pytest.raises(HTTPException):
        rate_limit.enforce_ai_user_limit(USER_A)


def test_a_request_refused_by_the_minute_budget_does_not_burn_the_hourly_one(monkeypatch):
    _limiters(monkeypatch, 2, 3)
    rate_limit.enforce_ai_user_limit(USER_A)
    rate_limit.enforce_ai_user_limit(USER_A)
    for _ in range(10):
        with pytest.raises(HTTPException):
            rate_limit.enforce_ai_user_limit(USER_A)
    assert len(rate_limit.LIMIT_AI_USER_HOUR._hits[USER_A]) == 2, "reddedilenler saatlik sayaca yazılmaz"


def test_default_budget_is_generous_for_real_conversations():
    assert rate_limit.LIMIT_AI_USER_MINUTE.max_requests >= 15
    assert rate_limit.LIMIT_AI_USER_HOUR.max_requests >= 100


def test_budget_can_be_tuned_from_the_environment(monkeypatch):
    monkeypatch.setenv("AI_USER_LIMIT_PER_MINUTE", "7")
    assert rate_limit._int_env("AI_USER_LIMIT_PER_MINUTE", 20) == 7
    monkeypatch.setenv("AI_USER_LIMIT_PER_MINUTE", "bozuk")
    assert rate_limit._int_env("AI_USER_LIMIT_PER_MINUTE", 20) == 20
    monkeypatch.setenv("AI_USER_LIMIT_PER_MINUTE", "0")
    assert rate_limit._int_env("AI_USER_LIMIT_PER_MINUTE", 20) == 1, "sıfır ve negatif değerler en az 1'e çekilir"


def test_an_empty_user_id_never_raises(monkeypatch):
    _limiters(monkeypatch, 1, 1)
    rate_limit.enforce_ai_user_limit("")
    rate_limit.enforce_ai_user_limit("   ")


def test_shared_demo_identities_are_not_throttled_as_one_person(monkeypatch):
    _limiters(monkeypatch, 1, 1)
    for _ in range(10):
        main._enforce_ai_user_limit("demo")
        main._enforce_ai_user_limit("00000000-0000-4000-8000-000000000001")


# ── Uçlar ────────────────────────────────────────────────────────────────────────────────────────

def _headers(user_id: str) -> dict:
    return {"Authorization": "Bearer " + jwt.encode({"sub": user_id, "aud": "authenticated"}, SECRET, algorithm="HS256")}


@pytest.fixture
def api(monkeypatch):
    """JWT açık; model ve DB sahte; çağrı sayısı sayılır."""
    monkeypatch.setenv("SUPABASE_JWT_SECRET", SECRET)
    monkeypatch.delenv("API_ALLOW_INSECURE_AUTH", raising=False)
    monkeypatch.setenv("FREE_CHAT_DAILY_LIMIT", "100")
    monkeypatch.setattr(free_chat_quota, "_backend", _MemoryDailyQuota())
    monkeypatch.setattr(plus_chat_quota, "_backend", _MemoryMonthlyQuota())
    rate_limit.LIMIT_CHAT_ASSESSMENT._hits.clear()  # IP başına sohbet sınırı bu testlerin konusu değil
    monkeypatch.setattr(main, "get_supabase", lambda: None)
    monkeypatch.setattr(main, "_require_privacy_permission", lambda *a, **k: None)
    monkeypatch.setattr(main, "_persist_chat_turn", lambda *a, **k: None)
    model_calls: list = []

    async def reply(**kwargs):
        model_calls.append(kwargs)
        return "Cevap."

    monkeypatch.setattr(rag_service, "chat_general", reply)
    return model_calls


def _chat(client, user_id, ip="1.1.1.1"):
    return client.post(
        "/chat_general",
        json={"user_id": user_id, "message": "SPF?", "history": []},
        headers={**_headers(user_id), "X-Forwarded-For": ip},
    )


def test_a_user_over_budget_gets_429_before_any_quota_or_model_cost(monkeypatch, client, api):
    _limiters(monkeypatch, 3, 100)

    statuses = [_chat(client, USER_A).status_code for _ in range(6)]

    assert statuses == [200, 200, 200, 429, 429, 429]
    assert len(api) == 3, "429 olan istekler modele hiç gitmez"
    assert free_chat_quota.free_chat_remaining(USER_A) == 97, "429 olanlar günlük kotadan da düşmez"


def test_changing_ip_does_not_reset_the_budget(monkeypatch, client, api):
    """Per-IP sınır VPN/mobil ağ değiştirerek aşılabilirdi; kullanıcı bütçesi aşılamaz."""
    _limiters(monkeypatch, 3, 100)

    statuses = [_chat(client, USER_A, ip=f"10.0.0.{i}").status_code for i in range(6)]

    assert statuses == [200, 200, 200, 429, 429, 429]


def test_unlimited_plus_users_are_bounded_too(monkeypatch, client, api):
    _limiters(monkeypatch, 4, 100)
    monkeypatch.setattr(main, "user_is_rebi_plus", lambda *a, **k: True)
    monkeypatch.setattr(main, "user_plus_chat_is_monthly_capped", lambda *a, **k: False)

    statuses = [_chat(client, USER_A).status_code for _ in range(7)]

    assert statuses.count(200) == 4 and statuses.count(429) == 3


def test_one_users_burst_does_not_lock_out_another(monkeypatch, client, api):
    _limiters(monkeypatch, 2, 100)
    assert [_chat(client, USER_A).status_code for _ in range(3)] == [200, 200, 429]
    assert _chat(client, USER_B).status_code == 200


def test_assessment_chat_shares_the_same_budget(monkeypatch, client, api):
    _limiters(monkeypatch, 2, 100)

    async def assess(**kwargs):
        return {"reply": "Peki.", "is_complete": False}

    monkeypatch.setattr(rag_service, "assessment_chat", assess)
    body = {"user_id": USER_A, "message": "merhaba", "history": [], "user_profile": {"mode": "free_chat"}}

    codes = [client.post("/chat_assessment", json=body, headers=_headers(USER_A)).status_code for _ in range(3)]

    assert codes == [200, 200, 429]
    assert free_chat_quota.free_chat_remaining(USER_A) == 98


def test_the_budget_is_checked_before_consent_so_a_flood_costs_no_database_reads(monkeypatch, client, api):
    _limiters(monkeypatch, 1, 100)
    checks: list = []
    monkeypatch.setattr(main, "_require_privacy_permission", lambda *a, **k: checks.append(1))

    for _ in range(5):
        _chat(client, USER_A)

    assert len(checks) == 1, "429 olan isteklerde rıza sorgusu (DB) çalışmaz"


def test_every_ai_endpoint_enforces_the_per_user_budget():
    """Yeni bir yapay zekâ ucu eklenirken bütçeyi atlamak kolay; kaynak denetimi bunu yakalar."""
    for name in (
        "chat",
        "chat_assessment",
        "chat_general_endpoint",
        "translate_routine_items_endpoint",
        "generate_routine",
        "daily_checkin",
    ):
        source = inspect.getsource(getattr(main, name))
        assert "_enforce_ai_user_limit(req.user_id)" in source, f"{name}: kullanıcı bütçesi uygulanmıyor"
        assert source.index("_enforce_ai_user_limit") < source.index("_require_privacy_permission"), (
            f"{name}: bütçe, DB'ye giden rıza sorgusundan önce uygulanmalı"
        )
