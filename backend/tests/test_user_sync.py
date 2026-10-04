"""Web ve mobilin aynı veriyi görmesini sağlayan uçlar."""

from __future__ import annotations

import asyncio

import jwt
import pytest

import main
from tests.fake_supabase import FakeSupabase

USER_ID = "22222222-2222-4222-8222-222222222222"
DEMO_UUID = "00000000-0000-4000-8000-000000000001"
SECRET = "test-secret-at-least-32-bytes-long"


@pytest.fixture
def headers(monkeypatch):
    monkeypatch.setenv("SUPABASE_JWT_SECRET", SECRET)
    monkeypatch.delenv("API_ALLOW_INSECURE_AUTH", raising=False)
    token = jwt.encode({"sub": USER_ID, "aud": "authenticated"}, SECRET, algorithm="HS256")
    return {"Authorization": f"Bearer {token}"}


def _db(monkeypatch, **tables) -> FakeSupabase:
    db = FakeSupabase(**tables)
    monkeypatch.setattr(main, "get_supabase", lambda: db)
    return db


def _chat_rows(count: int = 4) -> list[dict]:
    rows = []
    for i in range(count):
        rows.append({
            "seq": i + 1,
            "user_id": USER_ID,
            "role": "user" if i % 2 == 0 else "assistant",
            "content": f"mesaj {i + 1}",
            "surface": "general",
            "created_at": f"2026-10-04T10:0{i}:00+00:00",
        })
    return rows


def test_chat_history_is_returned_oldest_first_with_cursor(monkeypatch, client, headers):
    _db(monkeypatch, chat_history=_chat_rows())

    r = client.get("/chat/history", params={"user_id": USER_ID, "limit": 3}, headers=headers)

    assert r.status_code == 200, r.text
    body = r.json()
    assert [m["content"] for m in body["messages"]] == ["mesaj 2", "mesaj 3", "mesaj 4"]
    assert body["cursor"] == 4
    assert body["synced"] is True


def test_chat_history_after_cursor_returns_only_new_messages(monkeypatch, client, headers):
    _db(monkeypatch, chat_history=_chat_rows())

    r = client.get(
        "/chat/history",
        params={"user_id": USER_ID, "after_seq": 2},
        headers=headers,
    )

    assert [m["seq"] for m in r.json()["messages"]] == [3, 4]


def test_chat_history_surface_filter(monkeypatch, client, headers):
    rows = _chat_rows(2) + [{
        "seq": 3,
        "user_id": USER_ID,
        "role": "user",
        "content": "rutin sorusu",
        "surface": "concern",
        "created_at": "2026-10-04T11:00:00+00:00",
    }]
    _db(monkeypatch, chat_history=rows)

    r = client.get(
        "/chat/history",
        params={"user_id": USER_ID, "surface": "concern"},
        headers=headers,
    )

    assert [m["content"] for m in r.json()["messages"]] == ["rutin sorusu"]


def test_clearing_chat_removes_server_copy(monkeypatch, client, headers):
    db = _db(monkeypatch, chat_history=_chat_rows())

    r = client.delete("/chat/history", params={"user_id": USER_ID}, headers=headers)

    assert r.status_code == 200
    assert r.json() == {"ok": True, "synced": True}
    assert db.tables["chat_history"].rows == []


def test_demo_user_has_no_server_chat_history(monkeypatch, client):
    monkeypatch.setattr(main, "get_supabase", lambda: None)

    r = client.get("/chat/history", params={"user_id": DEMO_UUID})

    assert r.json() == {"user_id": DEMO_UUID, "messages": [], "cursor": None, "synced": False}


def test_chat_turn_is_persisted_for_both_roles(monkeypatch):
    db = _db(monkeypatch)

    main._persist_chat_turn(USER_ID, "general", "cildim kuru", "nemlendirici öner")

    rows = db.tables["chat_history"].inserted
    assert [(r["role"], r["content"]) for r in rows] == [
        ("user", "cildim kuru"),
        ("assistant", "nemlendirici öner"),
    ]
    assert all(r["surface"] == "general" for r in rows)


def test_half_turn_is_not_persisted(monkeypatch):
    db = _db(monkeypatch)

    main._persist_chat_turn(USER_ID, "general", "soru", "   ")

    assert "chat_history" not in db.tables or db.tables["chat_history"].inserted == []


def test_profile_is_readable_and_patchable(monkeypatch, client, headers):
    db = _db(monkeypatch, profiles=[{
        "id": USER_ID,
        "full_name": "Test",
        "skin_type": "normal",
        "age": 30,
        "gender": "female",
        "city": "İstanbul",
        "updated_at": "2026-10-01T10:00:00+00:00",
    }])

    r = client.get("/me/profile", params={"user_id": USER_ID}, headers=headers)
    assert r.json()["skin_type"] == "normal"
    assert r.json()["synced"] is True

    r = client.patch(
        "/me/profile",
        json={"user_id": USER_ID, "skin_type": "dry"},
        headers=headers,
    )
    assert r.status_code == 200, r.text
    assert r.json()["skin_type"] == "dry"
    # Gönderilmeyen alanlar korunur.
    assert r.json()["full_name"] == "Test"
    written = db.tables["profiles"].upserted[-1]
    assert set(written) == {"id", "skin_type", "updated_at"}


def test_profile_patch_rejects_empty_body_and_unknown_skin_type(monkeypatch, client, headers):
    _db(monkeypatch, profiles=[{"id": USER_ID}])

    assert client.patch("/me/profile", json={"user_id": USER_ID}, headers=headers).status_code == 400
    bad = client.patch(
        "/me/profile",
        json={"user_id": USER_ID, "skin_type": "bilinmiyor"},
        headers=headers,
    )
    assert bad.status_code == 422


def test_history_groups_tracking_and_checkin_per_day(monkeypatch, client, headers):
    from datetime import date, timedelta

    today = str(date.today())
    yesterday = str(date.today() - timedelta(days=1))
    _db(
        monkeypatch,
        daily_events=[
            {
                "user_id": USER_ID,
                "log_date": yesterday,
                "event_time": f"{yesterday}T09:00:00+00:00",
                "type": "water_intake",
                "payload": {"ml": 500},
            },
            {
                "user_id": USER_ID,
                "log_date": today,
                "event_time": f"{today}T09:00:00+00:00",
                "type": "makeup",
                "payload": {"used": True},
            },
        ],
        daily_logs=[{"user_id": USER_ID, "log_date": today, "applied_routine": True}],
        assessments=[{
            "id": "a1",
            "user_id": USER_ID,
            "concern": "acne",
            "severity_score": 4,
            "created_at": f"{today}T08:00:00+00:00",
        }],
    )

    r = client.get("/me/history", params={"user_id": USER_ID, "days": 7}, headers=headers)

    assert r.status_code == 200, r.text
    body = r.json()
    days = {d["log_date"]: d for d in body["days"]}
    assert days[yesterday]["tracking"]["water_ml_total"] == 500
    assert days[yesterday]["checkin"] is None
    assert days[today]["tracking"]["makeup"]["used"] is True
    assert days[today]["checkin"]["applied_routine"] is True
    assert body["assessments"][0]["concern"] == "acne"
    assert body["synced"] is True


def test_history_rejects_range_beyond_limit(monkeypatch, client, headers):
    _db(monkeypatch)

    r = client.get("/me/history", params={"user_id": USER_ID, "days": 400}, headers=headers)

    assert r.status_code == 422


def test_snapshot_bundles_routine_consent_and_chat_cursor(monkeypatch, client, headers):
    from datetime import date

    today = str(date.today())
    _db(
        monkeypatch,
        profiles=[{"id": USER_ID, "skin_type": "oily"}],
        routines=[{
            "user_id": USER_ID,
            "is_active": True,
            "created_at": f"{today}T07:00:00+00:00",
            "assessment_id": "a1",
            "active_routine": [{"time": "Sabah", "action": "Jel temizleyici"}],
        }],
        daily_events=[{
            "user_id": USER_ID,
            "log_date": today,
            "event_time": f"{today}T09:00:00+00:00",
            "type": "water_intake",
            "payload": {"ml": 750},
        }],
        daily_logs=[{"user_id": USER_ID, "log_date": today}],
        chat_history=_chat_rows(3),
        legal_consents=[{"user_id": USER_ID, "document_version": main._LEGAL_CONSENT_VERSION}],
        privacy_preferences=[{
            "user_id": USER_ID,
            "ai_processing_allowed": True,
            "location_processing_allowed": False,
            "photo_processing_allowed": True,
        }],
    )

    r = client.get("/me/snapshot", params={"user_id": USER_ID}, headers=headers)

    assert r.status_code == 200, r.text
    body = r.json()
    assert body["has_routine"] is True
    assert body["profile"]["skin_type"] == "oily"
    assert body["progress"]["water_ml_total"] == 750
    assert body["checkin_done"] is True
    assert body["chat_cursor"] == 3
    assert body["consent"] == {
        "legal_version": main._LEGAL_CONSENT_VERSION,
        "legal_accepted": True,
        "ai_processing_allowed": True,
        "location_processing_allowed": False,
        "photo_processing_allowed": True,
    }
    assert body["synced"] is True


def test_snapshot_reports_missing_consent(monkeypatch, client, headers):
    _db(monkeypatch, profiles=[{"id": USER_ID}])

    body = client.get("/me/snapshot", params={"user_id": USER_ID}, headers=headers).json()

    assert body["consent"]["legal_accepted"] is False
    assert body["consent"]["ai_processing_allowed"] is False
    assert body["has_routine"] is False


def test_local_history_is_imported_once(monkeypatch, client, headers):
    db = _db(monkeypatch, chat_history=[])
    payload = {
        "user_id": USER_ID,
        "messages": [
            {"role": "user", "content": "eski soru"},
            {"role": "assistant", "content": "eski yanıt"},
        ],
    }

    first = client.post("/chat/history/import", json=payload, headers=headers)
    second = client.post("/chat/history/import", json=payload, headers=headers)

    assert first.json()["imported"] == 2
    assert first.json()["skipped"] is False
    # Sunucuda geçmiş varsa ikinci aktarma kopya üretmez.
    assert second.json() == {"imported": 0, "skipped": True, "cursor": None}
    assert len(db.tables["chat_history"].rows) == 2


def test_import_drops_empty_messages_and_caps_count(monkeypatch, client, headers):
    db = _db(monkeypatch, chat_history=[])
    messages = [{"role": "user", "content": f"mesaj {i}"} for i in range(80)]
    messages.append({"role": "assistant", "content": "   "})

    r = client.post(
        "/chat/history/import",
        json={"user_id": USER_ID, "messages": messages},
        headers=headers,
    )

    assert r.json()["imported"] == 59
    assert len(db.tables["chat_history"].rows) == 59


def test_location_event_requires_location_consent(monkeypatch, client, headers):
    _db(monkeypatch, privacy_preferences=[{
        "user_id": USER_ID,
        "ai_processing_allowed": True,
        "location_processing_allowed": False,
    }])

    r = client.post(
        "/daily_tracking/ingest",
        json={"user_id": USER_ID, "type": "location", "payload": {"lat": 41.0, "lon": 29.0}},
        headers=headers,
    )

    assert r.status_code == 403
    assert "konum" in r.json()["detail"].lower()


def test_non_location_event_needs_no_consent(monkeypatch, client, headers):
    _db(monkeypatch)

    r = client.post(
        "/daily_tracking/ingest",
        json={"user_id": USER_ID, "type": "water_intake", "payload": {"ml": 200}},
        headers=headers,
    )

    assert r.status_code == 200


def test_plan_uses_profile_location_when_client_sends_none(monkeypatch, client, headers):
    _db(
        monkeypatch,
        profiles=[{"id": USER_ID, "location_lat": 41.0, "location_lon": 29.0}],
        privacy_preferences=[{"user_id": USER_ID, "location_processing_allowed": True}],
    )

    async def _weather(lat, lon):
        assert (lat, lon) == (41.0, 29.0)
        return {"uv_index": 8, "humidity": 40, "temperature": 28}

    monkeypatch.setattr(main, "fetch_weather", _weather)
    main._WEATHER_CACHE.clear()

    body = client.get("/today/plan", params={"user_id": USER_ID}, headers=headers).json()

    assert body["weather_source"] == "profile"
    assert body["weather"]["uv_index"] == 8
    assert "spf_refresh" in {r["id"] for r in body["reminders"]}


def test_plan_falls_back_to_defaults_without_location_consent(monkeypatch, client, headers):
    _db(
        monkeypatch,
        profiles=[{"id": USER_ID, "location_lat": 41.0, "location_lon": 29.0}],
        privacy_preferences=[{"user_id": USER_ID, "location_processing_allowed": False}],
    )

    async def _never_called(lat, lon):
        raise AssertionError("Konum izni yokken hava durumu çekilmemeli")

    monkeypatch.setattr(main, "fetch_weather", _never_called)

    body = client.get("/today/plan", params={"user_id": USER_ID}, headers=headers).json()

    assert body["weather_source"] == "default"


def test_weather_is_cached_per_region_and_time_block(monkeypatch):
    calls = []

    async def _weather(lat, lon):
        calls.append((lat, lon))
        return {"uv_index": 5, "humidity": 50, "temperature": 20}

    monkeypatch.setattr(main, "fetch_weather", _weather)
    main._WEATHER_CACHE.clear()

    first = asyncio.run(main._weather_for_coords(41.0150, 28.9790))
    second = asyncio.run(main._weather_for_coords(41.0210, 28.9755))

    assert first == second
    assert len(calls) == 1


def test_repeated_offline_event_is_written_once(monkeypatch, client, headers):
    db = _db(monkeypatch)
    payload = {
        "user_id": USER_ID,
        "type": "water_intake",
        "payload": {"ml": 250},
        "client_event_id": "mobil-1",
    }

    first = client.post("/daily_tracking/ingest", json=payload, headers=headers)
    second = client.post("/daily_tracking/ingest", json=payload, headers=headers)

    assert first.status_code == 200, first.text
    assert second.json()["aggregated"]["water_ml_total"] == 250
    events = db.tables["daily_events"]
    assert len(events.rows) == 1
    assert events.last_conflict == "user_id,client_event_id"
    assert events.last_ignore_duplicates is True


def test_repeated_offline_event_is_written_once_without_db(monkeypatch, client):
    monkeypatch.setattr(main, "get_supabase", lambda: None)
    payload = {
        "user_id": DEMO_UUID,
        "type": "water_intake",
        "payload": {"ml": 300},
        "client_event_id": "mobil-2",
    }

    client.post("/daily_tracking/ingest", json=payload)
    second = client.post("/daily_tracking/ingest", json=payload)

    assert second.json()["aggregated"]["water_ml_total"] == 300
