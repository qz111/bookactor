import asyncio
import base64
import io
import wave
import pytest
from unittest.mock import patch, MagicMock


def _make_wav(duration_ms: int = 200, sample_rate: int = 24000) -> bytes:
    """Generate a minimal valid WAV with silence."""
    num_frames = int(sample_rate * duration_ms / 1000)
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sample_rate)
        w.writeframes(b"\x00\x00" * num_frames)
    return buf.getvalue()


def _wav_duration_ms(wav_bytes: bytes) -> float:
    """Return duration in ms of a WAV file."""
    with wave.open(io.BytesIO(wav_bytes)) as w:
        return w.getnframes() / w.getframerate() * 1000


class TestAppendSilence:
    def test_wav_extends_duration(self):
        from backend.services.tts_service import _append_silence

        original = _make_wav(duration_ms=200)
        result = _append_silence(original, "wav", duration_ms=600)

        original_ms = _wav_duration_ms(original)
        result_ms = _wav_duration_ms(result)

        assert result_ms == pytest.approx(original_ms + 600, abs=50)

    def test_wav_returns_bytes(self):
        from backend.services.tts_service import _append_silence

        original = _make_wav()
        result = _append_silence(original, "wav")
        assert isinstance(result, bytes)
        assert len(result) > len(original)

    def test_fallback_on_error_returns_original(self):
        from backend.services.tts_service import _append_silence

        bad_bytes = b"not audio"
        result = _append_silence(bad_bytes, "wav")
        # Use identity check (`is`), not equality, to confirm the exact original
        # object is returned — not a copy with equal content.
        assert result is bad_bytes

    def test_mp3_calls_pydub(self):
        """MP3 path delegates to pydub; mock it to avoid ffmpeg dependency in CI."""
        from backend.services.tts_service import _append_silence

        mock_segment = MagicMock()
        mock_segment.frame_rate = 24000
        mock_combined = MagicMock()
        mock_segment.__add__ = MagicMock(return_value=mock_combined)

        fake_mp3 = b"fake_mp3_bytes"

        def fake_export(buf, format):
            buf.write(b"fake_mp3_with_silence")

        mock_combined.export = fake_export

        with patch("backend.services.tts_service.AudioSegment") as MockAS:
            MockAS.from_file.return_value = mock_segment
            MockAS.silent.return_value = MagicMock()

            result = _append_silence(fake_mp3, "mp3", duration_ms=600)

        call_args = MockAS.from_file.call_args
        assert call_args.args[0].getvalue() == fake_mp3
        MockAS.silent.assert_called_once_with(duration=600, frame_rate=24000)
        assert result == b"fake_mp3_with_silence"


class TestGenerateOneOpenai:
    """Smoke test that _generate_one_openai passes audio through _append_silence."""

    def test_silence_appended_to_openai_result(self):
        from backend.services import tts_service

        # Fake MP3 bytes (pydub path is mocked)
        fake_mp3 = b"fake_mp3"
        fake_silenced = b"fake_mp3_silenced"

        mock_response = MagicMock()
        mock_response.content = fake_mp3

        mock_client = MagicMock()

        async def fake_create(**kwargs):
            return mock_response

        mock_client.audio.speech.create = fake_create

        with patch.object(tts_service, "_append_silence", return_value=fake_silenced) as mock_silence:
            result = asyncio.run(
                tts_service._generate_one_openai(mock_client, {"index": 0, "text": "Hello", "voice": "alloy"})
            )

        mock_silence.assert_called_once_with(fake_mp3, "mp3")
        assert result["audio_b64"] == base64.b64encode(fake_silenced).decode()
        assert result["status"] == "ready"
        assert result["index"] == 0


class TestGenerateOneGemini:
    """Smoke test that _generate_one_gemini passes WAV through _append_silence."""

    def test_silence_appended_to_gemini_result(self):
        from backend.services import tts_service

        fake_wav = b"fake_wav"
        fake_silenced = b"fake_wav_silenced"

        # Mock the Gemini response structure
        mock_part = MagicMock()
        mock_part.inline_data.data = b"raw_pcm"
        mock_content = MagicMock()
        mock_content.parts = [mock_part]
        mock_candidate = MagicMock()
        mock_candidate.content = mock_content
        mock_response = MagicMock()
        mock_response.candidates = [mock_candidate]

        mock_client = MagicMock()
        mock_client.models.generate_content.return_value = mock_response

        with patch.object(tts_service, "_pcm_to_wav", return_value=fake_wav), \
             patch.object(tts_service, "_append_silence", return_value=fake_silenced) as mock_silence:
            result = asyncio.run(
                tts_service._generate_one_gemini(mock_client, {"index": 1, "text": "Hi", "voice": "Aoede"})
            )

        mock_silence.assert_called_once_with(fake_wav, "wav")
        assert result["audio_b64"] == base64.b64encode(fake_silenced).decode()
        assert result["status"] == "ready"
        assert result["index"] == 1
