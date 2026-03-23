import pytest
from fastapi.testclient import TestClient

@pytest.fixture
def client():
    from backend.main import app
    return TestClient(app)
