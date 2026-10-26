"""
Olay döngüsü ↔ iş parçacığı köprüsü.

Uç noktalar düz `def`: FastAPI bunları iş parçacığı havuzunda çalıştırır; senkron Supabase / Redis / Postgres
çağrıları (onlarca ms ile saniyeler arası) böylece olay döngüsünü bloklamaz. Bu uçların içinden gerçekten
asenkron işler (hava durumu HTTP'si, FCM, asenkron Gemini) `run_async` ile olay döngüsünde çalıştırılır.

İki ayrı havuz vardır ve bu bilinçlidir. Bir uç iş parçacığı, `run_async` ile döngüdeki bir coroutine'i
beklerken havuzdaki yerini tutar; o coroutine de senkron DB işi için ikinci bir iş parçacığı isterse ve
ikisi aynı havuzu paylaşırsa, havuz uç iş parçacıklarıyla dolduğunda hepsi birbirini bekler (kilitlenme).
Bu yüzden döngüden açılan iç işler (`run_sync`) kendi sınırlayıcısını kullanır; uç havuzu ne kadar dolu
olursa olsun iç işler ilerler.
"""

from __future__ import annotations

import asyncio
import functools
import os
import weakref

import anyio
import anyio.from_thread
import anyio.to_thread

from config import get_logger

log = get_logger("async_bridge")

DEFAULT_THREADPOOL_SIZE = 64


def run_async(fn, /, *args, **kwargs):
    """İş parçacığı havuzundaki senkron koddan bir coroutine fonksiyonunu olay döngüsünde çalıştırıp sonucunu döner."""
    return anyio.from_thread.run(functools.partial(fn, *args, **kwargs))


def run_sync_size() -> int:
    try:
        return max(8, int(os.getenv("INNER_THREADPOOL_SIZE") or DEFAULT_THREADPOOL_SIZE))
    except ValueError:
        return DEFAULT_THREADPOOL_SIZE


# Olay döngüsü başına bir sınırlayıcı (üretimde tek döngü; testler her seferinde yeni döngü açar).
_inner_limiters: "weakref.WeakKeyDictionary" = weakref.WeakKeyDictionary()


def _inner_limiter() -> anyio.CapacityLimiter:
    loop = asyncio.get_running_loop()
    limiter = _inner_limiters.get(loop)
    if limiter is None:
        limiter = _inner_limiters[loop] = anyio.CapacityLimiter(run_sync_size())
    return limiter


async def run_sync(fn, /, *args, **kwargs):
    """
    Olay döngüsündeki coroutine'den senkron (DB / embedding) bir işi iş parçacığında çalıştırır.
    Uç noktaların kullandığı havuzdan ayrı bir sınırlayıcı kullanır (bkz. modül açıklaması: kilitlenme önlemi).
    """
    return await anyio.to_thread.run_sync(functools.partial(fn, *args, **kwargs), limiter=_inner_limiter())


def threadpool_size() -> int:
    try:
        return max(8, int(os.getenv("THREADPOOL_SIZE") or DEFAULT_THREADPOOL_SIZE))
    except ValueError:
        return DEFAULT_THREADPOOL_SIZE


async def configure_threadpool() -> int:
    """
    Starlette'in varsayılan 40'lık iş parçacığı sınırını yükseltir. Bir sohbet isteği, LLM/DB beklerken bile
    bir iş parçacığı tutar; sınır dolarsa yeni istekler (bildirim, olay yazımı dahil) sırada bekler.
    """
    size = threadpool_size()
    anyio.to_thread.current_default_thread_limiter().total_tokens = size
    log.info("İş parçacığı havuzu: %d", size)
    return size
