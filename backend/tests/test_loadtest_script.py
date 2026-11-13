"""Yük testi betiği: sentetik kullanıcı güvenliği, token uyumu, ölçüm ve eşik hesabı, uçtan uca koşu."""

from __future__ import annotations

import asyncio
import json

import httpx
import jwt
import pytest

import loadtest
import main
import rag_service

SECRET = "test-secret-at-least-32-bytes-long"
UID = "abababab-abab-4bab-8bab-abababababab"


# ── Sentetik kullanıcı güvenliği ─────────────────────────────────────────────────────────────────

def _user(email, meta=None):
    return {"id": "u", "email": email, "user_metadata": meta}


def test_only_users_with_all_three_markers_count_as_loadtest_users():
    ok = _user("loadtest+20261027-1@loadtest.invalid", {"loadtest": True})
    assert loadtest.is_loadtest_user(ok, "loadtest")

    assert not loadtest.is_loadtest_user(_user("loadtest+1@loadtest.invalid", {}), "loadtest"), "meta işareti yok"
    assert not loadtest.is_loadtest_user(_user("loadtest+1@loadtest.invalid", None), "loadtest")
    assert not loadtest.is_loadtest_user(_user("loadtest+1@gmail.com", {"loadtest": True}), "loadtest"), "alan adı gerçek"
    assert not loadtest.is_loadtest_user(_user("ayse@loadtest.invalid", {"loadtest": True}), "loadtest"), "önek yok"
    assert not loadtest.is_loadtest_user(_user("ayse@example.com", {"loadtest": "evet"}), "loadtest")
    assert not loadtest.is_loadtest_user(_user("loadtest+1@loadtest.invalid", {"loadtest": True}), "baska-onek")


def test_synthetic_emails_use_a_reserved_domain_that_can_never_receive_mail():
    assert loadtest.EMAIL_DOMAIN.endswith(".invalid")


def test_minted_tokens_are_accepted_by_the_backend(monkeypatch, client):
    monkeypatch.setenv("SUPABASE_JWT_SECRET", SECRET)
    monkeypatch.delenv("API_ALLOW_INSECURE_AUTH", raising=False)
    monkeypatch.setattr(main, "get_supabase", lambda: None)
    token = loadtest.mint_token(UID, "loadtest+1@loadtest.invalid", SECRET)

    claims = jwt.decode(token, SECRET, algorithms=["HS256"], audience="authenticated")
    assert claims["sub"] == UID and claims["role"] == "authenticated" and claims["exp"] > claims["iat"]

    r = client.get("/me/snapshot", params={"user_id": UID}, headers={"Authorization": f"Bearer {token}"})
    assert r.status_code == 200, "sunucu kendi imzaladığımız token'ı kabul etmeli"
    other = client.get("/me/snapshot", params={"user_id": "baskasi"}, headers={"Authorization": f"Bearer {token}"})
    assert other.status_code == 403, "token yalnızca kendi kullanıcısı için geçerli"


# ── provision / cleanup ──────────────────────────────────────────────────────────────────────────

def _supabase_admin(created: list, users_pages=None, deleted=None):
    counter = {"n": 0}

    def handler(request: httpx.Request) -> httpx.Response:
        if request.method == "POST" and request.url.path == "/auth/v1/admin/users":
            counter["n"] += 1
            body = json.loads(request.content)
            created.append({"headers": dict(request.headers), "body": body})
            return httpx.Response(200, json={"id": f"00000000-0000-4000-8000-{counter['n']:012d}", "email": body["email"]})
        if request.method == "GET" and request.url.path == "/auth/v1/admin/users":
            page = int(request.url.params.get("page", "1"))
            return httpx.Response(200, json={"users": (users_pages or [[]])[page - 1]})
        if request.method == "DELETE" and request.url.path.startswith("/auth/v1/admin/users/"):
            deleted.append(request.url.path.rsplit("/", 1)[1])
            return httpx.Response(200, json={})
        return httpx.Response(404)

    return httpx.MockTransport(handler)


def _api(accepted: list):
    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path == "/legal-consent/status":
            return httpx.Response(200, json={"accepted": False, "document_version": "v7"})
        if request.url.path == "/legal-consent/accept":
            accepted.append({"auth": request.headers["authorization"], "body": json.loads(request.content)})
            return httpx.Response(200, json={"ok": True})
        return httpx.Response(404)

    return httpx.MockTransport(handler)


def test_provision_creates_flagged_users_mints_tokens_and_records_consent():
    created, accepted, logs = [], [], []

    async def go():
        async with httpx.AsyncClient(transport=_supabase_admin(created)) as sb, httpx.AsyncClient(
            base_url="http://api", transport=_api(accepted)
        ) as api:
            return await loadtest.provision(
                sb, api, supabase_url="https://x.supabase.co", service_key="servis-anahtari", jwt_secret=SECRET,
                count=3, prefix="loadtest", log=logs.append,
            )

    users = asyncio.run(go())

    assert len(users) == 3 and len({u["user_id"] for u in users}) == 3
    for c in created:
        assert c["body"]["email_confirm"] is True and c["body"]["user_metadata"] == {"loadtest": True}
        assert c["body"]["email"].startswith("loadtest+") and c["body"]["email"].endswith("@loadtest.invalid")
        assert c["headers"]["authorization"] == "Bearer servis-anahtari"
        assert len(c["body"]["password"]) >= 24, "parola rastgele ve uzun"
    # Rıza: sunucunun bildirdiği sürümle (sabit kodlanmış değil), yalnızca zorunlu izinlerle.
    assert [a["body"]["document_version"] for a in accepted] == ["v7"] * 3
    assert accepted[0]["body"]["location_processing_accepted"] is False and accepted[0]["body"]["photo_processing_accepted"] is False
    assert all(loadtest.is_loadtest_user({"email": u["email"], "user_metadata": {"loadtest": True}}, "loadtest") for u in users)
    claims = jwt.decode(users[0]["token"], SECRET, algorithms=["HS256"], audience="authenticated")
    assert claims["sub"] == users[0]["user_id"]


def test_cleanup_lists_by_default_and_never_touches_real_users():
    pages = [[
        {"id": "a", "email": "loadtest+1@loadtest.invalid", "user_metadata": {"loadtest": True}},
        {"id": "b", "email": "gercek@gmail.com", "user_metadata": {}},
        {"id": "c", "email": "loadtest+2@loadtest.invalid", "user_metadata": {"loadtest": True}},
        {"id": "d", "email": "loadtest+3@loadtest.invalid", "user_metadata": {}},  # meta işareti yok: dokunulmaz
    ]]
    deleted: list = []

    async def go(delete):
        async with httpx.AsyncClient(transport=_supabase_admin([], pages, deleted)) as sb:
            return await loadtest.cleanup(sb, supabase_url="https://x.supabase.co", service_key="k", prefix="loadtest",
                                          delete=delete, log=lambda *_: None)

    found = asyncio.run(go(False))
    assert [u["id"] for u in found] == ["a", "c"] and deleted == [], "varsayılan: yalnızca listeler"

    asyncio.run(go(True))
    assert sorted(deleted) == ["a", "c"], "yalnızca üç işareti taşıyanlar silinir"


def test_cleanup_walks_every_page():
    page1 = [{"id": f"x{i}", "email": f"loadtest+{i}@loadtest.invalid", "user_metadata": {"loadtest": True}} for i in range(200)]
    page2 = [{"id": "son", "email": "loadtest+999@loadtest.invalid", "user_metadata": {"loadtest": True}}]
    deleted: list = []

    async def go():
        async with httpx.AsyncClient(transport=_supabase_admin([], [page1, page2], deleted)) as sb:
            return await loadtest.cleanup(sb, supabase_url="https://x.supabase.co", service_key="k", prefix="loadtest",
                                          delete=True, log=lambda *_: None)

    assert len(asyncio.run(go())) == 201 and len(deleted) == 201


# ── Ölçüm ve eşikler ─────────────────────────────────────────────────────────────────────────────

def _stats(samples: dict, statuses: dict | None = None, health=None):
    s = loadtest.Stats()
    for name, values in samples.items():
        for v in values:
            s.latency_ms[name].append(v)
        for code, n in (statuses or {}).get(name, {"200": len(values)}).items():
            s.status[name][code] += n
            if code == "istisna" or (code.isdigit() and int(code) >= 500):
                s.errors[name] += n
    s.health_ms.extend(health or [20.0, 25.0, 30.0])
    return s


def test_percentiles_and_the_summary():
    assert loadtest.percentile([], 95) == 0.0
    assert loadtest.percentile([5], 99) == 5
    assert loadtest.percentile(list(range(1, 101)), 50) in (50, 51)
    assert loadtest.percentile(list(range(1, 101)), 95) in (95, 96)

    report = loadtest.summarize(_stats({"ingest": [10, 20, 30, 40]}), 2.0)
    assert report["requests"] == 4 and report["rps"] == 2.0 and report["endpoints"]["ingest"]["max_ms"] == 40
    assert report["error_rate"] == 0 and report["health_max_ms"] == 30


def test_a_healthy_run_passes_every_threshold():
    report = loadtest.summarize(_stats({"snapshot": [50] * 20, "chat": [3000] * 5}), 10)
    assert loadtest.verdict(report, p95_ms=500, chat_p95_ms=8000, max_error_rate=0.01, health_ms=500) == []


def test_each_failure_mode_is_reported_separately():
    report = loadtest.summarize(
        _stats(
            {"snapshot": [900] * 10, "chat": [9000] * 5, "ingest": [10] * 100},
            {"ingest": {"200": 90, "500": 6, "429": 4}},
            health=[900.0] * 5,
        ),
        10,
    )
    problems = loadtest.verdict(report, p95_ms=500, chat_p95_ms=8000, max_error_rate=0.01, health_ms=500)
    text = " | ".join(problems)
    assert "snapshot: p95" in text and "chat: p95" in text, "sohbet kendi (gevşek) eşiğiyle ölçülür"
    assert "hata oranı" in text and "429 oranı" in text and "/health p95" in text


def test_chat_uses_its_own_looser_threshold_and_others_the_strict_one():
    report = loadtest.summarize(_stats({"chat": [6000] * 10, "snapshot": [600] * 10}), 5)
    problems = loadtest.verdict(report, p95_ms=500, chat_p95_ms=8000, max_error_rate=0.01, health_ms=500)
    assert len(problems) == 1 and problems[0].startswith("snapshot")


def test_the_report_text_states_the_verdict():
    report = loadtest.summarize(_stats({"snapshot": [10] * 5}), 1)
    assert "SONUÇ: GEÇTİ" in loadtest.format_report(report, [])
    assert "SONUÇ: KALDI" in loadtest.format_report(report, ["x: p95 9 ms > 5 ms"])


def test_the_chat_budget_is_exact_under_concurrency():
    async def go():
        budget = loadtest.ChatBudget(7)
        return await asyncio.gather(*(budget.take() for _ in range(50)))

    assert sum(asyncio.run(go())) == 7
    assert loadtest.ChatBudget(0).enabled is False


# ── Uçtan uca koşu (gerçek uygulama, bellek içi taşıma) ──────────────────────────────────────────

def _app_client():
    return httpx.AsyncClient(transport=httpx.ASGITransport(app=main.app), base_url="http://t", timeout=30)


def test_a_short_run_against_the_real_app_measures_every_endpoint_without_errors(monkeypatch):
    monkeypatch.setattr(main, "get_supabase", lambda: None)

    async def go():
        async with _app_client() as client:
            return await loadtest.run_load(
                client, [{"user_id": "demo", "token": "x"}], virtual_users=4, duration=1.0, chat_messages=0, think=0
            )

    report = asyncio.run(go())
    main._MEM_DAILY_EVENTS.clear()

    assert set(report["endpoints"]) == {"snapshot", "today_plan", "ingest", "history"}, "yapay zekâ varsayılan olarak kapalı"
    assert report["requests"] > 20 and report["error_rate"] == 0 and report["rate_limited_rate"] == 0
    assert report["health_p95_ms"] > 0, "/health yük sürerken yoklanmalı"


def test_chat_messages_are_capped_by_the_budget(monkeypatch):
    monkeypatch.setattr(main, "get_supabase", lambda: None)
    calls: list = []

    async def reply(**kwargs):
        calls.append(1)
        return "Cevap."

    monkeypatch.setattr(rag_service, "chat_general", reply)

    async def go():
        async with _app_client() as client:
            return await loadtest.run_load(
                client, [{"user_id": "demo", "token": "x"}], virtual_users=4, duration=1.0, chat_messages=3, think=0
            )

    report = asyncio.run(go())
    main._MEM_DAILY_EVENTS.clear()

    assert report["endpoints"]["chat"]["n"] <= 3 and len(calls) <= 3, "toplam yapay zekâ mesajı sınırı aşılmaz"


def test_each_virtual_user_gets_its_own_forwarded_ip_unless_disabled():
    seen: list = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append((request.headers.get("authorization"), request.headers.get("x-forwarded-for")))
        return httpx.Response(200, json={})

    users = [{"user_id": f"u{i}", "token": f"t{i}"} for i in range(3)]

    async def go(spoof):
        seen.clear()
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler), base_url="http://x") as client:
            await loadtest.run_load(client, users, virtual_users=3, duration=0.3, chat_messages=0, think=0, spoof_ip=spoof)
        return list(seen)

    spoofed = asyncio.run(go(True))
    by_user: dict = {}
    for auth, ip in spoofed:
        if auth:
            by_user.setdefault(auth, set()).add(ip)
    assert len(by_user) == 3 and all(len(ips) == 1 for ips in by_user.values()), "kullanıcı başına sabit IP"
    assert len({next(iter(ips)) for ips in by_user.values()}) == 3, "kullanıcılar arasında farklı IP"

    plain = asyncio.run(go(False))
    assert {ip for auth, ip in plain if auth} == {"127.0.0.1"}


# ── Komut satırı ─────────────────────────────────────────────────────────────────────────────────

def _tokens_file(tmp_path, users=None):
    path = tmp_path / "tokens.json"
    path.write_text(json.dumps(users if users is not None else [{"user_id": "demo", "token": "x"}]), encoding="utf-8")
    return str(path)


def test_ai_cost_requires_an_explicit_flag_and_states_the_estimate(tmp_path, capsys, monkeypatch):
    monkeypatch.setattr(main, "get_supabase", lambda: None)
    tokens = _tokens_file(tmp_path)

    with pytest.raises(SystemExit, match="--allow-ai-cost"):
        asyncio.run(loadtest.amain(["run", "--tokens", tokens, "--chat-messages", "5"], transport=httpx.ASGITransport(app=main.app)))

    async def reply(**kwargs):
        return "Cevap."

    monkeypatch.setattr(rag_service, "chat_general", reply)
    code = asyncio.run(loadtest.amain(
        ["run", "--tokens", tokens, "--chat-messages", "5", "--allow-ai-cost", "--duration", "0.5", "--think", "0",
         "--users", "2", "--api", "http://t"],
        transport=httpx.ASGITransport(app=main.app),
    ))
    main._MEM_DAILY_EVENTS.clear()
    out = capsys.readouterr().out
    assert "Tahmini Gemini maliyeti: ~0.01 USD (5 mesaj)" in out and code in (0, 1)


def test_the_exit_code_reflects_the_thresholds_and_a_report_is_written(tmp_path, capsys, monkeypatch):
    monkeypatch.setattr(main, "get_supabase", lambda: None)
    tokens, report = _tokens_file(tmp_path), tmp_path / "rapor.json"
    base = ["run", "--tokens", tokens, "--duration", "0.6", "--think", "0", "--users", "2", "--api", "http://t",
            "--report", str(report)]

    lenient = asyncio.run(loadtest.amain(base + ["--p95-ms", "60000", "--health-ms", "60000"], transport=httpx.ASGITransport(app=main.app)))
    strict = asyncio.run(loadtest.amain(base + ["--p95-ms", "0"], transport=httpx.ASGITransport(app=main.app)))
    main._MEM_DAILY_EVENTS.clear()

    assert lenient == 0 and strict == 1
    saved = json.loads(report.read_text(encoding="utf-8"))
    assert saved["problems"] and "requests" in saved and "SONUÇ: KALDI" in capsys.readouterr().out


def test_an_empty_token_file_and_missing_secrets_stop_early(tmp_path, monkeypatch):
    with pytest.raises(SystemExit, match="boş"):
        asyncio.run(loadtest.amain(["run", "--tokens", _tokens_file(tmp_path, [])]))
    for name in ("SUPABASE_URL", "SUPABASE_SERVICE_KEY", "SUPABASE_JWT_SECRET"):
        monkeypatch.delenv(name, raising=False)
    with pytest.raises(SystemExit, match="SUPABASE_URL"):
        asyncio.run(loadtest.amain(["provision", "--count", "1"]))
    with pytest.raises(SystemExit, match="SUPABASE_URL"):
        asyncio.run(loadtest.amain(["cleanup"]))
