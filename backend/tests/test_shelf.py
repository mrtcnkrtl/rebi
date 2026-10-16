"""Rafım: "ürün bitti" -> "aldım" durumu olaylardan türetilir; 3. günde tek seferlik hatırlatma."""

from __future__ import annotations

from datetime import date, datetime, timedelta, timezone

import jwt
import pytest

import main
import shelf
from chat_context import build_today_summary
from tests.fake_supabase import FakeSupabase
from today_plan import build_reminders

USER_ID = "12121212-1212-4212-8212-121212121212"
SECRET = "test-secret-at-least-32-bytes-long"
DISPATCH_SECRET = "dispatch-secret-abcdefghijklmnop"
CALM = {"uv_index": 3, "humidity": 50, "temperature": 20}
TODAY = date(2026, 10, 16)


def _event(kind: str, product: str, day: str, time: str = "10:00", step: int | None = None) -> dict:
    payload = {"product": product}
    if step is not None:
        payload["step_order"] = step
    return {"type": kind, "payload": payload, "log_date": day, "event_time": f"{day}T{time}:00+00:00"}


def _fin(product, day, time="10:00", step=None):
    return _event(shelf.FINISHED, product, day, time, step)


def _res(product, day, time="12:00"):
    return _event(shelf.RESTOCKED, product, day, time)


# ── Türetme kuralı ──────────────────────────────────────────────────────────

def test_a_finished_product_is_out_until_it_is_restocked():
    out = shelf.derive_products_out([_fin("Niasinamid serum", "2026-10-14", step=20)], TODAY)

    assert [(p["product"], p["step_order"], p["days_out"], p["log_date"]) for p in out] == [
        ("Niasinamid serum", 20, 2, "2026-10-14")
    ]

    back = shelf.derive_products_out([_fin("Niasinamid serum", "2026-10-14"), _res("Niasinamid serum", "2026-10-15")], TODAY)
    assert back == []


def test_the_last_event_wins_so_a_restocked_product_can_finish_again():
    events = [
        _fin("SPF 50", "2026-10-01"),
        _res("SPF 50", "2026-10-03"),
        _fin("SPF 50", "2026-10-12", time="09:00"),
    ]

    out = shelf.derive_products_out(events, TODAY)

    assert len(out) == 1
    assert out[0]["log_date"] == "2026-10-12" and out[0]["days_out"] == 4


def test_finishing_twice_keeps_the_first_finish_date():
    out = shelf.derive_products_out([_fin("Krem", "2026-10-10"), _fin("Krem", "2026-10-14")], TODAY)

    assert [(p["log_date"], p["days_out"]) for p in out] == [("2026-10-10", 6)]


def test_case_and_extra_spaces_do_not_split_a_product():
    events = [_fin("  Jel   Temizleyici ", "2026-10-10"), _res("jel temizleyici", "2026-10-11")]

    assert shelf.derive_products_out(events, TODAY) == []
    assert shelf.product_key("Çift  Temizlik") == shelf.product_key("çift temizlik")


def test_most_recently_finished_is_listed_first():
    out = shelf.derive_products_out(
        [_fin("A", "2026-10-10"), _fin("B", "2026-10-15"), _fin("C", "2026-10-12")], TODAY
    )
    assert [p["product"] for p in out] == ["B", "C", "A"]


def test_bad_events_are_ignored():
    events = [
        {"type": shelf.FINISHED, "payload": {}, "log_date": "2026-10-10", "event_time": "x"},
        {"type": shelf.FINISHED, "payload": None, "log_date": "2026-10-10", "event_time": "x"},
        {"type": "water_intake", "payload": {"product": "X"}, "log_date": "2026-10-10", "event_time": "x"},
        {"type": shelf.RESTOCKED, "payload": {"product": "hiç bitmemiş"}, "log_date": "2026-10-10", "event_time": "x"},
        _fin("Geçerli", "kötü-tarih"),
    ]

    out = shelf.derive_products_out(events, TODAY)

    assert [p["product"] for p in out] == ["Geçerli"]
    assert out[0]["days_out"] == 0, "ayrıştırılamayan tarih 0 gün sayılır"


@pytest.mark.parametrize("step, expected", [(40, 40), (40.0, 40), ("40", None), (True, None), (None, None)])
def test_step_order_is_kept_only_when_numeric(step, expected):
    event = {"type": shelf.FINISHED, "payload": {"product": "P", "step_order": step}, "log_date": "2026-10-10", "event_time": "t"}

    assert shelf.derive_products_out([event], TODAY)[0]["step_order"] == expected


def test_the_list_is_capped_and_names_are_trimmed():
    events = [_fin(f"Ürün {i:03d}", "2026-10-10", time=f"{i // 60:02d}:{i % 60:02d}") for i in range(80)]
    out = shelf.derive_products_out(events, TODAY)
    assert len(out) == shelf.MAX_PRODUCTS_OUT

    long_name = "u" * 300
    assert len(shelf.derive_products_out([_fin(long_name, "2026-10-10")], TODAY)[0]["product"]) == 120


def test_restock_is_due_exactly_three_days_after_finishing():
    def out_after(days):
        day = str(TODAY - timedelta(days=days))
        return shelf.derive_products_out([_fin("Serum", day)], TODAY)

    assert shelf.restock_due(out_after(2)) == []
    assert [p["product"] for p in shelf.restock_due(out_after(3))] == ["Serum"]
    assert shelf.restock_due(out_after(4)) == [], "ertesi gün tekrarlamaz"
    assert shelf.restock_due(None) == []


# ── Uçlar ───────────────────────────────────────────────────────────────────

@pytest.fixture
def headers(monkeypatch):
    monkeypatch.setenv("SUPABASE_JWT_SECRET", SECRET)
    monkeypatch.delenv("API_ALLOW_INSECURE_AUTH", raising=False)
    token = jwt.encode({"sub": USER_ID, "aud": "authenticated"}, SECRET, algorithm="HS256")
    return {"Authorization": f"Bearer {token}"}


def _db(monkeypatch, events=(), **tables) -> FakeSupabase:
    rows = [{"user_id": USER_ID, **e} for e in events]
    db = FakeSupabase(daily_events=rows, **tables)
    monkeypatch.setattr(main, "get_supabase", lambda: db)
    return db


def _plan(client, headers):
    return client.get("/today/plan", params={"user_id": USER_ID}, headers=headers).json()


def _days_ago(n: int) -> str:
    return str(date.today() - timedelta(days=n))


def test_product_restocked_is_an_accepted_event_type(monkeypatch, client, headers):
    _db(monkeypatch)

    for kind in ("product_finished", "product_restocked"):
        r = client.post(
            "/daily_tracking/ingest",
            json={"user_id": USER_ID, "type": kind, "payload": {"product": "SPF 50", "step_order": 40}},
            headers=headers,
        )
        assert r.status_code == 200, r.text


def test_plan_lists_products_out_across_days_and_drops_restocked_ones(monkeypatch, client, headers):
    _db(monkeypatch, events=[
        _fin("Niasinamid serum", _days_ago(5), step=20),
        _fin("SPF 50", _days_ago(2), step=40),
        _fin("Temizleyici", _days_ago(9)),
        _res("Temizleyici", _days_ago(8)),
    ])

    body = _plan(client, headers)

    assert [(p["product"], p["days_out"], p["step_order"]) for p in body["products_out"]] == [
        ("SPF 50", 2, 40),
        ("Niasinamid serum", 5, 20),
    ]


def test_finish_then_restock_through_the_api_round_trips(monkeypatch, client, headers):
    _db(monkeypatch)

    def send(kind):
        return client.post(
            "/daily_tracking/ingest",
            json={"user_id": USER_ID, "type": kind, "payload": {"product": "Göz kremi"}},
            headers=headers,
        )

    send("product_finished")
    assert [p["product"] for p in _plan(client, headers)["products_out"]] == ["Göz kremi"]

    send("product_restocked")
    assert _plan(client, headers)["products_out"] == []


def test_products_out_are_per_user(monkeypatch, client, headers):
    db = _db(monkeypatch, events=[_fin("Benim ürünüm", _days_ago(1))])
    db.tables["daily_events"].rows.append({**_fin("Başkasının ürünü", _days_ago(1)), "user_id": "baska-kullanici"})

    assert [p["product"] for p in _plan(client, headers)["products_out"]] == ["Benim ürünüm"]


def test_events_older_than_a_year_do_not_count(monkeypatch, client, headers):
    _db(monkeypatch, events=[_fin("Çok eski", _days_ago(shelf.SHELF_LOOKBACK_DAYS + 5))])

    assert _plan(client, headers)["products_out"] == []


def test_without_a_database_the_memory_events_are_used(monkeypatch, client):
    monkeypatch.setattr(main, "get_supabase", lambda: None)
    uid = "00000000-0000-4000-8000-000000000001"
    main._MEM_DAILY_EVENTS.clear()
    try:
        for kind, name in (("product_finished", "A"), ("product_finished", "B"), ("product_restocked", "A")):
            r = client.post("/daily_tracking/ingest", json={"user_id": uid, "type": kind, "payload": {"product": name}})
            assert r.status_code == 200, r.text

        body = client.get("/today/plan", params={"user_id": uid}).json()

        assert [p["product"] for p in body["products_out"]] == ["B"]
    finally:
        main._MEM_DAILY_EVENTS.clear()


# ── Hatırlatma ──────────────────────────────────────────────────────────────

def _restock(reminders):
    return next((r for r in reminders if r["id"] == "restock_check"), None)


def test_restock_reminder_appears_only_on_the_third_day():
    def reminders(days):
        out = shelf.derive_products_out([_fin("Serum", str(TODAY - timedelta(days=days)))], TODAY)
        return build_reminders(CALM, {}, products_out=out)

    assert _restock(reminders(2)) is None
    r = _restock(reminders(3))
    assert r is not None and "Serum" in r["body"] and (r["start"], r["end"]) == ("18:00", "19:00")
    assert _restock(reminders(4)) is None


def test_restock_reminder_names_the_first_product_and_counts_the_rest():
    day = str(TODAY - timedelta(days=3))
    out = shelf.derive_products_out([_fin("Serum", day, time="09:00"), _fin("Krem", day, time="08:00"), _fin("Tonik", day, time="07:00")], TODAY)

    body = _restock(build_reminders(CALM, {}, products_out=out))["body"]

    assert body.startswith("Serum ve 2 ürün daha")


def test_restock_reminder_can_be_turned_off_and_follows_the_day_plan():
    day = str(TODAY - timedelta(days=3))
    out = shelf.derive_products_out([_fin("Serum", day)], TODAY)

    assert _restock(build_reminders(CALM, {}, settings={"enabled": {"restock": False}}, products_out=out)) is None
    r = _restock(build_reminders(CALM, {}, settings={"wake_time": "06:00", "sleep_time": "22:00"}, products_out=out))
    assert (r["start"], r["end"]) == ("17:00", "18:00")


def test_plan_carries_the_restock_reminder(monkeypatch, client, headers):
    _db(monkeypatch, events=[_fin("Serum", _days_ago(shelf.RESTOCK_REMINDER_DAYS))])

    reminders = _plan(client, headers)["reminders"]

    assert _restock(reminders) is not None


# ── Sohbet bağlamı ──────────────────────────────────────────────────────────

def test_chat_summary_mentions_products_that_ran_out():
    out = shelf.derive_products_out([_fin("Niasinamid serum", "2026-10-14"), _fin("SPF 50", "2026-10-15")], TODAY)

    summary = build_today_summary({"water_ml_total": 500}, products_out=out)

    assert "Biten ürünleri (yenisi alınmadı): SPF 50, Niasinamid serum" in summary
    assert "Biten ürünleri" not in build_today_summary({"water_ml_total": 500})


# ── Push dağıtımı ───────────────────────────────────────────────────────────

class _Sender:
    def __init__(self):
        self.calls = []

    async def __call__(self, tokens, title, body, data=None):
        self.calls.append({"title": title, "body": body, "data": data or {}})
        return {"status": "sent", "sent": 1, "invalid_tokens": []}


def _offset_for(hhmm: str) -> int:
    now = datetime.now(timezone.utc)
    target = int(hhmm[:2]) * 60 + int(hhmm[3:])
    delta = (target - (now.hour * 60 + now.minute)) % 1440
    return delta - 1440 if delta > 720 else delta


def _dispatch_setup(monkeypatch, local_time: str, finished_days_ago: int = 3):
    monkeypatch.setenv("PUSH_DISPATCH_SECRET", DISPATCH_SECRET)
    sender = _Sender()
    monkeypatch.setattr(main, "push_configured", lambda: True)
    monkeypatch.setattr(main, "send_push", sender)
    offset = _offset_for(local_time)
    local_today = (datetime.now(timezone.utc) + timedelta(minutes=offset)).date()
    db = FakeSupabase(
        device_tokens=[{
            "user_id": USER_ID, "token": "fcm-1", "platform": "android", "utc_offset_minutes": offset,
            "push_enabled": True, "last_seen_at": "2026-10-16T10:00:00+00:00",
        }],
        push_sends=[],
        daily_events=[{"user_id": USER_ID, **_fin("Serum", str(local_today - timedelta(days=finished_days_ago)))}],
    )
    db.tables["push_sends"].unique_on = ("user_id", "reminder_id", "log_date", "slot")
    monkeypatch.setattr(main, "get_supabase", lambda: db)
    return sender


def _dispatch(client):
    return client.post("/push/dispatch", headers={"X-Push-Dispatch-Token": DISPATCH_SECRET})


def test_dispatch_sends_the_restock_reminder_in_its_window_and_only_once(monkeypatch, client):
    sender = _dispatch_setup(monkeypatch, "18:05")

    first = _dispatch(client)
    second = _dispatch(client)

    assert first.status_code == 200, first.text
    restock = [c for c in sender.calls if c["data"]["reminder_id"] == "restock_check"]
    assert len(restock) == 1, "defter aynı hatırlatmanın ikinci kez gitmesini engeller"
    assert "Serum" in restock[0]["body"]
    assert second.json()["notifications_sent"] == 0


def test_dispatch_does_not_query_the_shelf_outside_the_restock_window(monkeypatch, client):
    sender = _dispatch_setup(monkeypatch, "13:00")

    def boom(*_args, **_kwargs):
        raise AssertionError("pencere kapalıyken Rafım sorgulanmamalı")

    monkeypatch.setattr(main, "_products_out", boom)

    assert _dispatch(client).status_code == 200
    assert not [c for c in sender.calls if c["data"]["reminder_id"] == "restock_check"]


def test_dispatch_sends_nothing_when_it_is_not_the_third_day(monkeypatch, client):
    sender = _dispatch_setup(monkeypatch, "18:05", finished_days_ago=5)

    _dispatch(client)

    assert not [c for c in sender.calls if c["data"]["reminder_id"] == "restock_check"]
