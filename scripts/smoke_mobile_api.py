#!/usr/bin/env python3
"""
Mobilin dayandığı uçları CANLI sunucuya karşı dener ve yanıtları `contract/*.json` ile karşılaştırır.

Kullanım (özel bir TEST hesabıyla; gerçek müşteri hesabıyla çalıştırmayın):

  # 1) Oturum anahtarını ver (iki yol):
  export REBI_SMOKE_TOKEN='eyJ...'                       # test hesabının access_token'ı
  # ya da e-posta + parola ile (Supabase URL ve anon anahtar gerekir):
  export SUPABASE_URL=https://xxxx.supabase.co SUPABASE_ANON_KEY=eyJ... REBI_SMOKE_PASSWORD='...'
  python3 scripts/smoke_mobile_api.py --email test@ornek.com

  # 2) Salt okunur kontrol:
  python3 scripts/smoke_mobile_api.py --api https://rebiovil.com/api

  # 3) Yazma yolunu da dene (su +10 ml sonra -10 ml, hatırlatıcı ayarını aynı değerle kaydet):
  python3 scripts/smoke_mobile_api.py --write

Çıkış kodu: tüm kontroller geçtiyse 0, aksi hâlde 1. Yalnızca standart kütüphane kullanır.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from pathlib import Path

CONTRACT_DIR = Path(__file__).resolve().parent.parent / "contract"
DEFAULT_API = "https://rebiovil.com/api"

_GREEN, _RED, _YELLOW, _RESET = "\033[32m", "\033[31m", "\033[33m", "\033[0m"
if not sys.stdout.isatty():
    _GREEN = _RED = _YELLOW = _RESET = ""


# ── Şekil karşılaştırması (backend/tests/test_contract.py ile aynı kural) ─────

def _kind(value) -> str:
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "bool"
    if isinstance(value, (int, float)):
        return "number"
    if isinstance(value, str):
        return "string"
    if isinstance(value, list):
        return "list"
    return "object"


def shape_problems(actual, expected, path: str = "$") -> list[str]:
    if expected is None:
        return []
    if actual is None:
        return [f"{path}: {_kind(expected)} bekleniyordu, null geldi"]
    if _kind(actual) != _kind(expected):
        return [f"{path}: {_kind(expected)} bekleniyordu, {_kind(actual)} geldi"]
    problems: list[str] = []
    if isinstance(expected, dict):
        for key, sub in expected.items():
            if key not in actual:
                problems.append(f"{path}.{key}: alan yok")
            else:
                problems += shape_problems(actual[key], sub, f"{path}.{key}")
    elif isinstance(expected, list) and expected and actual:
        problems += shape_problems(actual[0], expected[0], f"{path}[0]")
    return problems


# ── HTTP ────────────────────────────────────────────────────────────────────

def call(method: str, url: str, token: str | None = None, body: dict | None = None, timeout: int = 30):
    data = json.dumps(body).encode("utf-8") if body is not None else None
    headers = {"Content-Type": "application/json", "User-Agent": "rebi-smoke/1.0"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(url, data=data, method=method, headers=headers)
    started = time.monotonic()
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            raw, status = response.read(), response.status
    except urllib.error.HTTPError as e:
        raw, status = e.read(), e.code
    except Exception as e:  # ağ, DNS, zaman aşımı
        return 0, {"error": type(e).__name__}, time.monotonic() - started
    try:
        parsed = json.loads(raw.decode("utf-8") or "{}")
    except ValueError:
        parsed = {}
    return status, parsed, time.monotonic() - started


def user_id_from_token(token: str) -> str:
    """JWT `sub` alanı (imza doğrulanmaz; yalnızca user_id'yi bulmak için)."""
    payload = token.split(".")[1]
    payload += "=" * (-len(payload) % 4)
    return json.loads(base64.urlsafe_b64decode(payload))["sub"]


def login(email: str) -> str:
    base = os.environ.get("SUPABASE_URL", "").rstrip("/")
    anon = os.environ.get("SUPABASE_ANON_KEY", "")
    password = os.environ.get("REBI_SMOKE_PASSWORD", "")
    if not (base and anon and password):
        sys.exit("--email için SUPABASE_URL, SUPABASE_ANON_KEY ve REBI_SMOKE_PASSWORD ortam değişkenleri gerekir.")
    request = urllib.request.Request(
        f"{base}/auth/v1/token?grant_type=password",
        data=json.dumps({"email": email, "password": password}).encode("utf-8"),
        method="POST",
        headers={"apikey": anon, "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.loads(response.read())["access_token"]
    except urllib.error.HTTPError as e:
        sys.exit(f"Giriş başarısız: HTTP {e.code}")


# ── Kontroller ──────────────────────────────────────────────────────────────

class Report:
    def __init__(self) -> None:
        self.failed = 0

    def ok(self, name: str, detail: str = "") -> None:
        print(f"  {_GREEN}GEÇTİ{_RESET}  {name}" + (f"  {detail}" if detail else ""))

    def fail(self, name: str, detail: str) -> None:
        self.failed += 1
        print(f"  {_RED}KALDI{_RESET}  {name}\n         {detail}")

    def warn(self, name: str, detail: str) -> None:
        print(f"  {_YELLOW}UYARI{_RESET}  {name}  {detail}")


def contract_check(report: Report, name: str, label: str, status: int, body, seconds: float) -> None:
    if status != 200:
        report.fail(label, f"HTTP {status}: {str(body)[:200]}")
        return
    expected = json.loads((CONTRACT_DIR / f"{name}.json").read_text(encoding="utf-8"))
    problems = shape_problems(body, expected)
    if problems:
        report.fail(label, "sözleşme uyuşmuyor: " + "; ".join(problems[:5]))
    else:
        report.ok(label, f"({seconds * 1000:.0f} ms)")


def run(api: str, token: str, write: bool) -> int:
    report = Report()
    uid = user_id_from_token(token)
    q = urllib.parse.urlencode
    offset = -time.timezone // 60 if not time.daylight else -time.altzone // 60

    print(f"API: {api}\nKullanıcı: {uid}\n")

    print("Sunucu")
    status, health, _ = call("GET", f"{api}/health")
    if status != 200 or health.get("status") != "ok":
        report.fail("/health", f"HTTP {status}: {health}")
    else:
        report.ok("/health", f"db_schema={health.get('db_schema')} push={health.get('push')}")
        if health.get("db_schema") not in ("ok",):
            report.warn("db_schema", f"'{health.get('db_schema')}': yeni migration'lar uygulanmamış olabilir")
        if "push_dispatch" not in health:
            report.warn("push_dispatch", "/health'te yok: sunucu eski sürümde (mobil için güncel backend dağıtılmamış)")
        elif health.get("push") == "configured" and not health.get("push_dispatch"):
            report.warn("push_dispatch", "FCM açık ama henüz dağıtım turu çalışmamış (push-cron çalışıyor mu?)")

    print("\nOkuma uçları (sözleşmeye karşı)")
    for name, label, path, params in (
        ("me_snapshot", "GET /me/snapshot", "/me/snapshot", {"user_id": uid, "utc_offset_minutes": offset}),
        ("today_plan", "GET /today/plan", "/today/plan", {"user_id": uid, "utc_offset_minutes": offset}),
        ("reminder_settings", "GET /me/reminder-settings", "/me/reminder-settings", {"user_id": uid}),
        ("me_profile", "GET /me/profile", "/me/profile", {"user_id": uid}),
        ("me_history", "GET /me/history", "/me/history", {"user_id": uid, "days": 7, "utc_offset_minutes": offset}),
    ):
        status, body, seconds = call("GET", f"{api}{path}?{q(params)}", token)
        contract_check(report, name, label, status, body, seconds)
        if name == "today_plan" and status == 200 and body.get("weather_source") == "default":
            report.warn("hava", "weather_source=default: konum/hava alınamadı (konum izni yoksa normal)")

    for label, path, params in (
        ("GET /chat/history", "/chat/history", {"user_id": uid, "surface": "general", "limit": 1}),
        ("GET /chat_usage", "/chat_usage", {"user_id": uid}),
    ):
        status, body, seconds = call("GET", f"{api}{path}?{q(params)}", token)
        if status == 200:
            report.ok(label, f"({seconds * 1000:.0f} ms)")
        else:
            report.fail(label, f"HTTP {status}: {str(body)[:200]}")

    print("\nYetkilendirme")
    status, _, _ = call("GET", f"{api}/me/snapshot?{q({'user_id': uid})}")
    report.ok("tokensız istek reddedilir", f"(HTTP {status})") if status in (401, 403) else report.fail(
        "tokensız istek reddedilir", f"HTTP {status} geldi; 401/403 beklenirdi"
    )
    other = str(uuid.uuid4())
    status, _, _ = call("GET", f"{api}/me/snapshot?{q({'user_id': other})}", token)
    report.ok("başkasının verisi reddedilir", f"(HTTP {status})") if status in (401, 403) else report.fail(
        "başkasının verisi reddedilir", f"HTTP {status} geldi; 401/403 beklenirdi"
    )

    if write:
        print("\nYazma yolu (su +10 ml sonra -10 ml)")
        stamp = f"smoke-{int(time.time())}"
        status, before, _ = call("GET", f"{api}/today/plan?{q({'user_id': uid, 'utc_offset_minutes': offset})}", token)
        base_ml = before.get("progress", {}).get("water_ml_total") if status == 200 else None
        if base_ml is None:
            report.fail("başlangıç su değeri", f"HTTP {status}")
        else:
            for suffix, ml in (("a", 10), ("b", -10)):
                status, body, _ = call(
                    "POST", f"{api}/daily_tracking/ingest", token,
                    {"user_id": uid, "type": "water_intake", "payload": {"ml": ml},
                     "client_event_id": f"{stamp}-{suffix}", "source": "smoke"},
                )
                expected = base_ml + (10 if suffix == "a" else 0)
                got = (body.get("aggregated") or {}).get("water_ml_total") if status == 200 else None
                if got == expected:
                    report.ok(f"POST /daily_tracking/ingest ({ml:+d} ml)", f"→ toplam {got} ml")
                else:
                    report.fail(f"POST /daily_tracking/ingest ({ml:+d} ml)", f"HTTP {status}, toplam {got}, beklenen {expected}")
            # Aynı olay yeniden gönderilirse (çevrimdışı kuyruk) ikinci kez sayılmamalı.
            status, body, _ = call(
                "POST", f"{api}/daily_tracking/ingest", token,
                {"user_id": uid, "type": "water_intake", "payload": {"ml": -10},
                 "client_event_id": f"{stamp}-b", "source": "smoke"},
            )
            got = (body.get("aggregated") or {}).get("water_ml_total") if status == 200 else None
            if got == base_ml:
                report.ok("aynı olay tekrar gönderilince çift sayılmaz")
            else:
                report.fail("aynı olay tekrar gönderilince çift sayılmaz", f"toplam {got}, beklenen {base_ml}")

        status, current, _ = call("GET", f"{api}/me/reminder-settings?{q({'user_id': uid})}", token)
        if status == 200:
            settings = current["settings"]
            status, saved, _ = call(
                "PUT", f"{api}/me/reminder-settings", token, {"user_id": uid, **{k: v for k, v in settings.items()}}
            )
            if status == 200 and saved.get("settings") == settings:
                report.ok("PUT /me/reminder-settings (aynı değerle)")
            else:
                report.fail("PUT /me/reminder-settings", f"HTTP {status}: {str(saved)[:200]}")
        else:
            report.fail("PUT /me/reminder-settings", f"önce okunamadı: HTTP {status}")

    print()
    if report.failed:
        print(f"{_RED}{report.failed} kontrol kaldı.{_RESET}")
        return 1
    print(f"{_GREEN}Tüm kontroller geçti.{_RESET}")
    return 0


def main() -> None:
    parser = argparse.ArgumentParser(description="Mobil API duman testi (canlı sunucuya karşı).")
    parser.add_argument("--api", default=os.environ.get("REBI_API_URL", DEFAULT_API), help=f"API kökü (varsayılan {DEFAULT_API})")
    parser.add_argument("--email", help="Test hesabının e-postası (REBI_SMOKE_TOKEN yoksa giriş için)")
    parser.add_argument("--write", action="store_true", help="Yazma yolunu da dene (test hesabıyla kullanın)")
    args = parser.parse_args()

    token = os.environ.get("REBI_SMOKE_TOKEN", "").strip()
    if not token and args.email:
        token = login(args.email)
    if not token:
        sys.exit("REBI_SMOKE_TOKEN (ya da --email + SUPABASE_* ortam değişkenleri) gerekli. Ayrıntı: dosyanın başı.")
    sys.exit(run(args.api.rstrip("/"), token, args.write))


if __name__ == "__main__":
    main()
