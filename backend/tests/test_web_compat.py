"""Web'in (frontend/) gerçekte gönderdiği istek biçimleri.

Mobil için yapılan backend değişiklikleri (son olay geçerli, yerel gün, su sınırı…) web'i
bozmamalı. Bu testler web istemcisinin kullandığı gövdeleri aynen taklit eder:
`frontend/src/lib/dailyTracking.js` zaman damgası ya da `client_event_id` göndermez ve
`routine_completed_block` için yalnızca tek anahtar (`{morning: true}`) yollar.
"""

from __future__ import annotations

import jwt
import pytest

import main
from tests.fake_supabase import FakeSupabase

USER_ID = "77777777-7777-4777-8777-777777777777"
SECRET = "test-secret-at-least-32-bytes-long"


@pytest.fixture
def headers(monkeypatch):
    monkeypatch.setenv("SUPABASE_JWT_SECRET", SECRET)
    monkeypatch.delenv("API_ALLOW_INSECURE_AUTH", raising=False)
    token = jwt.encode({"sub": USER_ID, "aud": "authenticated"}, SECRET, algorithm="HS256")
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
def db(monkeypatch) -> FakeSupabase:
    fake = FakeSupabase()
    monkeypatch.setattr(main, "get_supabase", lambda: fake)
    return fake


def _web_ingest(client, headers, type_: str, payload: dict | None = None):
    """`ingestDailyTrackingEvent(userId, type, payload)` ile birebir aynı gövde."""
    return client.post(
        "/daily_tracking/ingest",
        json={"user_id": USER_ID, "type": type_, "payload": payload or {}, "source": "web"},
        headers=headers,
    )


def test_web_marks_morning_then_evening_and_both_stay_done(db, client, headers):
    assert _web_ingest(client, headers, "routine_completed_block", {"morning": True}).status_code == 200
    r = _web_ingest(client, headers, "routine_completed_block", {"evening": True})

    assert r.status_code == 200, r.text
    agg = r.json()["aggregated"]
    assert agg["routine_morning_done"] is True
    assert agg["routine_evening_done"] is True


def test_web_water_events_accumulate(db, client, headers):
    for ml in (250, 500, 250):
        assert _web_ingest(client, headers, "water_intake", {"ml": ml}).status_code == 200

    today = client.get("/daily_tracking/today", params={"user_id": USER_ID}, headers=headers).json()
    assert today["aggregated"]["water_ml_total"] == 1000


def test_web_makeup_and_nutrition_and_spf_events_are_aggregated(db, client, headers):
    _web_ingest(client, headers, "makeup", {"used": True, "removed": True})
    _web_ingest(client, headers, "nutrition", {"junk_food": True})
    r = _web_ingest(client, headers, "spf_refresh", {"n": 1})

    agg = r.json()["aggregated"]
    assert agg["makeup"]["used"] is True and agg["makeup"]["removed"] is True
    assert agg["nutrition"]["junk_food"] is True
    assert agg["spf_refreshes"] == 1


def test_web_sends_no_offset_so_the_server_day_is_used(db, client, headers):
    r = _web_ingest(client, headers, "water_intake", {"ml": 100})

    assert r.json()["log_date"] == str(main.date.today())
    plan = client.get("/today/plan", params={"user_id": USER_ID}, headers=headers).json()
    assert plan["log_date"] == str(main.date.today())
    assert plan["progress"]["water_ml_total"] == 100


@pytest.mark.parametrize(
    "timestamp, expected",
    [
        # Web / JS `toISOString()` hep Z (UTC) üretir: eski davranışla aynı gün.
        ("2026-10-15T23:30:00.000Z", "2026-10-15"),
        ("2026-10-15T00:10:00Z", "2026-10-15"),
        # Zaman damgası saat farkı taşıyorsa (mobil) olayın kendi yerel günü.
        ("2026-10-15T00:10:00+03:00", "2026-10-15"),
        ("2026-10-14T23:50:00-05:00", "2026-10-14"),
        # Farksız damga UTC sayılır.
        ("2026-10-15T08:00:00", "2026-10-15"),
    ],
)
def test_event_day_is_taken_from_the_timestamp(timestamp, expected):
    assert main._safe_date_from_timestamp(timestamp) == expected


def test_unparseable_timestamp_falls_back_to_today():
    assert main._safe_date_from_timestamp("dün gece") == str(main.date.today())
    assert main._safe_date_from_timestamp(None) == str(main.date.today())


def test_chat_and_checkin_requests_work_without_the_new_offset_field():
    # Yeni alan isteğe bağlı: web gövdesi onsuz geçerli kalır.
    assert main.ChatGeneralRequest(user_id="u", message="merhaba").utc_offset_minutes is None
    assert main.DailyCheckinRequest(
        user_id="u", sleep_hours=7, stress_today=2, skin_feeling="iyi", applied_routine=True
    ).utc_offset_minutes is None


def test_old_plan_consumers_still_find_every_original_field(db, client, headers):
    body = client.get("/today/plan", params={"user_id": USER_ID}, headers=headers).json()

    for key in (
        "user_id", "log_date", "has_routine", "routine", "weather", "weather_source",
        "environment_advice", "reminders", "progress", "checkin_done",
    ):
        assert key in body, key
    for key in ("water_ml_total", "makeup", "nutrition", "spf_refreshes", "routine_morning_done"):
        assert key in body["progress"], key
