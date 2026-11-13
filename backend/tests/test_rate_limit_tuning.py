"""IP sınırları CGNAT'ta meşru kullanıcıyı kilitlemez; gerçek koruma kullanıcı başınadır."""

from __future__ import annotations

import jwt
import pytest

import main
import rate_limit
from tests.fake_supabase import FakeSupabase

USER_A = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
USER_B = "dddddddd-dddd-4ddd-8ddd-dddddddddddd"
SECRET = "test-secret-at-least-32-bytes-long"


@pytest.fixture(autouse=True)
def _fresh_limits():
    for lim in (rate_limit.LIMIT_DAILY_TRACKING_INGEST, rate_limit.LIMIT_INGEST_USER):
        lim._hits.clear()
    yield
    for lim in (rate_limit.LIMIT_DAILY_TRACKING_INGEST, rate_limit.LIMIT_INGEST_USER):
        lim._hits.clear()


# ── Çarpan ───────────────────────────────────────────────────────────────────────────────────────

def test_default_multiplier_relaxes_ip_limits_but_not_the_security_ones():
    assert rate_limit.ip_multiplier() == 4.0
    assert rate_limit.LIMIT_TODAY_PLAN.max_requests == 240
    assert rate_limit.LIMIT_DAILY_CHECKIN.max_requests == 48
    assert rate_limit.LIMIT_GENERATE_ROUTINE.max_requests == 100
    assert rate_limit.LIMIT_DAILY_TRACKING_INGEST.max_requests == 480
    # Güvenlik amaçlı olanlar eski sıkı değerlerinde kalır.
    assert rate_limit.LIMIT_ACCOUNT_DELETE.max_requests == 3
    assert rate_limit.LIMIT_PUSH_DISPATCH.max_requests == 30
    assert rate_limit.LIMIT_INTRO_SEEN.max_requests == 60


def test_the_multiplier_is_tunable_and_one_restores_the_old_limits(monkeypatch):
    monkeypatch.setenv("RATE_LIMIT_IP_MULTIPLIER", "1")
    assert rate_limit._make_limiter(35, 60, "t").max_requests == 35
    monkeypatch.setenv("RATE_LIMIT_IP_MULTIPLIER", "10")
    assert rate_limit._make_limiter(35, 60, "t").max_requests == 350
    monkeypatch.setenv("RATE_LIMIT_IP_MULTIPLIER", "0.2")
    assert rate_limit._make_limiter(35, 60, "t").max_requests == 35, "1'in altına inemez: sınırı sıkılaştırmaz"
    monkeypatch.setenv("RATE_LIMIT_IP_MULTIPLIER", "bozuk")
    assert rate_limit._make_limiter(35, 60, "t").max_requests == 140


def test_unscaled_limiters_ignore_the_multiplier(monkeypatch):
    monkeypatch.setenv("RATE_LIMIT_IP_MULTIPLIER", "50")
    assert rate_limit._make_limiter(3, 3600, "t", scale=False).max_requests == 3


def test_many_users_behind_one_carrier_ip_are_not_locked_out(monkeypatch):
    """Sabah uygulama açılışı: aynı CGNAT IP'sinden bir dakikada 200 /today/plan isteği."""
    monkeypatch.setenv("RATE_LIMIT_IP_MULTIPLIER", "1")
    old = rate_limit._make_limiter(60, 60, "eski")
    monkeypatch.setenv("RATE_LIMIT_IP_MULTIPLIER", "4")
    new = rate_limit._make_limiter(60, 60, "yeni")

    assert sum(old.allow("100.64.0.1") for _ in range(200)) == 60, "eski sınır meşru kullanıcıları reddederdi"
    assert sum(new.allow("100.64.0.1") for _ in range(200)) == 200


# ── Olay yazımında kullanıcı başına sınır ────────────────────────────────────────────────────────

def _headers(user_id):
    return {"Authorization": "Bearer " + jwt.encode({"sub": user_id, "aud": "authenticated"}, SECRET, algorithm="HS256")}


@pytest.fixture
def api(monkeypatch):
    monkeypatch.setenv("SUPABASE_JWT_SECRET", SECRET)
    monkeypatch.delenv("API_ALLOW_INSECURE_AUTH", raising=False)
    db = FakeSupabase(daily_events=[])
    monkeypatch.setattr(main, "get_supabase", lambda: db)
    return db


def _ingest(client, user_id, n, ip="9.9.9.9"):
    return client.post(
        "/daily_tracking/ingest",
        json={"user_id": user_id, "type": "water_intake", "payload": {"ml": 50}, "client_event_id": f"{user_id[:4]}-{n}"},
        headers={**_headers(user_id), "X-Forwarded-For": ip},
    )


def test_a_single_account_cannot_flood_events_even_from_many_ips(monkeypatch, client, api):
    monkeypatch.setattr(rate_limit, "LIMIT_INGEST_USER", rate_limit.SlidingWindowLimiter(5, 60))

    codes = [_ingest(client, USER_A, i, ip=f"10.1.0.{i}").status_code for i in range(8)]

    assert codes == [200] * 5 + [429] * 3
    assert len(api.tables["daily_events"].rows) == 5, "reddedilen olaylar yazılmaz"


def test_the_ingest_limit_response_tells_the_client_to_retry(monkeypatch, client, api):
    monkeypatch.setattr(rate_limit, "LIMIT_INGEST_USER", rate_limit.SlidingWindowLimiter(1, 60))
    _ingest(client, USER_A, 0)

    r = _ingest(client, USER_A, 1)

    assert r.status_code == 429 and r.headers["retry-after"] == "15"


def test_one_users_flood_does_not_affect_another(monkeypatch, client, api):
    monkeypatch.setattr(rate_limit, "LIMIT_INGEST_USER", rate_limit.SlidingWindowLimiter(2, 60))
    assert [_ingest(client, USER_A, i).status_code for i in range(3)] == [200, 200, 429]
    assert _ingest(client, USER_B, 0).status_code == 200


def test_an_offline_outbox_flush_of_200_events_goes_through(client, api):
    """Mobil kuyruk en çok 200 olay tutar; bağlantı gelince hepsi arka arkaya gönderilir (eski IP sınırı 120'de keserdi)."""
    codes = [_ingest(client, USER_A, i).status_code for i in range(200)]

    assert codes.count(200) == 200
    assert len(api.tables["daily_events"].rows) == 200


def test_demo_identities_are_exempt_from_the_per_user_ingest_limit(monkeypatch, client):
    monkeypatch.setattr(rate_limit, "LIMIT_INGEST_USER", rate_limit.SlidingWindowLimiter(1, 60))
    monkeypatch.setattr(main, "get_supabase", lambda: None)
    for i in range(5):
        r = client.post("/daily_tracking/ingest", json={"user_id": "demo", "type": "water_intake", "payload": {"ml": 10}, "client_event_id": f"d{i}"})
        assert r.status_code == 200
    main._MEM_DAILY_EVENTS.clear()
