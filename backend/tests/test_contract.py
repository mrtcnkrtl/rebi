"""Mobil ↔ backend API sözleşmesi.

`contract/*.json` repo kökünde durur ve iki tarafın da ortak gerçeğidir:
- bu test, gerçek uç yanıtlarının fixture'daki her anahtarı aynı JSON türüyle taşıdığını doğrular
  (backend yeni alan ekleyebilir, mobilin dayandığı bir alanı silemez ya da türünü değiştiremez);
- `mobile/test/contract_test.dart` aynı dosyaları mobilin gerçek ayrıştırıcılarından geçirip değerleri doğrular.

Sözleşmeyi bilerek değiştirirken fixture'ları yeniden üretin:

    REBI_UPDATE_CONTRACT=1 python -m pytest tests/test_contract.py

ve mobil testini birlikte güncelleyin. Aynı sahneden (aşağıdaki `_seed`) üretildiği için mobil
testindeki beklenen değerler sabittir.
"""

from __future__ import annotations

import json
import os
from datetime import date, timedelta
from pathlib import Path

import jwt
import pytest

import main
from tests.fake_supabase import FakeSupabase

CONTRACT_DIR = Path(__file__).resolve().parents[2] / "contract"
UPDATE = os.getenv("REBI_UPDATE_CONTRACT") == "1"

USER_ID = "99999999-9999-4999-8999-999999999999"
SECRET = "test-secret-at-least-32-bytes-long"


@pytest.fixture
def headers(monkeypatch):
    monkeypatch.setenv("SUPABASE_JWT_SECRET", SECRET)
    monkeypatch.delenv("API_ALLOW_INSECURE_AUTH", raising=False)
    token = jwt.encode({"sub": USER_ID, "aud": "authenticated"}, SECRET, algorithm="HS256")
    return {"Authorization": f"Bearer {token}"}


def _event(day: str, hhmm: str, type_: str, payload: dict) -> dict:
    return {
        "user_id": USER_ID,
        "log_date": day,
        "event_time": f"{day}T{hhmm}:00+00:00",
        "type": type_,
        "payload": payload,
        "source": "mobile",
    }


def _seed(monkeypatch) -> FakeSupabase:
    """Dolu bir kullanıcı: rutin, bugünkü kayıtlar, dünkü su, check-in, hatırlatıcı ayarı."""
    today = str(date.today())
    yesterday = str(date.today() - timedelta(days=1))
    routine = [
        {"time": "Sabah", "category": "Bakım", "icon": "🧴", "step_order": 10,
         "action": "Temizleme: köpük temizleyici",
         "usage": "Yüzü ıslat, köpürt, ılık su ile durula."},
        {"time": "Sabah", "category": "Bakım", "icon": "🧊", "step_order": 30,
         "action": "Nemlendirici: Niasinamid + Hyaluronik asit (hafif jel)",
         "usage": "Temiz cilde, ince katman."},
        {"time": "Sabah", "category": "Koruma", "icon": "☀️", "step_order": 40,
         "action": "SPF 50 (geniş spektrumlu)", "usage": "Son adım olarak sür."},
        {"time": "Akşam", "category": "Bakım", "icon": "🌙", "step_order": 10,
         "action": "Temizleme: yağ bazlı temizleyici + jel", "usage": "Çift temizlik."},
    ]
    db = FakeSupabase(
        profiles=[{
            "id": USER_ID, "full_name": "Ayşe Yılmaz", "skin_type": "oily", "age": 29,
            "gender": "female", "city": "İstanbul", "updated_at": f"{today}T06:00:00+00:00",
        }],
        routines=[{
            "user_id": USER_ID, "is_active": True, "created_at": f"{today}T06:30:00+00:00",
            "assessment_id": "a1", "active_routine": routine,
        }],
        daily_events=[
            _event(yesterday, "10:00", "water_intake", {"ml": 500}),
            _event(today, "07:40", "routine_step", {"block": "morning", "step_order": 10, "done": True}),
            _event(today, "07:45", "routine_step", {"block": "morning", "step_order": 30, "done": True}),
            _event(today, "08:00", "water_intake", {"ml": 250}),
            _event(today, "10:00", "water_intake", {"ml": 500}),
            _event(today, "10:30", "makeup", {"used": True}),
            _event(today, "11:00", "nutrition", {"junk_food": True}),
            _event(today, "12:00", "spf_refresh", {}),
            _event(today, "12:30", "product_finished", {"product": "SPF 50 (geniş spektrumlu)", "step_order": 40}),
            _event(today, "07:00", "weather", {
                "uv_index": 6, "humidity": 38, "temperature": 18, "description": "Açık",
                "uv_window": {"start": "11:00", "end": "16:00", "peak": "13:00", "max": 6}, "uv_now": 2,
            }),
        ],
        daily_logs=[{
            "user_id": USER_ID, "log_date": today, "applied_routine": True,
            "skin_feeling": "iyi", "sleep_hours": 7.5, "stress_level": 2, "risk_score": 1,
        }],
        assessments=[{
            "id": "a1", "user_id": USER_ID, "concern": "acne", "severity_score": 4,
            "created_at": f"{yesterday}T08:00:00+00:00",
        }],
        reminder_settings=[{
            "user_id": USER_ID,
            "settings": {
                "wake_time": "07:00", "sleep_time": "23:00", "water_every_minutes": 90, "water_target_ml": 2500,
                "enabled": {"nutrition": False},
            },
        }],
        chat_history=[{
            "seq": 1, "user_id": USER_ID, "role": "user", "content": "Merhaba",
            "surface": "general", "created_at": f"{today}T09:00:00+00:00",
        }],
        legal_consents=[{"user_id": USER_ID, "document_version": main._LEGAL_CONSENT_VERSION}],
        privacy_preferences=[{
            "user_id": USER_ID, "ai_processing_allowed": True,
            "location_processing_allowed": True, "photo_processing_allowed": True,
        }],
    )
    monkeypatch.setattr(main, "get_supabase", lambda: db)
    return db


# ── Şekil karşılaştırması ───────────────────────────────────────────────────

def _kind(value) -> str:
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "bool"
    if isinstance(value, (int, float)):
        return "number"
    if isinstance(value, str):
        return "string"
    if isinstance(value, list):
        return "list"
    return "object"


def shape_problems(actual, expected, path: str = "$") -> list[str]:
    """Fixture'daki her anahtar gerçek yanıtta aynı türle bulunmalı; fazla alan sorun değil."""
    if expected is None:
        return []  # fixture'da null: tür belirsiz, her şey kabul
    if actual is None:
        return [f"{path}: {_kind(expected)} bekleniyordu, null geldi"]
    if _kind(actual) != _kind(expected):
        return [f"{path}: {_kind(expected)} bekleniyordu, {_kind(actual)} geldi"]
    problems: list[str] = []
    if isinstance(expected, dict):
        for key, sub in expected.items():
            if key not in actual:
                problems.append(f"{path}.{key}: alan yok")
            else:
                problems += shape_problems(actual[key], sub, f"{path}.{key}")
    elif isinstance(expected, list) and expected and actual:
        problems += shape_problems(actual[0], expected[0], f"{path}[0]")
    return problems


def _check(name: str, body: dict) -> None:
    path = CONTRACT_DIR / f"{name}.json"
    if UPDATE:
        CONTRACT_DIR.mkdir(exist_ok=True)
        path.write_text(json.dumps(body, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        return
    assert path.exists(), f"{path.name} yok; üretmek için REBI_UPDATE_CONTRACT=1 ile çalıştırın."
    expected = json.loads(path.read_text(encoding="utf-8"))
    problems = shape_problems(body, expected)
    assert not problems, f"{name} sözleşmesi bozuldu:\n  " + "\n  ".join(problems)


# ── Uçlar ───────────────────────────────────────────────────────────────────

def test_me_snapshot_contract(monkeypatch, client, headers):
    _seed(monkeypatch)
    r = client.get("/me/snapshot", params={"user_id": USER_ID}, headers=headers)
    assert r.status_code == 200, r.text
    _check("me_snapshot", r.json())


def test_today_plan_contract(monkeypatch, client, headers):
    _seed(monkeypatch)
    r = client.get("/today/plan", params={"user_id": USER_ID}, headers=headers)
    assert r.status_code == 200, r.text
    _check("today_plan", r.json())


def test_reminder_settings_contract(monkeypatch, client, headers):
    _seed(monkeypatch)
    r = client.get("/me/reminder-settings", params={"user_id": USER_ID}, headers=headers)
    assert r.status_code == 200, r.text
    _check("reminder_settings", r.json())


def test_me_history_contract(monkeypatch, client, headers):
    _seed(monkeypatch)
    r = client.get("/me/history", params={"user_id": USER_ID, "days": 7}, headers=headers)
    assert r.status_code == 200, r.text
    _check("me_history", r.json())


def test_me_profile_contract(monkeypatch, client, headers):
    _seed(monkeypatch)
    r = client.get("/me/profile", params={"user_id": USER_ID}, headers=headers)
    assert r.status_code == 200, r.text
    _check("me_profile", r.json())


def test_ingest_contract(monkeypatch, client, headers):
    _seed(monkeypatch)
    r = client.post(
        "/daily_tracking/ingest",
        json={
            "user_id": USER_ID, "type": "water_intake", "payload": {"ml": 250},
            "client_event_id": "contract-1",
        },
        headers=headers,
    )
    assert r.status_code == 200, r.text
    _check("daily_tracking_ingest", r.json())


# ── Sözleşmenin kendi güvenceleri ───────────────────────────────────────────

def test_shape_check_catches_a_removed_or_retyped_field():
    expected = {"progress": {"water_ml_total": 0, "makeup": {"used": False}}, "items": [{"id": "a"}]}

    assert shape_problems({"progress": {"water_ml_total": 5, "makeup": {"used": True}}, "items": [{"id": "x"}]},
                          expected) == []
    # Fazladan alan serbest
    assert shape_problems({"progress": {"water_ml_total": 5, "makeup": {"used": True}, "yeni": 1},
                           "items": [{"id": "x", "ekstra": 2}]}, expected) == []
    # Silinen alan
    assert shape_problems({"progress": {"makeup": {"used": True}}, "items": [{"id": "x"}]}, expected) == [
        "$.progress.water_ml_total: alan yok"
    ]
    # Tür değişimi (sayı → metin) ve null
    problems = shape_problems(
        {"progress": {"water_ml_total": "750", "makeup": None}, "items": [{"id": "x"}]}, expected
    )
    assert "$.progress.water_ml_total: number bekleniyordu, string geldi" in problems
    assert "$.progress.makeup: object bekleniyordu, null geldi" in problems


def test_every_contract_fixture_is_exercised_by_a_test():
    names = {p.stem for p in CONTRACT_DIR.glob("*.json")} if CONTRACT_DIR.exists() else set()
    covered = {
        "me_snapshot", "today_plan", "reminder_settings", "me_history", "me_profile", "daily_tracking_ingest",
    }
    assert names <= covered, f"Testi olmayan sözleşme dosyası: {sorted(names - covered)}"
