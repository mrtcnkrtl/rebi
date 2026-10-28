"""Cihaz kaydı, zamanı gelen hatırlatıcı hesabı ve push dağıtımı."""

from __future__ import annotations

import asyncio
from datetime import datetime, timezone

import jwt
import pytest

import main
import push_service
from tests.fake_supabase import FakeSupabase
from today_plan import due_reminders

USER_ID = "33333333-3333-4333-8333-333333333333"
OTHER_USER_ID = "44444444-4444-4444-8444-444444444444"
SECRET = "test-secret-at-least-32-bytes-long"
DISPATCH_SECRET = "dispatch-secret-abcdefghijklmnop"


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


class _Sender:
    """send_push yerine geçen kayıt tutucu."""

    def __init__(self, sent: int = 1, invalid: list[str] | None = None):
        self.calls: list[dict] = []
        self._sent = sent
        self._invalid = invalid or []

    async def __call__(self, tokens, title, body, data=None, category=None, data_only_tokens=frozenset()):
        self.calls.append({
            "tokens": list(tokens),
            "title": title,
            "data": data or {},
            "category": category,
            "data_only_tokens": set(data_only_tokens),
        })
        return {"status": "sent", "sent": self._sent, "invalid_tokens": list(self._invalid)}


def _enable_push(monkeypatch, sender: _Sender):
    monkeypatch.setenv("PUSH_DISPATCH_SECRET", DISPATCH_SECRET)
    monkeypatch.setattr(main, "push_configured", lambda: True)
    monkeypatch.setattr(main, "send_push", sender)


# ── Zamanı gelen hatırlatıcı hesabı ──────────────────────────────────────────

def test_single_window_reminder_is_due_inside_tolerance():
    reminder = {"id": "routine_morning", "start": "07:30", "end": "09:30"}

    assert [r["slot"] for r in due_reminders([reminder], "07:35")] == ["07:30"]
    assert due_reminders([reminder], "07:45") == []
    assert due_reminders([reminder], "07:25") == []


def test_repeating_reminder_fires_at_each_slot():
    reminder = {"id": "water_intake", "start": "09:00", "end": "21:00", "every_minutes": 120}

    assert [r["slot"] for r in due_reminders([reminder], "09:00")] == ["09:00"]
    assert [r["slot"] for r in due_reminders([reminder], "13:05")] == ["13:00"]
    assert due_reminders([reminder], "14:00") == []


def test_due_reminder_keeps_notification_fields():
    reminder = {
        "id": "water_intake",
        "title": "Su içme zamanı",
        "body": "İçtikçe kaydet.",
        "start": "09:00",
        "end": "21:00",
        "every_minutes": 120,
        "log_event": "water_intake",
    }

    due = due_reminders([reminder], "09:05")[0]

    assert due["title"] == "Su içme zamanı"
    assert due["log_event"] == "water_intake"
    assert due["slot"] == "09:00"


# ── Cihaz kaydı ──────────────────────────────────────────────────────────────

def test_device_registration_upserts_on_token(monkeypatch, client, headers):
    db = _db(monkeypatch)
    monkeypatch.setattr(main, "push_configured", lambda: True)

    r = client.post(
        "/devices/register",
        json={
            "user_id": USER_ID,
            "token": "fcm-token-1",
            "platform": "android",
            "utc_offset_minutes": 180,
            "app_version": "1.0.0",
        },
        headers=headers,
    )

    assert r.status_code == 200, r.text
    assert r.json() == {"ok": True, "push_configured": True, "synced": True, "dispatch_alive": False}
    devices = db.tables["device_tokens"]
    assert devices.last_conflict == "token"
    written = devices.upserted[-1]
    assert written["utc_offset_minutes"] == 180
    assert written["push_enabled"] is True
    assert written["last_seen_at"]


def test_device_registration_clamps_offset_and_rejects_empty_token(monkeypatch, client, headers):
    db = _db(monkeypatch)

    r = client.post(
        "/devices/register",
        json={
            "user_id": USER_ID,
            "token": "fcm-token-2",
            "platform": "ios",
            "utc_offset_minutes": 5000,
        },
        headers=headers,
    )
    assert db.tables["device_tokens"].upserted[-1]["utc_offset_minutes"] == 840

    bad = client.post(
        "/devices/register",
        json={"user_id": USER_ID, "token": "   ", "platform": "ios"},
        headers=headers,
    )
    assert bad.status_code == 422

    wrong_platform = client.post(
        "/devices/register",
        json={"user_id": USER_ID, "token": "t", "platform": "masaustu"},
        headers=headers,
    )
    assert wrong_platform.status_code == 422


def test_unregister_removes_only_own_device(monkeypatch, client, headers):
    db = _db(monkeypatch, device_tokens=[
        {"user_id": USER_ID, "token": "mine", "platform": "ios"},
        {"user_id": OTHER_USER_ID, "token": "theirs", "platform": "ios"},
    ])

    r = client.delete(
        "/devices/register",
        params={"user_id": USER_ID, "token": "theirs"},
        headers=headers,
    )
    assert r.status_code == 200
    assert {row["token"] for row in db.tables["device_tokens"].rows} == {"mine", "theirs"}

    client.delete(
        "/devices/register",
        params={"user_id": USER_ID, "token": "mine"},
        headers=headers,
    )
    assert {row["token"] for row in db.tables["device_tokens"].rows} == {"theirs"}


# ── Dağıtım ──────────────────────────────────────────────────────────────────

def test_dispatch_is_closed_without_secret(monkeypatch, client):
    monkeypatch.delenv("PUSH_DISPATCH_SECRET", raising=False)

    assert client.post("/push/dispatch").status_code == 503


def test_dispatch_rejects_wrong_secret(monkeypatch, client):
    monkeypatch.setenv("PUSH_DISPATCH_SECRET", DISPATCH_SECRET)

    r = client.post("/push/dispatch", headers={"X-Push-Dispatch-Token": "yanlis"})

    assert r.status_code == 401


def test_dispatch_reports_when_push_is_not_configured(monkeypatch, client):
    monkeypatch.setenv("PUSH_DISPATCH_SECRET", DISPATCH_SECRET)
    monkeypatch.setattr(main, "push_configured", lambda: False)

    r = client.post("/push/dispatch", headers={"X-Push-Dispatch-Token": DISPATCH_SECRET})

    assert r.json()["push_configured"] is False
    assert r.json()["notifications_sent"] == 0


def _dispatch(client):
    return client.post("/push/dispatch", headers={"X-Push-Dispatch-Token": DISPATCH_SECRET})


def test_dispatch_sends_due_reminder_once_per_day(monkeypatch, client):
    sender = _Sender()
    _enable_push(monkeypatch, sender)
    db = _db(
        monkeypatch,
        device_tokens=[
            {
                "user_id": USER_ID,
                "token": "fcm-1",
                "platform": "android",
                "utc_offset_minutes": 0,
                "push_enabled": True,
                "last_seen_at": "2026-10-04T10:00:00+00:00",
            },
        ],
        push_sends=[],
    )
    # Tekrar göndermeyi engelleyen şey veritabanındaki unique kısıttır.
    db.tables["push_sends"].unique_on = ("user_id", "reminder_id", "log_date", "slot")
    # Yerel saat 09:05 → su hatırlatıcısının 09:00 penceresi.
    monkeypatch.setattr(main, "due_reminders", lambda plan, now, tol, **_: [
        {
            "id": "water_intake",
            "title": "Su içme zamanı",
            "body": "İçtikçe kaydet.",
            "log_event": "water_intake",
            "slot": "09:00",
        }
    ])

    first = _dispatch(client)
    second = _dispatch(client)

    assert first.status_code == 200, first.text
    body = first.json()
    assert body["users_considered"] == 1
    assert body["reminders_sent"] == 1
    assert body["notifications_sent"] == 1
    assert sender.calls[0]["tokens"] == ["fcm-1"]
    assert sender.calls[0]["data"]["reminder_id"] == "water_intake"
    # İkinci çalıştırma defter yüzünden aynı hatırlatıcıyı göndermez.
    assert second.json()["notifications_sent"] == 0
    assert len(sender.calls) == 1
    assert len(db.tables["push_sends"].rows) == 1


_WATER_DUE = {
    "id": "water_intake",
    "title": "Su içme zamanı",
    "body": "İçtikçe kaydet.",
    "log_event": "water_intake",
    "slot": "09:00",
}


def _one_device(monkeypatch, sender, **extra_tables):
    _enable_push(monkeypatch, sender)
    db = _db(
        monkeypatch,
        device_tokens=[{
            "user_id": USER_ID,
            "token": "fcm-1",
            "platform": "android",
            "utc_offset_minutes": 0,
            "push_enabled": True,
            "last_seen_at": "2026-10-04T10:00:00+00:00",
        }],
        push_sends=[],
        **extra_tables,
    )
    db.tables["push_sends"].unique_on = ("user_id", "reminder_id", "log_date", "slot")
    monkeypatch.setattr(main, "due_reminders", lambda plan, now, tol, **_: [dict(_WATER_DUE)])
    return db


def test_failed_delivery_releases_the_slot_so_the_next_run_retries(monkeypatch, client):
    # FCM'e ulaşılamadı: sent=0, geçersiz token da yok.
    sender = _Sender(sent=0)
    db = _one_device(monkeypatch, sender)

    first = _dispatch(client).json()

    assert first["reminders_sent"] == 0
    assert first["deliveries_failed"] == 1
    assert db.tables["push_sends"].rows == []  # rezerv geri alındı

    # FCM düzeldi: aynı hatırlatıcı bir sonraki turda gider ve bir daha gitmez.
    sender._sent = 1
    second = _dispatch(client).json()
    third = _dispatch(client).json()

    assert second["reminders_sent"] == 1 and second["deliveries_failed"] == 0
    assert third["notifications_sent"] == 0
    assert len(sender.calls) == 2
    assert len(db.tables["push_sends"].rows) == 1


def test_ledger_write_error_is_not_mistaken_for_an_already_sent_reminder(monkeypatch, client, caplog):
    sender = _Sender()
    db = _one_device(monkeypatch, sender)

    def broken_insert(_payload):
        raise RuntimeError("connection reset")

    original_table = db.table

    def table(name):
        t = original_table(name)
        if name == "push_sends":
            t.insert = broken_insert
        return t

    db.table = table

    with caplog.at_level("ERROR"):
        body = _dispatch(client).json()

    assert sender.calls == []  # tekrarı önleyemediğimiz için gönderilmez
    assert body["reminders_sent"] == 0
    assert any("Gönderim defterine yazılamadı" in r.message for r in caplog.records)


def test_a_duplicate_slot_is_still_skipped_quietly(monkeypatch, client, caplog):
    sender = _Sender()
    db = _one_device(monkeypatch, sender)
    today = datetime.now(timezone.utc).date().isoformat()
    db.tables["push_sends"].rows.append(
        {"user_id": USER_ID, "reminder_id": "water_intake", "log_date": today, "slot": "09:00"}
    )

    with caplog.at_level("ERROR"):
        body = _dispatch(client).json()

    assert sender.calls == []
    assert body["deliveries_failed"] == 0
    assert not [r for r in caplog.records if r.levelname == "ERROR"]


def test_health_reports_the_last_dispatch_run(monkeypatch, client):
    main._PUSH_LAST_RUN.clear()
    assert client.get("/health").json()["push_dispatch"] is None

    sender = _Sender()
    _one_device(monkeypatch, sender)
    _dispatch(client)

    last = client.get("/health").json()["push_dispatch"]
    assert last["reminders_sent"] == 1
    assert last["users_considered"] == 1
    assert last["at"]
    main._PUSH_LAST_RUN.clear()


def _offset_for_local_time(hhmm: str) -> int:
    """Cihazın yerel saatini istenen değere getiren UTC farkı."""
    now = datetime.now(timezone.utc)
    target = int(hhmm[:2]) * 60 + int(hhmm[3:])
    delta = (target - (now.hour * 60 + now.minute)) % 1440
    return delta - 1440 if delta > 720 else delta


def test_dispatch_uses_the_real_reminder_plan(monkeypatch, client):
    sender = _Sender()
    _enable_push(monkeypatch, sender)
    db = _db(
        monkeypatch,
        device_tokens=[
            {
                "user_id": USER_ID,
                "token": "fcm-plan",
                "platform": "android",
                "utc_offset_minutes": _offset_for_local_time("09:05"),
                "push_enabled": True,
                "last_seen_at": "2026-10-04T10:00:00+00:00",
            },
        ],
        push_sends=[],
    )
    db.tables["push_sends"].unique_on = ("user_id", "reminder_id", "log_date", "slot")

    _dispatch(client)

    # 09:05'te yalnızca su hatırlatıcısının penceresi açık.
    assert [call["data"]["reminder_id"] for call in sender.calls] == ["water_intake"]


def test_dispatch_removes_invalid_device_tokens(monkeypatch, client):
    sender = _Sender(sent=0, invalid=["fcm-dead"])
    _enable_push(monkeypatch, sender)
    db = _db(monkeypatch, device_tokens=[
        {
            "user_id": USER_ID,
            "token": "fcm-dead",
            "platform": "ios",
            "utc_offset_minutes": 0,
            "push_enabled": True,
            "last_seen_at": "2026-10-04T10:00:00+00:00",
        },
    ])
    monkeypatch.setattr(main, "due_reminders", lambda plan, now, tol, **_: [
        {"id": "daily_checkin", "title": "Check-in", "body": "Cildin nasıldı?", "slot": "21:00"}
    ])

    body = _dispatch(client).json()

    assert body["invalid_tokens_removed"] == 1
    assert body["reminders_sent"] == 0
    assert db.tables["device_tokens"].rows == []


def test_dispatch_skips_devices_with_push_disabled(monkeypatch, client):
    sender = _Sender()
    _enable_push(monkeypatch, sender)
    _db(monkeypatch, device_tokens=[
        {
            "user_id": USER_ID,
            "token": "fcm-off",
            "platform": "ios",
            "utc_offset_minutes": 0,
            "push_enabled": False,
            "last_seen_at": "2026-10-04T10:00:00+00:00",
        },
    ])

    body = _dispatch(client).json()

    assert body["users_considered"] == 0
    assert sender.calls == []


# ── Gönderim servisi ─────────────────────────────────────────────────────────

def test_send_push_is_skipped_without_configuration(monkeypatch):
    monkeypatch.delenv("FCM_SERVICE_ACCOUNT_JSON", raising=False)

    result = asyncio.run(push_service.send_push(["token"], "Başlık", "Gövde"))

    assert result == {"status": "skipped", "sent": 0, "invalid_tokens": []}
    assert push_service.push_configured() is False


def test_send_push_is_skipped_without_tokens(monkeypatch):
    monkeypatch.setenv("FCM_SERVICE_ACCOUNT_JSON", '{"project_id": "rebi-test"}')

    result = asyncio.run(push_service.send_push([], "Başlık", "Gövde"))

    assert result["status"] == "skipped"
    assert push_service.push_configured() is True


def test_push_health_reports_configuration(monkeypatch, client):
    monkeypatch.delenv("FCM_SERVICE_ACCOUNT_JSON", raising=False)
    assert client.get("/health").json()["push"] == "off"

    monkeypatch.setenv("FCM_SERVICE_ACCOUNT_JSON", '{"project_id": "rebi-test"}')
    assert client.get("/health").json()["push"] == "configured"
