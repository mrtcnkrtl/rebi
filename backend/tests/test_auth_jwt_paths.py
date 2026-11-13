"""JWT doğrulama yolları: `kid` başlığı, JWKS hataları ve açıklamasız 500'ün önlenmesi.

Supabase "JWT Signing Keys" açıkken eski paylaşılan sırla (HS256) imzalanan token'lara da `kid` koyar. Eskiden `kid`
görünce JWKS'e gidiliyor, anahtar bulunamayınca PyJWT'nin `PyJWKClientError`'ı yakalanmıyor ve istek (ör. giriş sonrası
ilk çağrı olan rıza kaydı) açıklamasız `500 Internal Server Error` ile düşüyordu.
"""

from __future__ import annotations

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import ec
from fastapi import HTTPException, Request

import auth_deps
from auth_deps import enforce_supabase_user, user_is_rebi_plus

USER_ID = "11111111-1111-4111-8111-111111111111"
SECRET = "test-secret-at-least-32-bytes-long"
KID = "cc5b9aff-0d7d-4c92-a063-4fa11a1b3763"


def _request(token: str | None = None) -> Request:
    headers = []
    if token:
        headers.append((b"authorization", f"Bearer {token}".encode()))
    return Request({"type": "http", "method": "POST", "path": "/", "headers": headers})


class _FakeSigningKey:
    def __init__(self, key):
        self.key = key


class _FakeJwksClient:
    """`PyJWKClient` yerine: bilinen `kid` için anahtar verir, bilinmeyende gerçek PyJWT hatasını fırlatır."""

    def __init__(self, keys: dict | None = None, error: Exception | None = None):
        self._keys = keys or {}
        self._error = error

    def get_signing_key_from_jwt(self, token: str):
        if self._error is not None:
            raise self._error
        kid = jwt.get_unverified_header(token).get("kid")
        if kid not in self._keys:
            raise jwt.PyJWKClientError(f'Unable to find a signing key that matches: "{kid}"')
        return _FakeSigningKey(self._keys[kid])


@pytest.fixture(autouse=True)
def _env(monkeypatch):
    monkeypatch.setenv("SUPABASE_JWT_SECRET", SECRET)
    monkeypatch.setenv("SUPABASE_URL", "https://example.supabase.co")
    monkeypatch.delenv("API_ALLOW_INSECURE_AUTH", raising=False)
    monkeypatch.delenv("API_JWT_BYPASS_USER_IDS", raising=False)
    monkeypatch.delenv("REBI_PLUS_USER_IDS", raising=False)


def _use_jwks(monkeypatch, client: _FakeJwksClient) -> None:
    monkeypatch.setattr(auth_deps, "_get_jwks_client", lambda: client)


def test_hs256_token_with_kid_is_verified_with_the_secret_not_jwks(monkeypatch):
    """Asıl hata: HS256 + `kid` token'ı JWKS'e gidip 500 oluyordu."""
    _use_jwks(monkeypatch, _FakeJwksClient(error=jwt.PyJWKClientError("kid JWKS'te yok")))
    token = jwt.encode({"sub": USER_ID, "aud": "authenticated"}, SECRET, algorithm="HS256", headers={"kid": "legacy-secret-id"})

    enforce_supabase_user(_request(token), USER_ID)


def test_es256_token_is_verified_with_jwks(monkeypatch):
    private = ec.generate_private_key(ec.SECP256R1())
    _use_jwks(monkeypatch, _FakeJwksClient({KID: private.public_key()}))
    token = jwt.encode({"sub": USER_ID, "aud": "authenticated"}, private, algorithm="ES256", headers={"kid": KID})

    enforce_supabase_user(_request(token), USER_ID)

    with pytest.raises(HTTPException) as exc:
        enforce_supabase_user(_request(token), "22222222-2222-4222-8222-222222222222")
    assert exc.value.status_code == 403


def test_es256_token_with_unknown_kid_is_401_not_500(monkeypatch):
    private = ec.generate_private_key(ec.SECP256R1())
    _use_jwks(monkeypatch, _FakeJwksClient({KID: private.public_key()}))
    token = jwt.encode({"sub": USER_ID, "aud": "authenticated"}, private, algorithm="ES256", headers={"kid": "baska-anahtar"})

    with pytest.raises(HTTPException) as exc:
        enforce_supabase_user(_request(token), USER_ID)

    assert exc.value.status_code == 401
    assert "Geçersiz" in exc.value.detail


def test_es256_token_with_bad_signature_is_401(monkeypatch):
    real = ec.generate_private_key(ec.SECP256R1())
    attacker = ec.generate_private_key(ec.SECP256R1())
    _use_jwks(monkeypatch, _FakeJwksClient({KID: real.public_key()}))
    token = jwt.encode({"sub": USER_ID, "aud": "authenticated"}, attacker, algorithm="ES256", headers={"kid": KID})

    with pytest.raises(HTTPException) as exc:
        enforce_supabase_user(_request(token), USER_ID)

    assert exc.value.status_code == 401


def test_jwks_unreachable_is_503_not_a_forced_logout(monkeypatch):
    _use_jwks(monkeypatch, _FakeJwksClient(error=jwt.PyJWKClientConnectionError("Fail to fetch data from the url")))
    private = ec.generate_private_key(ec.SECP256R1())
    token = jwt.encode({"sub": USER_ID, "aud": "authenticated"}, private, algorithm="ES256", headers={"kid": KID})

    with pytest.raises(HTTPException) as exc:
        enforce_supabase_user(_request(token), USER_ID)

    assert exc.value.status_code == 503


def test_expired_token_still_says_session_expired(monkeypatch):
    token = jwt.encode({"sub": USER_ID, "aud": "authenticated", "exp": 1}, SECRET, algorithm="HS256")

    with pytest.raises(HTTPException) as exc:
        enforce_supabase_user(_request(token), USER_ID)

    assert exc.value.status_code == 401
    assert "süresi doldu" in exc.value.detail


def test_plus_check_never_raises_on_unknown_kid(monkeypatch):
    private = ec.generate_private_key(ec.SECP256R1())
    _use_jwks(monkeypatch, _FakeJwksClient({KID: private.public_key()}))
    token = jwt.encode({"sub": USER_ID, "aud": "authenticated"}, private, algorithm="ES256", headers={"kid": "baska-anahtar"})

    assert user_is_rebi_plus(_request(token), USER_ID) is False
