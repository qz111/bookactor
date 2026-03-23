import pytest
from unittest.mock import patch, AsyncMock

FAKE_AUDIO_RESULTS = [
    {"index": 0, "status": "ready", "audio_b64": "AAAA"},
    {"index": 1, "status": "error"},
]

@patch("backend.routers.tts.generate_audio", new_callable=AsyncMock, return_value=FAKE_AUDIO_RESULTS)
def test_tts_returns_audio_list(mock_svc, client):
    payload = {
        "lines": [
            {"index": 0, "text": "Hello", "voice": "alloy"},
            {"index": 1, "text": "World", "voice": "nova"},
        ]
    }
    response = client.post("/tts", json=payload)
    assert response.status_code == 200
    assert response.json() == FAKE_AUDIO_RESULTS

@patch("backend.routers.tts.generate_audio", new_callable=AsyncMock, return_value=FAKE_AUDIO_RESULTS)
def test_tts_passes_lines_to_service(mock_svc, client):
    lines = [{"index": 0, "text": "Hi", "voice": "alloy"}]
    client.post("/tts", json={"lines": lines})
    mock_svc.assert_called_once_with(lines)

def test_tts_requires_lines_field(client):
    response = client.post("/tts", json={})
    assert response.status_code == 422

def test_tts_requires_index_text_voice(client):
    response = client.post("/tts", json={"lines": [{"index": 0}]})
    assert response.status_code == 422
