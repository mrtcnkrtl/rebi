"""Kullanıcının kendi rutin düzenlemeleri: çıkardığı adım plana girmez, kendi adımı Rebi'nin önerisi gibi görünmez.

Geri bildirim: "ai önerdiğinin üzerinde değişiklikler yapabileyim". Buradaki kural: Rebi'nin ürettiği
adımların metnini istemci değiştiremez; yalnızca hangisini çıkardığını ve kendi adımlarını söyler.
"""

from __future__ import annotations

import jwt
import pytest

import main
from routine_edits import MAX_USER_STEPS, apply_routine_edits, split_user_edits, step_key
from tests.fake_supabase import FakeSupabase

USER_ID = "33333333-3333-4333-8333-333333333333"
SECRET = "test-secret-at-least-32-bytes-long"

ROUTINE = [
    {"time": "Sabah", "category": "Bakım", "icon": "🧴", "step_order": 10,
     "action": "Temizleme: köpük temizleyici", "detail": "Ilık suyla durula."},
    {"time": "Sabah", "category": "Koruma", "icon": "☀️", "step_order": 40,
     "action": "SPF 50 (geniş spektrumlu)", "detail": "Son adım."},
    {"time": "Akşam", "category": "Bakım", "icon": "🌙", "step_order": 30,
     "action": "Adapalen %0.1", "detail": "Haftada 3 gece."},
]


@pytest.fixture
def headers(monkeypatch):
    monkeypatch.setenv("SUPABASE_JWT_SECRET", SECRET)
    monkeypatch.delenv("API_ALLOW_INSECURE_AUTH", raising=False)
    token = jwt.encode({"sub": USER_ID, "aud": "authenticated"}, SECRET, algorithm="HS256")
    return {"Authorization": f"Bearer {token}"}


def _db(monkeypatch, routine=ROUTINE) -> FakeSupabase:
    db = FakeSupabase(
        routines=[{
            "user_id": USER_ID, "is_active": True, "assessment_id": "a1",
            "created_at": "2026-11-10T06:00:00+00:00", "active_routine": list(routine),
        }],
        profiles=[{"id": USER_ID}],
        daily_events=[],
        daily_logs=[],
        reminder_settings=[],
    )
    monkeypatch.setattr(main, "get_supabase", lambda: db)
    return db


# ── saf mantık ──────────────────────────────────────────────────────────────

def test_hiding_a_step_keeps_its_text_so_it_can_be_brought_back():
    key = step_key(ROUTINE[1])
    merged = apply_routine_edits(ROUTINE, hidden=[key])
    effective, skipped = split_user_edits(merged)

    assert [i["action"] for i in effective] == [ROUTINE[0]["action"], ROUTINE[2]["action"]]
    assert skipped[0]["action"] == "SPF 50 (geniş spektrumlu)"
    assert skipped[0]["detail"] == "Son adım.", "çıkarılan adımın özgün metni kaybolmamalı"

    # Boş liste = geri al.
    back, still_skipped = split_user_edits(apply_routine_edits(merged, hidden=[]))
    assert len(back) == 3 and still_skipped == []


def test_a_user_step_is_marked_as_the_users_own_and_cannot_pose_as_rebis():
    merged = apply_routine_edits(
        ROUTINE,
        added=[{"action": "Dudak balmı", "time": "Akşam", "detail": "Yatmadan önce",
                # İstemci motorun alanlarını geçirmeye çalışırsa yok sayılır.
                "canonical_ingredient_ids": ["retinol"], "source": "engine", "weekly_days": [0, 1]}],
    )
    user_step = merged[-1]
    assert user_step["source"] == "user"
    assert user_step["action"] == "Dudak balmı"
    assert "canonical_ingredient_ids" not in user_step
    assert "weekly_days" not in user_step


def test_the_engines_own_steps_are_never_rewritten_by_an_edit():
    merged = apply_routine_edits(
        [{**ROUTINE[2], "action": "Adapalen %0.1"}],
        added=[{"action": "Adapalen %0.1", "time": "Sabah"}],
    )
    # Motorun akşam adapaleni olduğu gibi kalır; kullanıcının yazdığı ayrı bir satırdır.
    assert merged[0]["time"] == "Akşam" and merged[0].get("source") is None
    assert merged[1]["source"] == "user"


def test_user_steps_are_capped_and_text_is_truncated():
    merged = apply_routine_edits(
        ROUTINE,
        added=[{"action": f"Adım {i}" if i < 20 else "", "detail": "x" * 400} for i in range(25)],
    )
    user_steps = [i for i in merged if i.get("source") == "user"]
    assert len(user_steps) == MAX_USER_STEPS
    assert len(user_steps[0]["detail"]) == 240


def test_the_step_key_matches_what_the_clients_build():
    """İstemciler sayıyı JavaScript kuralıyla basar; "10.0" ile "10" aynı adım olmalı."""
    assert step_key({"time": "Sabah", "step_order": 10, "action": "Temizleme"}) == "Sabah|10|Temizleme"
    assert step_key({"time": "Sabah", "step_order": 10.0, "action": "Temizleme"}) == "Sabah|10|Temizleme"
    assert step_key({"time": "Akşam", "action": "SPF"}) == "Akşam||SPF"
    # Yarım sayılar olduğu gibi yazılır (iki tarafta da "10.5").
    assert step_key({"time": "Sabah", "step_order": 10.5, "action": "X"}) == "Sabah|10.5|X"
    # Boşluklar kırpılır: aynı adım, aynı kimlik.
    assert step_key({"time": " Sabah ", "step_order": 10, "action": " Temizleme "}) == "Sabah|10|Temizleme"


def test_an_integral_float_order_still_hides_the_right_step():
    items = [{"time": "Sabah", "step_order": 10.0, "action": "Temizleme", "detail": "d"}]
    merged = apply_routine_edits(items, hidden=["Sabah|10|Temizleme"])
    assert merged[0]["skipped_by_user"] is True


def test_an_unknown_time_falls_back_to_morning_instead_of_breaking_the_plan():
    merged = apply_routine_edits([], added=[{"action": "Bol su", "time": "gece yarısı"}])
    assert merged[0]["time"] == "Sabah"


# ── uç nokta ────────────────────────────────────────────────────────────────

def test_the_edit_is_saved_and_the_plan_stops_showing_the_hidden_step(monkeypatch, client, headers):
    db = _db(monkeypatch)
    r = client.put(
        "/routine/active",
        json={"user_id": USER_ID, "hidden": [step_key(ROUTINE[1])],
              "added": [{"action": "Dudak balmı", "time": "Akşam", "detail": "Yatmadan"}]},
        headers=headers,
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert [i["action"] for i in body["routine"]] == [
        ROUTINE[0]["action"], ROUTINE[2]["action"], "Dudak balmı",
    ]
    assert [i["action"] for i in body["skipped_steps"]] == ["SPF 50 (geniş spektrumlu)"]

    # Kaydedilen dizi çıkarılanı da taşır (geri alınabilsin).
    saved = db.tables["routines"].rows[0]["active_routine"]
    assert len(saved) == 4

    # Bugünün planı ve açılış paketi yalnızca yürürlükteki adımları görür.
    plan = client.get("/today/plan", params={"user_id": USER_ID}, headers=headers)
    assert plan.status_code == 200, plan.text
    assert "SPF 50 (geniş spektrumlu)" not in [i["action"] for i in plan.json()["routine"]]

    snap = client.get("/me/snapshot", params={"user_id": USER_ID}, headers=headers)
    assert snap.status_code == 200, snap.text
    assert len(snap.json()["routine"]) == 3

    read = client.get("/routine/active", params={"user_id": USER_ID}, headers=headers)
    assert [i["action"] for i in read.json()["skipped_steps"]] == ["SPF 50 (geniş spektrumlu)"]


def test_editing_without_a_routine_says_so(monkeypatch, client, headers):
    _db(monkeypatch, routine=[])
    r = client.put("/routine/active", json={"user_id": USER_ID, "hidden": []}, headers=headers)
    assert r.status_code == 404, r.text


def test_someone_elses_routine_cannot_be_edited(monkeypatch, client, headers):
    _db(monkeypatch)
    r = client.put(
        "/routine/active",
        json={"user_id": "11111111-1111-4111-8111-111111111111", "hidden": []},
        headers=headers,
    )
    assert r.status_code == 403, r.text


def test_only_the_row_we_read_is_written_when_two_are_still_active(monkeypatch, client, headers):
    """Eski kayıtlarda birden fazla `is_active` satır kalabiliyor; düzenleme yalnız okunan satıra yazılmalı."""
    db = _db(monkeypatch)
    other = {
        "user_id": USER_ID, "is_active": True, "assessment_id": "a0",
        "created_at": "2026-01-01T06:00:00+00:00", "active_routine": [{"action": "Eski rutin", "time": "Sabah"}],
    }
    db.tables["routines"].rows.append(other)

    r = client.put("/routine/active", json={"user_id": USER_ID, "hidden": [step_key(ROUTINE[0])]}, headers=headers)
    assert r.status_code == 200, r.text
    # En yeni satır (a1) düzenlendi; eski satırın içeriği olduğu gibi kaldı.
    rows = {row["assessment_id"]: row["active_routine"] for row in db.tables["routines"].rows}
    assert [i["action"] for i in rows["a0"]] == ["Eski rutin"]
    assert any(i.get("skipped_by_user") for i in rows["a1"])


def test_absurdly_long_keys_are_dropped_instead_of_compared(monkeypatch, client, headers):
    """Gerçek bir adım kimliği kısadır; uzun değer hiçbir adıma eşleşmez, karşılaştırmaya girmez."""
    _db(monkeypatch)
    r = client.put(
        "/routine/active",
        json={"user_id": USER_ID, "hidden": ["x" * 5000, "", step_key(ROUTINE[0])]},
        headers=headers,
    )
    assert r.status_code == 200, r.text
    assert [i["action"] for i in r.json()["skipped_steps"]] == [ROUTINE[0]["action"]]


def test_a_guest_session_is_told_the_edit_cannot_be_saved(monkeypatch, client, headers):
    monkeypatch.setattr(main, "get_supabase", lambda: None)
    r = client.put("/routine/active", json={"user_id": USER_ID, "hidden": []}, headers=headers)
    assert r.status_code == 409, r.text


def test_an_empty_action_is_rejected_before_it_reaches_the_plan(monkeypatch, client, headers):
    _db(monkeypatch)
    r = client.put(
        "/routine/active",
        json={"user_id": USER_ID, "added": [{"action": "", "time": "Sabah"}]},
        headers=headers,
    )
    assert r.status_code == 422, r.text


def test_a_failed_write_is_reported_instead_of_pretending_to_save(monkeypatch, client, headers):
    db = _db(monkeypatch)
    table = db.tables["routines"]
    original = table.execute

    def execute():
        if table._op == "update":
            raise RuntimeError("yazılamadı")
        return original()

    table.execute = execute
    r = client.put("/routine/active", json={"user_id": USER_ID, "hidden": [step_key(ROUTINE[0])]}, headers=headers)
    assert r.status_code == 502, r.text


# ── check-in ile birlikte ────────────────────────────────────────────────────

def test_the_daily_checkin_does_not_wipe_the_users_own_edits(monkeypatch, client, headers):
    """Check-in rutini uyarlayıp `active_routine`'i baştan yazar; kullanıcının düzenlemesi o yazıda kaybolmamalı."""
    db = _db(monkeypatch)
    db.tables["privacy_preferences"] = type(db.tables["routines"])([
        {"user_id": USER_ID, "ai_processing_allowed": True,
         "location_processing_allowed": True, "photo_processing_allowed": True},
    ])
    db.tables["legal_consents"] = type(db.tables["routines"])([
        {"user_id": USER_ID, "document_version": main._LEGAL_CONSENT_VERSION},
    ])

    hidden_key = step_key(ROUTINE[1])
    r = client.put(
        "/routine/active",
        json={"user_id": USER_ID, "hidden": [hidden_key], "added": [{"action": "Dudak balmı", "time": "Akşam"}]},
        headers=headers,
    )
    assert r.status_code == 200, r.text

    # İrritasyon: uyarlama kesin çalışır ve rutini yeniden yazar.
    check = client.post(
        "/daily_checkin",
        json={"user_id": USER_ID, "sleep_hours": 5, "stress_today": 5,
              "skin_feeling": "irritasyon", "applied_routine": True},
        headers=headers,
    )
    assert check.status_code == 200, check.text
    # Uyarlama gerçekten çalıştı ve rutini yeniden yazdı (yoksa test boşa geçerdi).
    assert check.json()["changes"], "irritasyon check-in'i rutini değiştirmeli"
    assert db.tables["routines"].updated, "check-in active_routine'i yeniden yazmalı"

    saved = db.tables["routines"].rows[0]["active_routine"]
    actions = [i.get("action") for i in saved]
    assert "Dudak balmı" in actions, "kullanıcının kendi adımı check-in'de silinmemeli"
    dropped = [i for i in saved if i.get("skipped_by_user")]
    assert [i["action"] for i in dropped] == ["SPF 50 (geniş spektrumlu)"], "çıkarılan adım geri alınabilir kalmalı"

    # Check-in'in döndürdüğü bugünkü rutinde çıkarılan adım yok.
    assert "SPF 50 (geniş spektrumlu)" not in [i.get("action") for i in check.json()["today_routine"]]
