import pytest
from unittest.mock import patch, MagicMock

VALID_SCRIPT_JSON = """{
  "characters": [{"name": "Narrator", "voice": "alloy"}],
  "lines": [{"index": 0, "character": "Narrator", "text": "Once upon a time.", "page": 1, "status": "pending"}]
}"""

def _make_completion_mock(content: str):
    mock = MagicMock()
    mock.choices[0].message.content = content
    return mock

@patch("litellm.completion")
def test_generate_script_returns_parsed_dict(mock_completion):
    mock_completion.return_value = _make_completion_mock(VALID_SCRIPT_JSON)
    from backend.services.llm_service import generate_script
    result = generate_script(
        vlm_output=[{"page": 1, "text": "Once upon a time."}],
        language="en",
        llm_provider="gpt4o",
    )
    assert "characters" in result
    assert "lines" in result
    assert result["lines"][0]["status"] == "pending"

@patch("litellm.completion")
def test_generate_script_uses_gpt4o_model(mock_completion):
    mock_completion.return_value = _make_completion_mock(VALID_SCRIPT_JSON)
    from backend.services.llm_service import generate_script
    generate_script(vlm_output=[], language="en", llm_provider="gpt4o")
    assert "gpt-4o" in mock_completion.call_args.kwargs["model"]

@patch("litellm.completion")
def test_generate_script_uses_gemini_model(mock_completion):
    mock_completion.return_value = _make_completion_mock(VALID_SCRIPT_JSON)
    from backend.services.llm_service import generate_script
    generate_script(vlm_output=[], language="zh", llm_provider="gemini")
    assert "gemini" in mock_completion.call_args.kwargs["model"]

@patch("litellm.completion")
def test_generate_script_retries_once_on_bad_json(mock_completion):
    """First call returns invalid JSON; second call (stricter prompt) returns valid JSON."""
    mock_completion.side_effect = [
        _make_completion_mock("not json"),
        _make_completion_mock(VALID_SCRIPT_JSON),
    ]
    from backend.services.llm_service import generate_script
    result = generate_script(vlm_output=[], language="en", llm_provider="gpt4o")
    assert mock_completion.call_count == 2
    assert "characters" in result

@patch("litellm.completion")
def test_generate_script_raises_after_two_bad_responses(mock_completion):
    """Both attempts return invalid JSON → raises ValueError."""
    mock_completion.return_value = _make_completion_mock("not json")
    from backend.services.llm_service import generate_script
    with pytest.raises(ValueError, match="LLM returned invalid JSON"):
        generate_script(vlm_output=[], language="en", llm_provider="gpt4o")
    assert mock_completion.call_count == 2

@patch("litellm.completion")
def test_generate_script_includes_language_in_prompt(mock_completion):
    mock_completion.return_value = _make_completion_mock(VALID_SCRIPT_JSON)
    from backend.services.llm_service import generate_script
    generate_script(vlm_output=[], language="zh-TW", llm_provider="gpt4o")
    prompt_text = str(mock_completion.call_args)
    assert "zh-TW" in prompt_text
