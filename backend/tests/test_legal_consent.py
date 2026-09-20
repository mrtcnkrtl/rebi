from __future__ import annotations

import main


USER_ID = "11111111-1111-4111-8111-111111111111"


class _Result:
    def __init__(self, data):
        self.data = data


class _LegalConsentTable:
    def __init__(self):
        self.mode = ""
        self.inserted = None

    def select(self, _columns):
        self.mode = "select"
        return self

    def eq(self, _column, _value):
        return self

    def limit(self, _value):
        return self

    def insert(self, payload):
        self.mode = "insert"
        self.inserted = payload
        return self

    def execute(self):
        if self.mode == "select":
            return _Result([])
        return _Result([{**self.inserted, "accepted_at": "2026-09-20T14:00:00Z"}])


class _PrivacyTable:
    def __init__(self):
        self.saved = None

    def upsert(self, payload):
        self.saved = payload
        return self

    def execute(self):
        return _Result([self.saved])


class _Supabase:
    def __init__(self):
        self.consents = _LegalConsentTable()
        self.preferences = _PrivacyTable()

    def table(self, name):
        if name == "legal_consents":
            return self.consents
        assert name == "privacy_preferences"
        return self.preferences


def test_legal_consent_is_recorded_by_backend(monkeypatch, client):
    db = _Supabase()
    monkeypatch.setattr(main, "get_supabase", lambda: db)

    response = client.post(
        "/legal-consent/accept",
        json={
            "user_id": USER_ID,
            "document_version": "v2",
            "kvkk_accepted": True,
            "explicit_consent_accepted": True,
            "ai_processing_accepted": True,
            "location_processing_accepted": False,
            "photo_processing_accepted": True,
        },
    )

    assert response.status_code == 200
    assert db.consents.inserted == {
        "user_id": USER_ID,
        "document_version": "v2",
        "kvkk_accepted": True,
        "explicit_consent_accepted": True,
        "ai_processing_accepted": True,
        "location_processing_accepted": False,
        "photo_processing_accepted": True,
    }
    assert db.preferences.saved["photo_processing_allowed"] is True


def test_legal_consent_rejects_partial_acceptance(monkeypatch, client):
    monkeypatch.setattr(main, "get_supabase", _Supabase)

    response = client.post(
        "/legal-consent/accept",
        json={
            "user_id": USER_ID,
            "document_version": "v2",
            "kvkk_accepted": True,
            "explicit_consent_accepted": False,
            "ai_processing_accepted": True,
        },
    )

    assert response.status_code == 400
