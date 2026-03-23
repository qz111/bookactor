import pytest
from unittest.mock import patch, MagicMock

SAMPLE_PAGES_RESPONSE = '{"pages": [{"page": 1, "text": "Once upon a time"}, {"page": 2, "text": "The end"}]}'

def _make_completion_mock(content: str):
    mock = MagicMock()
    mock.choices[0].message.content = content
    return mock

@patch("litellm.completion")
def test_analyze_gemini_returns_pages(mock_completion):
    mock_completion.return_value = _make_completion_mock(SAMPLE_PAGES_RESPONSE)
    from backend.services.vlm_service import analyze_pages
    result = analyze_pages(
        image_bytes_list=[b"fakejpeg"],
        vlm_provider="gemini",
    )
    assert result == [{"page": 1, "text": "Once upon a time"}, {"page": 2, "text": "The end"}]
    mock_completion.assert_called_once()
    call_kwargs = mock_completion.call_args.kwargs
    assert call_kwargs["model"].startswith("gemini")

@patch("litellm.completion")
def test_analyze_gpt4o_uses_correct_model(mock_completion):
    mock_completion.return_value = _make_completion_mock(SAMPLE_PAGES_RESPONSE)
    from backend.services.vlm_service import analyze_pages
    analyze_pages(image_bytes_list=[b"fakejpeg"], vlm_provider="gpt4o")
    call_kwargs = mock_completion.call_args.kwargs
    assert "gpt-4o" in call_kwargs["model"]

@patch("litellm.completion")
def test_analyze_encodes_images_as_base64(mock_completion):
    mock_completion.return_value = _make_completion_mock(SAMPLE_PAGES_RESPONSE)
    from backend.services.vlm_service import analyze_pages
    analyze_pages(image_bytes_list=[b"fakejpeg", b"fakejpeg2"], vlm_provider="gemini")
    call_kwargs = mock_completion.call_args.kwargs
    messages = call_kwargs["messages"]
    image_items = [
        c for c in messages[-1]["content"]
        if isinstance(c, dict) and c.get("type") == "image_url"
    ]
    assert len(image_items) == 2

@patch("litellm.completion")
def test_analyze_raises_on_invalid_json(mock_completion):
    mock_completion.return_value = _make_completion_mock("not json at all")
    from backend.services.vlm_service import analyze_pages
    with pytest.raises(ValueError, match="VLM returned invalid JSON"):
        analyze_pages(image_bytes_list=[b"fakejpeg"], vlm_provider="gemini")

@patch("litellm.completion")
def test_analyze_raises_on_unknown_provider(mock_completion):
    from backend.services.vlm_service import analyze_pages
    with pytest.raises(ValueError, match="Unknown vlm_provider"):
        analyze_pages(image_bytes_list=[b"fakejpeg"], vlm_provider="unknown_provider")
    mock_completion.assert_not_called()
