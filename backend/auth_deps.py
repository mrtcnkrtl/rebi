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
