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
        processing_mode="text_heavy",
        openai_api_key="sk-test",
        google_api_key="goog-test",
    )
    assert result == [{"page": 1, "text": "Once upon a time"}, {"page": 2, "text": "The end"}]
    mock_completion.assert_called_once()
    call_kwargs = mock_completion.call_args.kwargs
    assert call_kwargs["model"].startswith("gemini")
    assert call_kwargs["api_key"] == "goog-test"

@patch("litellm.completion")
def test_analyze_gpt4o_uses_openai_key(mock_completion):
    mock_completion.return_value = _make_completion_mock(SAMPLE_PAGES_RESPONSE)
    from backend.services.vlm_service import analyze_pages
    analyze_pages(
        image_bytes_list=[b"fakejpeg"],
        vlm_provider="gpt4o",
        processing_mode="text_heavy",
        openai_api_key="sk-openai",
        google_api_key="goog-test",
    )
    call_kwargs = mock_completion.call_args.kwargs
    assert "gpt-4o" in call_kwargs["model"]
    assert call_kwargs["api_key"] == "sk-openai"

@patch("litellm.completion")
def test_analyze_picture_book_mode_uses_different_prompt(mock_completion):
    mock_completion.return_value = _make_completion_mock(SAMPLE_PAGES_RESPONSE)
    from backend.services.vlm_service import analyze_pages
    analyze_pages(
        image_bytes_list=[b"fakejpeg"],
        vlm_provider="gemini",
        processing_mode="picture_book",
        openai_api_key="sk-test",
        google_api_key="goog-test",
    )
    call_kwargs = mock_completion.call_args.kwargs
    system_content = call_kwargs["messages"][0]["content"]
    # picture_book prompt should mention illustrations/narrative, not pure OCR
    assert "illustration" in system_content.lower() or "narrative" in system_content.lower()

@patch("litellm.completion")
def test_analyze_text_heavy_mode_uses_ocr_prompt(mock_completion):
    mock_completion.return_value = _make_completion_mock(SAMPLE_PAGES_RESPONSE)
    from backend.services.vlm_service import analyze_pages
    analyze_pages(
        image_bytes_list=[b"fakejpeg"],
        vlm_provider="gemini",
        processing_mode="text_heavy",
        openai_api_key="sk-test",
        google_api_key="goog-test",
    )
    call_kwargs = mock_completion.call_args.kwargs
    system_content = call_kwargs["messages"][0]["content"]
    assert "text" in system_content.lower()

@patch("litellm.completion")
def test_analyze_encodes_images_as_base64(mock_completion):
    mock_completion.return_value = _make_completion_mock(SAMPLE_PAGES_RESPONSE)
    from backend.services.vlm_service import analyze_pages
    analyze_pages(
        image_bytes_list=[b"fakejpeg", b"fakejpeg2"],
        vlm_provider="gemini",
        processing_mode="text_heavy",
        openai_api_key="",
        google_api_key="goog-test",
    )
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
        analyze_pages(
            image_bytes_list=[b"fakejpeg"],
            vlm_provider="gemini",
            processing_mode="text_heavy",
            openai_api_key="",
            google_api_key="goog-test",
        )

@patch("litellm.completion")
def test_analyze_raises_on_unknown_provider(mock_completion):
    from backend.services.vlm_service import analyze_pages
    with pytest.raises(ValueError, match="Unknown vlm_provider"):
        analyze_pages(
            image_bytes_list=[b"fakejpeg"],
            vlm_provider="unknown_provider",
            processing_mode="text_heavy",
            openai_api_key="",
            google_api_key="",
        )
    mock_completion.assert_not_called()
