"""
Supabase kullanıcı JWT doğrulaması.

Korumalı uçlar varsayılan olarak fail-closed çalışır. Doğrulama kaynağı:
  - SUPABASE_JWT_SECRET ile HS256 (eski anon/service ve legacy user token)
  - SUPABASE_URL üzerindeki JWKS ile ES256/RS256 (yeni imza anahtarları)

İkisi de yoksa istek reddedilir. Yalnızca yerel geliştirmede açıkça
API_ALLOW_INSECURE_AUTH=1 verilerek JWT'siz çalışmaya izin verilebilir.
"""

from __future__ import annotations

import os
import jwt
from fastapi import HTTPException, Request

_jwks_client = None
_jwks_client_uri = ""


def _jwt_secret() -> str:
    return os.getenv("SUPABASE_JWT_SECRET", "").strip()


def _supabase_url() -> str:
    return os.getenv("SUPABASE_URL", "").strip().rstrip("/")


def _jwks_uri() -> str:
    base = _supabase_url()
    if not base:
        return ""
    return f"{base}/auth/v1/.well-known/jwks.json"


def insecure_auth_allowed() -> bool:
    """JWT'siz geliştirme modunu yalnızca açık opt-in ile etkinleştir."""
    value = os.getenv("API_ALLOW_INSECURE_AUTH", "").strip().lower()
    return value in {"1", "true", "yes", "on"}


def _bypass_user_ids() -> frozenset[str]:
    raw = os.getenv("API_JWT_BYPASS_USER_IDS", "")
    return frozenset(x.strip() for x in raw.split(",") if x.strip())


def jwt_auth_enabled() -> bool:
    return bool(_jwt_secret()) or bool(_jwks_uri())


def auth_configuration_valid() -> bool:
    """JWT anahtarı / JWKS veya açık geliştirme opt-in'i bulunmalı."""
    return jwt_auth_enabled() or insecure_auth_allowed()


def _get_jwks_client():
    global _jwks_client, _jwks_client_uri
    uri = _jwks_uri()
    if not uri:
        return None
    if _jwks_client is None or _jwks_client_uri != uri:
        _jwks_client = jwt.PyJWKClient(uri, cache_jwk_set=True, lifespan=3600)
        _jwks_client_uri = uri
    return _jwks_client


def _decode_access_token(token: str) -> dict:
    """Kullanıcı access token'ını HS256 veya JWKS ile doğrula."""
    try:
        header = jwt.get_unverified_header(token)
    except jwt.InvalidTokenError:
        raise jwt.InvalidTokenError("Geçersiz token başlığı")
    alg = str(header.get("alg") or "")
    kid = header.get("kid")

    def decode(key, algorithms: list[str], verify_aud: bool) -> dict:
        kwargs = {"algorithms": algorithms, "leeway": 10}
        if verify_aud:
            kwargs["audience"] = "authenticated"
        else:
            kwargs["options"] = {"verify_aud": False}
        return jwt.decode(token, key, **kwargs)

    def decode_hs256(verify_aud: bool) -> dict:
        secret = _jwt_secret()
        if not secret:
            raise jwt.InvalidTokenError("HS256 JWT secret missing")
        return decode(secret, ["HS256"], verify_aud)

    def decode_jwks(verify_aud: bool) -> dict:
        client = _get_jwks_client()
        if client is None:
            raise jwt.InvalidTokenError("JWKS not configured")
        key = client.get_signing_key_from_jwt(token).key
        algorithms = [alg] if alg in {"ES256", "RS256", "EdDSA"} else ["ES256", "RS256"]
        return decode(key, algorithms, verify_aud)

    def try_decode(fn):
        try:
            return fn(True)
        except jwt.ExpiredSignatureError:
            raise
        except jwt.InvalidTokenError:
            return fn(False)

    use_jwks = bool(kid) or alg in {"ES256", "RS256", "EdDSA"}
    if use_jwks:
        return try_decode(decode_jwks)
    return try_decode(decode_hs256)


def enforce_supabase_user(request: Request, user_id: str) -> None:
    """Bearer token içindeki sub ile user_id eşleşmesini zorunlu tut."""
    if not jwt_auth_enabled():
        if insecure_auth_allowed():
            return
        raise HTTPException(
            status_code=503,
            detail="Sunucu kimlik doğrulaması yapılandırılmamış.",
        )
    uid = (user_id or "").strip()
    if insecure_auth_allowed() and uid in _bypass_user_ids():
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

    try:
        payload = _decode_access_token(token)
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Oturum süresi doldu, yeniden giriş yapın")
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
    try:
        return _decode_access_token(token)
    except jwt.InvalidTokenError:
        return None


def user_is_rebi_plus(request: Request, user_id: str) -> bool:
    """
    Rebi Plus: yalnızca sunucu kontrollü JWT app_metadata veya
    REBI_PLUS_USER_IDS. Kullanıcının değiştirebildiği user_metadata yetki
    kaynağı olarak kabul edilmez.
    """
    if not jwt_auth_enabled():
        return insecure_auth_allowed()
    uid = (user_id or "").strip()
    if insecure_auth_allowed() and uid in _bypass_user_ids():
        return True
    if uid in _rebi_plus_user_ids_env():
        return True
    payload = decode_supabase_jwt_payload(request)
    if not payload:
        return False
    meta = payload.get("app_metadata") or {}
    if meta.get("rebi_plus") is True:
        return True
    if str(meta.get("subscription_tier", "")).lower() in (
        "plus",
        "pro",
        "premium",
        "plus_1000",
        "plus_lite",
        "plus_basic",
        "plus_starter",
    ):
        return True
    return False


def jwt_app_metadata(request: Request) -> dict:
    """Yalnızca sunucu tarafından yönetilen app_metadata alanını döndür."""
    payload = decode_supabase_jwt_payload(request)
    if not payload:
        return {}
    return dict(payload.get("app_metadata") or {})


def user_plus_chat_is_monthly_capped(request: Request, user_id: str) -> bool:
    """
    Plus içinde aylık mesaj kotası olan paket (ör. 1000). Sınırsız Plus için False.
    Supabase app_metadata:
      - rebi_plus_chat_plan: "1000" | "capped" | "limited" | "1k"
      - subscription_tier: plus_1000, plus_lite, plus_basic, plus_starter
    Tanımsız plan: mevcut Plus kullanıcıları için sınırsız (False).
    """
    if not jwt_auth_enabled():
        return False
    if not user_is_rebi_plus(request, user_id):
        return False
    meta = jwt_app_metadata(request)
    plan = str(meta.get("rebi_plus_chat_plan") or "").strip().lower()
    if plan in ("1000", "1k", "capped", "limited"):
        return True
    tier = str(meta.get("subscription_tier") or "").strip().lower()
    if tier in ("plus_1000", "plus_lite", "plus_basic", "plus_starter"):
        return True
    return False
