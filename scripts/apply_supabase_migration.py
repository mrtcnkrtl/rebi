#!/usr/bin/env python3
"""
Supabase'de bir SQL migrasyon dosyasını Management API ile çalıştırır.

Kimlik doğrulama (sırayla):
  1) Ortam değişkeni SUPABASE_ACCESS_TOKEN (Dashboard → Account → Access Tokens)
  2) macOS: Supabase CLI ile giriş yapılmışsa Keychain'deki "Supabase CLI" kaydı

Proje ref: backend/.env içindeki SUPABASE_URL'den çıkarılır (veya --project-ref).

Kullanım:
  python3 scripts/apply_supabase_migration.py
  python3 scripts/apply_supabase_migration.py database/migrations/foo.sql
  python3 scripts/apply_supabase_migration.py --project-ref abcdefghijklmnop
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_SQL = REPO_ROOT / "database" / "migrations" / "20260401_daily_events_and_assessment_update.sql"
ENV_FILE = REPO_ROOT / "backend" / ".env"


def load_env_file(path: Path) -> None:
    if not path.is_file():
        return
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, val = line.partition("=")
        key, val = key.strip(), val.strip().strip('"').strip("'")
        if key and key not in os.environ:
            os.environ[key] = val


def project_ref_from_url(url: str) -> str | None:
    m = re.search(r"https://([^.]+)\.supabase\.co", url.strip())
    return m.group(1) if m else None


def token_from_keychain() -> str | None:
    if sys.platform != "darwin":
        return None
    try:
        raw = subprocess.check_output(
            ["security", "find-generic-password", "-s", "Supabase CLI", "-w"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return None
    if raw.startswith("go-keyring-base64:"):
        try:
            return base64.b64decode(raw.split(":", 1)[1]).decode("utf-8")
        except (ValueError, UnicodeDecodeError):
            return None
    return raw or None


def get_access_token() -> str:
    tok = os.environ.get("SUPABASE_ACCESS_TOKEN", "").strip()
    if tok:
        return tok
    kc = token_from_keychain()
    if kc:
        return kc
    print(
        "Token bulunamadı. Şunlardan birini yapın:\n"
        "  • export SUPABASE_ACCESS_TOKEN='sbp_...'  (Supabase Dashboard → Account → Access Tokens)\n"
        "  • macOS: supabase login  (CLI oturumu Keychain'e yazılır)",
        file=sys.stderr,
    )
    sys.exit(1)


def run_query(project_ref: str, token: str, sql: str) -> tuple[int, str]:
    url = f"https://api.supabase.com/v1/projects/{project_ref}/database/query"
    body = json.dumps({"query": sql}).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=body,
        method="POST",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            # Bazı ortamlarda varsayılan Python UA Cloudflare 1010 ile bloklanıyor
            "User-Agent": "rebi-apply-supabase-migration/1.0",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            return resp.status, (resp.read().decode("utf-8") or "").strip()
    except urllib.error.HTTPError as e:
        err_body = e.read().decode("utf-8", errors="replace")
        return e.code, err_body


def main() -> None:
    parser = argparse.ArgumentParser(description="Supabase SQL migrasyonu çalıştır (Management API).")
    parser.add_argument(
        "sql_file",
        nargs="?",
        type=Path,
        default=DEFAULT_SQL,
        help=f"SQL dosyası (varsayılan: {DEFAULT_SQL.relative_to(REPO_ROOT)})",
    )
    parser.add_argument(
        "--project-ref",
        help="SUPABASE_URL yerine doğrudan proje ref (örn. eulcargzcatxdbjevkpm)",
    )
    args = parser.parse_args()

    load_env_file(ENV_FILE)

    ref = (args.project_ref or "").strip()
    if not ref:
        ref = project_ref_from_url(os.getenv("SUPABASE_URL", "")) or ""

    if not ref:
        print(
            "Project ref yok. backend/.env içinde SUPABASE_URL tanımlayın veya --project-ref verin.",
            file=sys.stderr,
        )
        sys.exit(1)

    sql_path = args.sql_file if args.sql_file.is_absolute() else (REPO_ROOT / args.sql_file).resolve()
    if not sql_path.is_file():
        print(f"Dosya bulunamadı: {sql_path}", file=sys.stderr)
        sys.exit(1)

    sql = sql_path.read_text(encoding="utf-8")
    token = get_access_token()

    status, body = run_query(ref, token, sql)
    if status in (200, 201):
        print(f"Tamam (HTTP {status}).")
        if body:
            print(body)
        return

    print(f"Hata HTTP {status}", file=sys.stderr)
    print(body[:2000] if body else "(gövde yok)", file=sys.stderr)
    sys.exit(1)


if __name__ == "__main__":
    main()
