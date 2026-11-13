"""Operasyon dosyaları: SQL kontrol dosyası salt okunur; belgeler yeni ayarları ve araçları anlatır."""

from __future__ import annotations

import re
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
SQL = (ROOT / "scripts" / "db_checks.sql").read_text(encoding="utf-8")


def _statements(sql: str) -> list[str]:
    no_comments = "\n".join(line for line in sql.splitlines() if not line.strip().startswith("--"))
    return [s.strip() for s in no_comments.split(";") if s.strip()]


def test_the_sql_check_file_only_reads():
    destructive = re.compile(r"\b(insert|update|delete|drop|truncate|alter|create|grant|revoke|vacuum|reindex)\b", re.I)
    statements = _statements(SQL)
    assert len(statements) >= 9
    for s in statements:
        assert re.match(r"^(select|with)\b", s, re.I), f"select ile başlamayan ifade: {s[:60]!r}"
        assert not destructive.search(s), f"yıkıcı sözcük: {s[:80]!r}"
        assert "purge_expired_rebi_data()" not in s, "retention fonksiyonu çağrılmamalı (yalnızca yorumda anılır)"


def test_the_retention_preview_uses_the_same_cutoffs_as_the_purge_function():
    migration = (ROOT / "supabase" / "migrations" / "20261004163000_push_notifications.sql").read_text(encoding="utf-8")
    for cutoff in ("180 days", "400 days", "730", "365 days", "30"):
        assert cutoff in migration and cutoff in SQL, f"{cutoff}: önizleme ile fonksiyon ayrışmış"


@pytest.mark.parametrize(
    ("path", "needles"),
    [
        ("deploy/.env.api.example", ["RATE_LIMIT_IP_MULTIPLIER", "GEMINI_DAILY_BUDGET_USD", "RETENTION_PURGE_DAILY",
                                      "INGEST_USER_LIMIT_PER_MINUTE"]),
        ("docs/DEPLOY.md", ["db_integrity", "weather_call", "gemini_budget", "RETENTION_PURGE_DAILY"]),
        ("docs/YUK-TESTI.md", ["provision", "cleanup --yes", "--allow-ai-cost", "loadtest.invalid"]),
    ],
)
def test_the_docs_mention_the_new_settings_and_tools(path, needles):
    text = (ROOT / path).read_text(encoding="utf-8")
    for needle in needles:
        assert needle in text, f"{path}: {needle} anlatılmamış"
