"""Sohbetin bugünkü durumu (hava, su, makyaj, beslenme, rutin) bilmesi."""

from __future__ import annotations

import asyncio

import jwt
import pytest

import main
import rag_service
from chat_context import build_today_summary
from tests.fake_supabase import FakeSupabase

USER_ID = "77777777-7777-4777-8777-777777777777"
SECRET = "test-secret-at-least-32-bytes-long"


# ── Özet metni ──────────────────────────────────────────────────────────────

def test_empty_day_has_no_summary():
    assert build_today_summary({}, None, False) == ""
    assert build_today_summary(None) == ""


def test_summary_covers_weather_water_makeup_food_and_routine():
    summary = build_today_summary(
        {
            "water_ml_total": 750,
            "spf_refreshes": 1,
            "makeup": {"logged": True, "used": True, "removed": True, "removal_method": "wipe"},
            "nutrition": {"snacks": True, "sweets": True, "dairy": False, "junk_food": True},
            "routine_morning_done": True,
            "routine_evening_done": False,
            "products_finished": [{"product": "SPF 50"}],
        },
        {"temperature": 27.4, "uv_index": 7, "humidity": 32},
        checkin_done=True,
    )

    assert "Hava: 27°C, UV 7, nem %32" in summary
    assert "Su: 750/2000 ml" in summary
    assert "Güneş kremini 1 kez yeniledi" in summary
    assert "Makyaj: yaptı, misel su / mendille" in summary
    assert "Yediği: abur cubur, şekerli / tatlı" in summary
    assert "süt ürünü" not in summary, "kapalı seçenek yazılmaz"
    assert "Rutin yapıldı: sabah" in summary and "akşam" not in summary
    assert "Bitirdiği ürün sayısı: 1" in summary
    assert "check-in yapıldı" in summary


@pytest.mark.parametrize(
    ("makeup", "expected"),
    [
        ({"logged": True, "used": False}, "Makyaj: yapmadı"),
        ({"logged": True, "used": True, "removed": False}, "Makyaj: yaptı, henüz temizlemedi"),
        ({"logged": True, "used": True, "removed": False, "removal_method": "none"}, "Makyaj: yaptı, temizlenmedi"),
        ({"logged": True, "used": True, "removed": True, "removal_method": "double"}, "Makyaj: yaptı, çift temizlik"),
    ],
)
def test_makeup_states(makeup, expected):
    assert expected in build_today_summary({"makeup": makeup})


def test_unlogged_makeup_is_not_mentioned():
    assert build_today_summary({"makeup": {"logged": False}}) == ""


def test_legacy_junk_food_flag_still_reads_as_snacks():
    assert "Yediği: abur cubur" in build_today_summary({"nutrition": {"junk_food": True}})
    assert "Abur cubur yemedi" in build_today_summary({"nutrition": {"junk_food": False}})


def test_partial_weather_and_bad_numbers_do_not_break():
    assert build_today_summary({}, {"temperature": "x", "uv_index": 5}) == "Hava: UV 5"
    assert build_today_summary({"water_ml_total": "bozuk"}) == ""


def test_summary_is_capped():
    huge = {"products_finished": [{"product": f"p{i}"} for i in range(500)], "water_ml_total": 1}
    assert len(build_today_summary(huge, {"temperature": 20})) <= 700


# ── Uç nokta ────────────────────────────────────────────────────────────────

@pytest.fixture
def headers(monkeypatch):
    monkeypatch.setenv("SUPABASE_JWT_SECRET", SECRET)
    monkeypatch.delenv("API_ALLOW_INSECURE_AUTH", raising=False)
    token = jwt.encode({"sub": USER_ID, "aud": "authenticated"}, SECRET, algorithm="HS256")
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
def chat_stubs(monkeypatch):
    """Kota, kanıt ve model çağrılarını kapatır; modele giden profil ipuçlarını yakalar."""
    seen: dict = {}

    async def fake_chat_general(**kwargs):
        seen.update(kwargs)
        return "Cevap."

    monkeypatch.setattr(rag_service, "chat_general", fake_chat_general)
    monkeypatch.setattr(rag_service, "_build_free_chat_evidence_bundle", lambda *a, **k: {"score": 0.0, "sources": []})
    monkeypatch.setattr(main, "user_is_rebi_plus", lambda *a, **k: True)
    monkeypatch.setattr(main, "user_plus_chat_is_monthly_capped", lambda *a, **k: False)
    monkeypatch.setattr(main, "_chat_usage_row", lambda *a, **k: ("plus_unlimited", None, None, None))
    monkeypatch.setattr(main, "_persist_chat_turn", lambda *a, **k: None)
    monkeypatch.setattr(main, "_require_privacy_permission", lambda *a, **k: None)
    return seen


def _db(monkeypatch, **tables) -> FakeSupabase:
    db = FakeSupabase(**tables)
    monkeypatch.setattr(main, "get_supabase", lambda: db)
    return db


def test_chat_receives_todays_summary(monkeypatch, client, headers, chat_stubs):
    today = str(main._local_today(None))
    _db(monkeypatch, daily_events=[
        {"user_id": USER_ID, "type": "water_intake", "payload": {"ml": 600}, "log_date": today, "event_time": "2026-10-05T09:00:00+00:00"},
        {"user_id": USER_ID, "type": "makeup", "payload": {"used": True}, "log_date": today, "event_time": "2026-10-05T09:05:00+00:00"},
        {"user_id": USER_ID, "type": "nutrition", "payload": {"sweets": True, "junk_food": True}, "log_date": today, "event_time": "2026-10-05T09:10:00+00:00"},
        {"user_id": USER_ID, "type": "weather", "payload": {"temperature": 31, "uv_index": 8, "humidity": 30}, "log_date": today, "event_time": "2026-10-05T09:15:00+00:00"},
    ])

    r = client.post("/chat_general", json={"user_id": USER_ID, "message": "SPF yeter mi?", "history": []}, headers=headers)

    assert r.status_code == 200, r.text
    summary = chat_stubs["profile_hint"]["today_summary"]
    assert "UV 8" in summary
    assert "Su: 600/2000 ml" in summary
    assert "Makyaj: yaptı, henüz temizlemedi" in summary
    assert "şekerli" in summary


def test_chat_reads_the_users_local_day(monkeypatch, client, headers, chat_stubs):
    ahead = str(main._local_today(14 * 60))
    _db(monkeypatch, daily_events=[
        {"user_id": USER_ID, "type": "water_intake", "payload": {"ml": 900}, "log_date": ahead, "event_time": "2026-10-05T09:00:00+00:00"},
    ])

    client.post(
        "/chat_general",
        json={"user_id": USER_ID, "message": "merhaba", "history": [], "utc_offset_minutes": 14 * 60},
        headers=headers,
    )

    assert "Su: 900/2000 ml" in chat_stubs["profile_hint"]["today_summary"]


def test_chat_without_any_data_sends_no_summary(monkeypatch, client, headers, chat_stubs):
    _db(monkeypatch)

    r = client.post("/chat_general", json={"user_id": USER_ID, "message": "merhaba", "history": []}, headers=headers)

    assert r.status_code == 200, r.text
    assert "today_summary" not in chat_stubs["profile_hint"]


def test_unreadable_events_never_break_the_chat(monkeypatch, client, headers, chat_stubs):
    class _Broken:
        def table(self, _name):
            raise RuntimeError("tablo yok")

    monkeypatch.setattr(main, "get_supabase", lambda: _Broken())

    r = client.post("/chat_general", json={"user_id": USER_ID, "message": "merhaba", "history": []}, headers=headers)

    assert r.status_code == 200, r.text
    assert r.json()["reply"] == "Cevap."


def test_invalid_utc_offset_is_rejected(monkeypatch, client, headers, chat_stubs):
    _db(monkeypatch)

    r = client.post(
        "/chat_general",
        json={"user_id": USER_ID, "message": "merhaba", "history": [], "utc_offset_minutes": 5000},
        headers=headers,
    )

    assert r.status_code == 422


def test_summary_builder_is_async_safe_for_demo_users():
    demo = "00000000-0000-4000-8000-000000000001"
    assert asyncio.run(main._chat_today_summary(object(), demo, None)) == ""
