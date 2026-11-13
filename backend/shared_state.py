"""
İşçiler (uvicorn --workers) arasında paylaşılan küçük durum: push dağıtıcısının imleci, son tur özeti ve
"aynı anda tek tur" kilidi.

API birden fazla süreçle çalıştığında süreç belleğindeki bir sözlük yalnızca o süreçte görünür: cron'un isteği
hangi işçiye düşerse imleç orada kalır, /health başka işçiden bakınca dağıtıcıyı "çalışmıyor" görür. REDIS_URL
tanımlıysa değerler Redis'te tutulur; yoksa ya da Redis o an erişilemezse süreç belleğine düşülür (tek işçide
eskisiyle aynı davranış). Redis yardımcıdır: okunamazsa çağıran asla hata görmez.
"""

from __future__ import annotations

import json
import threading
import time
import uuid
from contextlib import contextmanager
from typing import Any, Iterator, Optional

from config import get_logger
from redis_client import get_redis, redis_url

log = get_logger("shared_state")

_PREFIX = "rebi:state:"
_LOG_EVERY_SECONDS = 60.0
_last_log = 0.0


def _note(error: Exception, what: str) -> None:
    global _last_log
    now = time.monotonic()
    if now - _last_log >= _LOG_EVERY_SECONDS:
        _last_log = now
        log.warning("Paylaşılan durum Redis'e yazılamadı/okunamadı (%s), süreç belleği kullanılıyor: %s", what, type(error).__name__)


def _client():
    return get_redis() if redis_url() else None


def get_json(name: str, local: dict) -> Any:
    """
    `name` anahtarının değeri. Redis yoksa/okunamazsa `local` (süreç içi yedek) sözlüğünün içeriği döner.
    Redis'te değer hiç yazılmamışsa da yerel yedek döner (Redis sonradan açıldığında ilk okuma boş kalmasın).
    """
    r = _client()
    if r is not None:
        try:
            raw = r.get(_PREFIX + name)
            if raw is not None:
                return json.loads(raw)
        except Exception as e:  # Redis kapalı / bozuk değer
            _note(e, name)
    return dict(local)


def set_json(name: str, value: dict, local: dict, ttl_seconds: Optional[int] = None) -> None:
    """Değeri hem süreç içi yedeğe hem (varsa) Redis'e yazar. Yerel sözlük `update` ile güncellenir:
    başka iş parçacığı okurken bir an boş görünmez."""
    for key in [k for k in local if k not in value]:
        local.pop(key, None)
    local.update(value)
    r = _client()
    if r is None:
        return
    try:
        payload = json.dumps(value, ensure_ascii=False, default=str)
        if ttl_seconds:
            r.set(_PREFIX + name, payload, ex=int(ttl_seconds))
        else:
            r.set(_PREFIX + name, payload)
    except Exception as e:
        _note(e, name)


# ── Tek tur kilidi ───────────────────────────────────────────────────────────────────────────────

_local_locks: dict[str, threading.Lock] = {}
_local_locks_guard = threading.Lock()

# Yalnızca sahibi kilidi bırakabilsin: süresi dolup başkası almış bir kilidi geç biten tur silmesin.
_RELEASE_SCRIPT = """
if redis.call('get', KEYS[1]) == ARGV[1] then
  return redis.call('del', KEYS[1])
end
return 0
"""


def _local_lock(name: str) -> threading.Lock:
    with _local_locks_guard:
        lock = _local_locks.get(name)
        if lock is None:
            lock = _local_locks[name] = threading.Lock()
        return lock


@contextmanager
def single_run(name: str, ttl_seconds: int) -> Iterator[bool]:
    """
    `with single_run("push_dispatch", 300) as acquired:` — aynı anda yalnızca bir süreç/iş parçacığı `acquired=True`
    alır. Redis varsa süreçler arası (SET NX EX; çöken bir tur kilidi en geç `ttl_seconds` sonra bırakır),
    yoksa süreç içi. Redis o an erişilemezse süreç içi kilide düşülür: tur çalışır, hiçbir zaman kilitli kalmaz.
    """
    local = _local_lock(name)
    if not local.acquire(blocking=False):
        yield False
        return
    token = uuid.uuid4().hex
    r = _client()
    held_remote = False
    try:
        if r is not None:
            try:
                if not r.set(_PREFIX + "lock:" + name, token, nx=True, ex=max(1, int(ttl_seconds))):
                    yield False
                    return
                held_remote = True
            except Exception as e:
                _note(e, "lock:" + name)
        yield True
    finally:
        if held_remote:
            try:
                r.eval(_RELEASE_SCRIPT, 1, _PREFIX + "lock:" + name, token)
            except Exception as e:
                _note(e, "unlock:" + name)
        local.release()
