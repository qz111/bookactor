import pytest
from unittest.mock import patch

FAKE_SCRIPT = {
    "characters": [{"name": "Narrator", "voice": "alloy"}],
    "lines": [{"index": 0, "character": "Narrator", "text": "Once.", "page": 1, "status": "pending"}],
}

@patch("backend.routers.script.generate_script", return_value=FAKE_SCRIPT)
def test_script_returns_script(mock_svc, client):
    payload = {
        "vlm_output": [{"page": 1, "text": "Once upon a time"}],
        "language": "en",
        "llm_provider": "gpt4o",
        "openai_api_key": "sk-test",
        "google_api_key": "goog-test",
    }
    response = client.post("/script", json=payload)
    assert response.status_code == 200
    assert response.json() == {"script": FAKE_SCRIPT}

@patch("backend.routers.script.generate_script", return_value=FAKE_SCRIPT)
def test_script_passes_all_params_to_service(mock_svc, client):
    vlm_output = [{"page": 1, "text": "Hello"}]
    client.post("/script", json={
        "vlm_output": vlm_output, "language": "zh", "llm_provider": "gemini",
        "openai_api_key": "sk-test", "google_api_key": "goog-key",
    })
    mock_svc.assert_called_once_with(
        vlm_output=vlm_output,
        language="zh",
        llm_provider="gemini",
        openai_api_key="sk-test",
        google_api_key="goog-key",
    )

@patch("backend.routers.script.generate_script", side_effect=ValueError("LLM returned invalid JSON"))
def test_script_returns_422_on_llm_error(mock_svc, client):
    response = client.post("/script", json={
        "vlm_output": [], "language": "en", "llm_provider": "gpt4o",
        "openai_api_key": "", "google_api_key": "",
    })
    assert response.status_code == 422

def test_script_requires_all_fields(client):
    response = client.post("/script", json={"language": "en"})
    assert response.status_code == 422
