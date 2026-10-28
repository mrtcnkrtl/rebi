"""Bildirim butonlarıyla günlük veri toplama: plan, gönderim ve cevap ucu."""

from __future__ import annotations

import json
import typing
from datetime import datetime, timedelta, timezone

import pytest

import main
import push_service
from tests.test_push import (
    OTHER_USER_ID,
    USER_ID,
    _Sender,
    _db,
    _dispatch,
    _enable_push,
    headers,  # noqa: F401 — fixture
)
from today_plan import REMINDER_ACTIONS, build_reminders


def _today() -> str:
    return datetime.now(timezone.utc).date().isoformat()


# ── Plan ─────────────────────────────────────────────────────────────────────

def test_every_action_writes_a_known_event_type():
    allowed = set(typing.get_args(main.DailyTrackingClientEventType))

    for reminder_id, actions in REMINDER_ACTIONS.items():
        assert 1 <= len(actions) <= 3, reminder_id
        for action in actions:
            assert action["log_event"] in allowed, (reminder_id, action["id"])


def test_reminders_carry_actions_category_and_open_path():
    plan = {r["id"]: r for r in build_reminders({"uv_index": 7}, {}, checkin_done=False)}

    water = plan["water_intake"]
    assert water["category"] == "water_intake"
    assert [a["id"] for a in water["actions"]] == ["ml_250", "ml_500"]
    assert plan["daily_checkin"]["actions"] == []
    assert plan["daily_checkin"]["open_path"] == "/dashboard/checkin"
    assert plan["routine_morning"]["open_path"] == "/dashboard"


def test_plan_actions_are_copies():
    plan = build_reminders({}, {}, checkin_done=True)
    plan[0]["actions"][0]["payload"]["tampered"] = True

    assert all("tampered" not in a["payload"] for a in sum(REMINDER_ACTIONS.values(), []))


def test_actions_catalog_lists_categories(client):
    body = client.get("/push/actions").json()
    by_id = {c["id"]: c for c in body["categories"]}

    assert by_id["makeup_removal"]["actions"][0] == {"id": "double", "label": "Çift temizlik"}
    # Yük istemciye gitmez; cevabı sunucu çözer.
    assert "payload" not in by_id["water_intake"]["actions"][0]


# ── Cevap ucu ────────────────────────────────────────────────────────────────

def _respond(client, headers, **body):
    return client.post("/push/respond", json={"user_id": USER_ID, **body}, headers=headers)


def test_respond_writes_server_defined_event(monkeypatch, client, headers):
    db = _db(monkeypatch, daily_events=[], push_sends=[])

    r = _respond(
        client, headers,
        reminder_id="water_intake", action_id="ml_500", log_date=_today(), slot="13:00",
    )

    assert r.status_code == 200, r.text
    body = r.json()
    assert body["log_event"] == "water_intake"
    assert body["aggregated"]["water_ml_total"] == 500
    event = db.tables["daily_events"].rows[0]
    assert event["payload"] == {"ml": 500}
    assert event["source"] == "push"
    assert event["log_date"] == _today()
    ledger = db.tables["push_sends"].rows[0]
    assert ledger["action_id"] == "ml_500"
    assert ledger["slot"] == "13:00"
    assert ledger["responded_at"]


def test_second_tap_on_same_notification_is_not_counted(monkeypatch, client, headers):
    db = _db(monkeypatch, daily_events=[], push_sends=[])

    for _ in range(2):
        r = _respond(
            client, headers,
            reminder_id="water_intake", action_id="ml_250", log_date=_today(), slot="09:00",
        )

    assert r.json()["aggregated"]["water_ml_total"] == 250
    assert len(db.tables["daily_events"].rows) == 1


def test_response_to_local_notification_blocks_server_push_for_that_slot(
    monkeypatch, client, headers
):
    db = _db(monkeypatch, daily_events=[], push_sends=[])
    db.tables["push_sends"].unique_on = ("user_id", "reminder_id", "log_date", "slot")

    _respond(
        client, headers,
        reminder_id="routine_morning", action_id="done", log_date=_today(), slot="07:30",
    )

    assert main._claim_push_slot(db, USER_ID, "routine_morning", _today(), "07:30") is False


def test_makeup_removal_answer_marks_makeup_removed(monkeypatch, client, headers):
    _db(monkeypatch, daily_events=[], push_sends=[])

    r = _respond(client, headers, reminder_id="makeup_removal", action_id="wipe", slot="21:00")

    makeup = r.json()["aggregated"]["makeup"]
    assert makeup["removed"] is True
    assert makeup["removal_method"] == "wipe"


def test_respond_rejects_unknown_action(monkeypatch, client, headers):
    _db(monkeypatch, daily_events=[])

    assert _respond(client, headers, reminder_id="water_intake", action_id="ml_9999").status_code == 422
    assert _respond(client, headers, reminder_id="daily_checkin", action_id="done").status_code == 422
    assert _respond(
        client, headers, reminder_id="water_intake", action_id="ml_250", slot="9am"
    ).status_code == 422


def test_respond_rejects_other_users(monkeypatch, client, headers):
    _db(monkeypatch, daily_events=[])

    r = client.post(
        "/push/respond",
        json={"user_id": OTHER_USER_ID, "reminder_id": "spf_refresh", "action_id": "done"},
        headers=headers,
    )

    assert r.status_code == 403


def test_respond_ignores_far_away_log_date(monkeypatch, client, headers):
    db = _db(monkeypatch, daily_events=[], push_sends=[])
    old = (datetime.now(timezone.utc).date() - timedelta(days=10)).isoformat()

    r = _respond(client, headers, reminder_id="spf_refresh", action_id="done", log_date=old)

    assert r.json()["log_date"] != old
    assert db.tables["daily_events"].rows[0]["log_date"] != old


# ── Gönderim ─────────────────────────────────────────────────────────────────

def test_dispatch_sends_actions_and_data_only_for_capable_android(monkeypatch, client):
    sender = _Sender()
    _enable_push(monkeypatch, sender)
    seen = "2026-10-04T10:00:00+00:00"
    db = _db(
        monkeypatch,
        device_tokens=[
            {"user_id": USER_ID, "token": "android-new", "platform": "android",
             "actions_supported": True, "utc_offset_minutes": 0, "push_enabled": True,
             "last_seen_at": seen},
            {"user_id": USER_ID, "token": "android-old", "platform": "android",
             "actions_supported": False, "utc_offset_minutes": 0, "push_enabled": True,
             "last_seen_at": seen},
            {"user_id": USER_ID, "token": "ios", "platform": "ios",
             "actions_supported": True, "utc_offset_minutes": 0, "push_enabled": True,
             "last_seen_at": seen},
        ],
        push_sends=[],
    )
    db.tables["push_sends"].unique_on = ("user_id", "reminder_id", "log_date", "slot")
    water = next(r for r in build_reminders({}, {}) if r["id"] == "water_intake")
    monkeypatch.setattr(main, "due_reminders", lambda plan, now, tol, **_: [{**water, "slot": "09:00"}])

    assert _dispatch(client).status_code == 200

    call = sender.calls[0]
    assert call["category"] == "water_intake"
    assert call["data_only_tokens"] == {"android-new"}
    assert call["data"]["slot"] == "09:00"
    assert call["data"]["open_path"] == "/dashboard"
    assert json.loads(call["data"]["actions"]) == [
        {"id": "ml_250", "label": "1 bardak (250 ml)"},
        {"id": "ml_500", "label": "2 bardak (500 ml)"},
    ]


def test_device_registration_stores_action_support(monkeypatch, client, headers):
    db = _db(monkeypatch)

    client.post(
        "/devices/register",
        json={"user_id": USER_ID, "token": "t", "platform": "android", "actions_supported": True},
        headers=headers,
    )

    assert db.tables["device_tokens"].upserted[-1]["actions_supported"] is True


@pytest.mark.parametrize("data_only", [False, True])
def test_build_message_shapes(data_only):
    message = push_service.build_message(
        "tok", "Başlık", "Gövde", {"reminder_id": "water_intake"}, "water_intake", data_only
    )["message"]

    assert message["apns"]["payload"]["aps"]["category"] == "water_intake"
    if data_only:
        assert "notification" not in message
        assert message["data"]["title"] == "Başlık"
        assert message["data"]["body"] == "Gövde"
    else:
        assert message["notification"] == {"title": "Başlık", "body": "Gövde"}
        assert "title" not in message["data"]
