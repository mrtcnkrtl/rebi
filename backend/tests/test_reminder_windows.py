"""Faz E: kullanıcının kendi saat aralıkları, sessiz saatler ve push dağıtıcısının canlılığı."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

import jwt
import pytest

import main
from tests.fake_supabase import FakeSupabase
from today_plan import (
    build_reminders,
    due_reminders,
    in_quiet,
    normalize_reminder_settings,
    reminder_windows,
)

USER_ID = "77777777-7777-4777-8777-777777777777"
SECRET = "test-secret-at-least-32-bytes-long"
DISPATCH_SECRET = "dispatch-secret-abcdefghijklmnop"
CALM_WEATHER = {"uv_index": 3, "humidity": 50, "temperature": 20}


@pytest.fixture(autouse=True)
def _fresh_write_limits():
    """Bu dosya çok sayıda PUT yapar; süreç içi kayıt sınırı (30/saat) diğer test dosyalarının bütçesini yemesin."""
    limiter = main.LIMIT_USER_PROFILE_WRITE
    hits = getattr(limiter, "_hits", None)
    if hits is not None:
        hits.clear()
    yield
    if hits is not None:
        hits.clear()


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


def _put(client, headers, **body):
    return client.put("/me/reminder-settings", json={"user_id": USER_ID, **body}, headers=headers)


def _settings(client, headers) -> dict:
    return client.get("/me/reminder-settings", params={"user_id": USER_ID}, headers=headers).json()["settings"]


# ── Pencere düzenleme: model ────────────────────────────────────────────────

def test_a_users_window_replaces_the_default_one():
    windows = reminder_windows({"windows": {"lip_balm": {"start": "15:00", "end": "16:00"}}})

    assert windows["lip_balm"] == ("15:00", "16:00")
    assert windows["spf_refresh"] == ("11:00", "16:00"), "dokunulmayan pencere varsayılan kalır"


def test_a_users_window_is_clamped_to_the_awake_day():
    # Gün sonradan daraltıldı: 08:00–22:00; kayıtlı pencere gün dışına taşıyor.
    windows = reminder_windows(
        {
            "wake_time": "08:00",
            "sleep_time": "22:00",
            "windows": {"routine_morning": {"start": "06:00", "end": "09:00"}},
        }
    )

    assert windows["routine_morning"] == ("08:00", "09:00")


def test_a_window_squeezed_to_nothing_by_the_day_falls_back_to_the_default():
    windows = reminder_windows(
        {
            "wake_time": "09:00",
            "sleep_time": "22:00",
            "windows": {"routine_morning": {"start": "06:00", "end": "08:00"}},
        }
    )

    assert windows["routine_morning"] == ("09:00", "11:00")


def test_garbage_windows_are_dropped_when_settings_are_read():
    cleaned = normalize_reminder_settings(
        {
            "windows": {
                "uydurma": {"start": "10:00", "end": "11:00"},
                "lip_balm": {"start": "13:00", "end": "12:00"},
                "makeup_log": {"start": "10:00", "end": "10:10"},
                "nutrition_log": {"start": "yirmi", "end": "21:00"},
                "daily_checkin": "21:00",
                "water_intake": {"start": "10:00", "end": "18:00"},
            }
        }
    )

    assert cleaned["windows"] == {"water_intake": {"start": "10:00", "end": "18:00"}}


def test_the_users_spf_window_beats_the_uv_window():
    weather = {"uv_index": 8, "humidity": 50, "temperature": 24, "uv_window": {"start": "12:00", "end": "15:00"}}

    by_uv = {r["id"]: r for r in build_reminders(weather, {}, False, None)}
    by_user = {
        r["id"]: r
        for r in build_reminders(
            weather, {}, False, {"windows": {"spf_refresh": {"start": "09:00", "end": "10:00"}}}
        )
    }

    assert (by_uv["spf_refresh"]["start"], by_uv["spf_refresh"]["end"]) == ("12:00", "15:00")
    assert (by_user["spf_refresh"]["start"], by_user["spf_refresh"]["end"]) == ("09:00", "10:00")


def test_a_users_water_window_drives_the_water_slots():
    plan = build_reminders(
        CALM_WEATHER,
        {},
        False,
        {"water_every_minutes": 60, "windows": {"water_intake": {"start": "10:00", "end": "13:00"}}},
    )
    water = next(r for r in plan if r["id"] == "water_intake")

    assert (water["start"], water["end"]) == ("10:00", "13:00")
    assert [d["slot"] for d in due_reminders([water], "12:03", tolerance_minutes=10)] == ["12:00"]
    assert due_reminders([water], "14:00", tolerance_minutes=10) == []


# ── Sessiz saatler ──────────────────────────────────────────────────────────

@pytest.mark.parametrize(
    "minute, expected",
    [
        (12 * 60, False),
        (13 * 60, True),
        (13 * 60 + 59, True),
        (14 * 60, False),
    ],
)
def test_quiet_hours_within_a_day(minute, expected):
    assert in_quiet(minute, {"start": "13:00", "end": "14:00"}) is expected


@pytest.mark.parametrize(
    "minute, expected",
    [
        (22 * 60, True),
        (23 * 60 + 59, True),
        (0, True),
        (6 * 60 + 59, True),
        (7 * 60, False),
        (12 * 60, False),
        (21 * 60 + 59, False),
    ],
)
def test_quiet_hours_may_cross_midnight(minute, expected):
    assert in_quiet(minute, {"start": "22:00", "end": "07:00"}) is expected


def test_no_quiet_hours_never_silences_anything():
    assert in_quiet(12 * 60, None) is False
    assert in_quiet(12 * 60, {"start": "12:00", "end": "12:00"}) is False
    assert in_quiet(12 * 60, {"start": "yarin", "end": "07:00"}) is False


def test_quiet_hours_drop_the_slots_that_fall_inside_them():
    water = {"id": "water_intake", "start": "09:00", "end": "13:00", "every_minutes": 60}
    quiet = {"start": "10:30", "end": "11:30"}

    def slot_at(local_time: str):
        return [d["slot"] for d in due_reminders([water], local_time, tolerance_minutes=10, quiet=quiet)]

    assert slot_at("10:05") == ["10:00"]
    assert slot_at("11:05") == [], "11:00 yuvası sessiz saate (10:30–11:30) denk geliyor"
    assert slot_at("12:05") == ["12:00"]
    assert [d["slot"] for d in due_reminders([water], "11:05", tolerance_minutes=10)] == ["11:00"], "sessiz saat yoksa gider"


def test_a_one_shot_reminder_inside_quiet_hours_moves_to_their_end_when_the_window_allows():
    spot = {"id": "lip_balm", "start": "12:00", "end": "13:00", "every_minutes": None}
    quiet = {"start": "11:30", "end": "12:30"}

    assert due_reminders([spot], "12:00", quiet=quiet) == []
    assert [d["slot"] for d in due_reminders([spot], "12:31", quiet=quiet)] == ["12:30"]


def test_a_one_shot_reminder_entirely_inside_quiet_hours_is_silenced():
    spot = {"id": "nutrition_log", "start": "20:00", "end": "20:30", "every_minutes": None}
    quiet = {"start": "19:00", "end": "22:00"}

    assert due_reminders([spot], "20:10", quiet=quiet) == []
    assert due_reminders([spot], "22:00", quiet=quiet) == []


# ── Ayar uçları ─────────────────────────────────────────────────────────────

def test_windows_and_quiet_default_to_empty(monkeypatch, client, headers):
    _db(monkeypatch)

    settings = _settings(client, headers)

    assert settings["windows"] == {}
    assert settings["quiet"] is None


def test_windows_and_quiet_are_saved_merged_and_read_back(monkeypatch, client, headers):
    _db(monkeypatch)

    first = _put(client, headers, windows={"lip_balm": {"start": "15:00", "end": "16:00"}})
    second = _put(client, headers, windows={"water_intake": {"start": "10:00", "end": "18:00"}}, quiet={"start": "13:00", "end": "14:00"})
    third = _put(client, headers, water_every_minutes=60)

    assert first.status_code == second.status_code == third.status_code == 200
    settings = _settings(client, headers)
    assert settings["windows"] == {
        "lip_balm": {"start": "15:00", "end": "16:00"},
        "water_intake": {"start": "10:00", "end": "18:00"},
    }, "ikinci kayıt ilk pencereyi silmez, ilgisiz bir güncelleme de dokunmaz"
    assert settings["quiet"] == {"start": "13:00", "end": "14:00"}


def test_null_resets_one_window_or_all_of_them_and_clears_quiet(monkeypatch, client, headers):
    _db(monkeypatch)
    _put(
        client,
        headers,
        windows={"lip_balm": {"start": "15:00", "end": "16:00"}, "makeup_log": {"start": "09:00", "end": "09:45"}},
        quiet={"start": "22:00", "end": "07:00"},
    )

    one = _put(client, headers, windows={"lip_balm": None})
    assert one.json()["settings"]["windows"] == {"makeup_log": {"start": "09:00", "end": "09:45"}}
    assert one.json()["settings"]["quiet"] == {"start": "22:00", "end": "07:00"}, "gönderilmeyen alan değişmez"

    everything = _put(client, headers, windows=None, quiet=None)
    assert everything.json()["settings"]["windows"] == {}
    assert everything.json()["settings"]["quiet"] is None


@pytest.mark.parametrize(
    "body",
    [
        {"windows": {"uydurma": {"start": "10:00", "end": "11:00"}}},
        {"windows": {"lip_balm": {"start": "10:00", "end": "10:10"}}},
        {"windows": {"lip_balm": {"start": "14:00", "end": "12:00"}}},
        {"windows": {"lip_balm": {"start": "yarim", "end": "12:00"}}},
        {"windows": {"lip_balm": {"start": "12:00"}}},
        {"windows": {"lip_balm": {"start": "06:00", "end": "08:00"}}},
        {"windows": {"lip_balm": {"start": "21:00", "end": "23:30"}}},
        {"quiet": {"start": "13:00", "end": "13:00"}},
        {"quiet": {"start": "13:00"}},
        {"quiet": {"start": "ogle", "end": "14:00"}},
    ],
)
def test_invalid_windows_and_quiet_are_rejected_and_nothing_is_stored(monkeypatch, client, headers, body):
    db = _db(monkeypatch)

    r = _put(client, headers, **body)

    assert r.status_code == 422, r.text
    assert db.tables.get("reminder_settings") is None or not db.tables["reminder_settings"].rows


def test_windows_are_validated_against_the_day_sent_in_the_same_request(monkeypatch, client, headers):
    _db(monkeypatch)

    ok = _put(client, headers, wake_time="06:00", sleep_time="23:30", windows={"routine_morning": {"start": "06:00", "end": "07:00"}})
    bad = _put(client, headers, wake_time="09:00", windows={"routine_morning": {"start": "06:00", "end": "07:00"}})

    assert ok.status_code == 200, ok.text
    assert bad.status_code == 422, bad.text


def test_plan_uses_the_users_windows_and_returns_them(monkeypatch, client, headers):
    _db(monkeypatch)
    _put(client, headers, windows={"lip_balm": {"start": "15:00", "end": "16:00"}}, quiet={"start": "13:00", "end": "14:00"})

    r = client.get("/today/plan", params={"user_id": USER_ID}, headers=headers)

    assert r.status_code == 200, r.text
    body = r.json()
    assert body["reminder_settings"]["windows"] == {"lip_balm": {"start": "15:00", "end": "16:00"}}
    assert body["reminder_settings"]["quiet"] == {"start": "13:00", "end": "14:00"}
    lip_balm = [r for r in body["reminders"] if r["id"] == "lip_balm"]
    assert all((r["start"], r["end"]) == ("15:00", "16:00") for r in lip_balm), "plan, kullanıcının penceresini yansıtır"


# ── Dağıtım ─────────────────────────────────────────────────────────────────

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


def _device(local_time: str) -> dict:
    return {
        "user_id": USER_ID,
        "token": "cihaz",
        "platform": "android",
        "utc_offset_minutes": _offset_for_local_time(local_time),
        "push_enabled": True,
        "last_seen_at": "2026-10-04T10:00:00+00:00",
    }


def _dispatch(monkeypatch, client, sender, settings, local_time):
    monkeypatch.setenv("PUSH_DISPATCH_SECRET", DISPATCH_SECRET)
    monkeypatch.setattr(main, "push_configured", lambda: True)
    monkeypatch.setattr(main, "send_push", sender)
    db = _db(
        monkeypatch,
        device_tokens=[_device(local_time)],
        reminder_settings=[{"user_id": USER_ID, "settings": settings}],
        push_sends=[],
    )
    db.tables["push_sends"].unique_on = ("user_id", "reminder_id", "log_date", "slot")
    return client.post("/push/dispatch", headers={"X-Push-Dispatch-Token": DISPATCH_SECRET})


def test_dispatch_uses_the_users_own_window(monkeypatch, client):
    sender = _Sender()

    r = _dispatch(
        monkeypatch,
        client,
        sender,
        {"windows": {"routine_morning": {"start": "09:00", "end": "10:00"}}},
        "09:02",
    )

    assert r.status_code == 200, r.text
    # 09:00'da varsayılan su penceresi de açılır; kullanıcının sabah rutini penceresi (09:00) ayrıca gelir.
    assert "routine_morning" in [c["data"]["reminder_id"] for c in sender.calls]


def test_dispatch_stays_silent_in_quiet_hours(monkeypatch, client):
    sender = _Sender()

    r = _dispatch(monkeypatch, client, sender, {"quiet": {"start": "07:00", "end": "08:00"}}, "07:35")

    assert r.status_code == 200, r.text
    assert sender.calls == [], "07:30 sabah rutini sessiz saate denk geliyor"


def test_dispatch_after_quiet_hours_sends_normally(monkeypatch, client):
    sender = _Sender()

    _dispatch(monkeypatch, client, sender, {"quiet": {"start": "07:00", "end": "07:20"}}, "07:35")

    assert [c["data"]["reminder_id"] for c in sender.calls] == ["routine_morning"]


# ── Dağıtıcı canlı mı ───────────────────────────────────────────────────────

def _register(client, headers):
    return client.post(
        "/devices/register",
        json={"user_id": USER_ID, "token": "fcm-1", "platform": "android", "utc_offset_minutes": 180},
        headers=headers,
    )


def test_registration_reports_a_dead_dispatcher_when_it_never_ran(monkeypatch, client, headers):
    _db(monkeypatch)
    main._PUSH_LAST_RUN.clear()

    body = _register(client, headers).json()

    assert body["dispatch_alive"] is False


def test_registration_reports_a_live_dispatcher_after_a_recent_run(monkeypatch, client, headers):
    _db(monkeypatch)
    main._PUSH_LAST_RUN.clear()
    main._PUSH_LAST_RUN.update(at=main._utc_now_iso())

    try:
        assert _register(client, headers).json()["dispatch_alive"] is True
    finally:
        main._PUSH_LAST_RUN.clear()


def test_registration_reports_a_dispatcher_that_went_quiet_as_dead(monkeypatch, client, headers):
    _db(monkeypatch)
    main._PUSH_LAST_RUN.clear()
    main._PUSH_LAST_RUN.update(at=(datetime.now(timezone.utc) - timedelta(minutes=45)).isoformat())

    try:
        assert _register(client, headers).json()["dispatch_alive"] is False
    finally:
        main._PUSH_LAST_RUN.clear()


def test_a_dispatch_round_makes_the_dispatcher_count_as_alive(monkeypatch, client, headers):
    sender = _Sender()
    main._PUSH_LAST_RUN.clear()
    try:
        _dispatch(monkeypatch, client, sender, {}, "03:00")

        assert _register(client, headers).json()["dispatch_alive"] is True
    finally:
        main._PUSH_LAST_RUN.clear()


# ── Geçmiş: kullanıcının su hedefi ──────────────────────────────────────────

def test_history_reports_the_users_water_target(monkeypatch, client, headers):
    _db(monkeypatch, reminder_settings=[{"user_id": USER_ID, "settings": {"water_target_ml": 2500}}])

    r = client.get("/me/history", params={"user_id": USER_ID, "days": 7}, headers=headers)

    assert r.status_code == 200, r.text
    assert r.json()["water_target_ml"] == 2500


def test_history_water_target_defaults_to_two_litres(monkeypatch, client, headers):
    _db(monkeypatch)

    r = client.get("/me/history", params={"user_id": USER_ID, "days": 7}, headers=headers)

    assert r.json()["water_target_ml"] == 2000


def test_history_still_loads_when_settings_are_unreadable(monkeypatch, client, headers):
    db = _db(monkeypatch)

    def broken(*_a, **_k):
        raise RuntimeError("settings down")

    monkeypatch.setattr(main, "_load_reminder_settings", broken)
    r = client.get("/me/history", params={"user_id": USER_ID, "days": 7}, headers=headers)

    assert r.status_code == 200, r.text
    assert r.json()["water_target_ml"] == 2000
    assert db is not None
