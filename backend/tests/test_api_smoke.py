"""Hızlı API duman testleri (Sunucu / Gemini gerekmez veya kısıtlı)."""

import pytest

import main

DEMO_UUID = "00000000-0000-4000-8000-000000000001"


def test_root(client):
    r = client.get("/")
    assert r.status_code == 200
    data = r.json()
    assert "endpoints" in data
    assert "/health" in data["endpoints"]


def test_health(client):
    r = client.get("/health")
    assert r.status_code == 200
    body = r.json()
    assert body.get("status") == "ok"
    assert "jwt_auth" in body
    assert "rate_limit_backend" in body
    # Şema uygulaması sessizce başarısız olabiliyordu; durumu health söylüyor.
    assert body.get("db_schema") in {"ok", "skipped", "error", "unknown"}
    assert body.get("push") in {"configured", "off"}


def test_docs_are_disabled_unless_explicitly_enabled(monkeypatch):
    monkeypatch.delenv("API_DOCS_ENABLED", raising=False)
    assert main.docs_enabled() is False

    monkeypatch.setenv("API_DOCS_ENABLED", "1")
    assert main.docs_enabled() is True


def test_openapi_json(client):
    r = client.get("/openapi.json")
    assert r.status_code == 200
    spec = r.json()
    assert spec.get("openapi", "").startswith("3.")
    paths = spec.get("paths", {})
    assert "/generate_routine" in paths
    assert "/daily_checkin" in paths
    assert "/daily_tracking/ingest" in paths
    assert "/routine/active" in paths
    assert "/today/plan" in paths
    tags = {t["name"] for t in spec.get("tags", [])}
    assert "routine" in tags
    assert "tracking" in tags


def test_daily_checkin_status_demo(client):
    r = client.get("/daily_checkin/status", params={"user_id": DEMO_UUID})
    assert r.status_code == 200
    j = r.json()
    assert "already_checked_in" in j
    assert "log_date" in j


def test_routine_active_demo_has_no_routine(client):
    r = client.get("/routine/active", params={"user_id": DEMO_UUID})
    assert r.status_code == 200, r.text
    j = r.json()
    assert j["has_routine"] is False
    assert j["routine"] == []


def test_today_plan_demo_returns_advice_and_reminders(client):
    r = client.get("/today/plan", params={"user_id": DEMO_UUID})
    assert r.status_code == 200, r.text
    j = r.json()
    assert j["weather_source"] == "default"
    assert any("SPF" in item["action"] for item in j["environment_advice"])
    assert {"routine_morning", "water_intake"} <= {x["id"] for x in j["reminders"]}
    assert j["progress"]["makeup"]["logged"] is False


def test_makeup_and_product_events_are_accepted(client):
    for event_type, payload in (
        ("makeup", {"used": True}),
        ("product_finished", {"product": "SPF 50", "step_order": 40}),
    ):
        r = client.post(
            "/daily_tracking/ingest",
            json={"user_id": DEMO_UUID, "type": event_type, "payload": payload},
        )
        assert r.status_code == 200, r.text

    agg = r.json()["aggregated"]
    assert agg["makeup"]["used"] is True
    assert agg["products_finished"][0]["product"] == "SPF 50"


@pytest.mark.slow
def test_generate_routine_demo_no_db_error(client):
    """Demo kullanıcı: FK hatası olmadan 200 ve rutin listesi."""
    r = client.post(
        "/generate_routine",
        json={
            "user_id": DEMO_UUID,
            "full_name": "Test",
            "age": 25,
            "gender": "female",
            "concern": "acne",
            "skin_type": "normal",
            "severity_score": 5,
        },
    )
    assert r.status_code == 200, r.text
    data = r.json()
    assert isinstance(data.get("routine"), list)
    assert len(data["routine"]) >= 1
    assert "assessment_id" in data
