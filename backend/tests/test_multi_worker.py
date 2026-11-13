"""
Çok işçili çalışma (uvicorn --workers): işçiler arası paylaşılan durum ve tek seferlik işler.

- Push imleci ve son tur özeti Redis'te: cron isteği hangi işçiye düşerse düşsün tur kaldığı yerden sürer,
  /health başka işçiden bakınca da son turu görür.
- Aynı anda iki dağıtım turu çalışmaz (ikinci çağrı `already_running` döner).
- Açılıştaki migration'ları tek işçi uygular (Postgres danışma kilidi).
- Redis kapalıyken hiçbiri hata vermez; süreç içi yedeğe düşer.
"""

from __future__ import annotations

import threading
import time

import pytest
from fastapi.testclient import TestClient

import db_bootstrap
import main
import rate_limit
import redis_client
import shared_state
from fake_supabase import FakeSupabase

DISPATCH_SECRET = "test-dispatch-secret"


class SharedRedis:
    """İki işçinin göreceği ortak Redis: GET/SET (NX/EX) + sahibine göre silen EVAL."""

    def __init__(self):
        self.data: dict[str, str] = {}
        self.ttl: dict[str, int] = {}
        self.down = False
        self._lock = threading.Lock()

    def _check(self):
        if self.down:
            raise ConnectionError("Redis kapalı")

    def get(self, key):
        self._check()
        return self.data.get(key)

    def set(self, key, value, ex=None, nx=False):
        self._check()
        with self._lock:
            if nx and key in self.data:
                return None
            self.data[key] = value
            if ex:
                self.ttl[key] = ex
            return True

    def eval(self, script, numkeys, key, token):
        self._check()
        with self._lock:
            if self.data.get(key) == token:
                del self.data[key]
                return 1
            return 0


@pytest.fixture
def shared(monkeypatch):
    fake = SharedRedis()
    monkeypatch.setenv("REDIS_URL", "redis://fake:6379/0")
    monkeypatch.setattr(shared_state, "get_redis", lambda: fake)
    yield fake
    redis_client.reset_redis()


# ── shared_state ────────────────────────────────────────────────────────────────────────────────


def test_value_written_by_one_worker_is_read_by_another(shared):
    worker_a, worker_b = {}, {}  # her işçinin kendi süreç içi yedeği
    shared_state.set_json("push_cursor", {"after": "u-42"}, worker_a)
    assert shared_state.get_json("push_cursor", worker_b) == {"after": "u-42"}
    assert worker_b == {}, "öteki işçinin belleği değişmez; değer Redis'ten gelir"


def test_redis_down_falls_back_to_process_memory(shared):
    local = {}
    shared.down = True
    shared_state.set_json("push_last_run", {"at": "x"}, local)
    assert shared_state.get_json("push_last_run", local) == {"at": "x"}


def test_without_redis_url_state_is_process_local(monkeypatch):
    monkeypatch.delenv("REDIS_URL", raising=False)
    local = {}
    shared_state.set_json("k", {"a": 1}, local)
    assert shared_state.get_json("k", {}) == {}
    assert shared_state.get_json("k", local) == {"a": 1}


def test_set_json_replaces_old_keys_in_local_copy(monkeypatch):
    monkeypatch.delenv("REDIS_URL", raising=False)
    local = {"old": 1, "after": "u-1"}
    shared_state.set_json("k", {"after": None}, local)
    assert local == {"after": None}


def test_single_run_is_exclusive_across_workers(shared):
    with shared_state.single_run("job", 60) as first:
        assert first is True
        # Başka bir işçi: süreç içi kilidi ayrı, Redis kilidi ortak. Aynı süreçte bunu taklit etmek için süreç
        # içi kilidi atlayıp yalnızca Redis kilidini dener.
        assert shared.set("rebi:state:lock:job", "other", nx=True, ex=60) is None
    assert "rebi:state:lock:job" not in shared.data, "tur bitince kilit bırakılır"


def test_single_run_rejects_second_holder_in_same_process(shared):
    with shared_state.single_run("job", 60) as first:
        with shared_state.single_run("job", 60) as second:
            assert first is True and second is False


def test_single_run_does_not_release_someone_elses_lock(shared):
    with shared_state.single_run("job", 60) as acquired:
        assert acquired
        # Kilit süresi doldu ve başka bir işçi aldı.
        shared.data["rebi:state:lock:job"] = "other-worker"
    assert shared.data["rebi:state:lock:job"] == "other-worker"


def test_single_run_works_when_redis_is_down(shared):
    shared.down = True
    with shared_state.single_run("job", 60) as acquired:
        assert acquired is True, "Redis kapalıyken iş durmaz, süreç içi kilitle çalışır"


def test_lock_held_elsewhere_means_skip(shared):
    shared.data["rebi:state:lock:job"] = "other-worker"
    with shared_state.single_run("job", 60) as acquired:
        assert acquired is False
    assert shared.data["rebi:state:lock:job"] == "other-worker"


# ── push dağıtıcısı çok işçide ───────────────────────────────────────────────────────────────────


@pytest.fixture
def client():
    return TestClient(main.app)


@pytest.fixture
def push_env(monkeypatch, shared):
    monkeypatch.setenv("PUSH_DISPATCH_SECRET", DISPATCH_SECRET)
    monkeypatch.setattr(main, "push_configured", lambda: True)
    db = FakeSupabase(device_tokens=[], push_sends=[], daily_events=[], daily_logs=[], reminder_settings=[])
    monkeypatch.setattr(main, "get_supabase", lambda: db)
    main._PUSH_CURSOR["after"] = None
    main._PUSH_LAST_RUN.clear()
    rate_limit.LIMIT_PUSH_DISPATCH._hits.clear()
    yield shared
    main._PUSH_CURSOR["after"] = None
    main._PUSH_LAST_RUN.clear()
    rate_limit.LIMIT_PUSH_DISPATCH._hits.clear()


def _dispatch(client):
    return client.post("/push/dispatch", headers={"X-Push-Dispatch-Token": DISPATCH_SECRET})


def test_second_concurrent_dispatch_is_skipped(client, push_env):
    push_env.data["rebi:state:lock:push_dispatch"] = "another-worker"
    res = _dispatch(client)
    assert res.status_code == 200
    body = res.json()
    assert body["already_running"] is True
    assert body["users_considered"] == 0


def test_dispatch_lock_is_released_after_round(client, push_env):
    res = _dispatch(client)
    assert res.status_code == 200
    assert res.json()["already_running"] is False
    assert "rebi:state:lock:push_dispatch" not in push_env.data


def test_last_run_is_visible_from_another_worker(client, push_env):
    _dispatch(client)
    # Başka bir işçinin belleği boş: /health özeti Redis'ten okur.
    main._PUSH_LAST_RUN.clear()
    last = client.get("/health").json()["push_dispatch"]
    assert last and last["at"]
    assert main._dispatch_alive() is True


def test_cursor_left_by_one_worker_is_resumed_by_another(client, push_env, monkeypatch):
    seen = []

    def fake_page(supabase, after, max_users):
        seen.append(after)
        return {}, None, True

    monkeypatch.setattr(main, "_load_push_page", fake_page)
    push_env.data["rebi:state:push_cursor"] = '{"after": "user-0099"}'
    main._PUSH_CURSOR["after"] = None  # bu işçi imleci hiç görmedi
    _dispatch(client)
    assert seen == ["user-0099"]
    assert push_env.data["rebi:state:push_cursor"] == '{"after": null}', "tur bitti: sıradaki baştan başlar"


# ── migration kilidi ────────────────────────────────────────────────────────────────────────────


class _LockCursor:
    def __init__(self, free_after: int):
        self.calls = 0
        self.free_after = free_after

    def execute(self, sql, params=None):
        assert "pg_try_advisory_lock" in sql
        assert params == (db_bootstrap.MIGRATION_LOCK_KEY,)
        self.calls += 1

    def fetchone(self):
        return (self.calls > self.free_after,)


def test_migration_lock_waits_for_other_worker():
    cur = _LockCursor(free_after=3)
    sleeps = []
    assert db_bootstrap._acquire_migration_lock(cur, wait_seconds=30, sleep=sleeps.append) is True
    assert cur.calls == 4 and len(sleeps) == 3


def test_migration_lock_gives_up_after_wait():
    cur = _LockCursor(free_after=10**9)
    start = time.monotonic()
    assert db_bootstrap._acquire_migration_lock(cur, wait_seconds=0, sleep=lambda s: None) is False
    assert time.monotonic() - start < 1


def test_dockerfile_runs_multiple_workers():
    from pathlib import Path

    text = (Path(__file__).resolve().parents[1] / "Dockerfile").read_text(encoding="utf-8")
    assert "--workers ${WEB_CONCURRENCY:-2}" in text
    # nginx upstream keepalive (60 sn) kapanmış bağlantıya yazmasın diye uvicorn'unki daha uzun olmalı.
    assert "--timeout-keep-alive 75" in text
