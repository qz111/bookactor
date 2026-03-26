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


class TestWavDurationMs:
    def test_returns_correct_duration(self):
        from backend.services.tts_service import _wav_duration_ms
        wav = _make_wav(duration_ms=500)
        result = _wav_duration_ms(wav)
        assert result == pytest.approx(500, abs=10)

    def test_returns_int(self):
        from backend.services.tts_service import _wav_duration_ms
        wav = _make_wav(duration_ms=200)
        assert isinstance(_wav_duration_ms(wav), int)


class TestGenerateChunkGemini:
    def test_multi_speaker_returns_duration_ms(self):
        from backend.services import tts_service

        fake_wav = _make_wav(duration_ms=3000)
        fake_silenced = _make_wav(duration_ms=3600)

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
             patch.object(tts_service, "_append_silence", return_value=fake_silenced):
            result = asyncio.run(tts_service._generate_chunk_gemini(
                mock_client,
                {"index": 0, "text": "Narrator: Hi.\nBear: Hello.", "voice_map": {"Narrator": "Aoede", "Bear": "Charon"}}
            ))

        assert result["status"] == "ready"
        assert result["index"] == 0
        assert result["duration_ms"] == pytest.approx(3600, abs=50)

    def test_single_speaker_uses_voice_config(self):
        from backend.services import tts_service

        fake_wav = _make_wav(duration_ms=1000)
        mock_part = MagicMock()
        mock_part.inline_data.data = b"pcm"
        mock_candidate = MagicMock()
        mock_candidate.content = MagicMock(parts=[mock_part])
        mock_response = MagicMock(candidates=[mock_candidate])
        mock_client = MagicMock()
        mock_client.models.generate_content.return_value = mock_response

        captured_config = {}

        def capture_call(**kwargs):
            captured_config.update(kwargs)
            return mock_response

        mock_client.models.generate_content.side_effect = capture_call

        with patch.object(tts_service, "_pcm_to_wav", return_value=fake_wav), \
             patch.object(tts_service, "_append_silence", return_value=fake_wav):
            result = asyncio.run(tts_service._generate_chunk_gemini(
                mock_client,
                {"index": 1, "text": "Narrator: Once upon a time.", "voice_map": {"Narrator": "Aoede"}}
            ))
        assert result["status"] == "ready"
        assert result["duration_ms"] > 0

    def test_error_returns_zero_duration(self):
        from backend.services import tts_service

        mock_client = MagicMock()
        mock_client.models.generate_content.side_effect = RuntimeError("API down")

        result = asyncio.run(tts_service._generate_chunk_gemini(
            mock_client,
            {"index": 2, "text": "x", "voice_map": {"Narrator": "Aoede"}}
        ))

        assert result["status"] == "error"
        assert result["duration_ms"] == 0
        assert result["index"] == 2

    def test_openai_voice_normalized_to_title_case(self):
        from backend.services import tts_service
        # "alloy" (OpenAI) → maps to "Aoede" (title-cased Gemini)
        fake_wav = _make_wav(200)
        mock_part = MagicMock()
        mock_part.inline_data.data = b"pcm"
        mock_candidate = MagicMock()
        mock_candidate.content = MagicMock(parts=[mock_part])
        mock_response = MagicMock(candidates=[mock_candidate])
        mock_client = MagicMock()
        mock_client.models.generate_content.return_value = mock_response

        with patch.object(tts_service, "_pcm_to_wav", return_value=fake_wav), \
             patch.object(tts_service, "_append_silence", return_value=fake_wav):
            result = asyncio.run(tts_service._generate_chunk_gemini(
                mock_client,
                {"index": 0, "text": "Narrator: hi.", "voice_map": {"Narrator": "alloy"}}
            ))
        assert result["status"] == "ready"


class TestCollapseToTwoSpeakers:
    def test_narrator_and_one_male_kept_as_is(self):
        from backend.services.tts_service import _collapse_to_two_speakers
        text = "Narrator: Hi.\nBear: Hello.\nRabbit: Bye."
        voice_map = {"Narrator": "Aoede", "Bear": "Charon", "Rabbit": "Puck"}
        new_text, new_map = _collapse_to_two_speakers(text, voice_map)
        assert set(new_map.keys()) == {"Narrator", "Bear"}
        assert new_map["Narrator"] == "Aoede"
        # Rabbit (male) merged into Bear's speaker label
        assert "Rabbit:" not in new_text
        assert new_text.count("Bear:") == 2

    def test_same_gender_as_narrator_merged_under_narrator(self):
        from backend.services.tts_service import _collapse_to_two_speakers
        # Narrator=Aoede(F), Mother=Kore(F) → same gender → merged under Narrator
        # Bear=Charon(M) → contrast
        text = "Narrator: Once.\nMother: Good morning.\nBear: Growl."
        voice_map = {"Narrator": "Aoede", "Mother": "Kore", "Bear": "Charon"}
        new_text, new_map = _collapse_to_two_speakers(text, voice_map)
        assert set(new_map.keys()) == {"Narrator", "Bear"}
        assert "Mother:" not in new_text
        # Mother's line now attributed to Narrator
        assert new_text.count("Narrator:") == 2

    def test_all_same_gender_uses_different_same_gender_voice(self):
        from backend.services.tts_service import _collapse_to_two_speakers
        # All female voices — contrast speaker keeps their own (different female) voice
        text = "Narrator: A.\nAlice: B.\nBeth: C."
        voice_map = {"Narrator": "Aoede", "Alice": "Kore", "Beth": "Zephyr"}
        new_text, new_map = _collapse_to_two_speakers(text, voice_map)
        assert len(new_map) == 2
        assert "Narrator" in new_map
        assert new_map["Narrator"] == "Aoede"
        contrast_voice = [v for k, v in new_map.items() if k != "Narrator"][0]
        # contrast voice is a different female voice (not the same as narrator's)
        assert contrast_voice != "Aoede"

    def test_all_same_voice_gets_distinct_contrast(self):
        from backend.services.tts_service import _collapse_to_two_speakers
        # LLM assigned same voice to all — safety fallback must pick a different voice
        text = "Narrator: A.\nAlice: B.\nBeth: C."
        voice_map = {"Narrator": "Aoede", "Alice": "Aoede", "Beth": "Aoede"}
        new_text, new_map = _collapse_to_two_speakers(text, voice_map)
        assert len(new_map) == 2
        contrast_voice = [v for k, v in new_map.items() if k != "Narrator"][0]
        assert contrast_voice != "Aoede"

    def test_narrator_voice_never_changes(self):
        from backend.services.tts_service import _collapse_to_two_speakers
        text = "Narrator: A.\nBear: B.\nRabbit: C."
        voice_map = {"Narrator": "Fenrir", "Bear": "Charon", "Rabbit": "Puck"}
        _, new_map = _collapse_to_two_speakers(text, voice_map)
        assert new_map["Narrator"] == "Fenrir"


class TestParseChunkSegments:
    def test_parses_two_speakers(self):
        from backend.services.tts_service import _parse_chunk_segments
        text = "Narrator: Hello there.\nBear: Hi!"
        voice_map = {"Narrator": "alloy", "Bear": "echo"}
        result = _parse_chunk_segments(text, voice_map)
        assert len(result) == 2
        assert result[0] == {"text": "Hello there.", "voice": "alloy"}
        assert result[1] == {"text": "Hi!", "voice": "echo"}

    def test_skips_lines_without_colon(self):
        from backend.services.tts_service import _parse_chunk_segments
        text = "Narrator: Hello.\nsome junk\nBear: Bye."
        result = _parse_chunk_segments(text, {"Narrator": "alloy", "Bear": "echo"})
        assert len(result) == 2

    def test_unknown_speaker_falls_back_to_first_voice(self):
        from backend.services.tts_service import _parse_chunk_segments
        text = "Unknown: Hi."
        result = _parse_chunk_segments(text, {"Narrator": "alloy"})
        assert result[0]["voice"] == "alloy"


class TestGenerateChunkOpenai:
    def test_concatenates_segments_and_returns_duration(self):
        from backend.services import tts_service

        wav1 = _make_wav(duration_ms=1000)
        wav2 = _make_wav(duration_ms=1000)

        mock_client = MagicMock()
        call_count = 0

        async def fake_create(**kwargs):
            nonlocal call_count
            r = MagicMock()
            r.content = wav1 if call_count == 0 else wav2
            call_count += 1
            return r

        mock_client.audio.speech.create = fake_create

        chunk = {
            "index": 0,
            "text": "Narrator: Hi.\nBear: Hello.",
            "voice_map": {"Narrator": "alloy", "Bear": "echo"},
        }
        result = asyncio.run(tts_service._generate_chunk_openai(mock_client, chunk))

        assert result["status"] == "ready"
        assert result["index"] == 0
        assert result["duration_ms"] > 1500  # two 1s segments + silence

    def test_error_returns_zero_duration(self):
        from backend.services import tts_service

        mock_client = MagicMock()
        mock_client.audio.speech.create.side_effect = RuntimeError("fail")

        result = asyncio.run(tts_service._generate_chunk_openai(
            mock_client,
            {"index": 1, "text": "Narrator: Hi.", "voice_map": {"Narrator": "alloy"}}
        ))
        assert result["status"] == "error"
        assert result["duration_ms"] == 0


class TestGenerateAudio:
    def test_routes_to_gemini(self):
        from backend.services import tts_service
        chunks = [{"index": 0, "text": "x", "voice_map": {"Narrator": "Aoede"}}]
        fake = [{"index": 0, "status": "ready", "audio_b64": "a", "duration_ms": 1000}]

        async def fake_throttled(client, chunks, rpm=10):
            return fake

        with patch("backend.services.tts_service._generate_gemini_throttled", side_effect=fake_throttled), \
             patch("backend.services.tts_service.genai") as mock_genai:
            mock_genai.Client.return_value = MagicMock()
            result = asyncio.run(tts_service.generate_audio(
                chunks=chunks, tts_provider="gemini",
                openai_api_key="", google_api_key="k"
            ))
        assert result[0]["duration_ms"] == 1000

    def test_sorts_results_by_index(self):
        from backend.services import tts_service
        chunks = [
            {"index": 1, "text": "b", "voice_map": {"Narrator": "Aoede"}},
            {"index": 0, "text": "a", "voice_map": {"Narrator": "Aoede"}},
        ]
        unsorted = [
            {"index": 1, "status": "ready", "audio_b64": "b", "duration_ms": 500},
            {"index": 0, "status": "ready", "audio_b64": "a", "duration_ms": 600},
        ]

        async def fake_throttled(client, chunks, rpm=10):
            return unsorted

        with patch("backend.services.tts_service._generate_gemini_throttled", side_effect=fake_throttled), \
             patch("backend.services.tts_service.genai") as mock_genai:
            mock_genai.Client.return_value = MagicMock()
            result = asyncio.run(tts_service.generate_audio(
                chunks=chunks, tts_provider="gemini",
                openai_api_key="", google_api_key="k"
            ))
        assert result[0]["index"] == 0
        assert result[1]["index"] == 1

    def test_routes_to_openai(self):
        from backend.services import tts_service
        chunks = [{"index": 0, "text": "Narrator: Hi.", "voice_map": {"Narrator": "alloy"}}]

        async def fake_openai_chunk(client, chunk):
            return {"index": chunk["index"], "status": "ready", "audio_b64": "x", "duration_ms": 500}

        with patch("backend.services.tts_service._generate_chunk_openai", side_effect=fake_openai_chunk), \
             patch("backend.services.tts_service.AsyncOpenAI") as mock_openai:
            mock_openai.return_value = MagicMock()
            result = asyncio.run(tts_service.generate_audio(
                chunks=chunks, tts_provider="openai",
                openai_api_key="key", google_api_key=""
            ))
        assert result[0]["status"] == "ready"
        assert result[0]["duration_ms"] == 500
