"""Bildirim butonlarıyla günlük veri toplama: plan, gönderim ve cevap ucu."""

from __future__ import annotations

import json
import re
import typing
from datetime import datetime, timedelta, timezone
from pathlib import Path

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

_MOBILE_PLAN = Path(__file__).resolve().parents[2] / "mobile" / "lib" / "core" / "today_plan.dart"


@pytest.fixture(autouse=True)
def _forget_dispatch_runs():
    """Dağıtım turu bellekte iz bırakır; sonraki testlerin `dispatch_alive` değerine sızmasın."""
    yield
    main._PUSH_LAST_RUN.clear()


def _today() -> str:
    return datetime.now(timezone.utc).date().isoformat()


# ── Plan ─────────────────────────────────────────────────────────────────────

def test_every_action_writes_a_known_event_type():
    allowed = set(typing.get_args(main.DailyTrackingClientEventType))

    for reminder_id, actions in REMINDER_ACTIONS.items():
        assert 1 <= len(actions) <= 3, reminder_id
        for action in actions:
            assert action["log_event"] in allowed, (reminder_id, action["id"])


@pytest.mark.skipif(not _MOBILE_PLAN.exists(), reason="mobil kaynak yok")
def test_actions_match_the_mobile_app():
    """Sunucu listesi uygulamanın olay yazan düğmeleriyle aynı kalmalı."""
    source = _MOBILE_PLAN.read_text(encoding="utf-8")
    block = source[source.index("List<ReminderAction> reminderActions"):]
    block = block[: block.index("_ => const [],")]
    mobile = {}
    for reminder_id, body in re.findall(r"'(\w+)' => const \[(.*?)\],\n", block, re.S):
        quick = re.findall(r"ReminderAction\('(\w+)', type: '(\w+)'", body)
        if quick:
            mobile[reminder_id] = quick

    server = {
        reminder_id: [(a["id"], a["log_event"]) for a in actions]
        for reminder_id, actions in REMINDER_ACTIONS.items()
    }
    assert server == mobile


def test_reminders_carry_actions_category_and_open_path():
    plan = {r["id"]: r for r in build_reminders({"uv_index": 7}, {}, checkin_done=False)}

    water = plan["water_intake"]
    assert water["category"] == "rebi_water_intake"
    assert [a["id"] for a in water["actions"]] == ["water250", "water500"]
    assert plan["daily_checkin"]["actions"] == []
    assert plan["daily_checkin"]["category"] is None
    assert plan["daily_checkin"]["open_path"] == "/dashboard/checkin"
    assert plan["routine_morning"]["open_path"] == "/dashboard"


def test_plan_actions_are_copies():
    plan = build_reminders({}, {}, checkin_done=True)
    plan[0]["actions"][0]["payload"]["tampered"] = True

    assert all("tampered" not in a["payload"] for a in sum(REMINDER_ACTIONS.values(), []))


def test_actions_catalog_lists_categories(client):
    body = client.get("/push/actions").json()
    by_id = {c["id"]: c for c in body["categories"]}

    assert by_id["water_intake"]["category"] == "rebi_water_intake"
    assert by_id["water_intake"]["actions"][0] == {"id": "water250", "label": "+250 ml"}
    assert "makeup_removal" not in by_id
    # Yük istemciye gitmez; cevabı sunucu çözer.
    assert "payload" not in by_id["water_intake"]["actions"][0]


# ── Cevap ucu ────────────────────────────────────────────────────────────────

def _respond(client, headers, **body):
    return client.post("/push/respond", json={"user_id": USER_ID, **body}, headers=headers)


def test_respond_writes_server_defined_event(monkeypatch, client, headers):
    db = _db(monkeypatch, daily_events=[], push_sends=[])

    r = _respond(
        client, headers,
        reminder_id="water_intake", action_id="water500", log_date=_today(), slot="13:00",
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
    assert ledger["action_id"] == "water500"
    assert ledger["slot"] == "13:00"
    assert ledger["responded_at"]


def test_second_tap_on_same_notification_is_not_counted(monkeypatch, client, headers):
    db = _db(monkeypatch, daily_events=[], push_sends=[])

    for _ in range(2):
        r = _respond(
            client, headers,
            reminder_id="water_intake", action_id="water250", log_date=_today(), slot="09:00",
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


def test_respond_accepts_the_mobile_notification_action_id(monkeypatch, client, headers):
    _db(monkeypatch, daily_events=[], push_sends=[])

    r = _respond(client, headers, reminder_id="makeup_log", action_id="makeup_log:no", slot="10:00")

    assert r.status_code == 200, r.text
    makeup = r.json()["aggregated"]["makeup"]
    assert makeup["logged"] is True
    assert makeup["used"] is False


def test_respond_rejects_unknown_action(monkeypatch, client, headers):
    _db(monkeypatch, daily_events=[])

    assert _respond(client, headers, reminder_id="water_intake", action_id="water9999").status_code == 422
    assert _respond(client, headers, reminder_id="daily_checkin", action_id="done").status_code == 422
    # Uygulamada seçim ekranı açan cevaplar sunucuda düğme değildir.
    assert _respond(client, headers, reminder_id="nutrition_log", action_id="junkYes").status_code == 422
    assert _respond(
        client, headers, reminder_id="water_intake", action_id="water_intake:done"
    ).status_code == 422
    assert _respond(
        client, headers, reminder_id="water_intake", action_id="water250", slot="9am"
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
    assert call["category"] == "rebi_water_intake"
    assert call["action_tokens"] == {"android-new", "ios"}
    assert call["data_only_tokens"] == {"android-new"}
    assert call["data"]["slot"] == "09:00"
    assert call["data"]["open_path"] == "/dashboard"
    assert json.loads(call["data"]["actions"]) == [
        {"id": "water250", "label": "+250 ml"},
        {"id": "water500", "label": "+500 ml"},
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
        "tok", "Başlık", "Gövde", {"reminder_id": "water_intake"}, "rebi_water_intake", data_only
    )["message"]

    assert message["apns"]["payload"]["aps"]["category"] == "rebi_water_intake"
    if data_only:
        assert "notification" not in message
        assert message["data"]["title"] == "Başlık"
        assert message["data"]["body"] == "Gövde"
    else:
        assert message["notification"] == {"title": "Başlık", "body": "Gövde"}
        assert "title" not in message["data"]


def test_restock_reminder_opens_the_shelf():
    from today_plan import reminder_open_path

    assert reminder_open_path("restock_check") == "/dashboard/shelf"


def test_category_is_left_out_for_devices_without_action_support(monkeypatch):
    sent: list[dict] = []

    class _Response:
        status_code = 200

    class _Client:
        def __init__(self, *_, **__):
            pass

        async def __aenter__(self):
            return self

        async def __aexit__(self, *_):
            return False

        async def post(self, _url, json, headers):
            sent.append(json["message"])
            return _Response()

    monkeypatch.setenv("FCM_SERVICE_ACCOUNT_JSON", '{"project_id": "rebi-test"}')
    monkeypatch.setattr(push_service, "_access_token", lambda info: "token")
    monkeypatch.setattr(push_service.httpx, "AsyncClient", _Client)

    import asyncio

    asyncio.run(push_service.send_push(
        ["old-ios", "new-ios"], "Su", "İç", {}, "rebi_water_intake", action_tokens={"new-ios"},
    ))

    by_token = {m["token"]: m for m in sent}
    assert "payload" not in by_token["old-ios"]["apns"]
    assert by_token["new-ios"]["apns"]["payload"]["aps"]["category"] == "rebi_water_intake"
