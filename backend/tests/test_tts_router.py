import pytest
from fastapi.testclient import TestClient
from unittest.mock import AsyncMock, patch
from backend.main import app

client = TestClient(app)


class TestTtsRouter:
    def test_accepts_chunks_with_voice_map(self):
        fake_results = [{"index": 0, "status": "ready", "audio_b64": "abc", "duration_ms": 5000}]
        with patch("backend.routers.tts.generate_audio", new=AsyncMock(return_value=fake_results)):
            response = client.post("/tts", json={
                "chunks": [{"index": 0, "text": "Narrator: Hello.", "voice_map": {"Narrator": "Aoede"}}],
                "tts_provider": "gemini",
                "openai_api_key": "",
                "google_api_key": "key",
            })
        assert response.status_code == 200
        assert response.json()[0]["duration_ms"] == 5000

    def test_rejects_old_lines_field(self):
        response = client.post("/tts", json={
            "lines": [{"index": 0, "text": "Hello", "voice": "alloy"}],
            "tts_provider": "openai",
        })
        assert response.status_code == 422
