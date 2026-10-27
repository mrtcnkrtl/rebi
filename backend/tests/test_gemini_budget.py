"""Gemini günlük bütçe kesicisi: dolunca yeni çağrı yapılmaz, uygulama çökmez, sohbet bilgi tabanı özetine düşer."""

from __future__ import annotations

import asyncio
import logging
import threading
import time

import pytest

import ai_client
import main
import rag_service
import redis_client
from ai_client import GeminiBudgetExceeded

COST_PER_CALL = 0.00155  # 3500 giriş × 0,30/1M + 200 çıkış × 2,50/1M


class _Usage:
    prompt_token_count = 3500
    candidates_token_count = 200
    thoughts_token_count = 0


class _Response:
    text = "Kısa bir yanıt."
    usage_metadata = _Usage()
    candidates = []


class _FakeGemini:
    """Asenkron istemci; kaç kez çağrıldığını sayar."""

    def __init__(self):
        self.calls = 0
        outer = self

        class _Models:
            async def generate_content(self, **kwargs):
                outer.calls += 1
                return _Response()

        class _Aio:
            models = _Models()

        self.aio = _Aio()


class _FakeRedis:
    def __init__(self):
        self.data: dict[str, int] = {}
        self.ttl: dict[str, int] = {}
        self.down = False
        self._lock = threading.Lock()

    def _check(self):
        if self.down:
            raise ConnectionError("Redis kapalı")

    def incrby(self, key, amount):
        self._check()
        with self._lock:
            self.data[key] = int(self.data.get(key, 0)) + int(amount)
            return self.data[key]

    def get(self, key):
        self._check()
        value = self.data.get(key)
        return None if value is None else str(value)

    def expire(self, key, seconds):
        self._check()
        self.ttl[key] = seconds


@pytest.fixture(autouse=True)
def _clean(monkeypatch):
    monkeypatch.delenv("REDIS_URL", raising=False)
    monkeypatch.delenv("GEMINI_DAILY_BUDGET_USD", raising=False)
    redis_client.reset_redis()
    ai_client.reset_budget()
    ai_client.reset_usage()
    yield
    ai_client.reset_budget()
    ai_client.reset_usage()
    redis_client.reset_redis()


def _spend(n: int):
    for _ in range(n):
        ai_client.record_usage("deneme", "m", _Response(), 0.1)


# ── Kesici ───────────────────────────────────────────────────────────────────────────────────────

def test_the_breaker_is_off_by_default_so_nothing_changes_until_a_budget_is_set():
    _spend(50)
    ai_client.check_budget()  # asla yükseltmez
    assert ai_client.daily_budget_usd() == 0.0


@pytest.mark.parametrize("value", ["bozuk", "-5", "0", ""])
def test_unusable_budget_values_disable_the_breaker(monkeypatch, value):
    monkeypatch.setenv("GEMINI_DAILY_BUDGET_USD", value)
    _spend(10)
    ai_client.check_budget()


def test_calls_stop_once_the_estimated_daily_spend_reaches_the_budget(monkeypatch):
    monkeypatch.setenv("GEMINI_DAILY_BUDGET_USD", "0.01")

    _spend(6)  # 0,0093
    ai_client.check_budget()
    _spend(1)  # 0,01085

    with pytest.raises(GeminiBudgetExceeded, match="bütçesi doldu"):
        ai_client.check_budget()
    assert ai_client.spent_today_usd() == pytest.approx(7 * COST_PER_CALL, rel=1e-3)


def test_the_counter_resets_on_a_new_day(monkeypatch):
    from datetime import date as real_date

    days = ["2026-10-27"]

    class _Date(real_date):
        @classmethod
        def today(cls):
            return real_date.fromisoformat(days[0])

    monkeypatch.setattr(ai_client, "date", _Date)
    monkeypatch.setenv("GEMINI_DAILY_BUDGET_USD", "0.003")
    _spend(3)
    with pytest.raises(GeminiBudgetExceeded):
        ai_client.check_budget()

    days[0] = "2026-10-28"
    ai_client.check_budget()  # yeni gün: bütçe yeniden açılır
    assert ai_client.spent_today_usd() == 0


def test_warnings_are_logged_once_at_eighty_percent_and_once_at_the_limit(monkeypatch, caplog):
    monkeypatch.setenv("GEMINI_DAILY_BUDGET_USD", "0.01")
    with caplog.at_level(logging.WARNING, logger="ai_client"):
        _spend(10)
        for _ in range(3):
            with pytest.raises(GeminiBudgetExceeded):
                ai_client.check_budget()
    text = [r.getMessage() for r in caplog.records if "gemini_budget" in r.getMessage()]
    assert len([t for t in text if "%80" in t]) == 1 and len([t for t in text if "DOLDU" in t]) == 1


def test_llm_helper_makes_no_call_when_the_budget_is_spent(monkeypatch):
    fake = _FakeGemini()
    monkeypatch.setattr(rag_service, "gemini_client", fake)
    monkeypatch.setenv("GEMINI_DAILY_BUDGET_USD", "0.002")

    asyncio.run(rag_service._llm("deneme", model="m", contents="c"))  # bütçe içinde: gider (maliyet 0,00155)
    asyncio.run(rag_service._llm("deneme", model="m", contents="c"))  # ikincisi de gider (0,00155 < 0,002 iken kontrol)
    with pytest.raises(GeminiBudgetExceeded):
        asyncio.run(rag_service._llm("deneme", model="m", contents="c"))

    assert fake.calls == 2, "bütçe dolduktan sonra sağlayıcıya çağrı gitmez"


def test_a_blocked_call_is_not_recorded_as_a_provider_error(monkeypatch):
    monkeypatch.setattr(rag_service, "gemini_client", _FakeGemini())
    monkeypatch.setenv("GEMINI_DAILY_BUDGET_USD", "0.0001")
    _spend(1)
    with pytest.raises(GeminiBudgetExceeded):
        asyncio.run(rag_service._llm("chat_compose", model="m", contents="c"))
    assert ai_client.usage_snapshot().get("chat_compose", {}).get("errors", 0) == 0


# ── Redis ve çökme güvenliği ─────────────────────────────────────────────────────────────────────

def test_spend_is_shared_through_redis_across_processes_and_restarts(monkeypatch):
    import redis

    fake = _FakeRedis()
    monkeypatch.setattr(redis, "from_url", lambda *a, **k: fake)
    monkeypatch.setenv("REDIS_URL", "redis://redis:6379/0")
    monkeypatch.setenv("GEMINI_DAILY_BUDGET_USD", "0.01")

    _spend(4)
    ai_client.reset_budget()  # "yeniden başlatma / başka işçi": bellekte hiçbir şey yok
    _spend(3)

    assert ai_client.spent_today_usd() == pytest.approx(7 * COST_PER_CALL, rel=1e-3)
    with pytest.raises(GeminiBudgetExceeded):
        ai_client.check_budget()
    key = next(iter(fake.data))
    assert key.startswith("rebi:gemini:spend:") and fake.ttl[key] == 172800


def test_a_dead_redis_never_breaks_calls_or_accounting(monkeypatch):
    import redis

    fake = _FakeRedis()
    monkeypatch.setattr(redis, "from_url", lambda *a, **k: fake)
    monkeypatch.setenv("REDIS_URL", "redis://redis:6379/0")
    monkeypatch.setenv("GEMINI_DAILY_BUDGET_USD", "0.01")
    fake.down = True

    _spend(3)  # sayaç yazımı hata verir: bellek yedeğine düşer, istisna fırlatmaz
    ai_client.check_budget()
    _spend(5)
    with pytest.raises(GeminiBudgetExceeded):
        ai_client.check_budget()  # süreç içi sayaç yine de kesiciyi çalıştırır


def test_a_failing_budget_read_lets_the_call_through(monkeypatch):
    monkeypatch.setenv("GEMINI_DAILY_BUDGET_USD", "0.01")

    class _Broken:
        def get(self, day):
            raise RuntimeError("okunamadı")

        def add(self, day, micro):
            raise RuntimeError("yazılamadı")

    monkeypatch.setattr(ai_client, "_spend_backend", _Broken())
    ai_client.check_budget()  # bütçe yardımcıdır: sayaç bozuksa kullanıcıyı cezalandırmaz
    _spend(2)


# ── Uygulama: dolunca çökmez, zarif yedeğe düşer ─────────────────────────────────────────────────

def _exhaust(monkeypatch):
    fake = _FakeGemini()
    monkeypatch.setattr(rag_service, "gemini_client", fake)
    monkeypatch.setenv("GEMINI_DAILY_BUDGET_USD", "0.01")
    ai_client._add_spend(1.0)
    with pytest.raises(GeminiBudgetExceeded):
        ai_client.check_budget()
    return fake


def test_every_generation_call_is_protected_against_the_budget_exception():
    """Bütçe istisnası hiçbir yerde yakalanmadan uca ulaşıp 500'e dönüşmemeli (rag_service'te 13 çağrı)."""
    import ast
    import inspect

    tree = ast.parse(inspect.getsource(rag_service))

    class Visitor(ast.NodeVisitor):
        def __init__(self):
            self.stack, self.bare = [], []

        def visit_Try(self, node):
            for stmt in node.body:
                self.stack.append(node)
                self.visit(stmt)
                self.stack.pop()
            for h in node.handlers:
                for stmt in h.body:
                    self.visit(stmt)
            for stmt in node.orelse + node.finalbody:
                self.visit(stmt)

        def visit_Call(self, node):
            if isinstance(node.func, ast.Name) and node.func.id == "_llm":
                caught = any(
                    any(h.type is None or (isinstance(h.type, ast.Name) and h.type.id in ("Exception", "BaseException")) for h in t.handlers)
                    for t in self.stack
                )
                if not caught:
                    self.bare.append(node.lineno)
            self.generic_visit(node)

    v = Visitor()
    v.visit(tree)
    assert v.bare == [], f"try/except dışında _llm çağrısı: satırlar {v.bare}"


def test_chat_degrades_to_the_knowledge_base_summary_when_the_budget_is_spent(monkeypatch, client):
    fake = _exhaust(monkeypatch)

    def bundle(*_a, **_k):
        return {
            "context_text": "[Madde / içerik endeksi]\nretinol: akşam kullanılır, güneş kremi gerekir. " * 6,
            "score": 0.9, "ok": True, "max_sim": 0.8, "sources": [], "entity_text": "x" * 300,
        }

    monkeypatch.setattr(rag_service, "_build_free_chat_evidence_bundle", bundle)

    started = time.perf_counter()
    r = client.post("/chat_general", json={"user_id": "demo", "message": "Retinol akşam mı kullanılır?", "history": []})

    assert r.status_code == 200, r.text
    assert r.json()["reply"].strip(), "kullanıcı boş yanıt görmemeli"
    assert fake.calls == 0, "bütçe dolu: sağlayıcıya hiç gidilmedi"
    assert time.perf_counter() - started < 2.0, "yeniden deneme beklemeleri olmamalı"


def test_routine_generation_still_returns_a_routine_when_the_budget_is_spent(monkeypatch, client):
    fake = _exhaust(monkeypatch)

    r = client.post(
        "/generate_routine",
        json={"user_id": "00000000-0000-4000-8000-000000000001", "full_name": "Test", "age": 25,
              "gender": "female", "concern": "acne", "skin_type": "normal", "severity_score": 5},
    )

    assert r.status_code == 200, r.text
    assert len(r.json()["routine"]) >= 1, "rutini kural motoru üretir; yapay zekâ yalnızca cilalar"
    assert fake.calls == 0


def test_the_checkin_note_falls_back_without_raising(monkeypatch):
    fake = _exhaust(monkeypatch)

    note = asyncio.run(rag_service.adapt_routine_with_ai(
        current_routine=[{"time": "Sabah", "action": "Nemlendirici"}],
        daily_data={"skin_feeling": "irritasyon"},
        risk_score=70,
        changes=[],
    ))

    assert isinstance(note, str) and fake.calls == 0


def test_the_budget_exception_is_never_retried_with_backoff():
    from knowledge.evidence_fallback import is_gemini_non_retryable_error, is_gemini_retryable_error

    err = GeminiBudgetExceeded("429 günlük bütçe")  # metinde 429 geçse bile
    assert is_gemini_non_retryable_error(err) is True
