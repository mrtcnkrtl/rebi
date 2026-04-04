"""Hızlı API duman testleri (Sunucu / Gemini gerekmez veya kısıtlı)."""

import pytest

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


def test_openapi_json(client):
    r = client.get("/openapi.json")
    assert r.status_code == 200
    spec = r.json()
    assert spec.get("openapi", "").startswith("3.")
    paths = spec.get("paths", {})
    assert "/generate_routine" in paths
    assert "/daily_checkin" in paths
    assert "/daily_tracking/ingest" in paths
    tags = {t["name"] for t in spec.get("tags", [])}
    assert "routine" in tags
    assert "tracking" in tags


def test_daily_checkin_status_demo(client):
    r = client.get("/daily_checkin/status", params={"user_id": DEMO_UUID})
    assert r.status_code == 200
    j = r.json()
    assert "already_checked_in" in j
    assert "log_date" in j


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
