"""`GET /me/assessment/last`: yeni analiz, kullanıcıyı baştan doldurmaya zorlamasın.

Sihirbaz bu uçtan gelen cevaplarla açılır; bu yüzden uç her zaman en yeni analizi vermeli,
analiz yoksa hata değil `found: false` dönmeli ve başka kullanıcının kaydını sızdırmamalı.
"""

from __future__ import annotations

import jwt
import pytest

import main
from tests.fake_supabase import FakeSupabase

USER_ID = "55555555-5555-4555-8555-555555555555"
OTHER_ID = "44444444-4444-4444-8444-444444444444"
SECRET = "test-secret-at-least-32-bytes-long"


@pytest.fixture
def headers(monkeypatch):
    monkeypatch.setenv("SUPABASE_JWT_SECRET", SECRET)
    monkeypatch.delenv("API_ALLOW_INSECURE_AUTH", raising=False)
    token = jwt.encode({"sub": USER_ID, "aud": "authenticated"}, SECRET, algorithm="HS256")
    return {"Authorization": f"Bearer {token}"}


def _assessment(user_id: str, concern: str, created_at: str, skin_type: str = "oily") -> dict:
    return {
        "id": f"{user_id}-{created_at}",
        "user_id": user_id,
        "concern": concern,
        "severity_score": 7,
        "created_at": created_at,
        "lifestyle_data": {
            "skin_type": skin_type,
            "water_intake": 1.5,
            "sleep_hours": 6,
            "concerns": [{"id": concern, "severity_score": 7, "zones": ["left_cheek", "right_cheek"]}],
            "triggers": ["stress"],
        },
    }


def _db(monkeypatch, assessments: list[dict], profiles: list[dict] | None = None) -> FakeSupabase:
    db = FakeSupabase(
        assessments=assessments,
        profiles=profiles if profiles is not None else [
            {"id": USER_ID, "full_name": "Ayşe Yılmaz", "age": 31, "gender": "female", "skin_type": "oily"}
        ],
    )
    monkeypatch.setattr(main, "get_supabase", lambda: db)
    return db


def test_returns_the_newest_assessment_with_its_raw_answers(monkeypatch, client, headers):
    _db(monkeypatch, [
        _assessment(USER_ID, "dryness", "2026-10-01T08:00:00+00:00", skin_type="dry"),
        _assessment(USER_ID, "acne", "2026-11-05T08:00:00+00:00"),
    ])
    r = client.get("/me/assessment/last", params={"user_id": USER_ID}, headers=headers)
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["found"] is True
    assert body["concern"] == "acne"
    assert body["severity_score"] == 7
    assert body["lifestyle_data"]["skin_type"] == "oily"
    assert body["lifestyle_data"]["triggers"] == ["stress"]
    # Sihirbazın ilk sayfası profilden dolar.
    assert body["full_name"] == "Ayşe Yılmaz"
    assert body["age"] == 31
    assert body["gender"] == "female"


def test_without_an_assessment_the_answer_is_empty_not_an_error(monkeypatch, client, headers):
    _db(monkeypatch, [])
    r = client.get("/me/assessment/last", params={"user_id": USER_ID}, headers=headers)
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["found"] is False
    assert body["lifestyle_data"] == {}


def test_another_users_assessment_is_not_returned(monkeypatch, client, headers):
    _db(monkeypatch, [_assessment(OTHER_ID, "acne", "2026-11-05T08:00:00+00:00")])
    r = client.get("/me/assessment/last", params={"user_id": USER_ID}, headers=headers)
    assert r.status_code == 200, r.text
    assert r.json()["found"] is False


def test_someone_elses_token_cannot_read_the_answers(monkeypatch, client, headers):
    _db(monkeypatch, [_assessment(OTHER_ID, "acne", "2026-11-05T08:00:00+00:00")])
    r = client.get("/me/assessment/last", params={"user_id": OTHER_ID}, headers=headers)
    assert r.status_code == 403, r.text


def test_an_unreadable_database_says_so_instead_of_crashing(monkeypatch, client, headers):
    db = _db(monkeypatch, [])

    def boom():
        raise RuntimeError("bağlantı yok")

    db.tables["assessments"].execute = boom
    r = client.get("/me/assessment/last", params={"user_id": USER_ID}, headers=headers)
    assert r.status_code == 502, r.text
