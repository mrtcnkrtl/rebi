"""KVKK m.12 veri ihlali kaydı.

Kurula veya ilgili kişiye bildirim bu modülden gönderilmez. Kayıt, öğrenme anından
itibaren 72 saatlik son süreyi sabitler ve kritik log üretir. Bildirimi veri sorumlusu yapar.
"""

from __future__ import annotations

import logging
from datetime import datetime, timedelta, timezone

log = logging.getLogger("privacy_incident")

NOTIFY_WITHIN = timedelta(hours=72)


def parse_discovered_at(raw: str | None) -> datetime:
    if not raw or not str(raw).strip():
        return datetime.now(timezone.utc)
    text = str(raw).strip().replace("Z", "+00:00")
    parsed = datetime.fromisoformat(text)
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def record_privacy_incident(supabase, summary: str, discovered_at: datetime) -> dict:
    text = (summary or "").strip()
    if len(text) < 8:
        raise ValueError("summary")
    deadline = discovered_at.astimezone(timezone.utc) + NOTIFY_WITHIN
    row = {
        "summary": text,
        "discovered_at": discovered_at.astimezone(timezone.utc).isoformat(),
        "notify_kurul_by": deadline.isoformat(),
    }
    log.critical(
        "KVKK veri ihlali kaydı. Kurula bildirim son zamanı: %s. İlgili kişilere bildirim bu saatten önce değerlendirilmeli.",
        deadline.isoformat(),
    )
    inserted = supabase.table("privacy_incidents").insert(row).execute()
    saved = inserted.data[0] if getattr(inserted, "data", None) else row
    return saved
