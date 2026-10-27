"""Canlı DB öz-denetimi: eksik indeks/fonksiyon/retention cron'u görünür olur; sağlık yoklaması asla beklemez."""

from __future__ import annotations

import logging
import threading
import time
from contextlib import contextmanager

import pytest

import db_integrity
import main

_PUSH_UNIQUE = (
    "CREATE UNIQUE INDEX push_sends_user_id_reminder_id_log_date_slot_key ON public.push_sends "
    "USING btree (user_id, reminder_id, log_date, slot)"
)


def _healthy_indexes() -> dict[str, str]:
    names = list(db_integrity.CRITICAL_INDEXES) + list(db_integrity.PERFORMANCE_INDEXES)
    out = {n: f"CREATE INDEX {n} ON public.t USING btree (x)" for n in names}
    out["push_sends_user_id_reminder_id_log_date_slot_key"] = _PUSH_UNIQUE
    return out


class _Cursor:
    def __init__(self, indexes, functions, cron):
        self.indexes, self.functions, self.cron = indexes, functions, cron
        self.last = ""

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False

    def execute(self, sql, params=None, prepare=None):
        self.last = sql
        if "cron.job" in sql and self.cron == "boom":
            raise RuntimeError("permission denied for table job")

    def fetchall(self):
        if "pg_indexes" in self.last:
            return list(self.indexes.items())
        return [(f,) for f in self.functions]

    def fetchone(self):
        if "to_regclass" in self.last:
            return (self.cron != "no_extension",)
        return (1 if self.cron == "job" else 0,)


def _fake_db(monkeypatch, indexes=None, functions=None, cron="job", calls=None):
    indexes = _healthy_indexes() if indexes is None else indexes
    functions = set(db_integrity.CRITICAL_FUNCTIONS) if functions is None else functions

    @contextmanager
    def pg_conn(autocommit=True):
        if calls is not None:
            calls.append(1)

        class _Conn:
            def cursor(self):
                return _Cursor(indexes, functions, cron)

        yield _Conn()

    import knowledge.db

    monkeypatch.setattr(knowledge.db, "pg_conn", pg_conn)
    db_integrity.reset_cache()


@pytest.fixture(autouse=True)
def _clean_cache():
    db_integrity.reset_cache()
    yield
    db_integrity.reset_cache()


def test_a_complete_database_is_ok_with_an_active_retention_job(monkeypatch):
    _fake_db(monkeypatch)
    r = db_integrity.inspect_integrity()
    assert r["status"] == "ok" and r["retention"] == "pg_cron"
    assert r["missing_critical"] == [] and r["missing_performance"] == []


def test_missing_critical_pieces_are_degraded_and_named(monkeypatch):
    indexes = _healthy_indexes()
    del indexes["daily_events_user_client_event_idx"]
    _fake_db(monkeypatch, indexes=indexes)
    r = db_integrity.inspect_integrity()
    assert r["status"] == "degraded"
    assert any("daily_events_user_client_event_idx" in m for m in r["missing_critical"])

    indexes = _healthy_indexes()
    del indexes["push_sends_user_id_reminder_id_log_date_slot_key"]
    _fake_db(monkeypatch, indexes=indexes)
    r = db_integrity.inspect_integrity()
    assert r["status"] == "degraded" and any("push_sends" in m for m in r["missing_critical"])

    _fake_db(monkeypatch, functions={"match_knowledge_chunks"})
    r = db_integrity.inspect_integrity()
    assert r["status"] == "degraded" and any("purge_expired_rebi_data" in m for m in r["missing_critical"])


def test_a_non_unique_push_sends_index_does_not_count(monkeypatch):
    indexes = _healthy_indexes()
    indexes["push_sends_user_id_reminder_id_log_date_slot_key"] = _PUSH_UNIQUE.replace("UNIQUE ", "")
    _fake_db(monkeypatch, indexes=indexes)
    assert db_integrity.inspect_integrity()["status"] == "degraded"


def test_only_performance_indexes_missing_is_slow_not_degraded(monkeypatch):
    indexes = _healthy_indexes()
    del indexes["daily_events_user_type_time_idx"]
    _fake_db(monkeypatch, indexes=indexes)
    r = db_integrity.inspect_integrity()
    assert r["status"] == "slow" and r["missing_performance"] == ["daily_events_user_type_time_idx"]


@pytest.mark.parametrize(
    ("cron", "expected"),
    [("job", "pg_cron"), ("no_job", "no_cron_job"), ("no_extension", "no_pg_cron"), ("boom", "unknown")],
)
def test_retention_state_is_reported_without_affecting_the_schema_verdict(monkeypatch, cron, expected):
    _fake_db(monkeypatch, cron=cron)
    r = db_integrity.inspect_integrity()
    assert r["retention"] == expected
    assert r["status"] == "ok"


def test_an_unreachable_database_is_unknown_and_never_raises(monkeypatch):
    import knowledge.db

    @contextmanager
    def down(autocommit=True):
        raise RuntimeError("SUPABASE_DATABASE_URL tanımlı değil")
        yield

    monkeypatch.setattr(knowledge.db, "pg_conn", down)
    r = db_integrity.inspect_integrity()
    assert r["status"] == "unknown" and r["reason"] == "RuntimeError"


def test_results_are_cached_and_problems_are_logged_with_names(monkeypatch, caplog):
    indexes = _healthy_indexes()
    del indexes["daily_events_user_client_event_idx"]
    calls: list = []
    _fake_db(monkeypatch, indexes=indexes, cron="no_extension", calls=calls)

    with caplog.at_level(logging.WARNING, logger="db_integrity"):
        first = db_integrity.get_integrity()
        second = db_integrity.get_integrity()
        forced = db_integrity.get_integrity(force=True)

    assert first == second == forced and len(calls) == 2, "10 dk içinde yeniden sorgulanmaz; force yeniler"
    text = " ".join(r.getMessage() for r in caplog.records)
    assert "daily_events_user_client_event_idx" in text and "Retention temizliği zamanlanmamış" in text


def test_the_public_summary_hides_index_and_function_names(monkeypatch):
    indexes = _healthy_indexes()
    del indexes["daily_events_user_client_event_idx"]
    _fake_db(monkeypatch, indexes=indexes)
    summary = db_integrity.public_summary(db_integrity.inspect_integrity())
    assert summary == {"status": "degraded", "retention": "pg_cron", "missing_critical": 1, "missing_performance": 0}


def test_health_includes_the_summary_and_stays_200_when_the_database_is_degraded(monkeypatch, client):
    indexes = _healthy_indexes()
    del indexes["daily_events_user_client_event_idx"]
    _fake_db(monkeypatch, indexes=indexes)
    db_integrity.get_integrity(force=True)

    r = client.get("/health")

    assert r.status_code == 200
    assert r.json()["db_integrity"]["status"] == "degraded"
    assert "daily_events_user_client_event_idx" not in r.text


def test_health_never_waits_for_a_slow_database(monkeypatch, client):
    """Veritabanı yavaşken sağlık yoklaması beklerse Docker sağlık denetimi zaman aşımına düşer."""
    import knowledge.db

    @contextmanager
    def hanging(autocommit=True):
        time.sleep(1.5)
        raise RuntimeError("zaman aşımı")
        yield

    monkeypatch.setattr(knowledge.db, "pg_conn", hanging)
    db_integrity.reset_cache()

    started = time.perf_counter()
    r = client.get("/health")
    elapsed = time.perf_counter() - started

    assert r.status_code == 200 and elapsed < 1.0, f"sağlık DB'yi bekledi: {elapsed:.2f}s"
    assert r.json()["db_integrity"]["status"] == "unknown" and r.json()["db_integrity"]["pending"] is True
    time.sleep(1.8)  # arka plan iş parçacığı bitsin


def test_background_refresh_is_single_flight_and_fills_the_cache(monkeypatch):
    gate = threading.Event()
    runs: list = []

    def slow_inspect():
        runs.append(1)
        gate.wait(2)
        return {"status": "ok", "retention": "pg_cron", "missing_critical": [], "missing_performance": []}

    monkeypatch.setattr(db_integrity, "inspect_integrity", slow_inspect)
    db_integrity.reset_cache()

    for _ in range(5):
        db_integrity.refresh_in_background()
    time.sleep(0.1)
    gate.set()
    for _ in range(50):
        if db_integrity._cache["value"] is not None:
            break
        time.sleep(0.05)

    assert len(runs) == 1, "aynı anda tek yenileme"
    assert db_integrity.summary_nowait()["status"] == "ok"


def test_startup_triggers_a_check_and_survives_its_failure(monkeypatch):
    seen: list = []
    monkeypatch.setattr(main, "_refresh_db_integrity", lambda force=False: seen.append(force))
    main._bootstrap_database_schema()
    assert seen == [True]

    def explode(force=False):
        raise RuntimeError("beklenmeyen")

    monkeypatch.setattr(main, "_refresh_db_integrity", explode)
    main._bootstrap_database_schema()  # açılış düşmemeli
