import json
from unittest.mock import patch, MagicMock


def _mock_llm_response(content: str):
    mock_response = MagicMock()
    mock_response.choices = [MagicMock()]
    mock_response.choices[0].message.content = content
    return mock_response


class TestSystemPrompt:
    def test_prompt_contains_chunks_not_lines(self):
        from backend.services.llm_service import _system_prompt
        prompt = _system_prompt("gemini")
        assert '"chunks"' in prompt
        assert '"lines"' not in prompt

    def test_prompt_contains_char_range(self):
        from backend.services.llm_service import _system_prompt
        prompt = _system_prompt("gemini")
        assert "2000" in prompt
        assert "3000" in prompt

    def test_prompt_contains_duration_ms(self):
        from backend.services.llm_service import _system_prompt
        prompt = _system_prompt("gemini")
        assert "duration_ms" in prompt

    def test_prompt_contains_speakers(self):
        from backend.services.llm_service import _system_prompt
        prompt = _system_prompt("gemini")
        assert '"speakers"' in prompt

    def test_gemini_voices_title_case(self):
        from backend.services.llm_service import _system_prompt
        prompt = _system_prompt("gemini")
        assert "Aoede" in prompt
        assert "aoede" not in prompt


class TestSystemPromptQwen:
    def test_qwen_voices_in_prompt(self):
        from backend.services.llm_service import _system_prompt
        prompt = _system_prompt("qwen")
        assert "Cherry" in prompt
        assert "Ethan" in prompt
        assert "Serena" in prompt
        assert "Dylan" in prompt

    def test_qwen_prompt_excludes_gemini_voices(self):
        from backend.services.llm_service import _system_prompt
        prompt = _system_prompt("qwen")
        assert "Aoede" not in prompt
        assert "Charon" not in prompt

    def test_qwen_prompt_contains_utterance_length_rule(self):
        from backend.services.llm_service import _system_prompt
        prompt = _system_prompt("qwen")
        assert "250" in prompt

    def test_gemini_prompt_excludes_qwen_voices(self):
        from backend.services.llm_service import _system_prompt
        prompt = _system_prompt("gemini")
        assert "Cherry" not in prompt
        assert "Ethan" not in prompt


class TestGenerateScript:
    def test_returns_chunks_not_lines(self):
        from backend.services.llm_service import generate_script
        fake_output = {
            "characters": [{"name": "Narrator", "voice": "Aoede", "traits": "calm"}],
            "chunks": [
                {
                    "index": 0,
                    "text": "Narrator: Hello world.",
                    "speakers": ["Narrator"],
                    "duration_ms": 0,
                    "status": "pending",
                }
            ],
        }
        with patch("backend.services.llm_service.litellm") as mock_litellm:
            mock_litellm.completion.return_value = _mock_llm_response(json.dumps(fake_output))
            result = generate_script(
                vlm_output=[{"page": 1, "text": "Hello"}],
                language="en",
                llm_provider="gemini",
                tts_provider="gemini",
                openai_api_key="",
                google_api_key="key",
            )
        assert "chunks" in result
        assert "lines" not in result
        assert result["chunks"][0]["status"] == "pending"

    def test_all_chunks_set_pending(self):
        from backend.services.llm_service import generate_script
        fake_output = {
            "characters": [],
            "chunks": [
                {"index": 0, "text": "x", "speakers": [], "duration_ms": 0, "status": "ready"},
                {"index": 1, "text": "y", "speakers": [], "duration_ms": 0, "status": "ready"},
            ],
        }
        with patch("backend.services.llm_service.litellm") as mock_litellm:
            mock_litellm.completion.return_value = _mock_llm_response(json.dumps(fake_output))
            result = generate_script(
                vlm_output=[], language="en", llm_provider="gemini",
                tts_provider="gemini", openai_api_key="", google_api_key="k",
            )
        assert all(c["status"] == "pending" for c in result["chunks"])
