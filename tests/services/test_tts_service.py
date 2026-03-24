import asyncio
import base64
import pytest
from unittest.mock import patch, AsyncMock, MagicMock

FAKE_MP3 = b"\xff\xfb\x90\x00" * 100

def _make_tts_response(content: bytes):
    mock = MagicMock()
    mock.content = content
    return mock

def _make_openai_client_mock(speech_side_effect=None, speech_return=None):
    """Create a mock AsyncOpenAI client with audio.speech.create configured."""
    mock_client = MagicMock()
    if speech_side_effect is not None:
        mock_client.audio.speech.create = AsyncMock(side_effect=speech_side_effect)
    else:
        mock_client.audio.speech.create = AsyncMock(return_value=speech_return or _make_tts_response(FAKE_MP3))
    return mock_client

@pytest.mark.asyncio
async def test_generate_audio_returns_base64_for_all_lines():
    mock_client = _make_openai_client_mock()
    with patch("backend.services.tts_service.AsyncOpenAI", return_value=mock_client):
        from backend.services.tts_service import generate_audio
        results = await generate_audio(
            lines=[
                {"index": 0, "text": "Hello", "voice": "alloy"},
                {"index": 1, "text": "World", "voice": "nova"},
            ],
            openai_api_key="sk-test",
        )
    assert len(results) == 2
    assert results[0]["index"] == 0
    assert results[0]["status"] == "ready"
    assert results[0]["audio_b64"] == base64.b64encode(FAKE_MP3).decode()

@pytest.mark.asyncio
async def test_generate_audio_creates_client_with_provided_key():
    mock_client = _make_openai_client_mock()
    with patch("backend.services.tts_service.AsyncOpenAI", return_value=mock_client) as mock_cls:
        from backend.services.tts_service import generate_audio
        await generate_audio(lines=[], openai_api_key="sk-my-key")
    mock_cls.assert_called_once_with(api_key="sk-my-key")

@pytest.mark.asyncio
async def test_generate_audio_sets_error_on_tts_failure():
    mock_client = _make_openai_client_mock(speech_side_effect=Exception("API error"))
    with patch("backend.services.tts_service.AsyncOpenAI", return_value=mock_client):
        from backend.services.tts_service import generate_audio
        results = await generate_audio(
            lines=[{"index": 0, "text": "Hello", "voice": "alloy"}],
            openai_api_key="sk-test",
        )
    assert results[0]["status"] == "error"
    assert "audio_b64" not in results[0]

@pytest.mark.asyncio
async def test_generate_audio_preserves_order_under_concurrency():
    call_count = 0
    async def slow_then_fast(*, model, input, voice, response_format):
        nonlocal call_count
        call_count += 1
        if call_count == 1:
            await asyncio.sleep(0.05)
        return _make_tts_response(FAKE_MP3)

    mock_client = MagicMock()
    mock_client.audio.speech.create = slow_then_fast
    with patch("backend.services.tts_service.AsyncOpenAI", return_value=mock_client):
        from backend.services.tts_service import generate_audio
        results = await generate_audio(
            lines=[
                {"index": 0, "text": "First", "voice": "alloy"},
                {"index": 1, "text": "Second", "voice": "nova"},
            ],
            openai_api_key="sk-test",
        )
    assert [r["index"] for r in results] == [0, 1]

@pytest.mark.asyncio
async def test_generate_audio_uses_mp3_format():
    mock_client = _make_openai_client_mock()
    with patch("backend.services.tts_service.AsyncOpenAI", return_value=mock_client):
        from backend.services.tts_service import generate_audio
        await generate_audio(
            lines=[{"index": 0, "text": "Hi", "voice": "alloy"}],
            openai_api_key="sk-test",
        )
    call_kwargs = mock_client.audio.speech.create.call_args.kwargs
    assert call_kwargs.get("response_format") == "mp3"
