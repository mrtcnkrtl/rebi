"""Redis: paylaşılan zaman aşımlı istemci; kapanırsa uygulama düşmez, bellek yedeğine geçer; geri gelince döner."""

from __future__ import annotations

import logging
import threading
from pathlib import Path

import jwt
import pytest

import free_chat_quota
import main
import plus_chat_quota
import rag_service
import rate_limit
import redis_client
from redis_client import FallbackProxy

USER_ID = "55555555-5555-4555-8555-555555555555"
SECRET = "test-secret-at-least-32-bytes-long"


class FlakyRedis:
    """Redis'in INCR/DECR/EXPIRE/GET/PING + pipeline davranışı; `down=True` iken her çağrı bağlantı hatası verir."""

    def __init__(self):
        self.data: dict[str, int] = {}
        self.ttl: dict[str, int] = {}
        self.down = False
        self.pings = 0
        self._lock = threading.Lock()

    def _check(self):
        if self.down:
            raise ConnectionError("Redis kapalı")

    def incr(self, key):
        self._check()
        with self._lock:
            self.data[key] = int(self.data.get(key, 0)) + 1
            return self.data[key]

    def decr(self, key):
        self._check()
        with self._lock:
            self.data[key] = int(self.data.get(key, 0)) - 1
            return self.data[key]

    def get(self, key):
        self._check()
        value = self.data.get(key)
        return None if value is None else str(value)

    def expire(self, key, seconds):
        self._check()
        self.ttl[key] = seconds

    def ping(self):
        self._check()
        self.pings += 1
        return True

    def pipeline(self):
        outer = self

        class _Pipe:
            def __init__(self):
                self.ops = []

            def incr(self, key):
                self.ops.append(("incr", key))

            def expire(self, key, seconds):
                self.ops.append(("expire", key, seconds))

            def execute(self):
                outer._check()
                out = []
                for op, *args in self.ops:
                    out.append(getattr(outer, op)(*args))
                return out

        return _Pipe()


@pytest.fixture
def redis_env(monkeypatch):
    """REDIS_URL tanımlı; from_url sahte Redis döner; tüm Redis durumu temiz."""
    import redis

    fake = FlakyRedis()
    created: list[dict] = []

    def from_url(url, **kwargs):
        created.append({"url": url, **kwargs})
        return fake

    monkeypatch.setattr(redis, "from_url", from_url)
    monkeypatch.setenv("REDIS_URL", "redis://redis:6379/0")
    monkeypatch.delenv("REDIS_TIMEOUT_SECONDS", raising=False)
    redis_client.reset_redis()
    monkeypatch.setattr(free_chat_quota, "_backend", None)
    monkeypatch.setattr(plus_chat_quota, "_backend", None)
    yield fake, created
    redis_client.reset_redis()


# ── Paylaşılan istemci ───────────────────────────────────────────────────────────────────────────

def test_no_client_without_a_url(monkeypatch):
    monkeypatch.delenv("REDIS_URL", raising=False)
    redis_client.reset_redis()
    assert redis_client.get_redis() is None
    assert redis_client.redis_status() == "off"


def test_client_is_built_once_with_short_timeouts(redis_env):
    fake, created = redis_env

    first = redis_client.get_redis()
    assert redis_client.get_redis() is first and first is fake
    assert len(created) == 1
    opts = created[0]
    assert opts["url"] == "redis://redis:6379/0" and opts["decode_responses"] is True
    # Zaman aşımsız bir Redis çağrısı, Redis takılınca iş parçacığını sonsuza dek tutardı.
    assert opts["socket_timeout"] == 1.0 and opts["socket_connect_timeout"] == 1.0


def test_timeout_is_configurable_and_a_new_url_builds_a_new_client(redis_env, monkeypatch):
    fake, created = redis_env
    monkeypatch.setenv("REDIS_TIMEOUT_SECONDS", "2.5")
    redis_client.reset_redis()
    redis_client.get_redis()
    assert created[-1]["socket_timeout"] == 2.5

    monkeypatch.setenv("REDIS_URL", "redis://baska:6379/1")
    redis_client.get_redis()
    assert created[-1]["url"] == "redis://baska:6379/1" and len(created) == 2


def test_the_client_is_shared_across_threads(redis_env):
    fake, created = redis_env
    got: list = []
    threads = [threading.Thread(target=lambda: got.append(redis_client.get_redis())) for _ in range(16)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    assert len(created) == 1 and all(c is fake for c in got)


# ── Yedek sarmalayıcı ────────────────────────────────────────────────────────────────────────────

class _Primary:
    def __init__(self):
        self.calls = 0
        self.fail = False

    def value(self, x):
        self.calls += 1
        if self.fail:
            raise ConnectionError("kapalı")
        return f"redis:{x}"


class _Backup:
    def __init__(self):
        self.calls = 0

    def value(self, x):
        self.calls += 1
        return f"bellek:{x}"


def test_proxy_uses_the_primary_and_leaves_the_backup_alone_when_healthy():
    primary, backup = _Primary(), _Backup()
    proxy = FallbackProxy(primary, backup, "deneme")
    assert proxy.value(1) == "redis:1"
    assert backup.calls == 0


def test_proxy_falls_back_on_any_error_and_returns_when_the_primary_recovers():
    primary, backup = _Primary(), _Backup()
    proxy = FallbackProxy(primary, backup, "deneme")
    primary.fail = True
    assert proxy.value(1) == "bellek:1"
    primary.fail = False
    assert proxy.value(2) == "redis:2"


def test_proxy_logs_an_outage_once_a_minute_not_once_per_request(caplog):
    primary, backup = _Primary(), _Backup()
    primary.fail = True
    proxy = FallbackProxy(primary, backup, "deneme")
    with caplog.at_level(logging.WARNING, logger="redis_client"):
        for i in range(50):
            proxy.value(i)
    assert len([r for r in caplog.records if "bellek yedeğine" in r.getMessage()]) == 1


# ── Hız sınırlayıcı ──────────────────────────────────────────────────────────────────────────────

def test_limiter_counts_in_redis_with_one_round_trip_and_sets_an_expiry(redis_env):
    fake, _ = redis_env
    limiter = rate_limit._make_limiter(3, 60, "deneme", scale=False)

    assert [limiter.allow("ip") for _ in range(5)] == [True, True, True, False, False]
    key = next(iter(fake.data))
    assert fake.data[key] == 5 and fake.ttl[key] == 61


def test_limiter_keeps_enforcing_from_memory_while_redis_is_down_then_returns(redis_env):
    fake, _ = redis_env
    limiter = rate_limit._make_limiter(3, 60, "deneme", scale=False)
    assert [limiter.allow("ip") for _ in range(4)] == [True, True, True, False]

    fake.down = True
    # Redis yok: istek 500 vermez; süreç içi sınırlayıcı devreye girer ve sınırı uygular.
    assert [limiter.allow("baska") for _ in range(4)] == [True, True, True, False]

    fake.down = False
    assert limiter.allow("ip") is False, "Redis geri geldi: eski sayaç yeniden geçerli"


def test_every_module_level_limiter_survives_a_dead_redis(redis_env):
    fake, _ = redis_env
    fake.down = True
    limiter = rate_limit._make_limiter(2, 60, "x", scale=False)
    assert limiter.allow("ip") and limiter.allow("ip") and not limiter.allow("ip")


# ── Sohbet kotası ────────────────────────────────────────────────────────────────────────────────

def test_free_quota_lives_in_redis_when_available(redis_env, monkeypatch):
    fake, _ = redis_env
    monkeypatch.setenv("FREE_CHAT_DAILY_LIMIT", "3")

    ticket = free_chat_quota.free_chat_reserve("u")

    assert ticket is not None
    assert list(fake.data.values()) == [1] and free_chat_quota.free_chat_remaining("u") == 2
    free_chat_quota.free_chat_release("u", ticket)
    assert list(fake.data.values()) == [0]


def test_quota_keeps_working_when_redis_goes_down_mid_session(redis_env, monkeypatch):
    fake, _ = redis_env
    monkeypatch.setenv("FREE_CHAT_DAILY_LIMIT", "2")
    monkeypatch.setenv("PLUS_CHAT_MONTHLY_CAP", "10")
    assert free_chat_quota.free_chat_reserve("u") is not None

    fake.down = True
    # Kullanıcı sohbet etmeye devam eder; sayaçlar o süre süreç içindedir.
    assert free_chat_quota.free_chat_reserve("u") is not None
    assert free_chat_quota.free_chat_reserve("u") is not None
    assert free_chat_quota.free_chat_reserve("u") is None
    assert plus_chat_quota.plus_chat_reserve("p") is not None
    assert free_chat_quota.free_chat_remaining("u") == 0


def test_chat_endpoint_serves_normally_through_a_redis_outage(redis_env, monkeypatch, client):
    fake, _ = redis_env
    monkeypatch.setenv("SUPABASE_JWT_SECRET", SECRET)
    monkeypatch.delenv("API_ALLOW_INSECURE_AUTH", raising=False)
    monkeypatch.setenv("FREE_CHAT_DAILY_LIMIT", "5")
    monkeypatch.setattr(main, "get_supabase", lambda: None)
    monkeypatch.setattr(main, "_require_privacy_permission", lambda *a, **k: None)
    monkeypatch.setattr(main, "_persist_chat_turn", lambda *a, **k: None)

    async def ok(**kwargs):
        return "Cevap."

    monkeypatch.setattr(rag_service, "chat_general", ok)
    token = jwt.encode({"sub": USER_ID, "aud": "authenticated"}, SECRET, algorithm="HS256")
    headers = {"Authorization": f"Bearer {token}"}
    rate_limit.LIMIT_CHAT_ASSESSMENT._hits.clear()

    def ask():
        return client.post("/chat_general", json={"user_id": USER_ID, "message": "SPF?", "history": []}, headers=headers)

    up = ask().json()
    fake.down = True
    down = ask()
    fake.down = False
    back = ask().json()

    assert up["usage_remaining"] == 4
    assert down.status_code == 200 and down.json()["reply"] == "Cevap.", "Redis kapalıyken sohbet düşmemeli"
    assert back["usage_remaining"] == 3, "Redis geri gelince Redis'teki sayaç (yalnızca bellekteki ek turlar hariç) sürer"
    rate_limit.LIMIT_CHAT_ASSESSMENT._hits.clear()


# ── Sağlık ───────────────────────────────────────────────────────────────────────────────────────

def test_status_reports_ok_down_and_caches_between_probes(redis_env, monkeypatch):
    fake, _ = redis_env
    clock = [100.0]
    monkeypatch.setattr(redis_client.time, "monotonic", lambda: clock[0])
    redis_client.reset_redis()

    assert redis_client.redis_status() == "ok" and fake.pings == 1
    clock[0] += 5
    redis_client.redis_status()
    assert fake.pings == 1, "10 sn içinde yeniden yoklanmaz (sağlık yoklaması Redis'i dövmesin)"

    fake.down = True
    assert redis_client.redis_status() == "ok", "önbellekteki değer"
    clock[0] += 11
    assert redis_client.redis_status() == "down"
    fake.down = False
    clock[0] += 11
    assert redis_client.redis_status() == "ok"


def test_health_reports_the_redis_state_and_stays_200_when_it_is_down(redis_env, client):
    fake, _ = redis_env
    assert client.get("/health").json()["redis"] == "ok"

    fake.down = True
    redis_client.reset_redis()
    r = client.get("/health")
    assert r.status_code == 200 and r.json()["redis"] == "down", "Redis yardımcıdır: kapalıyken sağlık 503 olmaz"


def test_health_says_off_when_redis_is_not_configured(monkeypatch, client):
    monkeypatch.delenv("REDIS_URL", raising=False)
    redis_client.reset_redis()
    assert client.get("/health").json()["redis"] == "off"


# ── Dağıtım ──────────────────────────────────────────────────────────────────────────────────────

def test_compose_runs_a_private_persistent_redis_and_points_the_api_at_it():
    text = (Path(__file__).resolve().parents[2] / "docker-compose.yml").read_text(encoding="utf-8")
    redis_block = text.split("\n  redis:\n", 1)[1].split("\n  web:\n", 1)[0]

    assert "image: redis:7" in redis_block
    assert "--appendonly" in redis_block and "redis-data:/data" in redis_block, "yeniden başlatmada sayaçlar korunur"
    assert "ports:" not in redis_block, "Redis dışarı açılmamalı"
    assert "REDIS_URL: redis://redis:6379/0" in text
    assert "\nvolumes:\n  redis-data:" in text
