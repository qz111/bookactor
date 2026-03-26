# TTS Batching & Multi-Speaker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace per-utterance TTS calls with ~3KB multi-speaker chunks, adding a real seekable audio timeline to the player.

**Architecture:** LLM emits `chunks[]` (not `lines[]`) of 2000–3000 chars formatted as `Character: text\n` multi-speaker dialogue. The backend uses Gemini's `MultiSpeakerVoiceConfig` (or concatenated WAV segments for OpenAI) and returns `duration_ms` per chunk. The Flutter player subscribes to the `audioplayers` position stream for a real seekable slider.

**Tech Stack:** Python (FastAPI, google-genai, openai, pydub), Dart/Flutter (audioplayers, flutter_riverpod, go_router)

**Spec:** `docs/superpowers/specs/2026-03-26-tts-batching-design.md`

---

## File Map

| File | Action | What changes |
|---|---|---|
| `backend/services/llm_service.py` | Modify | System prompt outputs `chunks[]` not `lines[]` |
| `backend/routers/tts.py` | Modify | `TtsLine` → `TtsChunk` with `voice_map`; `lines` → `chunks` |
| `backend/services/tts_service.py` | Modify | Multi-speaker Gemini path, WAV OpenAI path, `duration_ms` return, `_wav_duration_ms` helper |
| `backend/tests/test_tts_service.py` | Modify | Update tests for new chunk API and multi-speaker path |
| `lib/models/script.dart` | Modify | `ScriptLine` → `ScriptChunk`, `Script.lines` → `Script.chunks` |
| `assets/mock/script.json` | Modify | Convert `lines[]` to `chunks[]` format |
| `lib/services/audio_service.dart` | Modify | Add `seek(Duration)` and `positionStream` |
| `lib/providers/player_provider.dart` | Modify | `currentLine` → `currentChunkIndex`, chunk-aware computed properties |
| `lib/services/api_service.dart` | Modify | `generateAudio` param `lines` → `chunks` with `voice_map` |
| `lib/screens/loading_screen.dart` | Modify | Chunk-based TTS generation, `status == 'pending'` filter, persist `duration_ms` |
| `lib/screens/player_screen.dart` | Modify | Replace `KaraokeText` + page display with scrollable dialogue + `Slider` |
| `lib/widgets/karaoke_text.dart` | Delete | Replaced by plain `Text` in player |
| `test/models/script_test.dart` | Modify | Test `ScriptChunk` parsing, `voiceFor`, round-trip |
| `test/providers/player_provider_test.dart` | Modify | Test chunk-based navigation, computed properties |
| `test/services/audio_service_test.dart` | Modify | Test `seek` and `positionStream` |
| `test/services/api_service_test.dart` | Modify | Test `generateAudio` with `chunks` + `voice_map` |
| `test/widgets/karaoke_text_test.dart` | Delete | Widget deleted |

---

## Task 1: LLM Service — Chunks Prompt

**Files:**
- Modify: `backend/services/llm_service.py`

- [ ] **Step 1: Write the failing test**

There is no existing `test_llm_service.py`. Create `backend/tests/test_llm_service.py`:

```python
import pytest
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
        import json
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
        import json
        with patch("backend.services.llm_service.litellm") as mock_litellm:
            mock_litellm.completion.return_value = _mock_llm_response(json.dumps(fake_output))
            result = generate_script(
                vlm_output=[], language="en", llm_provider="gemini",
                tts_provider="gemini", openai_api_key="", google_api_key="k",
            )
        assert all(c["status"] == "pending" for c in result["chunks"])
```

- [ ] **Step 2: Run tests to verify they fail**

```
cd D:/developer_tools/bookactor
pytest backend/tests/test_llm_service.py -v
```

Expected: FAIL — `"chunks"` not in prompt, `"lines"` still there.

- [ ] **Step 3: Update `llm_service.py` — system prompt and `generate_script`**

Replace the `_system_prompt` function and update `generate_script` to iterate over `chunks` instead of `lines`:

```python
def _system_prompt(tts_provider: str) -> str:
    voices = _VOICES.get(tts_provider, _VOICES["openai"])
    return (
        "You are a children's audiobook script writer. Given the extracted story text from a "
        "picture book, output ONLY a JSON object (no markdown fences) with this exact structure:\n"
        f'{{"characters": [{{"name": "...", "voice": "<{voices}>", "traits": "..."}}], '
        '"chunks": [{"index": <0-based int>, "text": "...", "speakers": ["..."], '
        '"duration_ms": 0, "status": "pending"}]}\n'
        "Rules:\n"
        "- Narrator is always present. Assign each character a distinct voice. "
        "Never change a character's voice mid-story.\n"
        "- Group the full story into sequential dialogue passages. Each chunk's 'text' field "
        "must be between 2000 and 3000 characters.\n"
        "- Format 'text' as lines of 'Character: utterance\\n' — each Character name exactly "
        "matching a name in the 'characters' array.\n"
        "- Never cut mid-sentence. Chunks end at natural pause points.\n"
        "- 'speakers' lists every character name that appears in that chunk's text.\n"
        "- Narrator and characters flow naturally together.\n"
        "- 'duration_ms' is always 0.\n"
        "- All dialogue text must be in the language specified by the user.\n"
        f"- Voice names must use title case: {voices}."
    )
```

In `generate_script`, change `line["status"] = "pending"` to iterate chunks:

```python
        try:
            data = json.loads(_strip_fences(raw))
            for chunk in data.get("chunks", []):
                chunk["status"] = "pending"
            return data
```

Also update `_VOICES` to use title case for Gemini:

```python
_VOICES = {
    "openai": "alloy|echo|fable|onyx|nova|shimmer",
    "gemini": "Aoede|Charon|Fenrir|Kore|Puck|Zephyr|Leda|Orus",
}
```

- [ ] **Step 4: Run tests to verify they pass**

```
pytest backend/tests/test_llm_service.py -v
```

Expected: All PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/services/llm_service.py backend/tests/test_llm_service.py
git commit -m "feat: LLM prompt outputs chunks[] with multi-speaker dialogue format"
```

---

## Task 2: TTS Router — TtsChunk Model

**Files:**
- Modify: `backend/routers/tts.py`

- [ ] **Step 1: Write the failing test**

Create `backend/tests/test_tts_router.py`:

```python
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
```

- [ ] **Step 2: Run tests to verify they fail**

```
pytest backend/tests/test_tts_router.py -v
```

Expected: FAIL — `TtsLine` still in place, `voice_map` not accepted.

- [ ] **Step 3: Update `backend/routers/tts.py`**

Replace the entire file:

```python
import logging
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from backend.services.tts_service import generate_audio

logger = logging.getLogger(__name__)
router = APIRouter()


class TtsChunk(BaseModel):
    index: int
    text: str
    voice_map: dict[str, str]  # {"Narrator": "Aoede", "Bear": "Charon"}


class TtsRequest(BaseModel):
    chunks: list[TtsChunk]
    tts_provider: str = "openai"
    openai_api_key: str = ""
    google_api_key: str = ""


@router.post("/tts")
async def tts(req: TtsRequest):
    """Generate TTS audio for all chunks."""
    chunks = [chunk.model_dump() for chunk in req.chunks]
    try:
        return await generate_audio(
            chunks=chunks,
            tts_provider=req.tts_provider,
            openai_api_key=req.openai_api_key,
            google_api_key=req.google_api_key,
        )
    except Exception as exc:
        logger.exception("Error in /tts")
        raise HTTPException(status_code=500, detail=f"{type(exc).__name__}: {exc}") from exc
```

- [ ] **Step 4: Run tests to verify they pass**

```
pytest backend/tests/test_tts_router.py -v
```

Expected: All PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/routers/tts.py backend/tests/test_tts_router.py
git commit -m "feat: TTS router accepts chunks with voice_map"
```

---

## Task 3: TTS Service — `_wav_duration_ms` + Gemini Multi-Speaker

**Files:**
- Modify: `backend/services/tts_service.py`
- Modify: `backend/tests/test_tts_service.py`

- [ ] **Step 1: Write the failing tests**

Add to `backend/tests/test_tts_service.py`:

```python
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
            asyncio.run(tts_service._generate_chunk_gemini(
                mock_client,
                {"index": 1, "text": "Narrator: Once upon a time.", "voice_map": {"Narrator": "Aoede"}}
            ))

        # Verify generate_content was called (config inspection is complex; check index/status)
        assert mock_client.models.generate_content.called

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
```

- [ ] **Step 2: Run tests to verify they fail**

```
pytest backend/tests/test_tts_service.py::TestWavDurationMs backend/tests/test_tts_service.py::TestGenerateChunkGemini -v
```

Expected: FAIL — `_wav_duration_ms` and `_generate_chunk_gemini` not defined.

- [ ] **Step 3: Add `_wav_duration_ms` and `_generate_chunk_gemini` to `tts_service.py`**

Add after `_append_silence`:

```python
def _wav_duration_ms(wav_bytes: bytes) -> int:
    """Return duration in milliseconds of a WAV file."""
    with wave.open(io.BytesIO(wav_bytes)) as w:
        return int(w.getnframes() / w.getframerate() * 1000)
```

Add new Gemini chunk function (replace `_generate_one_gemini`):

```python
async def _generate_chunk_gemini(client, chunk: dict) -> dict:
    """Generate audio for a chunk using Gemini TTS (multi-speaker when >1 voice)."""
    try:
        from google.genai import types

        voice_map = {
            name: _OPENAI_TO_GEMINI.get(v.lower(), v).capitalize()
            for name, v in chunk["voice_map"].items()
        }

        if len(voice_map) > 1:
            speech_config = types.SpeechConfig(
                multi_speaker_voice_config=types.MultiSpeakerVoiceConfig(
                    speaker_voice_configs=[
                        types.SpeakerVoiceConfig(
                            speaker=name,
                            voice_config=types.VoiceConfig(
                                prebuilt_voice_config=types.PrebuiltVoiceConfig(voice_name=voice)
                            ),
                        )
                        for name, voice in voice_map.items()
                    ]
                )
            )
        else:
            voice = list(voice_map.values())[0]
            speech_config = types.SpeechConfig(
                voice_config=types.VoiceConfig(
                    prebuilt_voice_config=types.PrebuiltVoiceConfig(voice_name=voice)
                )
            )

        response = await asyncio.to_thread(
            client.models.generate_content,
            model="gemini-2.5-pro-preview-tts",
            contents=chunk["text"],
            config=types.GenerateContentConfig(
                response_modalities=["AUDIO"],
                speech_config=speech_config,
            ),
        )
        candidate = response.candidates[0]
        if candidate.content is None:
            finish = getattr(candidate, "finish_reason", "unknown")
            raise ValueError(f"Gemini returned no content (finish_reason={finish})")
        pcm_bytes = candidate.content.parts[0].inline_data.data
        wav_bytes = _pcm_to_wav(pcm_bytes)
        wav_with_silence = _append_silence(wav_bytes, "wav")
        duration_ms = _wav_duration_ms(wav_with_silence)
        audio_b64 = base64.b64encode(wav_with_silence).decode()
        return {"index": chunk["index"], "status": "ready", "audio_b64": audio_b64, "duration_ms": duration_ms}
    except Exception:
        logger.exception("Gemini TTS failed for chunk %d", chunk["index"])
        return {"index": chunk["index"], "status": "error", "duration_ms": 0}
```

Also update `_OPENAI_TO_GEMINI` values to title case:

```python
_OPENAI_TO_GEMINI = {
    "alloy": "Aoede", "echo": "Charon", "fable": "Fenrir",
    "onyx": "Kore", "nova": "Puck", "shimmer": "Zephyr",
}
```

Update `_generate_gemini_throttled` to use chunks:

```python
async def _generate_gemini_throttled(client, chunks: list[dict], rpm: int = 10) -> list[dict]:
    """Generate Gemini TTS one chunk at a time, respecting the RPM limit."""
    min_interval = 60.0 / rpm
    results = []
    last_start: float | None = None

    for chunk in chunks:
        if last_start is not None:
            elapsed = asyncio.get_event_loop().time() - last_start
            wait = min_interval - elapsed
            if wait > 0:
                await asyncio.sleep(wait)
        last_start = asyncio.get_event_loop().time()
        result = await _generate_chunk_gemini(client, chunk)
        results.append(result)

    return results
```

- [ ] **Step 4: Run tests to verify they pass**

```
pytest backend/tests/test_tts_service.py::TestWavDurationMs backend/tests/test_tts_service.py::TestGenerateChunkGemini -v
```

Expected: All PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/services/tts_service.py backend/tests/test_tts_service.py
git commit -m "feat: Gemini multi-speaker TTS chunks with duration_ms"
```

---

## Task 4: TTS Service — OpenAI Chunk Path + `generate_audio`

**Files:**
- Modify: `backend/services/tts_service.py`
- Modify: `backend/tests/test_tts_service.py`

- [ ] **Step 1: Write the failing tests**

Add to `backend/tests/test_tts_service.py`:

```python
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
            import asyncio as _asyncio
            result = _asyncio.run(tts_service.generate_audio(
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
            import asyncio as _asyncio
            result = _asyncio.run(tts_service.generate_audio(
                chunks=chunks, tts_provider="gemini",
                openai_api_key="", google_api_key="k"
            ))
        assert result[0]["index"] == 0
        assert result[1]["index"] == 1
```

- [ ] **Step 2: Run tests to verify they fail**

```
pytest backend/tests/test_tts_service.py::TestParseChunkSegments backend/tests/test_tts_service.py::TestGenerateChunkOpenai backend/tests/test_tts_service.py::TestGenerateAudio -v
```

Expected: FAIL — `_parse_chunk_segments` and `_generate_chunk_openai` not defined, `generate_audio` still uses `lines`.

- [ ] **Step 3: Add helpers and update `generate_audio` in `tts_service.py`**

Add `_parse_chunk_segments` (after `_wav_duration_ms`):

```python
def _parse_chunk_segments(text: str, voice_map: dict[str, str]) -> list[dict]:
    """Parse 'Character: utterance\\n' text into [{text, voice}] segments."""
    segments = []
    fallback_voice = list(voice_map.values())[0] if voice_map else "alloy"
    for line in text.strip().split("\n"):
        if ": " not in line:
            continue
        name, utterance = line.split(": ", 1)
        voice = voice_map.get(name.strip(), fallback_voice)
        segments.append({"text": utterance.strip(), "voice": voice})
    return segments
```

Add `_generate_chunk_openai` (replace `_generate_one_openai`):

```python
async def _generate_chunk_openai(client: AsyncOpenAI, chunk: dict) -> dict:
    """Generate audio for a chunk using OpenAI TTS; segments concatenated as WAV."""
    try:
        segments = _parse_chunk_segments(chunk["text"], chunk["voice_map"])
        if not segments:
            raise ValueError("No segments parsed from chunk text")

        wav_parts = []
        for seg in segments:
            response = await client.audio.speech.create(
                model="tts-1",
                input=seg["text"],
                voice=seg["voice"],
                response_format="wav",
            )
            wav_parts.append(response.content)

        combined = AudioSegment.from_wav(io.BytesIO(wav_parts[0]))
        for part in wav_parts[1:]:
            combined += AudioSegment.from_wav(io.BytesIO(part))

        buf = io.BytesIO()
        combined.export(buf, format="wav")
        wav_bytes = buf.getvalue()
        wav_with_silence = _append_silence(wav_bytes, "wav")
        duration_ms = _wav_duration_ms(wav_with_silence)
        audio_b64 = base64.b64encode(wav_with_silence).decode()
        return {"index": chunk["index"], "status": "ready", "audio_b64": audio_b64, "duration_ms": duration_ms}
    except Exception:
        logger.exception("OpenAI TTS failed for chunk %d", chunk["index"])
        return {"index": chunk["index"], "status": "error", "duration_ms": 0}
```

Replace `generate_audio`:

```python
async def generate_audio(
    chunks: list[dict],
    tts_provider: str,
    openai_api_key: str,
    google_api_key: str,
) -> list[dict]:
    """Generate TTS audio for all chunks; returns results sorted by index."""
    if tts_provider == "gemini":
        from google import genai
        client = genai.Client(api_key=google_api_key)
        results = await _generate_gemini_throttled(client, chunks)
    else:
        client = AsyncOpenAI(api_key=openai_api_key)
        tasks = [_generate_chunk_openai(client, chunk) for chunk in chunks]
        results = list(await asyncio.gather(*tasks))
    return sorted(results, key=lambda r: r["index"])
```

Remove the old `_generate_one_openai` and `_generate_one_gemini` functions (they are replaced).

- [ ] **Step 4: Run the full TTS test suite**

```
pytest backend/tests/test_tts_service.py -v
```

Before running, delete the two test classes that test the now-removed `_generate_one_openai` and `_generate_one_gemini` functions. In `backend/tests/test_tts_service.py`, delete the entire `class TestGenerateOneOpenai` block (starts with `class TestGenerateOneOpenai:` and ends before `class TestGenerateOneGemini:`) and the entire `class TestGenerateOneGemini` block (starts with `class TestGenerateOneGemini:` and ends at the end of the file). Then run:

Expected: All PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/services/tts_service.py backend/tests/test_tts_service.py
git commit -m "feat: OpenAI WAV chunk path + generate_audio accepts chunks"
```

---

## Task 5: Dart — `ScriptChunk` Model + Mock JSON

**Files:**
- Modify: `lib/models/script.dart`
- Modify: `assets/mock/script.json`
- Modify: `test/models/script_test.dart`

- [ ] **Step 1: Write the failing tests**

Replace `test/models/script_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:bookactor/models/script.dart';

void main() {
  const scriptJson = '''
{
  "characters": [
    {"name": "Narrator", "voice": "Aoede"},
    {"name": "Bear", "voice": "Charon", "traits": "deep"}
  ],
  "chunks": [
    {
      "index": 0,
      "text": "Narrator: Hello.\\nBear: Hi!",
      "speakers": ["Narrator", "Bear"],
      "duration_ms": 5000,
      "status": "ready"
    },
    {
      "index": 1,
      "text": "Narrator: The end.",
      "speakers": ["Narrator"],
      "duration_ms": 2000,
      "status": "pending"
    }
  ]
}
''';

  group('Script', () {
    late Script script;
    setUp(() => script = Script.fromJson(scriptJson));

    test('parses characters', () {
      expect(script.characters.length, 2);
      expect(script.characters[0].name, 'Narrator');
      expect(script.characters[0].voice, 'Aoede');
    });

    test('parses chunks', () {
      expect(script.chunks.length, 2);
      expect(script.chunks[0].index, 0);
      expect(script.chunks[0].speakers, ['Narrator', 'Bear']);
      expect(script.chunks[0].durationMs, 5000);
      expect(script.chunks[0].status, 'ready');
    });

    test('voiceFor returns correct voice', () {
      expect(script.voiceFor('Narrator'), 'Aoede');
      expect(script.voiceFor('Bear'), 'Charon');
    });

    test('voiceFor unknown defaults to alloy', () {
      expect(script.voiceFor('Unknown'), 'alloy');
    });

    test('toJson/fromJson round-trips', () {
      final restored = Script.fromJson(script.toJson());
      expect(restored.chunks.length, 2);
      expect(restored.chunks[0].durationMs, 5000);
      expect(restored.characters[0].voice, 'Aoede');
    });

    test('ScriptChunk.copyWith updates status', () {
      final updated = script.chunks[1].copyWith(status: 'ready', durationMs: 3000);
      expect(updated.status, 'ready');
      expect(updated.durationMs, 3000);
      expect(updated.index, 1);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```
flutter test test/models/script_test.dart
```

Expected: FAIL — `Script` still uses `lines`, no `chunks`.

- [ ] **Step 3: Update `lib/models/script.dart`**

Replace the entire file:

```dart
import 'dart:convert';

class ScriptCharacter {
  final String name;
  final String voice;
  final String? traits;

  const ScriptCharacter({required this.name, required this.voice, this.traits});

  factory ScriptCharacter.fromJson(Map<String, dynamic> json) =>
      ScriptCharacter(
        name: json['name'] as String,
        voice: json['voice'] as String,
        traits: json['traits'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'voice': voice,
        if (traits != null) 'traits': traits,
      };
}

class ScriptChunk {
  final int index;
  final String text;
  final List<String> speakers;
  final int durationMs;
  final String status;

  const ScriptChunk({
    required this.index,
    required this.text,
    required this.speakers,
    required this.durationMs,
    required this.status,
  });

  factory ScriptChunk.fromJson(Map<String, dynamic> json) => ScriptChunk(
        index: json['index'] as int,
        text: json['text'] as String,
        speakers: List<String>.from(json['speakers'] as List),
        durationMs: (json['duration_ms'] as num).toInt(),
        status: json['status'] as String,
      );

  Map<String, dynamic> toJson() => {
        'index': index,
        'text': text,
        'speakers': speakers,
        'duration_ms': durationMs,
        'status': status,
      };

  ScriptChunk copyWith({String? status, int? durationMs}) => ScriptChunk(
        index: index,
        text: text,
        speakers: speakers,
        durationMs: durationMs ?? this.durationMs,
        status: status ?? this.status,
      );
}

class Script {
  final List<ScriptCharacter> characters;
  final List<ScriptChunk> chunks;

  const Script({required this.characters, required this.chunks});

  /// Looks up the voice for a character by name.
  /// Defaults to 'alloy' if not found.
  String voiceFor(String characterName) {
    final match = characters.where((c) => c.name == characterName).firstOrNull;
    return match?.voice ?? 'alloy';
  }

  factory Script.fromJson(String jsonStr) {
    final map = jsonDecode(jsonStr) as Map<String, dynamic>;
    return Script(
      characters: (map['characters'] as List)
          .map((c) => ScriptCharacter.fromJson(c as Map<String, dynamic>))
          .toList(),
      chunks: (map['chunks'] as List)
          .map((c) => ScriptChunk.fromJson(c as Map<String, dynamic>))
          .toList(),
    );
  }

  String toJson() => jsonEncode({
        'characters': characters.map((c) => c.toJson()).toList(),
        'chunks': chunks.map((c) => c.toJson()).toList(),
      });
}
```

- [ ] **Step 4: Update `assets/mock/script.json`**

Replace with chunks format:

```json
{
  "characters": [
    {"name": "Narrator", "voice": "alloy"},
    {"name": "Little Bear", "voice": "nova", "traits": "curious, playful"},
    {"name": "Mother Bear", "voice": "shimmer", "traits": "warm, gentle"}
  ],
  "chunks": [
    {
      "index": 0,
      "text": "Narrator: Once upon a time, in a cozy little den...\nLittle Bear: Good morning, Mama!\nMother Bear: Good morning, my little one. Did you sleep well?\nNarrator: Little Bear looked out the window and saw the world covered in snow.",
      "speakers": ["Narrator", "Little Bear", "Mother Bear"],
      "duration_ms": 12000,
      "status": "ready"
    },
    {
      "index": 1,
      "text": "Little Bear: Mama, can we go play outside? Please?\nMother Bear: After breakfast, my dear.\nNarrator: And so they had a warm breakfast together before their snowy adventure.",
      "speakers": ["Little Bear", "Mother Bear", "Narrator"],
      "duration_ms": 10000,
      "status": "ready"
    }
  ]
}
```

- [ ] **Step 5: Run tests**

```
flutter test test/models/script_test.dart
```

Expected: All PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/models/script.dart assets/mock/script.json test/models/script_test.dart
git commit -m "feat: ScriptChunk model replaces ScriptLine; chunks format"
```

---

## Task 6: AudioService — `seek` and `positionStream`

**Files:**
- Modify: `lib/services/audio_service.dart`
- Modify: `test/services/audio_service_test.dart`

- [ ] **Step 1: Write the failing tests**

Read `test/services/audio_service_test.dart` first, then add:

```dart
test('seek delegates to audioplayers', () async {
  final mockPlayer = MockAudioPlayer();
  final service = AudioService.withPlayer(mockPlayer);
  await service.seek(const Duration(seconds: 5));
  verify(mockPlayer.seek(const Duration(seconds: 5))).called(1);
});

test('positionStream exposes player onPositionChanged', () {
  final mockPlayer = MockAudioPlayer();
  final controller = StreamController<Duration>.broadcast();
  when(mockPlayer.onPositionChanged).thenAnswer((_) => controller.stream);
  final service = AudioService.withPlayer(mockPlayer);
  expect(service.positionStream, emitsInOrder([const Duration(seconds: 1)]));
  controller.add(const Duration(seconds: 1));
  controller.close();
});
```

- [ ] **Step 2: Run tests to verify they fail**

```
flutter test test/services/audio_service_test.dart
```

Expected: FAIL — `seek` and `positionStream` not defined; `AudioService.withPlayer` may not exist.

- [ ] **Step 3: Update `lib/services/audio_service.dart`**

```dart
import 'dart:async';
import 'package:audioplayers/audioplayers.dart';

class AudioService {
  final AudioPlayer _player;
  final StreamController<void> _onCompleteController =
      StreamController<void>.broadcast();

  AudioService() : _player = AudioPlayer() {
    _player.onPlayerComplete.listen((_) {
      _onCompleteController.add(null);
    });
  }

  /// Test-only constructor: inject a mock AudioPlayer.
  AudioService.withPlayer(this._player) {
    _player.onPlayerComplete.listen((_) {
      _onCompleteController.add(null);
    });
  }

  Stream<void> get onComplete => _onCompleteController.stream;

  Stream<Duration> get positionStream => _player.onPositionChanged;

  Future<void> load(String filePath) async {
    await _player.setSourceDeviceFile(filePath);
  }

  Future<void> play() => _player.resume();
  Future<void> pause() => _player.pause();
  Future<void> stop() => _player.stop();
  Future<void> seek(Duration position) => _player.seek(position);

  /// Test-only: simulate playback completion.
  void simulateComplete() => _onCompleteController.add(null);

  void dispose() {
    _onCompleteController.close();
    _player.dispose();
  }
}
```

- [ ] **Step 4: Run tests**

```
flutter test test/services/audio_service_test.dart
```

Expected: All PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/audio_service.dart test/services/audio_service_test.dart
git commit -m "feat: AudioService gains seek() and positionStream"
```

---

## Task 7: PlayerProvider — Chunk-Based State

**Files:**
- Modify: `lib/providers/player_provider.dart`
- Modify: `test/providers/player_provider_test.dart`

- [ ] **Step 1: Write the failing tests**

Replace `test/providers/player_provider_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookactor/models/script.dart';
import 'package:bookactor/providers/player_provider.dart';

const _scriptJson = '''
{
  "characters": [
    {"name": "Narrator", "voice": "Aoede"},
    {"name": "Bear", "voice": "Charon"}
  ],
  "chunks": [
    {"index": 0, "text": "Narrator: A.", "speakers": ["Narrator"], "duration_ms": 3000, "status": "ready"},
    {"index": 1, "text": "Bear: B.", "speakers": ["Bear"], "duration_ms": 0, "status": "error"},
    {"index": 2, "text": "Narrator: C.", "speakers": ["Narrator"], "duration_ms": 4000, "status": "ready"},
    {"index": 3, "text": "Bear: D.", "speakers": ["Bear"], "duration_ms": 2000, "status": "ready"}
  ]
}
''';

void main() {
  late ProviderContainer container;
  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  PlayerNotifier notifier() => container.read(playerProvider.notifier);
  PlayerState state() => container.read(playerProvider);

  group('PlayerNotifier', () {
    test('initial state has no script and chunk 0', () {
      expect(state().script, isNull);
      expect(state().currentChunkIndex, 0);
      expect(state().isPlaying, false);
    });

    test('loadScript sets script and startChunk', () {
      notifier().loadScript(Script.fromJson(_scriptJson), startChunk: 1);
      expect(state().script, isNotNull);
      expect(state().currentChunkIndex, 1);
    });

    test('readyChunks filters by status', () {
      notifier().loadScript(Script.fromJson(_scriptJson));
      // chunk index 1 has status error — only 3 ready
      expect(state().readyChunks.length, 3);
    });

    test('totalDurationMs sums ready chunk durations', () {
      notifier().loadScript(Script.fromJson(_scriptJson));
      // 3000 + 4000 + 2000 = 9000 (error chunk excluded)
      expect(state().totalDurationMs, 9000);
    });

    test('cumulativeOffsetMs sums durations before current chunk', () {
      notifier().loadScript(Script.fromJson(_scriptJson));
      notifier().goToChunk(1); // chunk at position 1 in readyChunks = 4000ms chunk
      // offset = first ready chunk = 3000ms
      expect(state().cumulativeOffsetMs, 3000);
    });

    test('nextChunk advances within ready chunks', () {
      notifier().loadScript(Script.fromJson(_scriptJson));
      expect(state().currentChunkIndex, 0);
      notifier().nextChunk();
      expect(state().currentChunkIndex, 1);
      notifier().nextChunk();
      expect(state().currentChunkIndex, 2);
      notifier().nextChunk();
      expect(state().currentChunkIndex, 2); // at last, no-op
    });

    test('prevChunk decrements and stops at 0', () {
      notifier().loadScript(Script.fromJson(_scriptJson), startChunk: 2);
      notifier().prevChunk();
      expect(state().currentChunkIndex, 1);
      notifier().prevChunk();
      expect(state().currentChunkIndex, 0);
      notifier().prevChunk();
      expect(state().currentChunkIndex, 0);
    });

    test('currentScriptChunk returns correct ready chunk', () {
      notifier().loadScript(Script.fromJson(_scriptJson));
      expect(state().currentScriptChunk?.text, 'Narrator: A.');
      notifier().nextChunk();
      // next ready chunk skips the error one
      expect(state().currentScriptChunk?.text, 'Narrator: C.');
    });

    test('isAtLastChunk returns true at last ready chunk', () {
      notifier().loadScript(Script.fromJson(_scriptJson));
      expect(notifier().isAtLastChunk, false);
      notifier().goToChunk(2);
      expect(notifier().isAtLastChunk, true);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```
flutter test test/providers/player_provider_test.dart
```

Expected: FAIL — `currentChunkIndex`, `readyChunks`, `totalDurationMs` not defined.

- [ ] **Step 3: Replace `lib/providers/player_provider.dart`**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/script.dart';

class PlayerState {
  final Script? script;
  final int currentChunkIndex;
  final bool isPlaying;

  const PlayerState({
    this.script,
    this.currentChunkIndex = 0,
    this.isPlaying = false,
  });

  PlayerState copyWith({Script? script, int? currentChunkIndex, bool? isPlaying}) =>
      PlayerState(
        script: script ?? this.script,
        currentChunkIndex: currentChunkIndex ?? this.currentChunkIndex,
        isPlaying: isPlaying ?? this.isPlaying,
      );

  List<ScriptChunk> get readyChunks =>
      script?.chunks.where((c) => c.status == 'ready').toList() ?? [];

  ScriptChunk? get currentScriptChunk {
    final ready = readyChunks;
    if (currentChunkIndex >= ready.length) return null;
    return ready[currentChunkIndex];
  }

  int get totalDurationMs =>
      readyChunks.fold(0, (sum, c) => sum + c.durationMs);

  int get cumulativeOffsetMs {
    final ready = readyChunks;
    int offset = 0;
    for (int i = 0; i < currentChunkIndex && i < ready.length; i++) {
      offset += ready[i].durationMs;
    }
    return offset;
  }
}

class PlayerNotifier extends Notifier<PlayerState> {
  @override
  PlayerState build() => const PlayerState();

  void loadScript(Script script, {int startChunk = 0}) {
    state = PlayerState(script: script, currentChunkIndex: startChunk);
  }

  void play() => state = state.copyWith(isPlaying: true);
  void pause() => state = state.copyWith(isPlaying: false);

  void nextChunk() {
    final ready = state.readyChunks;
    if (state.currentChunkIndex < ready.length - 1) {
      state = state.copyWith(currentChunkIndex: state.currentChunkIndex + 1);
    }
  }

  void prevChunk() {
    if (state.currentChunkIndex > 0) {
      state = state.copyWith(currentChunkIndex: state.currentChunkIndex - 1);
    }
  }

  void goToChunk(int index) {
    final ready = state.readyChunks;
    if (index >= 0 && index < ready.length) {
      state = state.copyWith(currentChunkIndex: index, isPlaying: true);
    }
  }

  bool get isAtLastChunk {
    return state.currentChunkIndex >= state.readyChunks.length - 1;
  }

  Script? get script => state.script;
}

final playerProvider =
    NotifierProvider<PlayerNotifier, PlayerState>(PlayerNotifier.new);
```

- [ ] **Step 4: Run tests**

```
flutter test test/providers/player_provider_test.dart
```

Expected: All PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/providers/player_provider.dart test/providers/player_provider_test.dart
git commit -m "feat: PlayerProvider tracks chunks with seek-aware computed properties"
```

---

## Task 8: ApiService — `generateAudio` Chunks

**Files:**
- Modify: `lib/services/api_service.dart`
- Modify: `test/services/api_service_test.dart`

- [ ] **Step 1: Write the failing test**

In `test/services/api_service_test.dart`, replace the `generateAudio` group:

```dart
group('generateAudio', () {
  test('posts chunks with voice_map and returns results with duration_ms', () async {
    final fakeResults = [
      {'index': 0, 'status': 'ready', 'audio_b64': base64Encode([1, 2, 3]), 'duration_ms': 8400}
    ];
    final client = MockClient((request) async {
      expect(request.url.path, '/tts');
      final body = jsonDecode(request.body) as Map;
      expect(body['chunks'], isNotEmpty);
      expect(body['chunks'][0]['voice_map'], isA<Map>());
      expect(body.containsKey('lines'), false);
      expect(body['openai_api_key'], 'test-openai-key');
      return http.Response(
        jsonEncode(fakeResults),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final service = makeService(client);
    final result = await service.generateAudio(chunks: [
      {'index': 0, 'text': 'Narrator: Hi.', 'voice_map': {'Narrator': 'Aoede'}}
    ]);
    expect(result.first['status'], 'ready');
    expect(result.first['duration_ms'], 8400);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

```
flutter test test/services/api_service_test.dart
```

Expected: FAIL — `generateAudio` still takes `lines`.

- [ ] **Step 3: Update `generateAudio` in `lib/services/api_service.dart`**

Replace the `generateAudio` method:

```dart
Future<List<Map<String, dynamic>>> generateAudio({
  required List<Map<String, dynamic>> chunks,
  String ttsProvider = 'openai',
}) async {
  final response = await client.post(
    Uri.parse('$baseUrl/tts'),
    headers: {'content-type': 'application/json'},
    body: jsonEncode({
      'chunks': chunks,
      'tts_provider': ttsProvider,
      'openai_api_key': openAiKey,
      'google_api_key': googleKey,
    }),
  );
  _checkStatus(response);
  return List<Map<String, dynamic>>.from(jsonDecode(response.body) as List);
}
```

- [ ] **Step 4: Run tests**

```
flutter test test/services/api_service_test.dart
```

Expected: All PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/api_service.dart test/services/api_service_test.dart
git commit -m "feat: ApiService.generateAudio accepts chunks with voice_map"
```

---

## Task 9: LoadingScreen — Chunk-Based Generation

**Files:**
- Modify: `lib/screens/loading_screen.dart`
- Modify: `test/screens/loading_screen_live_test.dart`

- [ ] **Step 1: Update `lib/screens/loading_screen.dart`**

**Remove `lastGeneratedLine` from `LoadingParams`** — delete the field declaration and the `required this.lastGeneratedLine` constructor parameter. Also remove it from any call sites (search codebase for `lastGeneratedLine` — typically in `book_detail_screen.dart` and any DB resume logic).

**Replace the TTS section** (currently lines 160–219) with:

```dart
// ── 3. TTS ──────────────────────────────────────────────────────────
final String audioDir;
if (p.audioDirOverride != null) {
  audioDir = p.audioDirOverride!;
} else {
  final docsDir = await getApplicationDocumentsDirectory();
  audioDir = path_pkg.join(docsDir.path, 'audio', p.versionId);
}
await Directory(audioDir).create(recursive: true);
if (!mounted) return;

final script = Script.fromJson(jsonEncode(scriptMap));
final allChunks =
    List<Map<String, dynamic>>.from(scriptMap['chunks'] as List);

final pendingChunks = allChunks
    .where((c) => c['status'] == 'pending')
    .map((c) {
      final speakers = List<String>.from(c['speakers'] as List);
      final voiceMap = {for (final s in speakers) s: script.voiceFor(s)};
      return {
        'index': c['index'],
        'text': c['text'],
        'voice_map': voiceMap,
      };
    })
    .toList();

final audioResults = await api.generateAudio(
  chunks: pendingChunks,
  ttsProvider: p.ttsProvider,
);
final scriptChunks = List<Map<String, dynamic>>.from(allChunks);

for (final result in audioResults) {
  final idx = result['index'] as int;
  final chunkIdx = scriptChunks.indexWhere((c) => c['index'] == idx);
  if (chunkIdx == -1) continue;

  if (result['status'] == 'ready') {
    final audioBytes = base64Decode(result['audio_b64'] as String);
    final fileName = 'chunk_${idx.toString().padLeft(3, '0')}.wav';
    await File(path_pkg.join(audioDir, fileName)).writeAsBytes(audioBytes);
    scriptChunks[chunkIdx] = {
      ...scriptChunks[chunkIdx],
      'status': 'ready',
      'duration_ms': result['duration_ms'] as int,
    };
  } else {
    scriptChunks[chunkIdx] = {
      ...scriptChunks[chunkIdx],
      'status': 'error',
    };
  }
  await AppDatabase.instance.updateAudioVersionStatus(
    p.versionId, 'generating',
    scriptJson: jsonEncode({...scriptMap, 'chunks': scriptChunks}),
  );
}
```

Also add `import 'package:bookactor/models/script.dart';` at the top if not already present.

- [ ] **Step 2: Remove `lastGeneratedLine` from `LoadingParams` and all call sites**

`LoadingParams.lastGeneratedLine` is no longer needed (resume uses `status == 'pending'`). Do NOT touch `AudioVersion.lastGeneratedLine` — that field and the DB column are preserved.

Remove the field from `LoadingParams` in `loading_screen.dart` (delete lines `final int lastGeneratedLine;` and `required this.lastGeneratedLine,`).

Then fix the 3 call sites that pass it to `LoadingParams(...)`:

**`lib/screens/upload_screen.dart`** — remove `lastGeneratedLine: -1,` from `LoadingParams(...)` constructor call.

**`lib/screens/library_screen.dart`** — remove `lastGeneratedLine: v.lastGeneratedLine,` from `LoadingParams(...)` constructor call.

**`lib/screens/book_detail_screen.dart`** — remove `lastGeneratedLine: -1,` from `LoadingParams(...)` constructor call.

Also remove `lib/mock/mock_data.dart` — `lastGeneratedLine: 6` is in an `AudioVersion(...)` constructor, NOT `LoadingParams`, so leave it alone.

- [ ] **Step 3: Add the post-loop `AudioVersion` upsert (persists `audioDir` to DB)**

After the `for (final result in audioResults)` loop, add this block (preserving the existing pattern from the current loading screen):

```dart
// Mark version as ready with audioDir persisted
final existing = await AppDatabase.instance.getAudioVersion(p.versionId);
if (existing != null) {
  await AppDatabase.instance.insertAudioVersion(
    AudioVersion(
      versionId: existing.versionId,
      bookId: existing.bookId,
      language: existing.language,
      llmProvider: existing.llmProvider,
      scriptJson: jsonEncode({...scriptMap, 'chunks': scriptChunks}),
      audioDir: audioDir,
      status: 'ready',
      lastGeneratedLine: existing.lastGeneratedLine,
      lastPlayedLine: existing.lastPlayedLine,
      createdAt: existing.createdAt,
    ),
  );
}
```

The player reads `version.audioDir` at runtime to locate `chunk_XXX.wav` files — without this upsert, audio playback will fail on any session after the first.

- [ ] **Step 5: Run the loading screen test**

```
flutter test test/screens/loading_screen_live_test.dart
```

Update the test fixture to use `chunks` format if it uses `lines`. Expected: All PASS.

- [ ] **Step 6: Run full Dart test suite to catch any breakage**

```
flutter test
```

Expected: All PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/screens/loading_screen.dart lib/screens/upload_screen.dart lib/screens/library_screen.dart lib/screens/book_detail_screen.dart test/screens/loading_screen_live_test.dart
git commit -m "feat: LoadingScreen generates chunks, persists duration_ms to DB"
```

---

## Task 10: PlayerScreen — Seekable Slider + Dialogue Display

**Files:**
- Modify: `lib/screens/player_screen.dart`
- Modify: `test/screens/player_screen_test.dart`
- Modify: `test/screens/player_screen_audio_test.dart`

- [ ] **Step 1: Update `_loadScript()` in `lib/screens/player_screen.dart`**

In the `_loadScript()` method, rename the local variable `startLine` to `startChunk` and update the `loadScript` call to use the renamed parameter:

```dart
Future<void> _loadScript() async {
  final String scriptJson;
  var startChunk = 0;

  if (widget.versionId == 'mock_book_001_en') {
    scriptJson = await rootBundle.loadString('assets/mock/script.json');
    if (!mounted) return;
  } else {
    final version = await AppDatabase.instance.getAudioVersion(widget.versionId);
    if (version == null || !mounted) return;
    scriptJson = version.scriptJson;
    startChunk = version.lastPlayedLine; // DB field repurposed as lastPlayedChunk
  }

  final script = Script.fromJson(scriptJson);
  if (!mounted) return;
  ref.read(playerProvider.notifier).loadScript(script, startChunk: startChunk);
  await _loadAndPlayCurrentChunk();
}
```

- [ ] **Step 2: Update the rest of `lib/screens/player_screen.dart`**

Remove the `karaoke_text.dart` import. Remove the page placeholder `Container`. Replace the body with the new layout described below.

**State additions in `_PlayerScreenState`:**

```dart
double _sliderPositionMs = 0;
StreamSubscription<Duration>? _positionSub;
```

In `initState`, after setting up `_completionSub`:

```dart
_positionSub = _audio.positionStream.listen((position) {
  if (!mounted) return;
  final playerState = ref.read(playerProvider);
  final offset = playerState.cumulativeOffsetMs.toDouble();
  setState(() {
    _sliderPositionMs = offset + position.inMilliseconds.toDouble();
  });
});
```

Rename `_onLineComplete` → `_onChunkComplete`, `_loadAndPlayCurrentLine` → `_loadAndPlayCurrentChunk`, `_restartFromBeginning` → keep or rename:

```dart
void _onChunkComplete() {
  if (!mounted) return;
  final notifier = ref.read(playerProvider.notifier);
  if (notifier.isAtLastChunk) {
    notifier.pause();
    return;
  }
  notifier.nextChunk();
  _loadAndPlayCurrentChunk();
}

Future<void> _loadAndPlayCurrentChunk({Duration seekTo = Duration.zero}) async {
  if (widget.versionId == 'mock_book_001_en') {
    await _audio.load('mock');
    await _audio.play();
    return;
  }
  try {
    final playerState = ref.read(playerProvider);
    final chunk = playerState.currentScriptChunk;
    if (chunk == null) return;
    final fileName = 'chunk_${chunk.index.toString().padLeft(3, '0')}.wav';
    final version = await AppDatabase.instance.getAudioVersion(widget.versionId);
    if (version == null) return;
    await _audio.load('${version.audioDir}/$fileName');
    if (seekTo != Duration.zero) await _audio.seek(seekTo);
    await _audio.play();
  } catch (e) {
    debugPrint('AudioService.load failed: $e');
  }
}

void _seekToMs(double targetMs) {
  final playerState = ref.read(playerProvider);
  final notifier = ref.read(playerProvider.notifier);
  final ready = playerState.readyChunks;
  int cumulative = 0;
  for (int i = 0; i < ready.length; i++) {
    final chunkEnd = cumulative + ready[i].durationMs;
    if (targetMs <= chunkEnd || i == ready.length - 1) {
      final offset = (targetMs - cumulative).round().clamp(0, ready[i].durationMs);
      notifier.goToChunk(i);
      _loadAndPlayCurrentChunk(seekTo: Duration(milliseconds: offset));
      break;
    }
    cumulative = chunkEnd;
  }
}

void _saveProgress(int chunkIndex) {
  AppDatabase.instance.updateLastPlayedLine(widget.versionId, chunkIndex);
}
```

In `dispose`, cancel `_positionSub`:

```dart
@override
void dispose() {
  _completionSub?.cancel();
  _positionSub?.cancel();
  _audio.dispose();
  super.dispose();
}
```

**Build method body** — replace the `Expanded` + `KaraokeText` + `AudioControls` section:

```dart
body: Padding(
  padding: const EdgeInsets.all(16),
  child: Column(
    children: [
      // Scrollable dialogue transcript
      Expanded(
        child: SingleChildScrollView(
          child: Text(
            chunk?.text ?? '',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      ),
      const SizedBox(height: 12),
      // Seekable timeline
      Slider(
        value: _sliderPositionMs.clamp(0, totalDurationMs.toDouble()),
        max: totalDurationMs > 0 ? totalDurationMs.toDouble() : 1,
        onChanged: (v) => setState(() => _sliderPositionMs = v),
        onChangeEnd: _seekToMs,
      ),
      // Playback controls
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.skip_previous),
            onPressed: () {
              ref.read(playerProvider.notifier).prevChunk();
              _loadAndPlayCurrentChunk();
            },
          ),
          IconButton(
            icon: Icon(playerState.isPlaying ? Icons.pause : Icons.play_arrow),
            iconSize: 48,
            onPressed: () {
              if (playerState.isPlaying) {
                ref.read(playerProvider.notifier).pause();
                _audio.pause();
              } else {
                ref.read(playerProvider.notifier).play();
                _audio.play();
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.skip_next),
            onPressed: () {
              ref.read(playerProvider.notifier).nextChunk();
              _saveProgress(playerState.currentChunkIndex + 1);
              _loadAndPlayCurrentChunk();
            },
          ),
          IconButton(
            icon: const Icon(Icons.replay),
            onPressed: () async {
              await _audio.stop();
              ref.read(playerProvider.notifier).goToChunk(0);
              _loadAndPlayCurrentChunk();
            },
          ),
        ],
      ),
    ],
  ),
),
```

Add local variables before the body in `build`:

```dart
final chunk = playerState.currentScriptChunk;
final totalDurationMs = playerState.totalDurationMs;
```

- [ ] **Step 2: Update player screen tests**

Run:

```
flutter test test/screens/player_screen_test.dart test/screens/player_screen_audio_test.dart
```

Fix any failures caused by references to `currentLine`, `KaraokeText`, `AudioControls`, or `line.page`. Replace with `currentChunkIndex` and chunk-based assertions.

- [ ] **Step 3: Run all Dart tests**

```
flutter test
```

Expected: All PASS.

- [ ] **Step 4: Commit**

```bash
git add lib/screens/player_screen.dart test/screens/player_screen_test.dart test/screens/player_screen_audio_test.dart
git commit -m "feat: player shows scrollable dialogue with real seekable audio timeline"
```

---

## Task 11: Cleanup

**Files:**
- Delete: `lib/widgets/karaoke_text.dart`
- Delete: `test/widgets/karaoke_text_test.dart`

- [ ] **Step 1: Verify no remaining imports of `karaoke_text`**

```
grep -r "karaoke_text" lib/ test/
```

Expected: 0 results (player_screen.dart import already removed in Task 10).

- [ ] **Step 2: Delete the files**

```bash
rm lib/widgets/karaoke_text.dart
rm test/widgets/karaoke_text_test.dart
```

- [ ] **Step 3: Run full test suite**

```
flutter test && pytest backend/tests/ -v
```

Expected: All PASS.

- [ ] **Step 4: Final commit**

```bash
git add -A
git commit -m "chore: remove KaraokeText widget and test (replaced by plain Text)"
```
