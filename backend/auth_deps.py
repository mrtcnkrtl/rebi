"""
Supabase kullanıcı JWT doğrulaması (HS256).

SUPABASE_JWT_SECRET tanımlıysa, korumalı uçlarda Authorization: Bearer ile
token içindeki sub, istekteki user_id ile eşleşmeli.

Geliştirme / demo: API_JWT_BYPASS_USER_IDS (virgüllü) bu user_id'ler için JWT istenmez.
Üretimde bu listeyi boş bırakın.
"""

from __future__ import annotations

import os
import jwt
from fastapi import HTTPException, Request


def _jwt_secret() -> str:
    return os.getenv("SUPABASE_JWT_SECRET", "").strip()


def _bypass_user_ids() -> frozenset[str]:
    raw = os.getenv(
        "API_JWT_BYPASS_USER_IDS",
        "00000000-0000-4000-8000-000000000001,demo,demo-user-id",
    )
    return frozenset(x.strip() for x in raw.split(",") if x.strip())


def jwt_auth_enabled() -> bool:
    return bool(_jwt_secret())


def enforce_supabase_user(request: Request, user_id: str) -> None:
    """JWT zorunluluğu açıksa Bearer token ve sub == user_id kontrolü."""
    if not jwt_auth_enabled():
        return
    uid = (user_id or "").strip()
    if uid in _bypass_user_ids():
        return

    auth = request.headers.get("Authorization") or request.headers.get("authorization") or ""
    if not auth.startswith("Bearer "):
        raise HTTPException(
            status_code=401,
            detail="Oturum gerekli: Authorization: Bearer <access_token>",
        )
    token = auth[7:].strip()
    if not token:
        raise HTTPException(status_code=401, detail="Geçersiz token")

    secret = _jwt_secret()
    try:
        payload = jwt.decode(
            token,
            secret,
            algorithms=["HS256"],
            audience="authenticated",
            leeway=10,
        )
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Oturum süresi doldu, yeniden giriş yapın")
    except jwt.InvalidTokenError:
        try:
            payload = jwt.decode(
                token,
                secret,
                algorithms=["HS256"],
                options={"verify_aud": False},
                leeway=10,
            )
        except jwt.InvalidTokenError:
            raise HTTPException(status_code=401, detail="Geçersiz oturum token'ı")

    sub = str(payload.get("sub") or "")
    if not sub or sub != str(user_id):
        raise HTTPException(status_code=403, detail="Token ile user_id eşleşmiyor")


def _rebi_plus_user_ids_env() -> frozenset[str]:
    raw = os.getenv("REBI_PLUS_USER_IDS", "").strip()
    if not raw:
        return frozenset()
    return frozenset(x.strip() for x in raw.split(",") if x.strip())


def decode_supabase_jwt_payload(request: Request) -> dict | None:
    """Bearer token varsa decode eder; hata olursa None."""
    if not jwt_auth_enabled():
        return None
    auth = request.headers.get("Authorization") or request.headers.get("authorization") or ""
    if not auth.startswith("Bearer "):
        return None
    token = auth[7:].strip()
    if not token:
        return None
    secret = _jwt_secret()
    try:
        return jwt.decode(
            token,
            secret,
            algorithms=["HS256"],
            audience="authenticated",
            leeway=10,
        )
    except jwt.ExpiredSignatureError:
        return None
    except jwt.InvalidTokenError:
        try:
            return jwt.decode(
                token,
                secret,
                algorithms=["HS256"],
                options={"verify_aud": False},
                leeway=10,
            )
        except jwt.InvalidTokenError:
            return None


def user_is_rebi_plus(request: Request, user_id: str) -> bool:
    """
    Rebi Plus: JWT user_metadata / app_metadata veya REBI_PLUS_USER_IDS.
    JWT kapalıyken (lokal geliştirme) herkes Plus sayılır — kota uygulanmaz.
    """
    if not jwt_auth_enabled():
        return True
    uid = (user_id or "").strip()
    if uid in _bypass_user_ids():
        return True
    if uid in _rebi_plus_user_ids_env():
        return True
    payload = decode_supabase_jwt_payload(request)
    if not payload:
        return False
    for meta in (payload.get("user_metadata") or {}, payload.get("app_metadata") or {}):
        if meta.get("rebi_plus") is True:
            return True
        if str(meta.get("subscription_tier", "")).lower() in ("plus", "pro", "premium"):
            return True
    return False
