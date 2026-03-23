import asyncio
import base64
import pytest
from unittest.mock import patch, AsyncMock, MagicMock

FAKE_MP3 = b"\xff\xfb\x90\x00" * 100  # fake mp3 bytes

def _make_tts_response(content: bytes):
    mock = MagicMock()
    mock.content = content
    return mock

@pytest.mark.asyncio
async def test_generate_audio_returns_base64_for_all_lines():
    with patch("backend.services.tts_service._tts_client") as mock_client:
        mock_client.audio.speech.create = AsyncMock(return_value=_make_tts_response(FAKE_MP3))
        from backend.services.tts_service import generate_audio
        results = await generate_audio([
            {"index": 0, "text": "Hello", "voice": "alloy"},
            {"index": 1, "text": "World", "voice": "nova"},
        ])
    assert len(results) == 2
    assert results[0]["index"] == 0
    assert results[0]["status"] == "ready"
    assert results[0]["audio_b64"] == base64.b64encode(FAKE_MP3).decode()

@pytest.mark.asyncio
async def test_generate_audio_sets_error_on_tts_failure():
    with patch("backend.services.tts_service._tts_client") as mock_client:
        mock_client.audio.speech.create = AsyncMock(side_effect=Exception("API error"))
        from backend.services.tts_service import generate_audio
        results = await generate_audio([{"index": 0, "text": "Hello", "voice": "alloy"}])
    assert results[0]["status"] == "error"
    assert "audio_b64" not in results[0]

@pytest.mark.asyncio
async def test_generate_audio_preserves_order_under_concurrency():
    """Parallel calls must return results indexed correctly regardless of completion order."""
    call_count = 0
    async def slow_then_fast(*, model, input, voice, response_format):
        nonlocal call_count
        call_count += 1
        if call_count == 1:
            await asyncio.sleep(0.05)
        return _make_tts_response(FAKE_MP3)

    with patch("backend.services.tts_service._tts_client") as mock_client:
        mock_client.audio.speech.create = slow_then_fast
        from backend.services.tts_service import generate_audio
        results = await generate_audio([
            {"index": 0, "text": "First", "voice": "alloy"},
            {"index": 1, "text": "Second", "voice": "nova"},
        ])
    assert [r["index"] for r in results] == [0, 1]

@pytest.mark.asyncio
async def test_generate_audio_uses_mp3_format():
    with patch("backend.services.tts_service._tts_client") as mock_client:
        mock_client.audio.speech.create = AsyncMock(return_value=_make_tts_response(FAKE_MP3))
        from backend.services.tts_service import generate_audio
        await generate_audio([{"index": 0, "text": "Hi", "voice": "alloy"}])
    call_kwargs = mock_client.audio.speech.create.call_args.kwargs
    assert call_kwargs.get("response_format") == "mp3"
