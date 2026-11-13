"""Hava sağlayıcısı: her çağrı sayılır/günlüğe yazılır; rutin ve check-in önbellekten yararlanır."""

from __future__ import annotations

import asyncio
import logging

import pytest

import main
import weather_service

DEMO_UUID = "00000000-0000-4000-8000-000000000001"


class _Response:
    def __init__(self, payload):
        self._payload = payload

    def raise_for_status(self):
        pass

    def json(self):
        return self._payload


_OK = {
    "current": {"time": "2026-10-16T14:15", "temperature_2m": 21.4, "relative_humidity_2m": 38, "weather_code": 1},
    "daily": {"uv_index_max": [8.2]},
}


def _stub_client(monkeypatch, behaviours: list):
    """Sıradaki davranış: dict (yanıt) ya da istisna. Her get çağrısı bir davranış tüketir."""
    calls: list = []

    class _Client:
        def __init__(self, *args, **kwargs):
            pass

        async def __aenter__(self):
            return self

        async def __aexit__(self, *_):
            return False

        async def get(self, url, params=None):
            calls.append(url)
            behaviour = behaviours[min(len(calls) - 1, len(behaviours) - 1)]
            if isinstance(behaviour, Exception):
                raise behaviour
            return _Response(behaviour)

    monkeypatch.setattr(weather_service.httpx, "AsyncClient", _Client)
    return calls


@pytest.fixture(autouse=True)
def _clean():
    weather_service.reset_usage()
    main._WEATHER_CACHE.clear()
    yield
    weather_service.reset_usage()
    main._WEATHER_CACHE.clear()


# ── Çağrı sayacı ─────────────────────────────────────────────────────────────────────────────────

def test_each_provider_call_is_counted_and_logged(monkeypatch, caplog):
    _stub_client(monkeypatch, [_OK])

    with caplog.at_level(logging.INFO, logger="weather"):
        asyncio.run(weather_service.fetch_weather_live(41.0, 29.0))
        asyncio.run(weather_service.fetch_weather_live(39.9, 32.8))

    assert weather_service.usage_snapshot() == {"open-meteo": {"calls": 2, "failures": 0}}
    lines = [r.getMessage() for r in caplog.records if "weather_call" in r.getMessage()]
    assert len(lines) == 2 and all("provider=open-meteo ok=1 ms=" in line for line in lines)


def test_failures_are_counted_separately(monkeypatch, caplog):
    _stub_client(monkeypatch, [RuntimeError("zaman aşımı")])
    monkeypatch.setattr(weather_service, "OPENWEATHER_API_KEY", "")

    with caplog.at_level(logging.INFO, logger="weather"):
        assert asyncio.run(weather_service.fetch_weather_live(41.0, 29.0)) is None

    assert weather_service.usage_snapshot() == {"open-meteo": {"calls": 1, "failures": 1}}
    assert any("provider=open-meteo ok=0" in r.getMessage() for r in caplog.records)


def test_the_fallback_provider_is_counted_too(monkeypatch):
    calls = _stub_client(monkeypatch, [RuntimeError("kapalı"), {"current": {"temp": 20.4, "humidity": 55, "uvi": 3.2, "weather": [{"description": "açık"}]}}])
    monkeypatch.setattr(weather_service, "OPENWEATHER_API_KEY", "anahtar")

    weather = asyncio.run(weather_service.fetch_weather_live(41.0, 29.0))

    assert weather["humidity"] == 55 and len(calls) == 2
    snap = weather_service.usage_snapshot()
    assert snap["open-meteo"] == {"calls": 1, "failures": 1} and snap["openweather"] == {"calls": 1, "failures": 0}


# ── Rutin / check-in önbelleği ───────────────────────────────────────────────────────────────────

def _provider(monkeypatch, result):
    calls: list = []

    async def fake(lat, lon):
        calls.append((lat, lon))
        return dict(result) if result else None

    monkeypatch.setattr(main, "fetch_weather_live", fake)
    return calls


def test_nearby_requests_share_one_provider_call(monkeypatch):
    calls = _provider(monkeypatch, {"temperature": 24, "humidity": 40, "uv_index": 6})

    first = asyncio.run(main._weather_cached(41.0150, 28.9790))
    second = asyncio.run(main._weather_cached(41.0410, 29.0100))  # aynı 0,1° hücresi
    other = asyncio.run(main._weather_cached(39.93, 32.86))  # başka hücre

    assert first["uv_index"] == 6 and second == first and other["uv_index"] == 6
    assert len(calls) == 2


def test_when_no_provider_answers_the_default_is_returned_like_before(monkeypatch):
    calls = _provider(monkeypatch, None)

    weather = asyncio.run(main._weather_cached(41.0, 29.0))
    again = asyncio.run(main._weather_cached(41.0, 29.0))

    assert weather == main.WEATHER_FALLBACK and again == weather
    assert len(calls) == 1, "başarısız çekim kısa süre saklanır: arka arkaya istek sağlayıcıyı dövmez"


def test_the_returned_weather_can_be_changed_by_the_caller_without_poisoning_the_cache(monkeypatch):
    _provider(monkeypatch, {"temperature": 24, "humidity": 40, "uv_index": 6})
    first = asyncio.run(main._weather_cached(41.0, 29.0))
    first["uv_index"] = 99
    assert asyncio.run(main._weather_cached(41.0, 29.0))["uv_index"] == 6


def test_routine_generation_uses_the_cache(monkeypatch, client):
    calls = _provider(monkeypatch, {"temperature": 24, "humidity": 40, "uv_index": 6})
    body = {
        "user_id": DEMO_UUID, "full_name": "Test", "age": 25, "gender": "female", "concern": "acne",
        "skin_type": "normal", "severity_score": 5, "location_lat": 41.01, "location_lon": 28.97,
    }

    for _ in range(3):
        assert client.post("/generate_routine", json=body).status_code == 200

    assert len(calls) == 1, "aynı bölgeden üç rutin isteği tek sağlayıcı çağrısı"


def test_no_endpoint_calls_the_provider_directly_any_more():
    import inspect

    for name in ("generate_routine", "daily_checkin", "today_plan_endpoint", "daily_tracking_ingest"):
        source = inspect.getsource(getattr(main, name))
        assert "fetch_weather_live" not in source and "run_async(fetch_weather," not in source, name
