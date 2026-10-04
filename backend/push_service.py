"""
FCM HTTP v1 üzerinden bildirim gönderimi.

Yapılandırma (`FCM_SERVICE_ACCOUNT_JSON`) yoksa gönderim atlanır; uygulamanın
geri kalanı bundan etkilenmez. Hatırlatıcı planını üreten taraf `today_plan`,
kime gönderileceğine karar veren taraf ise `/push/dispatch` uç noktasıdır.
"""

from __future__ import annotations

import json
import os
import threading
from pathlib import Path

import anyio
import httpx

from config import get_logger

log = get_logger("push")

_FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging"
_FCM_TIMEOUT = 10.0
# Bu durum kodları token'ın artık geçerli olmadığını gösterir (UNREGISTERED,
# SENDER_ID_MISMATCH); kayıt silinir.
_INVALID_TOKEN_STATUSES = frozenset({403, 404})

_credentials_lock = threading.Lock()
_credentials = None


def _service_account_info() -> dict | None:
    """Servis hesabı: ya doğrudan JSON ya da JSON dosyasının yolu."""
    raw = (os.getenv("FCM_SERVICE_ACCOUNT_JSON") or "").strip()
    if not raw:
        return None
    try:
        if raw.startswith("{"):
            return json.loads(raw)
        return json.loads(Path(raw).read_text(encoding="utf-8"))
    except Exception as e:
        log.error("FCM servis hesabı okunamadı: %s", type(e).__name__)
        return None


def push_configured() -> bool:
    return _service_account_info() is not None


def _project_id(info: dict) -> str:
    return (os.getenv("FCM_PROJECT_ID") or info.get("project_id") or "").strip()


def _access_token(info: dict) -> str:
    from google.auth.transport.requests import Request
    from google.oauth2 import service_account

    global _credentials
    with _credentials_lock:
        if _credentials is None:
            _credentials = service_account.Credentials.from_service_account_info(
                info, scopes=[_FCM_SCOPE]
            )
        if not _credentials.valid:
            _credentials.refresh(Request())
        return str(_credentials.token)


async def send_push(
    tokens: list[str],
    title: str,
    body: str,
    data: dict | None = None,
) -> dict:
    """
    Verilen cihazlara tek bildirim gönderir.

    Döner: {"status": "sent" | "skipped" | "error", "sent": int,
            "invalid_tokens": [...]} — geçersiz token'ları çağıran siler.
    """
    info = _service_account_info()
    if not info or not tokens:
        return {"status": "skipped", "sent": 0, "invalid_tokens": []}

    project = _project_id(info)
    if not project:
        log.error("FCM proje kimliği yok; gönderim atlandı.")
        return {"status": "skipped", "sent": 0, "invalid_tokens": []}

    try:
        access_token = await anyio.to_thread.run_sync(_access_token, info)
    except Exception as e:
        log.error("FCM erişim anahtarı alınamadı: %s", type(e).__name__)
        return {"status": "error", "sent": 0, "invalid_tokens": []}

    url = f"https://fcm.googleapis.com/v1/projects/{project}/messages:send"
    headers = {"Authorization": f"Bearer {access_token}"}
    payload = {k: str(v) for k, v in (data or {}).items()}
    sent = 0
    invalid: list[str] = []

    async with httpx.AsyncClient(timeout=_FCM_TIMEOUT) as client:
        for token in tokens:
            message = {
                "message": {
                    "token": token,
                    "notification": {"title": title, "body": body},
                    "data": payload,
                    "android": {"priority": "high"},
                    "apns": {"headers": {"apns-priority": "10"}},
                }
            }
            try:
                response = await client.post(url, json=message, headers=headers)
            except Exception as e:
                log.error("FCM isteği başarısız: %s", type(e).__name__)
                continue
            if response.status_code < 300:
                sent += 1
            elif response.status_code in _INVALID_TOKEN_STATUSES:
                invalid.append(token)
            else:
                log.error("FCM gönderimi reddedildi: status=%s", response.status_code)

    return {"status": "sent", "sent": sent, "invalid_tokens": invalid}
