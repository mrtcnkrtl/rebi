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

from main import app


@pytest.fixture
def client() -> TestClient:
    return TestClient(app)
