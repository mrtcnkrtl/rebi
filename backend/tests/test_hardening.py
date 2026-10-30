"""Sağlamlaştırma: olay döngüsü bloklanmaz, paylaşılan istemciler, zaman aşımları, token günlüğü, girdi sınırları."""

from __future__ import annotations

import asyncio
import logging
import threading
import time

import httpx
import jwt
import pytest
from pydantic import ValidationError

import ai_client
import main
import rag_service
import supabase_client
from knowledge import db as pgdb

USER_ID = "88888888-8888-4888-8888-888888888888"
SECRET = "test-secret-at-least-32-bytes-long"


# ── Uç noktalar iş parçacığında: olay döngüsü bloklanmaz ─────────────────────────────────────────────

# Gerçekten asenkron iş yapmayan tek uçlar (G/Ç yok). Yeni bir `async def` uç eklenirse içinde senkron
# Supabase/Redis/Postgres çağrısı olup olmadığına bakılmalıdır; bu test kazara eklenmeyi yakalar.
_ASYNC_ENDPOINTS_ALLOWED = {"root", "health", "push_actions"}


def test_no_endpoint_runs_sync_io_on_the_event_loop():
    offenders = sorted(
        route.endpoint.__name__
        for route in main.app.routes
        if hasattr(route, "endpoint")
        and asyncio.iscoroutinefunction(route.endpoint)
        and route.endpoint.__name__ not in _ASYNC_ENDPOINTS_ALLOWED
        and route.path not in {"/docs", "/redoc", "/openapi.json", "/docs/oauth2-redirect"}
    )
    assert offenders == [], f"async uçlar senkron G/Ç yapıyorsa olay döngüsünü bloklar: {offenders}"


class _SlowTable:
    """supabase-py gibi senkron bloklayan sahte tablo."""

    def __init__(self, delay: float):
        self.delay = delay

    def __getattr__(self, _name):
        return lambda *a, **k: self

    def execute(self):
        time.sleep(self.delay)

        class _R:
            data = [{"full_name": "Ada", "skin_type": "dry"}]

        return _R()


class _SlowSupabase:
    def __init__(self, delay: float):
        self.delay = delay

    def table(self, _name):
        return _SlowTable(self.delay)


def test_concurrent_requests_do_not_serialize_on_slow_database(monkeypatch):
    monkeypatch.setattr(main, "get_supabase", lambda: _SlowSupabase(0.15))

    async def run():
        transport = httpx.ASGITransport(app=main.app)
        lags: list[float] = []
        stop = asyncio.Event()

        async def watch_loop():
            while not stop.is_set():
                t = time.perf_counter()
                await asyncio.sleep(0.02)
                lags.append(time.perf_counter() - t - 0.02)

        async with httpx.AsyncClient(transport=transport, base_url="http://t") as c:
            watcher = asyncio.create_task(watch_loop())
            started = time.perf_counter()
            responses = await asyncio.gather(
                *(c.get("/me/profile", params={"user_id": USER_ID}) for _ in range(8))
            )
            wall = time.perf_counter() - started
            stop.set()
            await watcher
        return responses, wall, max(lags)

    responses, wall, worst_lag = asyncio.run(run())

    assert all(r.status_code == 200 for r in responses)
    # Seri çalışsaydı 8 × 0,15 = 1,2 sn olurdu (taban çizgisinde olay döngüsü bu sürece kilitleniyordu).
    assert wall < 0.8, f"istekler sıraya girdi: {wall:.2f}s"
    assert worst_lag < 0.12, f"olay döngüsü bloklandı: {worst_lag:.2f}s"


def test_saturated_endpoint_pool_cannot_deadlock_inner_work():
    """
    Uç iş parçacığı, döngüdeki bir coroutine'i beklerken havuzdaki yerini tutar; o coroutine senkron iş için
    ikinci bir iş parçacığı ister. İkisi aynı sınırlayıcıyı paylaşsaydı, havuz uç iş parçacıklarıyla dolunca
    hepsi birbirini beklerdi. İç işler ayrı sınırlayıcı kullandığı için bu olmaz.
    """
    import anyio.to_thread
    from async_bridge import run_async, run_sync
    from starlette.concurrency import run_in_threadpool

    async def inner():
        # Döngüdeki coroutine senkron DB işi ister (rag_service / _chat_today_summary'nin yaptığı gibi).
        return await run_sync(lambda: time.sleep(0.02) or "ok")

    def endpoint():
        # `def` uç: iş parçacığı havuzunda çalışır, döngüdeki işi bekler.
        return run_async(inner)

    async def run():
        anyio.to_thread.current_default_thread_limiter().total_tokens = 3
        return await asyncio.wait_for(
            asyncio.gather(*(run_in_threadpool(endpoint) for _ in range(12))), timeout=10
        )

    assert asyncio.run(run()) == ["ok"] * 12


def test_run_async_bridges_thread_to_event_loop():
    from async_bridge import run_async

    async def double(x, *, add=0):
        await asyncio.sleep(0)
        return x * 2 + add

    async def run():
        from starlette.concurrency import run_in_threadpool

        return await run_in_threadpool(lambda: run_async(double, 20, add=2))

    assert asyncio.run(run()) == 42


# ── Paylaşılan Supabase istemcisi ────────────────────────────────────────────────────────────────

def test_shared_supabase_client_is_built_once_and_reused(monkeypatch):
    built = []

    class _Fake:
        postgrest = object()
        storage = object()

    def fake_create(url, key, options=None):
        built.append((url, options))
        return _Fake()

    import supabase

    monkeypatch.setattr(supabase, "create_client", fake_create)
    monkeypatch.setattr(supabase_client, "SUPABASE_URL", "https://example.supabase.co")
    supabase_client.reset_shared_client()
    try:
        first = supabase_client.get_shared_client()
        results: list = []
        threads = [threading.Thread(target=lambda: results.append(supabase_client.get_shared_client())) for _ in range(12)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()
        assert all(r is first for r in results)
        assert len(built) == 1
        assert built[0][1].postgrest_client_timeout == supabase_client.REST_TIMEOUT_SECONDS
    finally:
        supabase_client.reset_shared_client()


def test_shared_supabase_client_is_none_when_unconfigured(monkeypatch):
    monkeypatch.setattr(supabase_client, "SUPABASE_URL", "")
    supabase_client.reset_shared_client()
    assert supabase_client.get_shared_client() is None


def test_main_get_supabase_delegates_to_the_shared_client(monkeypatch):
    sentinel = object()
    monkeypatch.setattr(main, "get_shared_client", lambda: sentinel)
    assert main.get_supabase() is sentinel


# ── Zaman aşımları ───────────────────────────────────────────────────────────────────────────────

def test_gemini_clients_get_timeouts_and_are_shared(monkeypatch):
    created = []

    class _FakeClient:
        def __init__(self, **kwargs):
            created.append(kwargs)

    from google import genai

    monkeypatch.setattr(genai, "Client", _FakeClient)
    monkeypatch.setattr(ai_client, "GEMINI_API_KEY", "key")
    monkeypatch.setattr(ai_client, "_clients", {})

    request_client = ai_client.get_client()
    assert ai_client.get_client() is request_client
    batch_client = ai_client.get_client(batch=True)
    assert batch_client is not request_client

    assert len(created) == 2
    assert created[0]["http_options"].timeout == int(ai_client.REQUEST_TIMEOUT_SECONDS * 1000)
    assert created[1]["http_options"].timeout == int(ai_client.BATCH_TIMEOUT_SECONDS * 1000)
    assert ai_client.BATCH_TIMEOUT_SECONDS >= ai_client.REQUEST_TIMEOUT_SECONDS


def test_gemini_client_is_none_without_key(monkeypatch):
    monkeypatch.setattr(ai_client, "GEMINI_API_KEY", "")
    monkeypatch.setattr(ai_client, "_clients", {})
    assert ai_client.get_client() is None


def test_postgres_connect_timeout_is_short_by_default_and_overridable(monkeypatch):
    monkeypatch.delenv("POSTGRES_CONNECT_TIMEOUT", raising=False)
    assert pgdb._connect_timeout_sec() == 20
    monkeypatch.setenv("POSTGRES_CONNECT_TIMEOUT", "300")
    assert pgdb._connect_timeout_sec() == 300
    monkeypatch.setenv("POSTGRES_CONNECT_TIMEOUT", "99999")
    assert pgdb._connect_timeout_sec() == 900
    monkeypatch.setenv("POSTGRES_CONNECT_TIMEOUT", "bozuk")
    assert pgdb._connect_timeout_sec() == 20


class _FakeConn:
    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False

    def execute(self, *_a, **_k):
        return None


def test_postgres_connections_are_capped_and_always_released(monkeypatch):
    import psycopg

    monkeypatch.setattr(psycopg, "connect", lambda *a, **k: _FakeConn())
    monkeypatch.setattr(pgdb, "postgres_dsn", lambda: "postgresql://x")
    monkeypatch.setattr(pgdb, "_conn_slots", threading.BoundedSemaphore(1))
    monkeypatch.setattr(pgdb, "_connect_timeout_sec", lambda: 0.1)

    with pgdb.pg_conn():
        # Tek yuva dolu: ikinci bağlantı sırada bekleyip zaman aşımına uğrar, sonsuza dek takılmaz.
        with pytest.raises(RuntimeError, match="sırası dolu"):
            with pgdb.pg_conn():
                pass
    # Yuva geri verildi.
    with pgdb.pg_conn():
        pass

    # İçeride hata olsa da yuva sızmaz.
    with pytest.raises(ValueError):
        with pgdb.pg_conn():
            raise ValueError("boom")
    with pgdb.pg_conn():
        pass


# ── Token kullanım günlüğü ───────────────────────────────────────────────────────────────────────

class _Usage:
    prompt_token_count = 3500
    candidates_token_count = 200
    thoughts_token_count = 0


class _Response:
    text = "yanıt"
    usage_metadata = _Usage()


class _AioModels:
    def __init__(self, response=None, error=None):
        self.response, self.error, self.calls = response, error, []

    async def generate_content(self, **kwargs):
        self.calls.append(kwargs)
        if self.error:
            raise self.error
        return self.response


def _client_with(models):
    class _Aio:
        pass

    class _C:
        aio = _Aio()

    _C.aio.models = models
    return _C()


@pytest.fixture(autouse=False)
def clean_usage():
    ai_client.reset_usage()
    yield
    ai_client.reset_usage()


def test_usage_is_logged_with_tokens_and_estimated_cost(caplog, clean_usage):
    with caplog.at_level(logging.INFO, logger="ai_client"):
        info = ai_client.record_usage("chat_compose", "gemini-2.5-flash", _Response(), 1.25)

    assert info["in"] == 3500 and info["out"] == 200
    # 3500 × 0,30/1M + 200 × 2,50/1M = 0,00155
    assert info["cost_usd"] == pytest.approx(0.00155, rel=1e-6)
    line = next(r.getMessage() for r in caplog.records if "gemini_usage" in r.getMessage())
    assert "label=chat_compose" in line and "in=3500" in line and "out=200" in line and "ms=1250" in line
    snap = ai_client.usage_snapshot()["chat_compose"]
    assert snap["calls"] == 1 and snap["in"] == 3500 and snap["out"] == 200


def test_thinking_tokens_are_billed_as_output(clean_usage):
    class _Thinking(_Usage):
        thoughts_token_count = 800

    class _R(_Response):
        usage_metadata = _Thinking()

    info = ai_client.record_usage("x", "m", _R(), 0.1)
    assert info["thoughts"] == 800
    assert ai_client.usage_snapshot()["x"]["out"] == 1000
    assert info["cost_usd"] == pytest.approx(ai_client.estimate_cost_usd(3500, 1000))


def test_usage_logging_never_breaks_on_a_response_without_metadata(clean_usage):
    info = ai_client.record_usage("y", None, object(), 0.0)
    assert info == {"in": 0, "out": 0, "thoughts": 0, "cost_usd": 0.0}


def test_llm_helper_logs_success_and_counts_errors(monkeypatch, caplog, clean_usage):
    ok = _AioModels(response=_Response())
    monkeypatch.setattr(rag_service, "gemini_client", _client_with(ok))

    async def run():
        r = await rag_service._llm("chat_compose", model="m", contents="c")
        monkeypatch.setattr(
            rag_service, "gemini_client", _client_with(_AioModels(error=TimeoutError("zaman aşımı")))
        )
        with pytest.raises(TimeoutError):
            await rag_service._llm("chat_compose", model="m", contents="c")
        return r

    with caplog.at_level(logging.INFO, logger="ai_client"):
        assert asyncio.run(run()).text == "yanıt"

    assert ok.calls == [{"model": "m", "contents": "c"}]
    snap = ai_client.usage_snapshot()["chat_compose"]
    assert snap["calls"] == 1 and snap["errors"] == 1
    assert any("gemini_error label=chat_compose kind=TimeoutError" in r.getMessage() for r in caplog.records)


def test_every_generation_call_goes_through_the_logged_helper():
    import inspect

    source = inspect.getsource(rag_service)
    assert "gemini_client.models.generate_content" not in source, "token günlüğünü atlayan doğrudan çağrı"


# ── Girdi sınırları ──────────────────────────────────────────────────────────────────────────────

def test_chat_general_request_clips_message_and_history():
    req = main.ChatGeneralRequest(
        user_id=USER_ID,
        message="a" * 50_000,
        history=[{"role": "user", "content": f"{i}-" + "b" * 10_000} for i in range(100)] + ["sözlük değil", 7],
    )
    assert len(req.message) == main.CHAT_MESSAGE_MAX_CHARS
    assert len(req.history) == main.CHAT_HISTORY_MAX_TURNS
    assert all(len(m["content"]) <= main.CHAT_HISTORY_ITEM_MAX_CHARS for m in req.history)
    assert all(isinstance(m, dict) for m in req.history)


def test_short_inputs_pass_through_untouched():
    history = [{"role": "user", "content": "Merhaba"}, {"role": "assistant", "content": "Selam"}]
    req = main.ChatGeneralRequest(user_id=USER_ID, message="Retinol akşam mı?", history=history)
    assert req.message == "Retinol akşam mı?"
    assert req.history == history
    assert main.ChatGeneralRequest(user_id=USER_ID, message="x", history=None).history is None
    assert main.ChatGeneralRequest(user_id=USER_ID, message="x", history=[]).history == []


def test_a_realistic_inci_list_is_not_clipped():
    inci = ", ".join(f"Ingredient {i}" for i in range(120))  # ~1,7 bin karakter
    assert len(inci) < main.CHAT_MESSAGE_MAX_CHARS
    assert main.ChatGeneralRequest(user_id=USER_ID, message=inci).message == inci


def test_concern_and_assessment_requests_clip_too():
    chat = main.ChatRequest(user_id=USER_ID, message="z" * 9000, history=[{"role": "user", "content": "q" * 9000}] * 50)
    assert len(chat.message) == main.CHAT_MESSAGE_MAX_CHARS and len(chat.history) == main.CHAT_HISTORY_MAX_TURNS

    assess = main.AssessmentChatRequest(
        user_id=USER_ID,
        message="m" * 9000,
        history=[{"role": "user", "content": "h" * 9000}] * 50,
        user_profile={f"k{i}": "v" * 5000 for i in range(200)} | {"mode": "free_chat"},
    )
    assert len(assess.message) == main.CHAT_MESSAGE_MAX_CHARS
    # Değerlendirme sohbeti tüm geçmişi tarar: sınır genel sohbetten geniştir.
    assert len(assess.history) == main.ASSESSMENT_HISTORY_MAX_TURNS > main.CHAT_HISTORY_MAX_TURNS
    assert len(assess.user_profile) == main.CHAT_PROFILE_MAX_KEYS
    assert all(len(v) <= main.CHAT_PROFILE_VALUE_MAX_CHARS for v in assess.user_profile.values())
    assert main.AssessmentChatRequest(user_id=USER_ID, message="x", user_profile={"mode": "free_chat"}).user_profile == {
        "mode": "free_chat"
    }


def test_translate_request_clips_items():
    items = [{"action": "a" * 5000, "detail": "d", "time": "AM"} for _ in range(100)]
    req = main.TranslateRoutineItemsRequest(user_id=USER_ID, routine_items=items)
    assert len(req.routine_items) == main.TRANSLATE_MAX_ITEMS
    assert len(req.routine_items[0]["action"]) == main.TRANSLATE_ITEM_FIELD_MAX_CHARS
    assert req.routine_items[0]["time"] == "AM"


def test_invalid_shapes_are_still_rejected():
    with pytest.raises(ValidationError):
        main.ChatGeneralRequest(user_id=USER_ID)  # message zorunlu


# ── /chat_general: kırpılmış girdi modele gider, kanıt paketi ikinci kez kurulmaz ───────────────────

@pytest.fixture
def headers(monkeypatch):
    monkeypatch.setenv("SUPABASE_JWT_SECRET", SECRET)
    monkeypatch.delenv("API_ALLOW_INSECURE_AUTH", raising=False)
    token = jwt.encode({"sub": USER_ID, "aud": "authenticated"}, SECRET, algorithm="HS256")
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
def chat_env(monkeypatch):
    seen: dict = {}
    bundle_builds: list = []

    async def fake_chat_general(**kwargs):
        seen.update(kwargs)
        kwargs["evidence_out"].update({"score": 0.62, "sources": [{"title": "Kaynak", "url": ""}]})
        return "Cevap."

    monkeypatch.setattr(rag_service, "chat_general", fake_chat_general)
    monkeypatch.setattr(
        rag_service, "_build_free_chat_evidence_bundle", lambda *a, **k: bundle_builds.append(1) or {"score": 0.0}
    )
    monkeypatch.setattr(main, "get_supabase", lambda: None)
    monkeypatch.setattr(main, "user_is_rebi_plus", lambda *a, **k: True)
    monkeypatch.setattr(main, "user_plus_chat_is_monthly_capped", lambda *a, **k: False)
    monkeypatch.setattr(main, "_chat_usage_row", lambda *a, **k: ("plus_unlimited", None, None, None))
    monkeypatch.setattr(main, "_persist_chat_turn", lambda *a, **k: None)
    monkeypatch.setattr(main, "_require_privacy_permission", lambda *a, **k: None)
    return seen, bundle_builds


def test_chat_general_forwards_clipped_input(client, headers, chat_env):
    seen, _ = chat_env
    r = client.post(
        "/chat_general",
        json={
            "user_id": USER_ID,
            "message": "x" * 100_000,
            "history": [{"role": "user", "content": "h" * 100_000}] * 60,
        },
        headers=headers,
    )
    assert r.status_code == 200, r.text
    assert len(seen["user_message"]) == main.CHAT_MESSAGE_MAX_CHARS
    assert len(seen["history"]) == main.CHAT_HISTORY_MAX_TURNS
    assert all(len(m["content"]) == main.CHAT_HISTORY_ITEM_MAX_CHARS for m in seen["history"])


def test_chat_general_reports_evidence_without_rebuilding_the_bundle(client, headers, chat_env):
    _, bundle_builds = chat_env
    r = client.post("/chat_general", json={"user_id": USER_ID, "message": "SPF?", "history": []}, headers=headers)
    body = r.json()
    assert r.status_code == 200, r.text
    assert body["evidence_score"] == pytest.approx(0.62)
    assert body["evidence_used"] is True
    assert body["evidence_sources"] == [{"title": "Kaynak", "url": ""}]
    assert bundle_builds == [], "kanıt paketi yanıttan sonra yeniden kurulmamalı (çift DB + embedding maliyeti)"


def test_chat_general_evidence_is_empty_when_no_retrieval_happened(monkeypatch, client, headers, chat_env):
    async def boundary_reply(**kwargs):
        return "Tıbbi sınır yanıtı."  # kanıt aranmadı: evidence_out boş kalır

    monkeypatch.setattr(rag_service, "chat_general", boundary_reply)
    r = client.post("/chat_general", json={"user_id": USER_ID, "message": "teşhis koy", "history": []}, headers=headers)
    body = r.json()
    assert r.status_code == 200, r.text
    assert body["evidence_score"] is None and body["evidence_used"] is None


# ── Bellek içi sayaçlar iş parçacıklarında doğru sayar ───────────────────────────────────────────

def test_memory_quota_counts_exactly_under_threads():
    from free_chat_quota import _MemoryDailyQuota
    from plus_chat_quota import _MemoryMonthlyQuota

    daily, monthly = _MemoryDailyQuota(), _MemoryMonthlyQuota()

    def hammer():
        for _ in range(500):
            assert daily.reserve("u", 10**9) is not None
            assert monthly.reserve("u", "2026-10", 10**9)

    threads = [threading.Thread(target=hammer) for _ in range(8)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()

    assert daily.count_today("u") == 4000
    assert monthly.count_month("u", "2026-10") == 4000


def test_sliding_window_limiter_is_exact_under_threads():
    from rate_limit import SlidingWindowLimiter

    limiter = SlidingWindowLimiter(max_requests=100, window_seconds=60)
    allowed: list[bool] = []

    def hammer():
        for _ in range(50):
            allowed.append(limiter.allow("ip"))

    threads = [threading.Thread(target=hammer) for _ in range(8)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()

    assert sum(allowed) == 100


# ── Fotoğraf yükleme: büyük dosya belleğe tamamen alınmadan reddedilir ───────────────────────────

def test_oversized_photo_is_rejected(monkeypatch, client):
    monkeypatch.setattr(main, "_require_privacy_permission", lambda *a, **k: None)
    monkeypatch.setattr(main, "get_supabase", lambda: object())
    big = b"\xff\xd8\xff" + b"0" * (main._MAX_PHOTO_BYTES + 10)
    r = client.post(
        "/upload_photo",
        params={"user_id": "demo"},
        files={"file": ("x.jpg", big, "image/jpeg")},
    )
    assert r.status_code == 400
    assert "büyük" in r.json()["detail"]
