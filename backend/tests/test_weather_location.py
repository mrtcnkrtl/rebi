"""Hava durumunun kullanıcıya her koşulda ulaşması: sağlayıcı sertleştirme, bayat değer, şehir araması, konumun profile kaydı."""

from __future__ import annotations

import asyncio

import pytest

import main
import weather_service
from tests.test_user_sync import USER_ID, _db, headers  # noqa: F401  (headers: fixture)

_OK = {
    "current": {"time": "2026-10-16T14:15", "temperature_2m": 21.4, "relative_humidity_2m": 38, "weather_code": 1},
    "daily": {"uv_index_max": [8.2]},
}


class _Response:
    def __init__(self, payload):
        self._payload = payload

    def raise_for_status(self):
        pass

    def json(self):
        return self._payload


def _stub_client(monkeypatch, behaviours: list):
    """Sıradaki davranış: dict (yanıt) ya da istisna. Her get çağrısı (url, params) kaydeder."""
    calls: list = []

    class _Client:
        def __init__(self, *args, **kwargs):
            pass

        async def __aenter__(self):
            return self

        async def __aexit__(self, *_):
            return False

        async def get(self, url, params=None):
            calls.append((url, dict(params or {})))
            behaviour = behaviours[min(len(calls) - 1, len(behaviours) - 1)]
            if isinstance(behaviour, Exception):
                raise behaviour
            return _Response(behaviour)

    monkeypatch.setattr(weather_service.httpx, "AsyncClient", _Client)
    return calls


@pytest.fixture(autouse=True)
def _clean(monkeypatch):
    weather_service.reset_usage()
    main._WEATHER_CACHE.clear()
    main._PLACES_CACHE.clear()
    monkeypatch.setattr(weather_service, "OPENWEATHER_API_KEY", "")
    monkeypatch.setattr(weather_service, "OPEN_METEO_API_KEY", "")
    yield
    main._WEATHER_CACHE.clear()
    main._PLACES_CACHE.clear()


# ── Sağlayıcı sertleştirme ───────────────────────────────────────────────────────────────────────

@pytest.mark.parametrize("missing", ["temperature_2m", "relative_humidity_2m"])
def test_a_response_with_a_missing_value_is_a_failure_not_a_made_up_reading(monkeypatch, missing):
    payload = {"current": {k: v for k, v in _OK["current"].items() if k != missing}, "daily": _OK["daily"]}
    _stub_client(monkeypatch, [payload])

    assert asyncio.run(weather_service.fetch_weather_live(41.0, 29.0)) is None
    assert weather_service.usage_snapshot() == {"open-meteo": {"calls": 1, "failures": 1}}


def test_a_response_without_uv_is_a_failure_too(monkeypatch):
    _stub_client(monkeypatch, [{"current": _OK["current"], "daily": {}}])
    assert asyncio.run(weather_service.fetch_weather_live(41.0, 29.0)) is None


def test_the_free_endpoint_is_used_without_a_key(monkeypatch):
    calls = _stub_client(monkeypatch, [_OK])

    weather = asyncio.run(weather_service.fetch_weather_live(41.0, 29.0))

    assert weather["temperature"] == 21 and weather["uv_index"] == 8
    url, params = calls[0]
    assert url == "https://api.open-meteo.com/v1/forecast" and "apikey" not in params


def test_the_paid_endpoint_and_key_are_used_when_configured(monkeypatch):
    monkeypatch.setattr(weather_service, "OPEN_METEO_API_KEY", "gizli")
    calls = _stub_client(monkeypatch, [_OK])

    assert asyncio.run(weather_service.fetch_weather_live(41.0, 29.0)) is not None

    url, params = calls[0]
    assert url == "https://customer-api.open-meteo.com/v1/forecast" and params["apikey"] == "gizli"


# ── Bayat değer (sağlayıcı geçici olarak yok) ────────────────────────────────────────────────────

def _provider(monkeypatch, results: list):
    calls: list = []

    async def fake(lat, lon):
        calls.append((lat, lon))
        r = results[min(len(calls) - 1, len(results) - 1)]
        return dict(r) if r else None

    monkeypatch.setattr(main, "fetch_weather_live", fake)
    return calls


GOOD = {"temperature": 24, "humidity": 40, "uv_index": 6}


def _expire(key=(41.0, 29.0)):
    """Önbellek girdisini süresi dolmuş say (son gerçek ölçüm korunur)."""
    expires, data, good = main._WEATHER_CACHE[key]
    main._WEATHER_CACHE[key] = (0.0, data, good)


def test_when_the_provider_goes_down_the_last_real_reading_is_still_served(monkeypatch):
    calls = _provider(monkeypatch, [GOOD, None])
    assert asyncio.run(main._weather_for_coords(41.0, 29.0))["uv_index"] == 6
    _expire()

    served = asyncio.run(main._weather_for_coords(41.0, 29.0))

    assert served == GOOD, "sağlayıcı yokken son gerçek ölçüm gösterilir"
    assert len(calls) == 2
    # Kısa süre sonra sağlayıcı tekrar denenir (bayat değer kalıcı olmaz).
    assert main._WEATHER_CACHE[(41.0, 29.0)][0] - __import__("time").monotonic() <= main._WEATHER_FAILURE_TTL_SECONDS


def test_a_reading_older_than_three_hours_is_not_served(monkeypatch):
    _provider(monkeypatch, [GOOD, None])
    asyncio.run(main._weather_for_coords(41.0, 29.0))
    expires, data, (at, reading) = main._WEATHER_CACHE[(41.0, 29.0)]
    main._WEATHER_CACHE[(41.0, 29.0)] = (0.0, data, (at - main._WEATHER_STALE_MAX_SECONDS - 60, reading))

    assert asyncio.run(main._weather_for_coords(41.0, 29.0)) is None


def test_a_region_that_never_had_a_reading_gets_none_not_a_default(monkeypatch):
    _provider(monkeypatch, [None])
    assert asyncio.run(main._weather_for_coords(41.0, 29.0)) is None


def test_once_the_provider_is_back_the_fresh_reading_replaces_the_stale_one(monkeypatch):
    fresh = {"temperature": 19, "humidity": 55, "uv_index": 2}
    _provider(monkeypatch, [GOOD, None, fresh])
    asyncio.run(main._weather_for_coords(41.0, 29.0))
    _expire()
    asyncio.run(main._weather_for_coords(41.0, 29.0))
    _expire()

    assert asyncio.run(main._weather_for_coords(41.0, 29.0)) == fresh


# ── Şehir araması ────────────────────────────────────────────────────────────────────────────────

_GEO = {
    "results": [
        {"name": "Ankara", "latitude": 39.91987, "longitude": 32.85427, "admin1": "Ankara", "country": "Türkiye"},
        {"name": "Ankara", "latitude": 40.0, "longitude": 33.0, "country": "Türkiye"},
        {"name": "Bozuk"},  # koordinatsız aday atlanır
    ]
}


def test_search_places_parses_and_rounds_coordinates(monkeypatch):
    calls = _stub_client(monkeypatch, [_GEO])

    places = asyncio.run(weather_service.search_places("Ankara", language="tr"))

    assert places[0] == {"name": "Ankara", "region": "Ankara", "country": "Türkiye", "lat": 39.92, "lon": 32.85}
    assert len(places) == 2 and places[1]["region"] is None
    url, params = calls[0]
    assert url == "https://geocoding-api.open-meteo.com/v1/search"
    assert params["name"] == "Ankara" and params["language"] == "tr"
    assert weather_service.usage_snapshot() == {"open-meteo-geocoding": {"calls": 1, "failures": 0}}


def test_search_places_distinguishes_not_found_from_service_down(monkeypatch):
    _stub_client(monkeypatch, [{}])
    assert asyncio.run(weather_service.search_places("Yokyer")) == []

    _stub_client(monkeypatch, [RuntimeError("kapalı")])
    assert asyncio.run(weather_service.search_places("Ankara")) is None


def test_search_places_ignores_too_short_queries_without_calling_the_provider(monkeypatch):
    calls = _stub_client(monkeypatch, [_GEO])
    assert asyncio.run(weather_service.search_places(" a ")) == []
    assert calls == []


@pytest.fixture
def consent(monkeypatch):
    def grant(allowed: bool = True, **tables):
        return _db(monkeypatch, privacy_preferences=[{"user_id": USER_ID, "location_processing_allowed": allowed}], **tables)

    return grant


def _places(monkeypatch, result):
    calls: list = []

    async def fake(query, language="tr", count=5):
        calls.append((query, language))
        return [dict(p) for p in result] if result is not None else None

    monkeypatch.setattr(main, "search_places", fake)
    return calls


ANKARA = {"name": "Ankara", "region": "Ankara", "country": "Türkiye", "lat": 39.92, "lon": 32.85}


def test_search_endpoint_returns_places_and_caches_repeated_queries(monkeypatch, client, headers, consent):
    consent()
    calls = _places(monkeypatch, [ANKARA])

    for q in ("Ankara", "  ankara "):
        r = client.get("/weather/search", params={"user_id": USER_ID, "q": q}, headers=headers)
        assert r.status_code == 200, r.text
        assert r.json() == {"places": [ANKARA]}

    assert len(calls) == 1, "aynı sorgu (büyük/küçük harf, boşluk fark etmez) sağlayıcıyı bir kez çağırır"


def test_search_endpoint_needs_location_consent(monkeypatch, client, headers, consent):
    consent(allowed=False)
    calls = _places(monkeypatch, [ANKARA])

    r = client.get("/weather/search", params={"user_id": USER_ID, "q": "Ankara"}, headers=headers)

    assert r.status_code == 403 and calls == []


def test_search_endpoint_reports_a_provider_outage_and_does_not_cache_it(monkeypatch, client, headers, consent):
    consent()
    calls = _places(monkeypatch, None)

    for _ in range(2):
        r = client.get("/weather/search", params={"user_id": USER_ID, "q": "Ankara"}, headers=headers)
        assert r.status_code == 502

    assert len(calls) == 2, "başarısız arama saklanmaz: servis düzelince hemen yeniden denenir"


def test_search_endpoint_validates_the_query(monkeypatch, client, headers, consent):
    consent()
    _places(monkeypatch, [ANKARA])

    assert client.get("/weather/search", params={"user_id": USER_ID, "q": "a"}, headers=headers).status_code == 422
    assert client.get("/weather/search", params={"user_id": USER_ID, "q": "x" * 81}, headers=headers).status_code == 422
    assert client.get("/weather/search", params={"user_id": USER_ID, "q": "Ankara", "lang": "de"}, headers=headers).status_code == 422
    assert client.get("/weather/search", params={"user_id": USER_ID}, headers=headers).status_code == 422


# ── Konumun profile kaydı ────────────────────────────────────────────────────────────────────────

def _patch(client, headers, **body):
    return client.patch("/me/profile", json={"user_id": USER_ID, **body}, headers=headers)


def test_device_location_is_saved_rounded_when_consent_exists(monkeypatch, client, headers, consent):
    db = consent(profiles=[{"id": USER_ID}])

    r = _patch(client, headers, location_lat=41.01234, location_lon=28.97654)

    assert r.status_code == 200, r.text
    assert r.json()["location_saved"] is True
    written = db.tables["profiles"].upserted[-1]
    assert (written["location_lat"], written["location_lon"]) == (41.01, 28.98)


def test_location_is_refused_without_location_consent(monkeypatch, client, headers, consent):
    db = consent(allowed=False, profiles=[{"id": USER_ID}])

    r = _patch(client, headers, location_lat=41.0, location_lon=29.0)

    assert r.status_code == 403
    assert db.tables["profiles"].upserted == []


@pytest.mark.parametrize(
    "body",
    [
        {"location_lat": 41.0},
        {"location_lon": 29.0},
        {"location_lat": 91.0, "location_lon": 29.0},
        {"location_lat": 41.0, "location_lon": 181.0},
    ],
)
def test_an_incomplete_or_out_of_range_location_is_rejected(monkeypatch, client, headers, consent, body):
    consent(profiles=[{"id": USER_ID}])
    assert _patch(client, headers, **body).status_code == 422


def test_a_typed_city_is_resolved_to_a_location_once_when_consent_exists(monkeypatch, client, headers, consent):
    db = consent(profiles=[{"id": USER_ID}])
    calls = _places(monkeypatch, [ANKARA])

    r = _patch(client, headers, city="Ankara")

    assert r.status_code == 200, r.text
    assert r.json()["location_saved"] is True and calls == [("Ankara", "tr")]
    written = db.tables["profiles"].upserted[-1]
    assert (written["city"], written["location_lat"], written["location_lon"]) == ("Ankara", 39.92, 32.85)


def test_a_city_that_cannot_be_found_is_still_saved_as_text(monkeypatch, client, headers, consent):
    db = consent(profiles=[{"id": USER_ID}])
    _places(monkeypatch, [])

    r = _patch(client, headers, city="Hayalî Köy")

    assert r.status_code == 200 and r.json()["location_saved"] is False
    assert "location_lat" not in db.tables["profiles"].upserted[-1]


def test_a_city_is_not_sent_to_the_provider_without_location_consent(monkeypatch, client, headers, consent):
    db = consent(allowed=False, profiles=[{"id": USER_ID}])
    calls = _places(monkeypatch, [ANKARA])

    r = _patch(client, headers, city="Ankara")

    assert r.status_code == 200 and r.json()["location_saved"] is False and calls == []
    assert db.tables["profiles"].upserted[-1]["city"] == "Ankara"


def test_an_explicit_location_wins_over_resolving_the_city(monkeypatch, client, headers, consent):
    db = consent(profiles=[{"id": USER_ID}])
    calls = _places(monkeypatch, [ANKARA])

    _patch(client, headers, city="Ankara", location_lat=38.42, location_lon=27.14)

    assert calls == []
    written = db.tables["profiles"].upserted[-1]
    assert (written["location_lat"], written["location_lon"]) == (38.42, 27.14)


def test_a_saved_location_gives_the_plan_live_weather_without_the_device(monkeypatch, client, headers, consent):
    consent(profiles=[{"id": USER_ID, "location_lat": 39.92, "location_lon": 32.85}])

    async def _weather(lat, lon):
        assert (lat, lon) == (39.92, 32.85)
        return dict(GOOD)

    monkeypatch.setattr(main, "fetch_weather_live", _weather)

    body = client.get("/today/plan", params={"user_id": USER_ID}, headers=headers).json()

    assert body["weather_source"] == "profile" and body["weather"]["uv_index"] == 6
