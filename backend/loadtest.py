#!/usr/bin/env python3
"""
Rebi yük testi: sentetik kullanıcı oluşturur, gerçekçi bir kullanım karışımıyla API'yi yükler, temizler.

Kullanım (VPS'te, api konteynerinin içinden; adım adım anlatım: docs/YUK-TESTI.md):

  docker compose exec api python loadtest.py provision --count 50 --out /tmp/tokens.json
  docker compose exec api python loadtest.py run --tokens /tmp/tokens.json --duration 120 --users 50
  docker compose exec api python loadtest.py run --tokens /tmp/tokens.json --chat-messages 200 --allow-ai-cost
  docker compose exec api python loadtest.py cleanup            # önce yalnızca listeler
  docker compose exec api python loadtest.py cleanup --yes      # sentetik kullanıcıları siler

Güvenlik:
- Sentetik kullanıcılar yalnızca `loadtest+...@loadtest.invalid` e-postasıyla ve `user_metadata.loadtest=true` ile
  oluşturulur; `cleanup` yalnızca bu ikisini birden taşıyanları siler (gerçek kullanıcıya dokunamaz).
- Yapay zekâ çağrısı varsayılan olarak KAPALIDIR (`--chat-messages 0`); açmak için `--allow-ai-cost` gerekir ve
  tahmini maliyet başlamadan yazılır.
- `run`, doğrudan api konteynerine (http://127.0.0.1:8000) bağlanır; IP başına hız sınırlarına takılmamak için her
  sanal kullanıcıya ayrı bir X-Forwarded-For verir (nginx üzerinden gidilirse nginx bunu ezer).

Çıkış kodu: eşikler (p95, hata oranı) tutarsa 0, aksi hâlde 1.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import random
import secrets
import statistics
import sys
import time
import uuid
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Optional

import httpx
import jwt

EMAIL_DOMAIN = "loadtest.invalid"  # RFC 2606: gerçek bir alan adına asla çözülmez
DEFAULT_API = "http://127.0.0.1:8000"
TOKEN_TTL = timedelta(hours=6)
CHAT_COST_PER_MESSAGE_USD = 0.002  # docs/DEPLOY.md: ~3500 giriş + 350 çıkış token'ı

CHAT_QUESTIONS = [
    "Retinolü akşam mı sürmeliyim?",
    "Güneş kremini kaç saatte bir yenilemeliyim?",
    "Niasinamid ile C vitamini birlikte kullanılır mı?",
    "Cildim çok kuru, hangi içeriklere bakmalıyım?",
    "Sivilce izleri için ne önerirsin?",
    "Makyajı nasıl temizlemeliyim?",
]


def _now() -> datetime:
    return datetime.now(timezone.utc)


# ── Sentetik kullanıcılar ────────────────────────────────────────────────────────────────────────

def mint_token(user_id: str, email: str, secret: str, now: Optional[datetime] = None) -> str:
    """Supabase'in HS256 erişim anahtarına benzer, yerelde imzalanmış token (Auth hız sınırına takılmaz)."""
    issued = now or _now()
    payload = {
        "sub": user_id,
        "aud": "authenticated",
        "role": "authenticated",
        "email": email,
        "iat": int(issued.timestamp()),
        "exp": int((issued + TOKEN_TTL).timestamp()),
    }
    return jwt.encode(payload, secret, algorithm="HS256")


def is_loadtest_user(user: dict, prefix: str) -> bool:
    """Gerçek kullanıcıyı silmemek için üç koşul birden: e-posta öneki, alan adı ve meta işareti."""
    email = str(user.get("email") or "")
    meta = user.get("user_metadata") or {}
    return email.startswith(f"{prefix}+") and email.endswith(f"@{EMAIL_DOMAIN}") and meta.get("loadtest") is True


def _admin_headers(service_key: str) -> dict:
    return {"apikey": service_key, "Authorization": f"Bearer {service_key}"}


async def provision(
    sb: httpx.AsyncClient,
    api: httpx.AsyncClient,
    *,
    supabase_url: str,
    service_key: str,
    jwt_secret: str,
    count: int,
    prefix: str,
    log=print,
) -> list[dict]:
    """`count` sentetik kullanıcı: Supabase'de oluşturur, yerelde token üretir, rıza kaydını API'den yazar."""
    stamp = _now().strftime("%Y%m%d%H%M%S")
    users: list[dict] = []
    for i in range(count):
        email = f"{prefix}+{stamp}-{i}@{EMAIL_DOMAIN}"
        created = await sb.post(
            f"{supabase_url}/auth/v1/admin/users",
            headers=_admin_headers(service_key),
            json={
                "email": email,
                "password": secrets.token_urlsafe(24),
                "email_confirm": True,
                "user_metadata": {"loadtest": True},
            },
        )
        created.raise_for_status()
        user_id = created.json()["id"]
        token = mint_token(user_id, email, jwt_secret)
        auth = {"Authorization": f"Bearer {token}"}
        status = await api.get("/legal-consent/status", params={"user_id": user_id}, headers=auth)
        status.raise_for_status()
        accepted = await api.post(
            "/legal-consent/accept",
            headers=auth,
            json={
                "user_id": user_id,
                "document_version": status.json()["document_version"],
                "kvkk_accepted": True,
                "explicit_consent_accepted": True,
                "ai_processing_accepted": True,
                "location_processing_accepted": False,
                "photo_processing_accepted": False,
            },
        )
        accepted.raise_for_status()
        users.append({"user_id": user_id, "email": email, "token": token})
        if (i + 1) % 10 == 0 or i + 1 == count:
            log(f"  {i + 1}/{count} kullanıcı hazır")
    return users


async def list_loadtest_users(sb: httpx.AsyncClient, *, supabase_url: str, service_key: str, prefix: str) -> list[dict]:
    found: list[dict] = []
    page = 1
    while True:
        r = await sb.get(
            f"{supabase_url}/auth/v1/admin/users",
            headers=_admin_headers(service_key),
            params={"page": page, "per_page": 200},
        )
        r.raise_for_status()
        body = r.json()
        batch = body.get("users", []) if isinstance(body, dict) else body
        found.extend(u for u in batch if is_loadtest_user(u, prefix))
        if len(batch) < 200:
            return found
        page += 1


async def cleanup(
    sb: httpx.AsyncClient, *, supabase_url: str, service_key: str, prefix: str, delete: bool, log=print
) -> list[dict]:
    """Sentetik kullanıcıları listeler; `delete=True` ise siler (kullanıcıya bağlı tüm veri cascade ile gider)."""
    users = await list_loadtest_users(sb, supabase_url=supabase_url, service_key=service_key, prefix=prefix)
    for u in users:
        log(f"  {u['email']}")
        if delete:
            r = await sb.delete(f"{supabase_url}/auth/v1/admin/users/{u['id']}", headers=_admin_headers(service_key))
            r.raise_for_status()
    log(f"{'Silinen' if delete else 'Bulunan (silinmedi; --yes ile silinir)'}: {len(users)} sentetik kullanıcı")
    return users


# ── Yük ──────────────────────────────────────────────────────────────────────────────────────────

class Stats:
    def __init__(self) -> None:
        self.latency_ms: dict[str, list[float]] = defaultdict(list)
        self.status: dict[str, dict[str, int]] = defaultdict(lambda: defaultdict(int))
        self.errors: dict[str, int] = defaultdict(int)
        self.health_ms: list[float] = []

    def record(self, name: str, status: Optional[int], started: float) -> None:
        self.latency_ms[name].append((time.perf_counter() - started) * 1000)
        if status is None:
            self.errors[name] += 1
            self.status[name]["istisna"] += 1
        else:
            self.status[name][str(status)] += 1
            if status >= 500:
                self.errors[name] += 1


def percentile(values: list[float], p: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    k = max(0, min(len(ordered) - 1, int(round(p / 100 * (len(ordered) - 1)))))
    return ordered[k]


def summarize(stats: Stats, wall_seconds: float) -> dict:
    endpoints = {}
    for name, lat in stats.latency_ms.items():
        total = len(lat)
        codes = dict(stats.status[name])
        endpoints[name] = {
            "n": total,
            "p50_ms": round(percentile(lat, 50)),
            "p95_ms": round(percentile(lat, 95)),
            "p99_ms": round(percentile(lat, 99)),
            "max_ms": round(max(lat)),
            "errors": stats.errors[name],
            "rate_limited": codes.get("429", 0),
            "status": codes,
        }
    total = sum(e["n"] for e in endpoints.values())
    return {
        "seconds": round(wall_seconds, 1),
        "requests": total,
        "rps": round(total / wall_seconds, 1) if wall_seconds else 0,
        "error_rate": round(sum(e["errors"] for e in endpoints.values()) / total, 4) if total else 0,
        "rate_limited_rate": round(sum(e["rate_limited"] for e in endpoints.values()) / total, 4) if total else 0,
        "health_p95_ms": round(percentile(stats.health_ms, 95)),
        "health_max_ms": round(max(stats.health_ms)) if stats.health_ms else 0,
        "endpoints": endpoints,
    }


def verdict(report: dict, *, p95_ms: float, chat_p95_ms: float, max_error_rate: float, health_ms: float) -> list[str]:
    """Eşikleri aşanların listesi (boşsa test geçti)."""
    problems: list[str] = []
    for name, e in report["endpoints"].items():
        limit = chat_p95_ms if name == "chat" else p95_ms
        if e["p95_ms"] > limit:
            problems.append(f"{name}: p95 {e['p95_ms']} ms > {int(limit)} ms")
    if report["error_rate"] > max_error_rate:
        problems.append(f"hata oranı {report['error_rate']:.2%} > {max_error_rate:.2%} (5xx/istisna)")
    if report["rate_limited_rate"] > max_error_rate:
        problems.append(f"429 oranı {report['rate_limited_rate']:.2%}: hız sınırları meşru yükü reddediyor")
    if report["health_p95_ms"] > health_ms:
        problems.append(f"/health p95 {report['health_p95_ms']} ms > {int(health_ms)} ms: sunucu yük altında yanıtsız kaldı")
    return problems


def _iso_local(offset_hours: int = 3) -> str:
    return (_now() + timedelta(hours=offset_hours)).strftime("%Y-%m-%dT%H:%M:%S") + f"+{offset_hours:02d}:00"


class VirtualUser:
    """Gerçekçi bir kullanım döngüsü: uygulamayı aç, su kaydet, plana/geçmişe bak, ara sıra sohbet et."""

    def __init__(self, client: httpx.AsyncClient, user: dict, stats: Stats, chat_budget: "ChatBudget", ip: str, think: float):
        self.client, self.user, self.stats, self.chat_budget, self.think = client, user, stats, chat_budget, think
        self.uid = user["user_id"]
        self.headers = {"Authorization": f"Bearer {user['token']}", "X-Forwarded-For": ip}

    async def _call(self, name: str, method: str, path: str, **kwargs) -> None:
        started = time.perf_counter()
        status: Optional[int] = None
        try:
            r = await self.client.request(method, path, headers=self.headers, **kwargs)
            status = r.status_code
        except Exception:
            status = None
        self.stats.record(name, status, started)

    async def open_app(self) -> None:
        await self._call("snapshot", "GET", "/me/snapshot", params={"user_id": self.uid, "utc_offset_minutes": 180})
        await self._call("today_plan", "GET", "/today/plan", params={"user_id": self.uid, "utc_offset_minutes": 180})

    async def log_water(self) -> None:
        await self._call(
            "ingest", "POST", "/daily_tracking/ingest",
            json={"user_id": self.uid, "type": "water_intake", "payload": {"ml": 200},
                  "timestamp": _iso_local(), "client_event_id": str(uuid.uuid4())},
        )

    async def history(self) -> None:
        await self._call("history", "GET", "/me/history", params={"user_id": self.uid, "days": 30, "utc_offset_minutes": 180})

    async def chat(self) -> bool:
        if not await self.chat_budget.take():
            return False
        await self._call(
            "chat", "POST", "/chat_general",
            json={"user_id": self.uid, "message": random.choice(CHAT_QUESTIONS), "history": [], "utc_offset_minutes": 180},
        )
        return True

    async def loop(self, until: float) -> None:
        actions = [(self.open_app, 20), (self.log_water, 45), (self.history, 10), (self.open_app, 15)]
        if self.chat_budget.enabled:
            actions.append((self.chat, 10))
        while time.perf_counter() < until:
            action = random.choices([a for a, _ in actions], weights=[w for _, w in actions])[0]
            await action()
            await asyncio.sleep(random.uniform(0.2, 1.0) * self.think)


class ChatBudget:
    """Toplam sohbet mesajı sayısı (yapay zekâ maliyetini sınırlar); tüm sanal kullanıcılar paylaşır."""

    def __init__(self, total: int) -> None:
        self.remaining, self.enabled = total, total > 0
        self._lock = asyncio.Lock()

    async def take(self) -> bool:
        async with self._lock:
            if self.remaining <= 0:
                return False
            self.remaining -= 1
            return True


async def _probe_health(client: httpx.AsyncClient, stats: Stats, stop: asyncio.Event) -> None:
    """Yük sürerken /health'i yoklar: olay döngüsü kilitlenirse bu gecikme artar."""
    while not stop.is_set():
        started = time.perf_counter()
        try:
            await client.get("/health")
            stats.health_ms.append((time.perf_counter() - started) * 1000)
        except Exception:
            stats.health_ms.append(30_000.0)
        try:
            await asyncio.wait_for(stop.wait(), timeout=2.0)
        except asyncio.TimeoutError:
            pass


async def run_load(
    client: httpx.AsyncClient,
    users: list[dict],
    *,
    virtual_users: int,
    duration: float,
    chat_messages: int,
    think: float = 1.0,
    spoof_ip: bool = True,
) -> dict:
    stats, budget = Stats(), ChatBudget(chat_messages)
    stop = asyncio.Event()
    prober = asyncio.create_task(_probe_health(client, stats, stop))
    started = time.perf_counter()
    until = started + duration
    vus = []
    for i in range(virtual_users):
        ip = f"10.{(i // 250) % 250}.{i % 250}.{random.randint(1, 250)}" if spoof_ip else "127.0.0.1"
        vus.append(VirtualUser(client, users[i % len(users)], stats, budget, ip, think))
    await asyncio.gather(*(vu.loop(until) for vu in vus))
    wall = time.perf_counter() - started
    stop.set()
    await prober
    return summarize(stats, wall)


def format_report(report: dict, problems: list[str]) -> str:
    lines = [
        f"Süre {report['seconds']} sn · istek {report['requests']} · {report['rps']} istek/sn · "
        f"hata {report['error_rate']:.2%} · 429 {report['rate_limited_rate']:.2%} · "
        f"/health p95 {report['health_p95_ms']} ms (maks {report['health_max_ms']} ms)",
        f"{'uç':<14}{'n':>7}{'p50':>8}{'p95':>8}{'p99':>8}{'maks':>8}{'5xx':>6}{'429':>6}",
    ]
    for name, e in sorted(report["endpoints"].items()):
        lines.append(f"{name:<14}{e['n']:>7}{e['p50_ms']:>8}{e['p95_ms']:>8}{e['p99_ms']:>8}{e['max_ms']:>8}{e['errors']:>6}{e['rate_limited']:>6}")
    lines.append("SONUÇ: " + ("GEÇTİ" if not problems else "KALDI"))
    lines += [f"  - {p}" for p in problems]
    return "\n".join(lines)


# ── Komut satırı ─────────────────────────────────────────────────────────────────────────────────

def _env(name: str) -> str:
    value = os.getenv(name, "").strip()
    if not value:
        raise SystemExit(f"{name} tanımlı değil (api konteynerinde deploy/.env.api'den gelir).")
    return value


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)

    pv = sub.add_parser("provision", help="sentetik kullanıcı oluştur ve token dosyası yaz")
    pv.add_argument("--count", type=int, default=50)
    pv.add_argument("--out", default="loadtest-tokens.json")
    pv.add_argument("--api", default=DEFAULT_API)
    pv.add_argument("--prefix", default="loadtest")

    rn = sub.add_parser("run", help="yük uygula")
    rn.add_argument("--tokens", required=True)
    rn.add_argument("--api", default=DEFAULT_API)
    rn.add_argument("--users", type=int, default=20, help="eşzamanlı sanal kullanıcı")
    rn.add_argument("--duration", type=float, default=60.0, help="saniye")
    rn.add_argument("--think", type=float, default=1.0, help="bekleme çarpanı (0 = bekleme yok)")
    rn.add_argument("--chat-messages", type=int, default=0, help="toplam sohbet mesajı (yapay zekâ maliyeti!)")
    rn.add_argument("--allow-ai-cost", action="store_true", help="sohbet mesajlarını açmak için zorunlu")
    rn.add_argument("--no-spoof-ip", action="store_true", help="X-Forwarded-For gönderme")
    rn.add_argument("--p95-ms", type=float, default=500.0)
    rn.add_argument("--chat-p95-ms", type=float, default=8000.0)
    rn.add_argument("--health-ms", type=float, default=500.0)
    rn.add_argument("--max-error-rate", type=float, default=0.01)
    rn.add_argument("--report", default="", help="JSON raporu yazılacak dosya")

    cl = sub.add_parser("cleanup", help="sentetik kullanıcıları listele / sil")
    cl.add_argument("--yes", action="store_true", help="gerçekten sil (yoksa yalnızca listeler)")
    cl.add_argument("--prefix", default="loadtest")
    return p


async def amain(argv: Optional[list[str]] = None, *, transport: Optional[httpx.AsyncBaseTransport] = None) -> int:
    args = build_parser().parse_args(argv)

    if args.cmd == "provision":
        supabase_url = _env("SUPABASE_URL").rstrip("/")
        async with httpx.AsyncClient(timeout=30) as sb, httpx.AsyncClient(base_url=args.api, timeout=30, transport=transport) as api:
            users = await provision(
                sb, api, supabase_url=supabase_url, service_key=_env("SUPABASE_SERVICE_KEY"),
                jwt_secret=_env("SUPABASE_JWT_SECRET"), count=args.count, prefix=args.prefix,
            )
        out = Path(args.out)
        out.write_text(json.dumps(users, indent=2), encoding="utf-8")
        try:
            out.chmod(0o600)  # token'lar hassas
        except OSError:
            pass
        print(f"{len(users)} kullanıcı hazır → {out}. İş bitince: python loadtest.py cleanup --yes")
        return 0

    if args.cmd == "cleanup":
        supabase_url = _env("SUPABASE_URL").rstrip("/")
        async with httpx.AsyncClient(timeout=30) as sb:
            await cleanup(sb, supabase_url=supabase_url, service_key=_env("SUPABASE_SERVICE_KEY"), prefix=args.prefix, delete=args.yes)
        return 0

    users = json.loads(Path(args.tokens).read_text(encoding="utf-8"))
    if not users:
        raise SystemExit("Token dosyası boş.")
    if args.chat_messages > 0:
        if not args.allow_ai_cost:
            raise SystemExit(f"--chat-messages {args.chat_messages} yapay zekâ çağrısı demek; onaylamak için --allow-ai-cost ekleyin.")
        print(f"Tahmini Gemini maliyeti: ~{args.chat_messages * CHAT_COST_PER_MESSAGE_USD:.2f} USD ({args.chat_messages} mesaj)")
    async with httpx.AsyncClient(base_url=args.api, timeout=60, transport=transport,
                                 limits=httpx.Limits(max_connections=max(50, args.users * 2))) as client:
        report = await run_load(
            client, users, virtual_users=args.users, duration=args.duration, chat_messages=args.chat_messages,
            think=args.think, spoof_ip=not args.no_spoof_ip,
        )
    problems = verdict(report, p95_ms=args.p95_ms, chat_p95_ms=args.chat_p95_ms,
                       max_error_rate=args.max_error_rate, health_ms=args.health_ms)
    print(format_report(report, problems))
    if args.report:
        Path(args.report).write_text(json.dumps({**report, "problems": problems}, indent=2, ensure_ascii=False), encoding="utf-8")
    return 0 if not problems else 1


def main() -> int:
    return asyncio.run(amain())


if __name__ == "__main__":
    sys.exit(main())
