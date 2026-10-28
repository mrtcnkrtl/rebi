"""Kullanıcının gün düzenine göre hatırlatıcı pencereleri ve ayar uçları."""

from __future__ import annotations

from datetime import date, datetime, timedelta, timezone

import jwt
import pytest

import main
from tests.fake_supabase import FakeSupabase
from today_plan import (
    DEFAULT_REMINDER_SETTINGS,
    build_reminders,
    normalize_reminder_settings,
    reminder_windows,
)

USER_ID = "55555555-5555-4555-8555-555555555555"
OTHER_USER_ID = "66666666-6666-4666-8666-666666666666"
SECRET = "test-secret-at-least-32-bytes-long"
DISPATCH_SECRET = "dispatch-secret-abcdefghijklmnop"
CALM_WEATHER = {"uv_index": 3, "humidity": 50, "temperature": 20}


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


def _by_id(reminders: list[dict]) -> dict[str, dict]:
    return {r["id"]: r for r in reminders}


# ── Pencereler ──────────────────────────────────────────────────────────────

def test_default_settings_reproduce_the_original_fixed_windows():
    windows = reminder_windows(None)

    assert windows == {
        "routine_morning": ("07:30", "09:30"),
        "makeup_log": ("10:00", "11:00"),
        "spf_refresh": ("11:00", "16:00"),
        "lip_balm": ("12:00", "13:00"),
        "water_intake": ("09:00", "21:00"),
        "nutrition_log": ("20:00", "20:30"),
        "routine_evening": ("21:00", "23:00"),
        "makeup_removal": ("21:00", "23:00"),
        "daily_checkin": ("21:00", "22:30"),
        "restock_check": ("18:00", "19:00"),
    }


def test_windows_follow_wake_and_sleep_times():
    windows = reminder_windows({"wake_time": "06:00", "sleep_time": "22:00"})

    assert windows["routine_morning"] == ("06:00", "08:00")
    assert windows["water_intake"] == ("07:30", "20:00")
    assert windows["routine_evening"] == ("20:00", "22:00")
    assert windows["daily_checkin"] == ("20:00", "21:30")
    assert windows["nutrition_log"] == ("19:00", "19:30")


def test_every_window_stays_inside_the_awake_day_and_is_ordered():
    for wake, sleep in [("04:00", "13:00"), ("04:00", "23:59"), ("10:00", "23:59"), ("06:15", "21:40")]:
        windows = reminder_windows({"wake_time": wake, "sleep_time": sleep})
        for reminder_id, (start, end) in windows.items():
            assert wake <= start <= end <= sleep, (reminder_id, wake, sleep, start, end)


def test_broken_settings_fall_back_to_defaults():
    assert normalize_reminder_settings(None) == DEFAULT_REMINDER_SETTINGS
    assert normalize_reminder_settings("bozuk") == DEFAULT_REMINDER_SETTINGS

    broken = normalize_reminder_settings({
        "wake_time": "25:00",
        "sleep_time": "23:00",
        "water_every_minutes": 45,
        "enabled": {"water": "yes", "spf": False, "uydurma": False},
    })

    assert broken["wake_time"] == "07:30", "geçersiz saat ikisini birden varsayılana döndürür"
    assert broken["water_every_minutes"] == 120
    assert broken["water_target_ml"] == 2000
    assert broken["enabled"]["water"] is True
    assert broken["enabled"]["spf"] is False
    assert "uydurma" not in broken["enabled"]


def test_too_short_or_out_of_range_day_is_rejected_as_a_pair():
    for wake, sleep in [("10:00", "17:00"), ("03:00", "23:00"), ("08:00", "08:00")]:
        s = normalize_reminder_settings({"wake_time": wake, "sleep_time": sleep})
        assert (s["wake_time"], s["sleep_time"]) == ("07:30", "23:00"), (wake, sleep)


# ── Hatırlatıcılar ──────────────────────────────────────────────────────────

def test_reminders_use_the_users_day_and_water_interval():
    settings = {"wake_time": "06:00", "sleep_time": "22:00", "water_every_minutes": 60}

    reminders = _by_id(build_reminders(CALM_WEATHER, {}, settings=settings))

    assert (reminders["routine_morning"]["start"], reminders["routine_morning"]["end"]) == ("06:00", "08:00")
    assert reminders["water_intake"]["every_minutes"] == 60
    assert (reminders["water_intake"]["start"], reminders["water_intake"]["end"]) == ("07:30", "20:00")


def test_disabled_categories_are_dropped_but_others_stay():
    settings = {"enabled": {"water": False, "makeup": False, "checkin": False}}

    ids = set(_by_id(build_reminders(CALM_WEATHER, {}, settings=settings)))

    assert not ids & {"water_intake", "makeup_log", "makeup_removal", "daily_checkin"}
    assert {"routine_morning", "routine_evening", "nutrition_log"} <= ids


def test_disabling_a_category_also_drops_its_conditional_reminders():
    settings = {"enabled": {"makeup": False, "spf": False, "lip_balm": False}}
    weather = {"uv_index": 9, "humidity": 20, "temperature": 5}
    aggregated = {"makeup": {"logged": True, "used": True, "removed": False}}

    ids = set(_by_id(build_reminders(weather, aggregated, settings=settings)))

    assert not ids & {"makeup_removal", "spf_refresh", "lip_balm"}


def test_reminders_stay_sorted_by_start_for_any_day():
    reminders = build_reminders(CALM_WEATHER, {}, settings={"wake_time": "09:00", "sleep_time": "23:30"})

    starts = [r["start"] for r in reminders]
    assert starts == sorted(starts)


# ── Uçlar ───────────────────────────────────────────────────────────────────

def test_settings_default_when_nothing_is_stored(monkeypatch, client, headers):
    _db(monkeypatch)

    r = client.get("/me/reminder-settings", params={"user_id": USER_ID}, headers=headers)

    assert r.status_code == 200, r.text
    body = r.json()
    assert body["settings"] == DEFAULT_REMINDER_SETTINGS
    assert body["synced"] is True


def test_settings_are_saved_merged_and_read_back(monkeypatch, client, headers):
    db = _db(monkeypatch)

    first = client.put(
        "/me/reminder-settings",
        json={"user_id": USER_ID, "wake_time": "06:30", "water_every_minutes": 90},
        headers=headers,
    )
    second = client.put(
        "/me/reminder-settings",
        json={"user_id": USER_ID, "enabled": {"spf": False}},
        headers=headers,
    )
    read = client.get("/me/reminder-settings", params={"user_id": USER_ID}, headers=headers)

    assert first.status_code == 200, first.text
    assert second.status_code == 200, second.text
    settings = read.json()["settings"]
    assert settings["wake_time"] == "06:30"
    assert settings["sleep_time"] == "23:00", "gönderilmeyen alan değişmez"
    assert settings["water_every_minutes"] == 90, "ikinci kayıt öncekini silmez"
    assert settings["enabled"]["spf"] is False
    assert settings["enabled"]["water"] is True
    assert db.tables["reminder_settings"].rows[0]["user_id"] == USER_ID
    assert db.tables["reminder_settings"].last_conflict == "user_id"


@pytest.mark.parametrize(
    "body",
    [
        {"wake_time": "7.30"},
        {"sleep_time": "yarın"},
        {"wake_time": "12:00", "sleep_time": "18:00"},
        {"wake_time": "03:00"},
        {"sleep_time": "05:00"},
        {"water_every_minutes": 45},
        {"water_target_ml": 500},
        {"water_target_ml": 2100},
        {"enabled": {"uydurma": True}},
    ],
)
def test_invalid_settings_are_rejected_and_nothing_is_stored(monkeypatch, client, headers, body):
    db = _db(monkeypatch)

    r = client.put("/me/reminder-settings", json={"user_id": USER_ID, **body}, headers=headers)

    assert r.status_code == 422, r.text
    assert db.tables.get("reminder_settings") is None or not db.tables["reminder_settings"].rows


def test_settings_of_another_user_are_forbidden(monkeypatch, client, headers):
    _db(monkeypatch)

    assert client.get("/me/reminder-settings", params={"user_id": OTHER_USER_ID}, headers=headers).status_code == 403
    assert client.put(
        "/me/reminder-settings", json={"user_id": OTHER_USER_ID, "wake_time": "06:00"}, headers=headers
    ).status_code == 403


def test_settings_without_a_database_are_kept_in_memory(monkeypatch, client):
    monkeypatch.setattr(main, "get_supabase", lambda: None)
    uid = "00000000-0000-4000-8000-000000000001"

    put = client.put("/me/reminder-settings", json={"user_id": uid, "sleep_time": "22:30"})
    read = client.get("/me/reminder-settings", params={"user_id": uid})

    assert put.status_code == 200, put.text
    assert put.json()["synced"] is False
    assert read.json()["settings"]["sleep_time"] == "22:30"
    main._MEM_REMINDER_SETTINGS.pop(uid, None)


def test_unreadable_settings_table_falls_back_to_defaults(monkeypatch, client, headers):
    class _Broken:
        def table(self, _name):
            raise RuntimeError("tablo yok")

    monkeypatch.setattr(main, "get_supabase", lambda: _Broken())

    r = client.get("/me/reminder-settings", params={"user_id": USER_ID}, headers=headers)

    assert r.status_code == 200
    assert r.json()["settings"] == DEFAULT_REMINDER_SETTINGS


def test_plan_applies_stored_settings_and_returns_them(monkeypatch, client, headers):
    _db(monkeypatch, reminder_settings=[{
        "user_id": USER_ID,
        "settings": {
            "wake_time": "06:00",
            "sleep_time": "22:00",
            "water_every_minutes": 180,
            "enabled": {"checkin": False},
        },
    }])

    r = client.get("/today/plan", params={"user_id": USER_ID}, headers=headers)

    assert r.status_code == 200, r.text
    body = r.json()
    reminders = _by_id(body["reminders"])
    assert body["reminder_settings"]["wake_time"] == "06:00"
    assert reminders["routine_morning"]["start"] == "06:00"
    assert reminders["water_intake"]["every_minutes"] == 180
    assert "daily_checkin" not in reminders


def test_plan_without_stored_settings_keeps_the_original_windows(monkeypatch, client, headers):
    _db(monkeypatch)

    body = client.get("/today/plan", params={"user_id": USER_ID}, headers=headers).json()

    assert body["reminder_settings"] == DEFAULT_REMINDER_SETTINGS
    assert _by_id(body["reminders"])["routine_morning"]["start"] == "07:30"


# ── Push dağıtımı ───────────────────────────────────────────────────────────

class _Sender:
    def __init__(self):
        self.calls: list[dict] = []

    async def __call__(self, tokens, title, body, data=None, **_kwargs):
        self.calls.append({"tokens": list(tokens), "data": data or {}})
        return {"status": "sent", "sent": 1, "invalid_tokens": []}


def _offset_for_local_time(hhmm: str) -> int:
    now = datetime.now(timezone.utc)
    target = int(hhmm[:2]) * 60 + int(hhmm[3:])
    delta = (target - (now.hour * 60 + now.minute)) % 1440
    return delta - 1440 if delta > 720 else delta


def _device(uid: str, token: str, local_time: str) -> dict:
    return {
        "user_id": uid,
        "token": token,
        "platform": "android",
        "utc_offset_minutes": _offset_for_local_time(local_time),
        "push_enabled": True,
        "last_seen_at": "2026-10-04T10:00:00+00:00",
    }


def test_dispatch_sends_on_the_users_own_schedule(monkeypatch, client):
    sender = _Sender()
    monkeypatch.setenv("PUSH_DISPATCH_SECRET", DISPATCH_SECRET)
    monkeypatch.setattr(main, "push_configured", lambda: True)
    monkeypatch.setattr(main, "send_push", sender)
    db = _db(
        monkeypatch,
        device_tokens=[
            _device(USER_ID, "erken-kalkan", "06:05"),
            _device(OTHER_USER_ID, "varsayilan", "06:05"),
        ],
        reminder_settings=[{"user_id": USER_ID, "settings": {"wake_time": "06:00", "sleep_time": "22:00"}}],
        push_sends=[],
    )
    db.tables["push_sends"].unique_on = ("user_id", "reminder_id", "log_date", "slot")

    r = client.post("/push/dispatch", headers={"X-Push-Dispatch-Token": DISPATCH_SECRET})

    assert r.status_code == 200, r.text
    # 06:05'te yalnızca erken kalkanın sabah rutini penceresi (06:00) açık; varsayılan kullanıcı için 07:30.
    assert [(c["tokens"], c["data"]["reminder_id"]) for c in sender.calls] == [(["erken-kalkan"], "routine_morning")]


def test_dispatch_skips_categories_the_user_turned_off(monkeypatch, client):
    sender = _Sender()
    monkeypatch.setenv("PUSH_DISPATCH_SECRET", DISPATCH_SECRET)
    monkeypatch.setattr(main, "push_configured", lambda: True)
    monkeypatch.setattr(main, "send_push", sender)
    _db(
        monkeypatch,
        device_tokens=[_device(USER_ID, "sessiz", "07:35")],
        reminder_settings=[{"user_id": USER_ID, "settings": {"enabled": {"routine": False}}}],
        push_sends=[],
    )

    client.post("/push/dispatch", headers={"X-Push-Dispatch-Token": DISPATCH_SECRET})

    assert sender.calls == []


# ── Gün sınırı ───────────────────────────────────────────────────────────────

def test_event_timestamp_with_offset_keeps_the_local_day():
    assert main._safe_date_from_timestamp("2026-10-05T00:30:00+03:00") == "2026-10-05"
    assert main._safe_date_from_timestamp("2026-10-04T23:30:00-05:00") == "2026-10-04"


def test_event_timestamp_without_offset_is_a_utc_day():
    assert main._safe_date_from_timestamp("2026-10-04T21:30:00Z") == "2026-10-04"
    assert main._safe_date_from_timestamp("2026-10-04T21:30:00") == "2026-10-04"


def test_unparseable_timestamp_falls_back_to_today():
    assert main._safe_date_from_timestamp("dün") == str(date.today())
    assert main._safe_date_from_timestamp(None) == str(date.today())


def test_local_today_follows_the_clients_offset():
    assert main._local_today(None) == date.today()

    before = datetime.now(timezone.utc)
    ahead = main._local_today(14 * 60)
    behind = main._local_today(-12 * 60)
    after = datetime.now(timezone.utc)

    assert ahead in {(t + timedelta(hours=14)).date() for t in (before, after)}
    assert behind in {(t - timedelta(hours=12)).date() for t in (before, after)}
    # Anlamsız fark güvenli aralığa çekilir.
    assert main._local_today(99999) == main._local_today(840)


def test_ingest_at_half_past_midnight_lands_on_the_local_day(monkeypatch, client, headers):
    db = _db(monkeypatch)

    r = client.post(
        "/daily_tracking/ingest",
        json={
            "user_id": USER_ID,
            "type": "water_intake",
            "payload": {"ml": 250},
            "timestamp": "2026-10-05T00:30:00+03:00",
            "client_event_id": "gece-yarisi",
        },
        headers=headers,
    )

    assert r.status_code == 200, r.text
    assert r.json()["log_date"] == "2026-10-05"
    assert db.tables["daily_events"].upserted[0]["log_date"] == "2026-10-05"


def test_plan_reads_the_users_local_day(monkeypatch, client, headers):
    tomorrow_for_the_user = str(main._local_today(14 * 60))
    _db(monkeypatch, daily_events=[{
        "user_id": USER_ID,
        "type": "water_intake",
        "payload": {"ml": 700},
        "log_date": tomorrow_for_the_user,
        "event_time": "2026-10-05T00:30:00+14:00",
    }])

    shifted = client.get(
        "/today/plan", params={"user_id": USER_ID, "utc_offset_minutes": 14 * 60}, headers=headers
    ).json()

    assert shifted["log_date"] == tomorrow_for_the_user
    assert shifted["progress"]["water_ml_total"] == 700


def test_offset_outside_the_valid_range_is_rejected(monkeypatch, client, headers):
    _db(monkeypatch)

    r = client.get("/today/plan", params={"user_id": USER_ID, "utc_offset_minutes": 5000}, headers=headers)

    assert r.status_code == 422


# ── Günlük su hedefi ─────────────────────────────────────────────────────────

def _water(reminders):
    return next((r for r in reminders if r["id"] == "water_intake"), None)


def test_water_target_defaults_to_two_litres_and_survives_garbage():
    assert normalize_reminder_settings(None)["water_target_ml"] == 2000
    assert normalize_reminder_settings({"water_target_ml": 2500})["water_target_ml"] == 2500
    for bad in (1234, "2500", None, True, -1):
        assert normalize_reminder_settings({"water_target_ml": bad})["water_target_ml"] == 2000, bad


def test_water_reminder_stops_at_the_users_own_target():
    below_default = {"water_ml_total": 2200}

    assert _water(build_reminders(CALM_WEATHER, below_default)) is None  # 2000 ml hedefi aşıldı
    r = _water(build_reminders(CALM_WEATHER, below_default, settings={"water_target_ml": 2500}))
    assert r is not None and "2500 ml" in r["body"]
    assert _water(build_reminders(CALM_WEATHER, {"water_ml_total": 1600}, settings={"water_target_ml": 1500})) is None


def test_water_target_is_saved_and_merged_like_other_fields(monkeypatch, client, headers):
    _db(monkeypatch)

    put = client.put("/me/reminder-settings", json={"user_id": USER_ID, "water_target_ml": 2500}, headers=headers)
    again = client.put("/me/reminder-settings", json={"user_id": USER_ID, "wake_time": "06:30"}, headers=headers)
    read = client.get("/me/reminder-settings", params={"user_id": USER_ID}, headers=headers)

    assert put.status_code == 200, put.text
    assert put.json()["settings"]["water_target_ml"] == 2500
    assert again.json()["settings"]["water_target_ml"] == 2500, "başka alanı kaydetmek hedefi silmez"
    assert read.json()["settings"]["water_target_ml"] == 2500


def test_plan_returns_the_target_and_uses_it_for_the_water_reminder(monkeypatch, client, headers):
    _db(
        monkeypatch,
        reminder_settings=[{"user_id": USER_ID, "settings": {"water_target_ml": 3000}}],
        daily_events=[{
            "user_id": USER_ID, "log_date": str(date.today()), "event_time": "2026-10-16T09:00:00+00:00",
            "type": "water_intake", "payload": {"ml": 2400},
        }],
    )

    body = client.get("/today/plan", params={"user_id": USER_ID}, headers=headers).json()

    assert body["reminder_settings"]["water_target_ml"] == 3000
    assert _water(body["reminders"]) is not None, "2400 ml, 3000 ml hedefinin altında: hatırlatıcı sürer"
