"""Retention güvenlik ağı: pg_cron yoksa günlük temizlik (yalnızca açıkça istenirse); pg_cron aktifse asla çift işlem."""

from __future__ import annotations

import calendar
import io
import json
import time

import pytest

import db_integrity
import main
import push_cron
from tests.fake_supabase import FakeSupabase

SECRET = "dispatch-secret-abcdefghijklmnop"
HEADERS = {"X-Push-Dispatch-Token": SECRET}
PURGE_RESULT = {"daily_events": 12, "chat_history": 3}


@pytest.fixture
def db(monkeypatch):
    monkeypatch.setenv("PUSH_DISPATCH_SECRET", SECRET)
    fake = FakeSupabase()
    fake.rpc_handlers["purge_expired_rebi_data"] = lambda params: PURGE_RESULT
    monkeypatch.setattr(main, "get_supabase", lambda: fake)
    return fake


def _retention(monkeypatch, state: str):
    monkeypatch.setattr(main, "get_integrity", lambda force=False: {"retention": state})


# ── Uç ───────────────────────────────────────────────────────────────────────────────────────────

def test_the_endpoint_is_closed_without_the_secret(monkeypatch, client):
    monkeypatch.delenv("PUSH_DISPATCH_SECRET", raising=False)
    assert client.post("/maintenance/purge").status_code == 503


def test_the_endpoint_rejects_a_wrong_secret_and_deletes_nothing(db, client):
    r = client.post("/maintenance/purge", headers={"X-Push-Dispatch-Token": "yanlis"})
    assert r.status_code == 401 and db.rpc_calls == []


def test_without_pg_cron_the_purge_runs(db, client, monkeypatch):
    _retention(monkeypatch, "no_pg_cron")
    r = client.post("/maintenance/purge", headers=HEADERS)
    assert r.status_code == 200 and r.json() == {"ok": True, "deleted": PURGE_RESULT}
    assert db.rpc_calls == ["purge_expired_rebi_data"]


def test_an_active_pg_cron_job_makes_the_endpoint_do_nothing(db, client, monkeypatch):
    """Çift temizlik olmaz: iş zaten günlük çalışıyor."""
    _retention(monkeypatch, "pg_cron")
    r = client.post("/maintenance/purge", headers=HEADERS)
    assert r.json() == {"ok": True, "skipped": "pg_cron_active"} and db.rpc_calls == []


def test_the_check_can_be_overridden_for_a_deliberate_manual_run(db, client, monkeypatch):
    _retention(monkeypatch, "pg_cron")
    r = client.post("/maintenance/purge", params={"only_if_no_cron": "false"}, headers=HEADERS)
    assert r.json()["deleted"] == PURGE_RESULT and db.rpc_calls == ["purge_expired_rebi_data"]


@pytest.mark.parametrize("state", ["no_cron_job", "unknown"])
def test_when_pg_cron_cannot_be_confirmed_the_purge_still_runs(db, client, monkeypatch, state):
    _retention(monkeypatch, state)
    assert client.post("/maintenance/purge", headers=HEADERS).json()["deleted"] == PURGE_RESULT


def test_a_failing_integrity_check_does_not_block_the_purge(db, client, monkeypatch):
    def explode(force=False):
        raise RuntimeError("okunamadı")

    monkeypatch.setattr(main, "get_integrity", explode)
    assert client.post("/maintenance/purge", headers=HEADERS).status_code == 200


def test_a_failing_purge_is_a_502_not_a_crash(db, client, monkeypatch):
    _retention(monkeypatch, "no_pg_cron")

    def boom(params):
        raise RuntimeError("canceling statement due to statement timeout")

    db.rpc_handlers["purge_expired_rebi_data"] = boom

    r = client.post("/maintenance/purge", headers=HEADERS)

    assert r.status_code == 502 and "çalıştırılamadı" in r.json()["detail"]


def test_the_endpoint_needs_a_database(monkeypatch, client):
    monkeypatch.setenv("PUSH_DISPATCH_SECRET", SECRET)
    monkeypatch.setattr(main, "get_supabase", lambda: None)
    assert client.post("/maintenance/purge", headers=HEADERS).status_code == 503


# ── push-cron tetikleyicisi ──────────────────────────────────────────────────────────────────────

def _utc(day: str, hhmm: str) -> float:
    return calendar.timegm(time.strptime(f"{day} {hhmm}", "%Y-%m-%d %H:%M"))


class _Resp(io.BytesIO):
    def __enter__(self):
        return self

    def __exit__(self, *_):
        return False


def _opener(calls, payload=None, error=None):
    def open_(request, timeout):
        calls.append(request)
        if error is not None:
            raise error
        return _Resp(json.dumps(payload or {"ok": True, "deleted": PURGE_RESULT}).encode("utf-8"))

    return open_


URL = "http://api:8000/push/dispatch?max_users=20000"


def test_it_is_off_by_default(monkeypatch):
    monkeypatch.delenv("RETENTION_PURGE_DAILY", raising=False)
    calls: list = []
    assert push_cron.maybe_purge(_utc("2026-10-27", "04:00"), URL, "k", {}, _opener(calls)) is False
    assert calls == []


@pytest.mark.parametrize("value", ["0", "false", "", "hayir"])
def test_only_explicit_opt_in_values_enable_it(monkeypatch, value):
    monkeypatch.setenv("RETENTION_PURGE_DAILY", value)
    assert push_cron.purge_enabled() is False


def test_the_purge_url_is_derived_from_the_dispatch_url(monkeypatch):
    monkeypatch.delenv("RETENTION_PURGE_URL", raising=False)
    assert push_cron.purge_url(URL) == "http://api:8000/maintenance/purge?only_if_no_cron=1"
    monkeypatch.setenv("RETENTION_PURGE_URL", "http://baska:9000/x")
    assert push_cron.purge_url(URL) == "http://baska:9000/x"


def test_it_waits_for_the_pg_cron_hour_then_runs_once_a_day(monkeypatch):
    monkeypatch.setenv("RETENTION_PURGE_DAILY", "1")
    monkeypatch.delenv("RETENTION_PURGE_URL", raising=False)
    calls: list = []
    state: dict = {}

    assert push_cron.maybe_purge(_utc("2026-10-27", "03:15"), URL, "k", state, _opener(calls)) is False, "03:20'den önce"
    assert push_cron.maybe_purge(_utc("2026-10-27", "03:20"), URL, "k", state, _opener(calls)) is True
    assert push_cron.maybe_purge(_utc("2026-10-27", "03:25"), URL, "k", state, _opener(calls)) is False, "bugün bitti"
    assert push_cron.maybe_purge(_utc("2026-10-27", "23:55"), URL, "k", state, _opener(calls)) is False
    assert push_cron.maybe_purge(_utc("2026-10-28", "03:20"), URL, "k", state, _opener(calls)) is True

    assert len(calls) == 2
    request = calls[0]
    assert request.get_method() == "POST" and request.get_header("X-push-dispatch-token") == "k"
    assert request.full_url == "http://api:8000/maintenance/purge?only_if_no_cron=1"


def test_a_failed_attempt_is_retried_after_thirty_minutes_not_every_tick(monkeypatch):
    monkeypatch.setenv("RETENTION_PURGE_DAILY", "1")
    calls: list = []
    state: dict = {}

    assert push_cron.maybe_purge(_utc("2026-10-27", "04:00"), URL, "k", state, _opener(calls, error=OSError("ağ yok"))) is True
    assert push_cron.maybe_purge(_utc("2026-10-27", "04:05"), URL, "k", state, _opener(calls)) is False
    assert push_cron.maybe_purge(_utc("2026-10-27", "04:25"), URL, "k", state, _opener(calls)) is False
    assert push_cron.maybe_purge(_utc("2026-10-27", "04:30"), URL, "k", state, _opener(calls)) is True
    assert push_cron.maybe_purge(_utc("2026-10-27", "04:35"), URL, "k", state, _opener(calls)) is False, "başarıdan sonra bugün bitti"
    assert state["done_day"] == "2026-10-27"


def test_a_server_side_skip_counts_as_done_for_the_day(monkeypatch):
    monkeypatch.setenv("RETENTION_PURGE_DAILY", "1")
    calls: list = []
    state: dict = {}
    skipped = {"ok": True, "skipped": "pg_cron_active"}
    assert push_cron.maybe_purge(_utc("2026-10-27", "05:00"), URL, "k", state, _opener(calls, payload=skipped)) is True
    assert push_cron.maybe_purge(_utc("2026-10-27", "05:35"), URL, "k", state, _opener(calls)) is False
    assert len(calls) == 1


def test_a_rejected_response_is_not_marked_done(monkeypatch):
    monkeypatch.setenv("RETENTION_PURGE_DAILY", "1")
    state: dict = {}
    calls: list = []
    assert push_cron.maybe_purge(_utc("2026-10-27", "06:00"), URL, "k", state, _opener(calls, payload={"detail": "x"})) is True
    assert "done_day" not in state
