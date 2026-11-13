"""PostgREST yanıt sınırı (varsayılan 1000 satır): sınırı aşan okumalar sayfalanır, en yeni kayıtlar kaybolmaz."""

from __future__ import annotations

from datetime import timedelta

import jwt
import pytest

import main
from tests.fake_supabase import FakeSupabase

USER_ID = "66666666-6666-4666-8666-666666666666"
SECRET = "test-secret-at-least-32-bytes-long"
SERVER_CAP = 1000


@pytest.fixture
def headers(monkeypatch):
    monkeypatch.setenv("SUPABASE_JWT_SECRET", SECRET)
    monkeypatch.delenv("API_ALLOW_INSECURE_AUTH", raising=False)
    token = jwt.encode({"sub": USER_ID, "aud": "authenticated"}, SECRET, algorithm="HS256")
    return {"Authorization": f"Bearer {token}"}


def _db(monkeypatch, events: list[dict]) -> FakeSupabase:
    db = FakeSupabase(daily_events=events, daily_logs=[], assessments=[], reminder_settings=[])
    db.tables["daily_events"].max_rows = SERVER_CAP  # Supabase'in varsayılan `db-max-rows` sınırı
    monkeypatch.setattr(main, "get_supabase", lambda: db)
    return db


def _event(day, minute: int, kind: str = "water_intake", payload: dict | None = None, n: int = 0) -> dict:
    return {
        "id": f"{day}-{n:05d}",
        "user_id": USER_ID,
        "log_date": str(day),
        "event_time": f"{day}T{minute // 60:02d}:{minute % 60:02d}:00+00:00",
        "type": kind,
        "payload": payload if payload is not None else {"ml": 100},
        "source": "mobile",
    }


def test_ninety_days_of_busy_history_keeps_the_newest_days(monkeypatch, client, headers):
    today = main._local_today(None)
    events = []
    for back in range(90):
        day = today - timedelta(days=back)
        events += [_event(day, 8 * 60 + k, n=k) for k in range(30)]  # günde 30 olay → 2.700 satır
    assert len(events) > 2 * SERVER_CAP
    _db(monkeypatch, events)

    r = client.get("/me/history", params={"user_id": USER_ID, "days": 90}, headers=headers)

    assert r.status_code == 200, r.text
    days = {d["log_date"]: d["tracking"] for d in r.json()["days"]}
    assert len(days) == 90, "sınırı aşan okumada günler eksilmemeli"
    assert days[str(today)]["water_ml_total"] == 3000, "en yeni gün (bugün) kaybolmamalı"
    assert days[str(today - timedelta(days=89))]["water_ml_total"] == 3000
    assert all(t["water_ml_total"] == 3000 for t in days.values()), "hiçbir günün olayları yarım kalmamalı"


def test_a_single_unpaged_read_would_have_lost_the_newest_days(monkeypatch):
    """Düzeltmenin gerekçesi: tek sorgu eskiden yeniye sıralıyken yalnızca ilk 1000 satırı döner."""
    today = main._local_today(None)
    events = []
    for back in range(90):
        events += [_event(today - timedelta(days=back), 8 * 60 + k, n=k) for k in range(30)]
    db = _db(monkeypatch, events)

    rows = db.table("daily_events").select().order("event_time").order("id").execute().data

    assert len(rows) == SERVER_CAP
    assert max(r["log_date"] for r in rows) < str(today - timedelta(days=50)), "en yeni gün tek okumada kayıp"


def test_todays_progress_includes_the_newest_events_on_a_day_past_the_cap(monkeypatch, client, headers):
    today = main._local_today(None)
    events = [_event(today, 60 + k % 600, n=k) for k in range(SERVER_CAP + 300)]
    # En yeni olay: sabah rutini tamamlandı. Sayfalanmazsa tam bu olay kesilirdi.
    events.append(_event(today, 23 * 60 + 59, "routine_completed_block", {"morning": True}, n=9999))
    _db(monkeypatch, events)

    r = client.get(
        "/daily_tracking/today",
        params={"user_id": USER_ID, "log_date": str(today)},
        headers=headers,
    )

    assert r.status_code == 200, r.text
    agg = r.json()["aggregated"]
    assert agg["routine_morning_done"] is True
    assert agg["water_ml_total"] == (SERVER_CAP + 300) * 100


def test_ingest_response_reads_back_the_whole_day(monkeypatch, client, headers):
    today = main._local_today(None)
    events = [_event(today, 60 + k % 600, n=k) for k in range(SERVER_CAP + 300)]
    _db(monkeypatch, events)

    r = client.post(
        "/daily_tracking/ingest",
        json={
            "user_id": USER_ID,
            "type": "routine_completed_block",
            "payload": {"morning": True},
            "timestamp": f"{today}T23:59:00+00:00",
            "client_event_id": "yeni-olay-1",
        },
        headers=headers,
    )

    assert r.status_code == 200, r.text
    agg = r.json()["aggregated"]
    assert agg["routine_morning_done"] is True, "az önce yazılan en yeni olay yanıta yansımalı"
    assert agg["water_ml_total"] == (SERVER_CAP + 300) * 100


def test_a_normal_day_still_costs_one_query(monkeypatch, client, headers):
    today = main._local_today(None)
    db = _db(monkeypatch, [_event(today, 8 * 60 + k, n=k) for k in range(40)])

    client.get("/daily_tracking/today", params={"user_id": USER_ID, "log_date": str(today)}, headers=headers)

    assert db.tables["daily_events"].select_calls == 1, "küçük sonuçta ek sorgu yok"


def test_shelf_events_are_read_past_the_cap_too(monkeypatch):
    today = main._local_today(None)
    noise = [_event(today - timedelta(days=1), 60 + k % 600, "product_finished", {"product": f"Ürün {k}"}, n=k)
             for k in range(SERVER_CAP + 50)]
    newest = _event(today, 23 * 60, "product_finished", {"product": "SPF 50"}, n=99999)
    db = _db(monkeypatch, noise + [newest])
    db.tables["daily_events"].max_rows = SERVER_CAP

    rows = main._load_shelf_events(db, USER_ID, today)

    assert len(rows) == SERVER_CAP + 51 and rows[-1]["payload"]["product"] == "SPF 50"
