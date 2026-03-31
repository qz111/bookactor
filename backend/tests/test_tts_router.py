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


class TestDesignVoicesRouter:
    def test_returns_200_with_characters_list(self):
        fake_chars = [
            {"name": "Bear", "voice_prompt": "big bear", "voice_id": "v_bear"},
            {"name": "Rabbit", "voice_prompt": "small rabbit", "voice_id": "v_rabbit"},
        ]
        with patch("backend.routers.tts.design_voices", new=AsyncMock(return_value=fake_chars)):
            response = client.post("/tts/design-voices", json={
                "characters": [
                    {"name": "Bear", "voice_prompt": "big bear", "voice_id": None},
                    {"name": "Rabbit", "voice_prompt": "small rabbit", "voice_id": None},
                ],
                "language": "en",
                "qwen_api_key": "test-key",
            })
        assert response.status_code == 200
        data = response.json()
        assert len(data["characters"]) == 2
        assert data["characters"][0]["voice_id"] == "v_bear"

    def test_passes_through_existing_voice_id(self):
        existing = [{"name": "Bear", "voice_prompt": "desc", "voice_id": "already_set"}]
        with patch("backend.routers.tts.design_voices", new=AsyncMock(return_value=existing)):
            response = client.post("/tts/design-voices", json={
                "characters": [{"name": "Bear", "voice_prompt": "desc", "voice_id": "already_set"}],
                "language": "en",
                "qwen_api_key": "key",
            })
        assert response.status_code == 200
        assert response.json()["characters"][0]["voice_id"] == "already_set"
