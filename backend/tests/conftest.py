import os

import pytest
from fastapi.testclient import TestClient

# Test suite uses the demo identity without a real Supabase JWT. Production
# defaults remain fail-closed; tests opt in to the explicit development mode.
os.environ.setdefault("API_ALLOW_INSECURE_AUTH", "1")
os.environ.setdefault(
    "API_JWT_BYPASS_USER_IDS",
    "00000000-0000-4000-8000-000000000001,demo,demo-user-id",
)
# Şema testleri /openapi.json okur; üretimde dokümantasyon kapalıdır.
os.environ.setdefault("API_DOCS_ENABLED", "1")

from main import app


@pytest.fixture
def client() -> TestClient:
    return TestClient(app)


@pytest.fixture(autouse=True)
def _fresh_ai_user_budget():
    """Kullanıcı başına yapay zekâ bütçesi süreç genelidir; testler birbirinin bütçesini tüketmesin."""
    import rate_limit

    for limiter in (rate_limit.LIMIT_AI_USER_MINUTE, rate_limit.LIMIT_AI_USER_HOUR):
        if hasattr(limiter, "_hits"):
            limiter._hits.clear()
    yield
