"""Mağaza abonelikleri: kademe çözümü, günlük kademe kotası, RevenueCat eşitlemesi ve webhook."""

from __future__ import annotations

import time
from collections import defaultdict, deque

import jwt
import pytest

import free_chat_quota
import main
import plus_chat_quota
import rag_service
import rate_limit
import store_subscription
from free_chat_quota import _MemoryDailyQuota
from plus_chat_quota import _MemoryMonthlyQuota
from store_subscription import StoreEntitlement, active_store_tier, best_entitlement, tier_daily_limits

USER_ID = "99999999-9999-4999-8999-999999999999"
SECRET = "test-secret-at-least-32-bytes-long"
DAY_MS = 86_400_000


def _now_ms() -> int:
    return int(time.time() * 1000)


# ── Saf yardımcılar ──────────────────────────────────────────────────────────────────────────────

def test_tier_daily_limits_default_and_env_override(monkeypatch):
    monkeypatch.delenv("REBI_TIER_DAILY_LIMITS", raising=False)
    assert tier_daily_limits() == {"plus": 50, "pro": 80, "max": 120}
    monkeypatch.setenv("REBI_TIER_DAILY_LIMITS", "plus:40, pro:x, max:150, bilinmeyen:9")
    assert tier_daily_limits() == {"plus": 40, "pro": 80, "max": 150}


def test_active_store_tier_respects_expiry_and_grace():
    now = 1_000_000_000_000
    meta = lambda exp: {"rebi_store": {"tier": "pro", "expires_at_ms": exp}}
    assert active_store_tier(meta(now + 1), now) == "pro"
    assert active_store_tier(meta(now - 60_000), now) == "pro", "kısa yenileme gecikmesi kilitlemez"
    assert active_store_tier(meta(now - DAY_MS), now) is None
    assert active_store_tier({"rebi_store": {"tier": "pro", "expires_at_ms": None}}, now) == "pro"
    assert active_store_tier({"rebi_store": {"tier": "gold"}}, now) is None
    assert active_store_tier({"rebi_store": None}, now) is None
    assert active_store_tier({}, now) is None


def test_best_entitlement_picks_highest_active_tier():
    now = 1_000_000_000_000
    future = "2100-01-01T00:00:00Z"
    past = "2000-01-01T00:00:00Z"
    sub = {
        "entitlements": {
            "plus": {"expires_date": future, "product_identifier": "rebi_plus_monthly"},
            "max": {"expires_date": past, "product_identifier": "rebi_max_monthly"},
            "pro": {"expires_date": future, "product_identifier": "rebi_pro_yearly"},
            "baska": {"expires_date": future, "product_identifier": "x"},
        },
        "subscriptions": {"rebi_pro_yearly": {"store": "play_store"}},
    }
    ent = best_entitlement(sub, now)
    assert ent and ent.tier == "pro" and ent.product_id == "rebi_pro_yearly" and ent.store == "play_store"
    assert best_entitlement({"entitlements": {}}, now) is None


def test_webhook_authorization_header(monkeypatch):
    monkeypatch.delenv("REVENUECAT_WEBHOOK_AUTH", raising=False)
    assert not store_subscription.webhook_authorized("anything"), "anahtar tanımsızsa her şey reddedilir"
    monkeypatch.setenv("REVENUECAT_WEBHOOK_AUTH", "s3cret")
    assert store_subscription.webhook_authorized("s3cret")
    assert store_subscription.webhook_authorized("Bearer s3cret")
    assert not store_subscription.webhook_authorized("wrong")
    assert not store_subscription.webhook_authorized(None)


# ── Uç noktalar ──────────────────────────────────────────────────────────────────────────────────

@pytest.fixture
def jwt_env(monkeypatch):
    monkeypatch.setenv("SUPABASE_JWT_SECRET", SECRET)
    monkeypatch.delenv("API_ALLOW_INSECURE_AUTH", raising=False)
    monkeypatch.delenv("REBI_PLUS_USER_IDS", raising=False)
    monkeypatch.setenv("FREE_CHAT_DAILY_LIMIT", "3")
    monkeypatch.setenv("REBI_TIER_DAILY_LIMITS", "plus:5,pro:7,max:9")
    monkeypatch.setattr(free_chat_quota, "_backend", _MemoryDailyQuota())
    monkeypatch.setattr(plus_chat_quota, "_backend", _MemoryMonthlyQuota())
    monkeypatch.setattr(rate_limit.LIMIT_CHAT_ASSESSMENT, "_hits", defaultdict(deque))
    monkeypatch.setattr(rate_limit.LIMIT_SUBSCRIPTION_SYNC, "_hits", defaultdict(deque))
    monkeypatch.setattr(main, "get_supabase", lambda: None)
    monkeypatch.setattr(main, "_require_privacy_permission", lambda *a, **k: None)
    monkeypatch.setattr(main, "_persist_chat_turn", lambda *a, **k: None)

    async def ok(**kwargs):
        return "Cevap."

    monkeypatch.setattr(rag_service, "chat_general", ok)


def _headers(app_metadata: dict | None = None) -> dict:
    claims = {"sub": USER_ID, "aud": "authenticated", "app_metadata": app_metadata or {}}
    return {"Authorization": f"Bearer {jwt.encode(claims, SECRET, algorithm='HS256')}"}


def _store(tier: str, exp_ms: int | None = None) -> dict:
    return {"rebi_store": {"tier": tier, "expires_at_ms": exp_ms if exp_ms is not None else _now_ms() + DAY_MS}}


def _post_general(client, headers):
    return client.post("/chat_general", json={"user_id": USER_ID, "message": "SPF?", "history": []}, headers=headers)


def test_store_tier_gets_its_daily_limit(client, jwt_env):
    h = _headers(_store("pro"))
    bodies = [_post_general(client, h).json() for _ in range(8)]
    assert [b["chat_quota_exceeded"] for b in bodies] == [False] * 7 + [True]
    assert bodies[0]["usage_kind"] == "plan_daily" and bodies[0]["usage_limit"] == 7
    assert bodies[0]["usage_remaining"] == 6
    assert "yarın yenilenir" in bodies[-1]["reply"] and "üst pakete" in bodies[-1]["reply"]

    usage = client.get("/chat_usage", params={"user_id": USER_ID}, headers=h).json()
    assert usage == {"kind": "plan_daily", "remaining": 0, "limit": 7, "period": "day"}


def test_top_tier_exceeded_message_does_not_upsell(client, jwt_env):
    h = _headers(_store("max"))
    for _ in range(9):
        _post_general(client, h)
    body = _post_general(client, h).json()
    assert body["chat_quota_exceeded"] and "üst pakete" not in body["reply"]


def test_upgrade_mid_day_keeps_todays_usage(client, jwt_env):
    for _ in range(3):
        _post_general(client, _headers())
    assert _post_general(client, _headers()).json()["chat_quota_exceeded"] is True
    body = _post_general(client, _headers(_store("plus"))).json()
    assert not body["chat_quota_exceeded"] and body["usage_remaining"] == 1, "bugünkü 3 + 1 = 4 / 5"


def test_expired_store_tier_falls_back_to_free(client, jwt_env):
    body = _post_general(client, _headers(_store("max", _now_ms() - DAY_MS))).json()
    assert body["usage_kind"] == "free_daily" and body["usage_limit"] == 3


def test_legacy_unlimited_plus_wins_over_store_tier(client, jwt_env):
    meta = {"rebi_plus": True, **_store("plus")}
    for _ in range(7):
        body = _post_general(client, _headers(meta)).json()
        assert not body["chat_quota_exceeded"] and body["usage_kind"] == "plus_unlimited"


def test_store_tier_counts_as_plus_for_other_perks(jwt_env):
    from starlette.requests import Request

    def req(meta):
        return Request({"type": "http", "headers": [(b"authorization", _headers(meta)["Authorization"].encode())]})

    assert main.user_is_rebi_plus(req(_store("plus")), USER_ID) is True
    assert main.user_is_rebi_plus(req(_store("plus", _now_ms() - DAY_MS)), USER_ID) is False


def test_subscription_sync_writes_metadata(monkeypatch, client, jwt_env):
    monkeypatch.setenv("REVENUECAT_SECRET_API_KEY", "sk_test")
    written = {}

    async def fake_fetch(uid):
        return {
            "entitlements": {"max": {"expires_date": "2100-01-01T00:00:00Z", "product_identifier": "rebi_max_yearly"}},
            "subscriptions": {"rebi_max_yearly": {"store": "app_store"}},
        }

    async def fake_write(uid, ent):
        written[uid] = ent

    monkeypatch.setattr(store_subscription, "fetch_revenuecat_subscriber", fake_fetch)
    monkeypatch.setattr(store_subscription, "write_store_metadata", fake_write)
    r = client.post("/subscription/sync", json={"user_id": USER_ID}, headers=_headers())
    assert r.status_code == 200 and r.json()["tier"] == "max"
    assert written[USER_ID] == StoreEntitlement("max", 4102444800000, "rebi_max_yearly", "app_store")

    other = client.post("/subscription/sync", json={"user_id": "11111111-1111-4111-8111-111111111111"}, headers=_headers())
    assert other.status_code == 403, "başkasının aboneliği eşitlenemez"


def test_subscription_sync_unavailable_without_key(monkeypatch, client, jwt_env):
    monkeypatch.delenv("REVENUECAT_SECRET_API_KEY", raising=False)
    assert client.post("/subscription/sync", json={"user_id": USER_ID}, headers=_headers()).status_code == 503


def test_webhook_resyncs_every_affected_supabase_user(monkeypatch, client, jwt_env):
    monkeypatch.setenv("REVENUECAT_WEBHOOK_AUTH", "hook-secret")
    synced = []

    async def fake_sync(uid):
        synced.append(uid)
        return None

    monkeypatch.setattr(main, "sync_user_from_revenuecat", fake_sync)
    other = "11111111-1111-4111-8111-111111111111"
    event = {
        "event": {
            "type": "TRANSFER",
            "app_user_id": USER_ID,
            "aliases": ["$RCAnonymousID:abc", USER_ID],
            "transferred_from": [other],
            "transferred_to": [USER_ID],
        }
    }
    assert client.post("/webhooks/revenuecat", json=event).status_code == 401
    assert client.post("/webhooks/revenuecat", json=event, headers={"Authorization": "nope"}).status_code == 401
    r = client.post("/webhooks/revenuecat", json=event, headers={"Authorization": "hook-secret"})
    assert r.status_code == 200 and sorted(synced) == sorted([USER_ID, other])


def test_webhook_failure_asks_revenuecat_to_retry(monkeypatch, client, jwt_env):
    monkeypatch.setenv("REVENUECAT_WEBHOOK_AUTH", "hook-secret")

    async def boom(uid):
        raise RuntimeError("supabase yok")

    monkeypatch.setattr(main, "sync_user_from_revenuecat", boom)
    r = client.post(
        "/webhooks/revenuecat",
        json={"event": {"type": "RENEWAL", "app_user_id": USER_ID}},
        headers={"Authorization": "hook-secret"},
    )
    assert r.status_code == 502
