"""Saatlik UV'den güneş kremi penceresi ve "havaya göre üç karar" (SPF, nemlendirici, dudak balsamı)."""

from __future__ import annotations

import asyncio

import jwt
import pytest

import main
import weather_service
from tests.fake_supabase import FakeSupabase
from today_plan import build_reminders, build_weather_decisions

USER_ID = "88888888-8888-4888-8888-888888888888"
SECRET = "test-secret-at-least-32-bytes-long"


def _hours(values: list[float], day: str = "2026-10-16"):
    return [f"{day}T{h:02d}:00" for h in range(24)], values


def _uv_day(peak_hours: dict[int, float]) -> list[float]:
    return [peak_hours.get(h, 0.0) for h in range(24)]


# ── uv_window / uv_at ───────────────────────────────────────────────────────

def test_uv_window_is_the_contiguous_high_run_around_the_peak():
    times, values = _hours(_uv_day({9: 2, 10: 4, 11: 5, 12: 7, 13: 8, 14: 7, 15: 5, 16: 3, 17: 1}))

    window = weather_service.uv_window(times, values)

    assert window == {"start": "11:00", "end": "16:00", "peak": "13:00", "max": 8}


def test_uv_window_ignores_a_separate_earlier_high_run():
    # 08:00'de kısa bir yükselti, asıl zirve öğleden sonra; pencere zirveyi içeren kesintisiz aralıktır.
    times, values = _hours(_uv_day({8: 5, 9: 1, 13: 6, 14: 6}))

    assert weather_service.uv_window(times, values) == {"start": "13:00", "end": "15:00", "peak": "13:00", "max": 6}


@pytest.mark.parametrize("values", [_uv_day({}), _uv_day({12: 4})])
def test_no_window_when_uv_never_reaches_the_threshold(values):
    times, _ = _hours(values)
    assert weather_service.uv_window(times, values) is None


def test_uv_window_tolerates_missing_or_mismatched_data():
    assert weather_service.uv_window(None, None) is None
    assert weather_service.uv_window(["2026-10-16T10:00"], [6, 7]) is None
    assert weather_service.uv_window([], []) is None
    times, values = _hours([None] * 24)  # kaynak boş değer gönderirse
    assert weather_service.uv_window(times, values) is None


def test_uv_at_reads_the_current_hour():
    times, values = _hours(_uv_day({14: 6.4}))

    assert weather_service.uv_at("2026-10-16T14:15", times, values) == 6
    assert weather_service.uv_at("2026-10-16T03:00", times, values) == 0
    assert weather_service.uv_at(None, times, values) is None


# ── Open-Meteo yanıtı ───────────────────────────────────────────────────────

class _Response:
    def __init__(self, payload):
        self._payload = payload

    def raise_for_status(self):
        pass

    def json(self):
        return self._payload


def _stub_open_meteo(monkeypatch, payload):
    class _Client:
        def __init__(self, *args, **kwargs):
            pass

        async def __aenter__(self):
            return self

        async def __aexit__(self, *_):
            return False

        async def get(self, url, params=None):
            assert params["hourly"] == "uv_index", "saatlik UV istenmeli"
            return _Response(payload)

    monkeypatch.setattr(weather_service.httpx, "AsyncClient", _Client)


def _open_meteo_payload(hourly=True):
    times, values = _hours(_uv_day({11: 5, 12: 7, 13: 8, 14: 6, 15: 5}))
    payload = {
        "current": {"time": "2026-10-16T14:15", "temperature_2m": 21.4, "relative_humidity_2m": 38, "weather_code": 1},
        "daily": {"uv_index_max": [8.2]},
    }
    if hourly:
        payload["hourly"] = {"time": times, "uv_index": values}
    return payload


def test_fetch_reads_the_uv_window_and_current_uv(monkeypatch):
    _stub_open_meteo(monkeypatch, _open_meteo_payload())

    weather = asyncio.run(weather_service.fetch_weather_live(41.0, 29.0))

    assert weather["uv_index"] == 8 and weather["temperature"] == 21 and weather["humidity"] == 38
    assert weather["uv_window"] == {"start": "11:00", "end": "16:00", "peak": "13:00", "max": 8}
    assert weather["uv_now"] == 6


def test_fetch_without_hourly_data_still_returns_current_weather(monkeypatch):
    _stub_open_meteo(monkeypatch, _open_meteo_payload(hourly=False))

    weather = asyncio.run(weather_service.fetch_weather_live(41.0, 29.0))

    assert weather["uv_index"] == 8
    assert "uv_window" not in weather and "uv_now" not in weather


def test_broken_hourly_data_does_not_drop_the_current_weather(monkeypatch):
    payload = _open_meteo_payload()
    payload["hourly"] = {"time": ["bozuk"], "uv_index": [9]}
    _stub_open_meteo(monkeypatch, payload)

    weather = asyncio.run(weather_service.fetch_weather_live(41.0, 29.0))

    assert weather is not None and weather["temperature"] == 21
    assert "uv_window" not in weather


# ── Üç karar ────────────────────────────────────────────────────────────────

@pytest.mark.parametrize(
    "uv, spf, level, refresh",
    [(9, "50+", "extreme", True), (6, "50", "high", True), (4, "30+", "moderate", False), (1, "30", "low", False)],
)
def test_spf_decision_follows_the_advice_thresholds(uv, spf, level, refresh):
    decision = build_weather_decisions({"uv_index": uv, "humidity": 50, "temperature": 20})["spf"]

    assert (decision["spf"], decision["level"], decision["refresh"]) == (spf, level, refresh)
    assert decision["refresh_every_minutes"] == (120 if refresh else None)
    assert decision["window"] is None


def test_spf_decision_carries_the_real_uv_window():
    weather = {"uv_index": 8, "humidity": 50, "temperature": 20,
               "uv_window": {"start": "11:00", "end": "16:00", "peak": "13:00", "max": 8}}

    assert build_weather_decisions(weather)["spf"]["window"] == {"start": "11:00", "end": "16:00", "peak": "13:00"}


@pytest.mark.parametrize(
    "humidity, temperature, kind",
    [
        (20, 20, "intense"),   # çok kuru
        (60, 2, "barrier"),    # çok soğuk
        (30, 20, "boost"),     # kuru
        (80, 20, "light"),     # nemli
        (50, 38, "light_hot"), # çok sıcak
        (55, 20, "standard"),
        (20, 2, "intense"),    # ikisi birden: nem önce gelir
    ],
)
def test_moisture_decision_picks_the_dominant_condition(humidity, temperature, kind):
    decision = build_weather_decisions({"uv_index": 3, "humidity": humidity, "temperature": temperature})["moisture"]

    assert decision["kind"] == kind
    assert decision["night_mask"] is (humidity < 25)


@pytest.mark.parametrize(
    "humidity, temperature, needed, reason",
    [(50, 20, False, None), (50, 8, True, "cold"), (30, 20, True, "dry"), (30, 5, True, "both")],
)
def test_lip_balm_decision(humidity, temperature, needed, reason):
    decision = build_weather_decisions({"uv_index": 3, "humidity": humidity, "temperature": temperature})["lip_balm"]

    assert decision == {"needed": needed, "reason": reason}


def test_decisions_agree_with_the_reminders_for_the_same_weather():
    weather = {"uv_index": 6, "humidity": 30, "temperature": 8}
    decisions = build_weather_decisions(weather)
    ids = {r["id"] for r in build_reminders(weather, {})}

    assert ("spf_refresh" in ids) is decisions["spf"]["refresh"]
    assert ("lip_balm" in ids) is decisions["lip_balm"]["needed"]


def test_decisions_survive_missing_weather_values():
    decisions = build_weather_decisions({})

    assert decisions["spf"]["spf"] == "30+" and decisions["moisture"]["kind"] == "standard"
    assert decisions["lip_balm"]["needed"] is False


# ── SPF hatırlatma penceresi ────────────────────────────────────────────────

def _spf(reminders):
    return next(r for r in reminders if r["id"] == "spf_refresh")


def test_spf_reminder_uses_the_real_uv_window_when_known():
    weather = {"uv_index": 8, "humidity": 50, "temperature": 20,
               "uv_window": {"start": "11:00", "end": "16:00", "peak": "13:00", "max": 8}}
    r = _spf(build_reminders(weather, {}))
    assert (r["start"], r["end"]) == ("11:00", "16:00")

    narrow = {**weather, "uv_window": {"start": "12:00", "end": "15:00", "peak": "13:00", "max": 8}}
    r = _spf(build_reminders(narrow, {}))
    assert (r["start"], r["end"]) == ("12:00", "15:00") and r["every_minutes"] == 120


def test_spf_window_is_clamped_to_the_awake_day():
    weather = {"uv_index": 7, "humidity": 50, "temperature": 20,
               "uv_window": {"start": "06:00", "end": "20:00", "peak": "13:00", "max": 7}}
    r = _spf(build_reminders(weather, {}, settings={"wake_time": "08:00", "sleep_time": "18:00"}))

    assert (r["start"], r["end"]) == ("08:00", "18:00")


def test_spf_reminder_falls_back_to_the_fixed_window_without_hourly_data():
    r = _spf(build_reminders({"uv_index": 7, "humidity": 50, "temperature": 20}, {}))
    assert (r["start"], r["end"]) == ("11:00", "16:00")  # varsayılan gün düzeninde eski sabit pencere

    unusable = {"uv_index": 7, "humidity": 50, "temperature": 20,
                "uv_window": {"start": "23:00", "end": "23:20"}}  # uyku saatine sığmayan pencere
    r = _spf(build_reminders(unusable, {}))
    assert (r["start"], r["end"]) == ("11:00", "16:00")


# ── Uç ──────────────────────────────────────────────────────────────────────

def test_plan_endpoint_returns_the_decisions(monkeypatch, client):
    monkeypatch.setenv("SUPABASE_JWT_SECRET", SECRET)
    monkeypatch.delenv("API_ALLOW_INSECURE_AUTH", raising=False)
    token = jwt.encode({"sub": USER_ID, "aud": "authenticated"}, SECRET, algorithm="HS256")
    db = FakeSupabase(daily_events=[{
        "user_id": USER_ID, "log_date": str(main.date.today()), "event_time": "2026-10-16T07:00:00+00:00",
        "type": "weather",
        "payload": {"uv_index": 8, "humidity": 22, "temperature": 3,
                    "uv_window": {"start": "11:00", "end": "16:00", "peak": "13:00", "max": 8}},
    }])
    monkeypatch.setattr(main, "get_supabase", lambda: db)

    body = client.get("/today/plan", params={"user_id": USER_ID}, headers={"Authorization": f"Bearer {token}"}).json()

    assert body["weather_decisions"]["spf"]["spf"] == "50+"
    assert body["weather_decisions"]["spf"]["window"]["peak"] == "13:00"
    assert body["weather_decisions"]["moisture"]["kind"] == "intense"
    assert body["weather_decisions"]["lip_balm"] == {"needed": True, "reason": "both"}
    assert (_spf(body["reminders"])["start"], _spf(body["reminders"])["end"]) == ("11:00", "16:00")
