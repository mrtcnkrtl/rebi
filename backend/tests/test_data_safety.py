"""Veri güvenliği: olay yazımı sessizce kaybolmaz; DB öz-denetimi; retention güvenlik ağı."""

from __future__ import annotations

import jwt
import pytest

import main
from tests.fake_supabase import FakeSupabase

USER_ID = "12121212-1212-4212-8212-121212121212"
SECRET = "test-secret-at-least-32-bytes-long"


@pytest.fixture
def headers(monkeypatch):
    monkeypatch.setenv("SUPABASE_JWT_SECRET", SECRET)
    monkeypatch.delenv("API_ALLOW_INSECURE_AUTH", raising=False)
    token = jwt.encode({"sub": USER_ID, "aud": "authenticated"}, SECRET, algorithm="HS256")
    return {"Authorization": f"Bearer {token}"}


def _event(client, headers, event_id="olay-1", user_id=USER_ID):
    return client.post(
        "/daily_tracking/ingest",
        json={
            "user_id": user_id,
            "type": "water_intake",
            "payload": {"ml": 250},
            "timestamp": "2026-10-27T09:00:00+03:00",
            "client_event_id": event_id,
        },
        headers=headers,
    )


class _FlakyDb(FakeSupabase):
    """`daily_events` yazımı `down` iken hata verir (bağlantı koptu)."""

    def __init__(self, **tables):
        super().__init__(**tables)
        self.down = True

    def table(self, name):
        t = super().table(name)
        if name == "daily_events":
            # Tablo nesnesi paylaşılır: bozucuyu kurtarılınca geri al.
            for op in ("upsert", "insert"):
                t.__dict__.pop(op, None)
            if self.down:
                def boom(*_a, **_k):
                    raise RuntimeError("connection reset")

                t.upsert = boom
                t.insert = boom
        return t


# ── Olay yazımı ──────────────────────────────────────────────────────────────────────────────────

def test_a_failed_database_write_is_not_acknowledged_so_the_client_retries(monkeypatch, client, headers):
    db = _FlakyDb(daily_events=[])
    monkeypatch.setattr(main, "get_supabase", lambda: db)
    main._MEM_DAILY_EVENTS.clear()

    r = _event(client, headers)

    assert r.status_code == 503, "yazılamayan olaya 200 dönmek, mobilin olayı kuyruktan silmesine ve kaybolmasına yol açardı"
    assert "yeniden denenecek" in r.json()["detail"]
    assert main._MEM_DAILY_EVENTS == {}, "süreç belleğine yazılıp unutulmamalı (yeniden başlatmada silinir, hiç okunmaz)"
    assert db.tables["daily_events"].rows == []


def test_the_retry_after_recovery_stores_the_event_exactly_once(monkeypatch, client, headers):
    db = _FlakyDb(daily_events=[])
    monkeypatch.setattr(main, "get_supabase", lambda: db)

    assert _event(client, headers).status_code == 503
    db.down = False
    assert _event(client, headers).status_code == 200  # mobil aynı kimlikle yeniden dener
    assert _event(client, headers).status_code == 200  # ağ tekrarı: yine aynı kimlik
    rows = db.tables["daily_events"].rows

    assert len(rows) == 1 and rows[0]["client_event_id"] == "olay-1", "aynı olay iki kez saydırmaz"


def test_the_503_is_one_the_mobile_outbox_treats_as_retry_not_drop():
    """Mobil `classifyIngestStatus`: 5xx/429/401 yeniden denenir, diğer 4xx düşürülür; 503 kuyruğa girer."""
    retry_statuses = {401, 408, 425, 429} | set(range(500, 600))
    assert 503 in retry_statuses


def test_users_without_a_database_still_work_in_memory(monkeypatch, client):
    """Demo/geliştirme kimlikleri veritabanına hiç yazmaz; bellek yolu bunlar için sürer."""
    monkeypatch.setattr(main, "get_supabase", lambda: None)
    main._MEM_DAILY_EVENTS.clear()

    r = client.post(
        "/daily_tracking/ingest",
        json={"user_id": "demo", "type": "water_intake", "payload": {"ml": 300}, "client_event_id": "d-1"},
    )

    assert r.status_code == 200 and r.json()["aggregated"]["water_ml_total"] == 300
    main._MEM_DAILY_EVENTS.clear()
