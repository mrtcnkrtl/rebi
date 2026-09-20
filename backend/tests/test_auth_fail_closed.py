from __future__ import annotations

import jwt
import pytest
from fastapi import HTTPException, Request

from auth_deps import enforce_supabase_user, user_is_rebi_plus


USER_ID = "11111111-1111-4111-8111-111111111111"


def _request(token: str | None = None) -> Request:
    headers = []
    if token:
        headers.append((b"authorization", f"Bearer {token}".encode()))
    return Request({"type": "http", "method": "GET", "path": "/", "headers": headers})


def test_missing_jwt_secret_blocks_protected_request(monkeypatch):
    monkeypatch.delenv("SUPABASE_JWT_SECRET", raising=False)
    monkeypatch.delenv("API_ALLOW_INSECURE_AUTH", raising=False)

    with pytest.raises(HTTPException) as exc:
        enforce_supabase_user(_request(), USER_ID)

    assert exc.value.status_code == 503


def test_explicit_development_opt_in_allows_jwtless_request(monkeypatch):
    monkeypatch.delenv("SUPABASE_JWT_SECRET", raising=False)
    monkeypatch.setenv("API_ALLOW_INSECURE_AUTH", "1")

    enforce_supabase_user(_request(), USER_ID)


def test_bypass_list_is_ignored_without_development_opt_in(monkeypatch):
    monkeypatch.setenv("SUPABASE_JWT_SECRET", "test-secret-at-least-32-bytes-long")
    monkeypatch.delenv("API_ALLOW_INSECURE_AUTH", raising=False)
    monkeypatch.setenv("API_JWT_BYPASS_USER_IDS", USER_ID)

    with pytest.raises(HTTPException) as exc:
        enforce_supabase_user(_request(), USER_ID)

    assert exc.value.status_code == 401


def test_valid_jwt_must_match_requested_user(monkeypatch):
    secret = "test-secret-at-least-32-bytes-long"
    monkeypatch.setenv("SUPABASE_JWT_SECRET", secret)
    monkeypatch.delenv("API_ALLOW_INSECURE_AUTH", raising=False)
    token = jwt.encode(
        {"sub": USER_ID, "aud": "authenticated"},
        secret,
        algorithm="HS256",
    )

    enforce_supabase_user(_request(token), USER_ID)

    with pytest.raises(HTTPException) as exc:
        enforce_supabase_user(_request(token), "22222222-2222-4222-8222-222222222222")

    assert exc.value.status_code == 403


def test_plus_entitlement_ignores_user_metadata(monkeypatch):
    secret = "test-secret-at-least-32-bytes-long"
    monkeypatch.setenv("SUPABASE_JWT_SECRET", secret)
    monkeypatch.delenv("API_ALLOW_INSECURE_AUTH", raising=False)
    monkeypatch.delenv("REBI_PLUS_USER_IDS", raising=False)

    user_controlled = jwt.encode(
        {
            "sub": USER_ID,
            "aud": "authenticated",
            "user_metadata": {"rebi_plus": True, "subscription_tier": "premium"},
            "app_metadata": {},
        },
        secret,
        algorithm="HS256",
    )
    server_controlled = jwt.encode(
        {
            "sub": USER_ID,
            "aud": "authenticated",
            "user_metadata": {},
            "app_metadata": {"rebi_plus": True},
        },
        secret,
        algorithm="HS256",
    )

    assert user_is_rebi_plus(_request(user_controlled), USER_ID) is False
    assert user_is_rebi_plus(_request(server_controlled), USER_ID) is True


def test_health_reports_misconfiguration(monkeypatch, client):
    monkeypatch.delenv("SUPABASE_JWT_SECRET", raising=False)
    monkeypatch.delenv("API_ALLOW_INSECURE_AUTH", raising=False)

    response = client.get("/health")

    assert response.status_code == 503
    assert response.json()["auth_mode"] == "blocked"
