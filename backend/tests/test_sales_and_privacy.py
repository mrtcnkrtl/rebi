"""Plus satış onayı ve 72 saatlik veri ihlali kaydı."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

import jwt
import pytest

import main
from privacy_incident import parse_discovered_at, record_privacy_incident
from tests.fake_supabase import FakeSupabase

USER_ID = "55555555-5555-4555-8555-555555555555"
SECRET = "test-secret-at-least-32-bytes-long"
INCIDENT_SECRET = "incident-secret-abcdefghijklmnop"


def _headers(monkeypatch):
    monkeypatch.setenv("SUPABASE_JWT_SECRET", SECRET)
    monkeypatch.delenv("API_ALLOW_INSECURE_AUTH", raising=False)
    token = jwt.encode({"sub": USER_ID, "aud": "authenticated"}, SECRET, algorithm="HS256")
    return {"Authorization": f"Bearer {token}"}


def test_sales_consent_rejects_partial(client, monkeypatch):
    _headers(monkeypatch)
    monkeypatch.setattr(main, "get_supabase", lambda: FakeSupabase())
    res = client.post(
        "/sales-consent/accept",
        headers=_headers(monkeypatch),
        json={
            "user_id": USER_ID,
            "document_version": "v1",
            "pre_info_accepted": True,
            "distance_contract_accepted": False,
        },
    )
    assert res.status_code == 400


def test_sales_consent_records_both(client, monkeypatch):
    db = FakeSupabase()
    monkeypatch.setattr(main, "get_supabase", lambda: db)
    res = client.post(
        "/sales-consent/accept",
        headers=_headers(monkeypatch),
        json={
            "user_id": USER_ID,
            "document_version": "v1",
            "pre_info_accepted": True,
            "distance_contract_accepted": True,
        },
    )
    assert res.status_code == 200
    assert res.json()["already_recorded"] is False
    rows = db.table("sales_consents").rows
    assert rows[0]["pre_info_accepted"] is True
    assert rows[0]["distance_contract_accepted"] is True


def test_privacy_incident_closed_without_secret(client, monkeypatch):
    monkeypatch.delenv("PRIVACY_INCIDENT_SECRET", raising=False)
    monkeypatch.setattr(main, "get_supabase", lambda: FakeSupabase())
    res = client.post("/privacy/incidents", json={"summary": "ornek ihlal ozeti"})
    assert res.status_code == 503


def test_privacy_incident_sets_72h_deadline(client, monkeypatch):
    monkeypatch.setenv("PRIVACY_INCIDENT_SECRET", INCIDENT_SECRET)
    db = FakeSupabase()
    monkeypatch.setattr(main, "get_supabase", lambda: db)
    discovered = datetime(2026, 11, 1, 12, 0, tzinfo=timezone.utc)
    res = client.post(
        "/privacy/incidents",
        headers={"x-privacy-incident-token": INCIDENT_SECRET},
        json={"summary": "ornek ihlal ozeti", "discovered_at": discovered.isoformat()},
    )
    assert res.status_code == 200
    body = res.json()
    deadline = datetime.fromisoformat(body["notify_kurul_by"])
    assert deadline - discovered == timedelta(hours=72)
    assert db.table("privacy_incidents").rows[0]["summary"] == "ornek ihlal ozeti"


def test_parse_discovered_at_defaults_to_now():
    before = datetime.now(timezone.utc)
    parsed = parse_discovered_at(None)
    after = datetime.now(timezone.utc)
    assert before <= parsed <= after


def test_record_rejects_short_summary():
    with pytest.raises(ValueError):
        record_privacy_incident(FakeSupabase(), "kisa", datetime.now(timezone.utc))
