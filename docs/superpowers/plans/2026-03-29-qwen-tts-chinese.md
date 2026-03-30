# Qwen TTS Chinese Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When the user selects Chinese (`zh` or `zh-TW`) as the audio language, automatically use Alibaba's `qwen-tts-instruct-flash` model via DashScope for TTS, with a locked "Qwen" option in the UI and a new Qwen API key field in settings.

**Architecture:** Approach A — Flutter sets `tts_provider = "qwen"` when Chinese is selected and locks the dropdown. Backend adds a new Qwen branch in `generate_audio` using an `AsyncOpenAI` client pointed at DashScope's OpenAI-compatible endpoint. Segments are merged by same-voice consecutive lines, split at sentence boundaries if over 300 Chinese chars, and throttled at 180 RPM.

**Tech Stack:** Python (FastAPI, openai SDK, pydub), Dart/Flutter (Riverpod, flutter_secure_storage)

**Spec:** `docs/superpowers/specs/2026-03-29-qwen-tts-chinese-design.md`

---

## File Map

| File | Change |
|---|---|
| `backend/services/llm_service.py` | Add `"qwen"` to `_VOICES`; conditionalize gender guidance in `_system_prompt` |
| `backend/tests/test_llm_service.py` | Add `TestSystemPromptQwen` class |
| `backend/services/tts_service.py` | Add `qwen_api_key` param, `_merge_qwen_segments`, `_split_qwen_segment`, `_flatten_split_qwen_segments`, `_call_qwen_segment`, `_generate_qwen_throttled`; new branch in `generate_audio` |
| `backend/routers/tts.py` | Add `qwen_api_key` to `TtsRequest`; pass to `generate_audio` |
| `backend/tests/test_tts_service.py` | Add `TestMergeQwenSegments`, `TestSplitQwenSegment`, `TestCallQwenSegment`, `TestGenerateQwenThrottled`, extend `TestGenerateAudio` |
| `lib/services/settings_service.dart` | Add `_qwenKey` constant; add `qwenKey` to `getKeys`/`saveKeys`/`clearKeys` — update return record type |
| `lib/providers/settings_provider.dart` | Update `apiKeysProvider` and `apiServiceProvider` for new `qwen` record field |
| `lib/services/api_service.dart` | Add `qwenKey` constructor field; pass `qwen_api_key` in `generateAudio` body |
| `lib/screens/settings_screen.dart` | Add Qwen API Key text field and controller; wire `saveKeys`/`_loadExistingKeys` |
| `lib/screens/upload_screen.dart` | Add Chinese detection helper; lock TTS dropdown when Chinese; add Qwen dropdown item |
| `lib/screens/book_detail_screen.dart` | Same locking in `_NewLanguageSheetState`; write `ttsProvider` to `AudioVersion` on insert; add Qwen dropdown item |

---

## Task 1: LLM service — add Qwen voices and conditionalize gender guidance

**Files:**
- Modify: `backend/services/llm_service.py`
- Test: `backend/tests/test_llm_service.py`

The `_system_prompt` function currently hardcodes Gemini gender guidance unconditionally (line 51). We need to:
1. Add `"qwen"` to `_VOICES`
2. Move the gender guidance line inside a provider-conditional block

- [ ] **Step 1: Write failing tests**

Add to `backend/tests/test_llm_service.py`:

```python
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
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd backend && python -m pytest tests/test_llm_service.py::TestSystemPromptQwen -v
```
Expected: 4 FAILED (Cherry/Ethan not in prompt, Aoede still in qwen prompt)

- [ ] **Step 3: Implement**

In `backend/services/llm_service.py`:

```python
# In _VOICES dict, add:
"qwen": "Cherry|Ethan|Serena|Dylan",
```

Replace the hardcoded gender guidance line (currently line ~51):
```python
"- Female voices: Aoede, Kore, Zephyr, Leda. Male voices: Charon, Fenrir, Puck, Orus.\n"
```
with a conditional block. The full `_system_prompt` function should build `prompt` as a string and append the gender section conditionally:

```python
def _system_prompt(tts_provider: str) -> str:
    voices = _VOICES.get(tts_provider, _VOICES["openai"])
    prompt = (
        "You are a children's audiobook script writer. Given the extracted story text from a "
        "picture book, output ONLY a JSON object (no markdown fences) with this exact structure:\n"
        f'{{"characters": [{{"name": "...", "voice": "<{voices}>", "traits": "..."}}], '
        '"chunks": [{"index": <0-based int>, "text": "...", "speakers": ["..."], '
        '"duration_ms": 0, "status": "pending"}]}\n'
        "Rules:\n"
        "- Narrator is always present. Assign each character a distinct voice. "
        "Never change a character's voice mid-story.\n"
        "- Group the full story into sequential dialogue passages. Each chunk's 'text' field "
        "must not exceed 3500 bytes when UTF-8 encoded. "
        "For Latin-script languages (English, French, German, etc.) this allows roughly 2000–3000 characters. "
        "For CJK scripts (Chinese, Japanese, Korean) limit to roughly 800–1000 characters per chunk.\n"
        "- Format 'text' as lines of 'Character: utterance\\n' — each Character name exactly "
        "matching a name in the 'characters' array.\n"
        "- Never cut mid-sentence. Chunks end at natural pause points.\n"
        "- 'speakers' lists every character name that appears in that chunk's text.\n"
        "- Narrator and characters flow naturally together.\n"
        "- 'duration_ms' is always 0.\n"
        "- LANGUAGE RULE: Only the 'text' field inside each chunk must be written in "
        "the language specified by the user. All other fields — character names, traits, "
        "voice names, speakers lists, and all keys — must remain in English.\n"
        "- Character names in the 'text' field must be the same English names as in 'characters'.\n"
        "- Every character must have a UNIQUE voice — never assign the same voice to two characters.\n"
    )
    if tts_provider == "gemini":
        prompt += "- Female voices: Aoede, Kore, Zephyr, Leda. Male voices: Charon, Fenrir, Puck, Orus.\n"
    elif tts_provider == "qwen":
        prompt += "- Female voices: Cherry, Serena. Male voices: Ethan, Dylan.\n"
        prompt += (
            "- For Qwen TTS (Chinese): keep each individual character utterance under "
            "250 Chinese characters. Split long speeches into multiple lines if needed.\n"
        )
    prompt += (
        "- Use gender contrast: if Narrator uses a female voice, assign male voices to male "
        "characters and vice versa. Mix genders across characters for the best listening experience.\n"
        f"- Voice names must use title case: {voices}."
    )
    return prompt
```

- [ ] **Step 4: Run all LLM service tests**

```bash
cd backend && python -m pytest tests/test_llm_service.py -v
```
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add backend/services/llm_service.py backend/tests/test_llm_service.py
git commit -m "feat: add qwen voices and conditionalize gender guidance in llm_service"
```

---

## Task 2: TTS service — segment helpers (`_merge`, `_split`, `_flatten`)

**Files:**
- Modify: `backend/services/tts_service.py`
- Test: `backend/tests/test_tts_service.py`

These three pure functions process the `[{text, voice}]` list before calling the Qwen API.

- [ ] **Step 1: Write failing tests**

Add to `backend/tests/test_tts_service.py`:

```python
class TestMergeQwenSegments:
    def test_merges_consecutive_same_voice(self):
        from backend.services.tts_service import _merge_qwen_segments
        segs = [
            {"text": "你好", "voice": "Cherry"},
            {"text": "再见", "voice": "Cherry"},
        ]
        result = _merge_qwen_segments(segs)
        assert len(result) == 1
        assert result[0]["text"] == "你好，再见"
        assert result[0]["voice"] == "Cherry"

    def test_does_not_merge_different_voices(self):
        from backend.services.tts_service import _merge_qwen_segments
        segs = [
            {"text": "你好", "voice": "Cherry"},
            {"text": "再见", "voice": "Ethan"},
        ]
        result = _merge_qwen_segments(segs)
        assert len(result) == 2

    def test_respects_300_char_limit(self):
        from backend.services.tts_service import _merge_qwen_segments
        # Two segments that together exceed 300 chars should NOT be merged
        long_a = "甲" * 200
        long_b = "乙" * 200
        segs = [{"text": long_a, "voice": "Cherry"}, {"text": long_b, "voice": "Cherry"}]
        result = _merge_qwen_segments(segs)
        assert len(result) == 2

    def test_separator_counts_toward_limit(self):
        from backend.services.tts_service import _merge_qwen_segments
        # Each 150 chars — combined is 150+1+150=301, over limit
        a = "甲" * 150
        b = "乙" * 150
        segs = [{"text": a, "voice": "Cherry"}, {"text": b, "voice": "Cherry"}]
        result = _merge_qwen_segments(segs)
        assert len(result) == 2

    def test_empty_input(self):
        from backend.services.tts_service import _merge_qwen_segments
        assert _merge_qwen_segments([]) == []

    def test_segment_at_exactly_300_chars_not_split(self):
        from backend.services.tts_service import _merge_qwen_segments
        segs = [{"text": "甲" * 300, "voice": "Cherry"}]
        result = _merge_qwen_segments(segs)
        assert len(result) == 1
        assert len(result[0]["text"]) == 300


class TestSplitQwenSegment:
    def test_short_segment_returned_as_is(self):
        from backend.services.tts_service import _split_qwen_segment
        seg = {"text": "你好世界。", "voice": "Cherry"}
        assert _split_qwen_segment(seg) == [seg]

    def test_splits_at_last_sentence_end_before_300(self):
        from backend.services.tts_service import _split_qwen_segment
        # 250 chars + 。 + 60 chars = 311 total — must split at the 。
        part_a = "甲" * 250 + "。"
        part_b = "乙" * 60
        seg = {"text": part_a + part_b, "voice": "Cherry"}
        result = _split_qwen_segment(seg)
        assert len(result) == 2
        assert result[0]["text"] == part_a
        assert result[1]["text"] == part_b

    def test_falls_back_to_comma_when_no_sentence_end(self):
        from backend.services.tts_service import _split_qwen_segment
        # 250 chars + ， + 60 chars, no 。！？
        part_a = "甲" * 250 + "，"
        part_b = "乙" * 60
        seg = {"text": part_a + part_b, "voice": "Ethan"}
        result = _split_qwen_segment(seg)
        assert len(result) == 2
        assert result[0]["text"].endswith("，")

    def test_hard_splits_at_300_when_no_punctuation(self):
        from backend.services.tts_service import _split_qwen_segment
        text = "甲" * 400  # no punctuation at all
        seg = {"text": text, "voice": "Cherry"}
        result = _split_qwen_segment(seg)
        assert len(result) == 2
        assert len(result[0]["text"]) == 300
        assert len(result[1]["text"]) == 100

    def test_voice_preserved_in_all_pieces(self):
        from backend.services.tts_service import _split_qwen_segment
        seg = {"text": "甲" * 400, "voice": "Serena"}
        result = _split_qwen_segment(seg)
        assert all(p["voice"] == "Serena" for p in result)

    def test_flatten_expands_all_segments(self):
        from backend.services.tts_service import _flatten_split_qwen_segments
        segs = [
            {"text": "甲" * 400, "voice": "Cherry"},  # will be split
            {"text": "短文", "voice": "Ethan"},        # will not be split
        ]
        result = _flatten_split_qwen_segments(segs)
        assert len(result) == 3  # 2 pieces from first + 1 from second
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd backend && python -m pytest tests/test_tts_service.py::TestMergeQwenSegments tests/test_tts_service.py::TestSplitQwenSegment -v
```
Expected: ALL FAILED (functions don't exist yet)

- [ ] **Step 3: Implement**

Add to `backend/services/tts_service.py` (after `_parse_chunk_segments`, before the audio generation functions):

```python
def _merge_qwen_segments(segments: list[dict]) -> list[dict]:
    """Merge consecutive same-voice segments that fit within 300 chars (incl. separator)."""
    if not segments:
        return []
    merged = [segments[0].copy()]
    for seg in segments[1:]:
        last = merged[-1]
        if seg["voice"] == last["voice"] and len(last["text"]) + 1 + len(seg["text"]) <= 300:
            last["text"] = last["text"] + "，" + seg["text"]
        else:
            merged.append(seg.copy())
    return merged


def _split_qwen_segment(seg: dict) -> list[dict]:
    """Split a segment exceeding 300 chars at sentence boundaries."""
    text, voice = seg["text"], seg["voice"]
    if len(text) <= 300:
        return [seg]
    results = []
    while len(text) > 300:
        window = text[:300]
        cut = max(window.rfind("。"), window.rfind("！"), window.rfind("？"))
        if cut == -1:
            cut = window.rfind("，")
        if cut == -1:
            cut = 299  # hard split
        results.append({"text": text[:cut + 1], "voice": voice})
        text = text[cut + 1:]
    if text:
        results.append({"text": text, "voice": voice})
    return results


def _flatten_split_qwen_segments(segments: list[dict]) -> list[dict]:
    return [piece for seg in segments for piece in _split_qwen_segment(seg)]
```

- [ ] **Step 4: Run tests**

```bash
cd backend && python -m pytest tests/test_tts_service.py::TestMergeQwenSegments tests/test_tts_service.py::TestSplitQwenSegment -v
```
Expected: ALL PASS

- [ ] **Step 5: Run full test suite to check no regressions**

```bash
cd backend && python -m pytest tests/test_tts_service.py -v
```
Expected: ALL PASS

- [ ] **Step 6: Commit**

```bash
git add backend/services/tts_service.py backend/tests/test_tts_service.py
git commit -m "feat: add _merge_qwen_segments, _split_qwen_segment, _flatten helpers"
```

---

## Task 3: TTS service — `_call_qwen_segment` and `_generate_qwen_throttled`

**Files:**
- Modify: `backend/services/tts_service.py`
- Modify: `backend/routers/tts.py`
- Test: `backend/tests/test_tts_service.py`

`_call_qwen_segment` is one DashScope API call. `_generate_qwen_throttled` orchestrates all chunks at 180 RPM.

- [ ] **Step 1: Write failing tests**

Add to `backend/tests/test_tts_service.py`:

```python
class TestCallQwenSegment:
    def test_returns_wav_bytes_on_success(self):
        from backend.services import tts_service

        fake_wav = _make_wav(500)
        mock_response = MagicMock()
        mock_response.content = fake_wav
        mock_client = MagicMock()

        async def fake_create(**kwargs):
            return mock_response

        mock_client.audio.speech.create = fake_create
        result = asyncio.run(tts_service._call_qwen_segment(
            mock_client, {"text": "你好", "voice": "Cherry"}
        ))
        assert result == fake_wav

    def test_returns_none_on_empty_response(self):
        from backend.services import tts_service

        mock_response = MagicMock()
        mock_response.content = b""
        mock_client = MagicMock()

        async def fake_create(**kwargs):
            return mock_response

        mock_client.audio.speech.create = fake_create
        result = asyncio.run(tts_service._call_qwen_segment(
            mock_client, {"text": "你好", "voice": "Cherry"}
        ))
        assert result is None

    def test_returns_none_on_exception(self):
        from backend.services import tts_service

        mock_client = MagicMock()

        async def fake_create(**kwargs):
            raise RuntimeError("API down")

        mock_client.audio.speech.create = fake_create
        result = asyncio.run(tts_service._call_qwen_segment(
            mock_client, {"text": "你好", "voice": "Cherry"}
        ))
        assert result is None

    def test_calls_correct_model_and_format(self):
        from backend.services import tts_service

        fake_wav = _make_wav(200)
        mock_response = MagicMock()
        mock_response.content = fake_wav
        mock_client = MagicMock()
        captured = {}

        async def fake_create(**kwargs):
            captured.update(kwargs)
            return mock_response

        mock_client.audio.speech.create = fake_create
        asyncio.run(tts_service._call_qwen_segment(
            mock_client, {"text": "你好", "voice": "Cherry"}
        ))
        assert captured["model"] == "qwen-tts-instruct-flash"
        assert captured["response_format"] == "wav"
        assert captured["voice"] == "Cherry"
        assert captured["input"] == "你好"


class TestGenerateQwenThrottled:
    def test_returns_ready_result_for_each_chunk(self):
        from backend.services import tts_service

        fake_wav = _make_wav(500)
        mock_client = MagicMock()

        async def fake_call(client, seg):
            return fake_wav

        chunks = [
            {"index": 0, "text": "Narrator: 你好。", "voice_map": {"Narrator": "Cherry"}},
            {"index": 1, "text": "Bear: 再见。", "voice_map": {"Bear": "Ethan"}},
        ]
        with patch.object(tts_service, "_call_qwen_segment", side_effect=fake_call):
            results = asyncio.run(tts_service._generate_qwen_throttled(mock_client, chunks))

        assert len(results) == 2
        assert all(r["status"] == "ready" for r in results)

    def test_chunk_error_on_segment_failure(self):
        from backend.services import tts_service

        mock_client = MagicMock()

        async def fake_call(client, seg):
            return None  # simulates failure

        chunks = [{"index": 0, "text": "Narrator: 你好。", "voice_map": {"Narrator": "Cherry"}}]
        with patch.object(tts_service, "_call_qwen_segment", side_effect=fake_call):
            results = asyncio.run(tts_service._generate_qwen_throttled(mock_client, chunks))

        assert results[0]["status"] == "error"
        assert results[0]["duration_ms"] == 0

    def test_silence_appended_to_output(self):
        from backend.services import tts_service

        raw_wav = _make_wav(500)
        mock_client = MagicMock()

        async def fake_call(client, seg):
            return raw_wav

        chunks = [{"index": 0, "text": "Narrator: 你好。", "voice_map": {"Narrator": "Cherry"}}]
        with patch.object(tts_service, "_call_qwen_segment", side_effect=fake_call):
            results = asyncio.run(tts_service._generate_qwen_throttled(mock_client, chunks))

        # silence adds ~600 ms; raw wav is 500 ms → result must be > 500
        assert results[0]["status"] == "ready"
        assert results[0]["duration_ms"] > 500


class TestGenerateAudioQwen:
    def test_routes_to_qwen_with_dashscope_base_url(self):
        from backend.services import tts_service

        fake_result = [{"index": 0, "status": "ready", "audio_b64": "x", "duration_ms": 500}]

        async def fake_throttled(client, chunks, rpm=180):
            return fake_result

        with patch("backend.services.tts_service._generate_qwen_throttled", side_effect=fake_throttled), \
             patch("backend.services.tts_service.AsyncOpenAI") as mock_openai:
            mock_openai.return_value = MagicMock()
            result = asyncio.run(tts_service.generate_audio(
                chunks=[{"index": 0, "text": "Narrator: 你好。", "voice_map": {"Narrator": "Cherry"}}],
                tts_provider="qwen",
                openai_api_key="",
                google_api_key="",
                qwen_api_key="test-key",
            ))

        mock_openai.assert_called_once_with(
            api_key="test-key",
            base_url="https://dashscope.aliyuncs.com/compatible-mode/v1",
        )
        assert result[0]["status"] == "ready"
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd backend && python -m pytest tests/test_tts_service.py::TestCallQwenSegment tests/test_tts_service.py::TestGenerateQwenThrottled tests/test_tts_service.py::TestGenerateAudioQwen -v
```
Expected: ALL FAILED

- [ ] **Step 3: Implement `_call_qwen_segment` and `_generate_qwen_throttled`**

Add to `backend/services/tts_service.py` (after `_flatten_split_qwen_segments`):

```python
async def _call_qwen_segment(client: AsyncOpenAI, seg: dict) -> bytes | None:
    """Call DashScope for a single segment. Returns WAV bytes or None on error."""
    try:
        response = await client.audio.speech.create(
            model="qwen-tts-instruct-flash",
            input=seg["text"],
            voice=seg["voice"],
            response_format="wav",
        )
        if not response.content:
            raise ValueError("Empty response from DashScope")
        return response.content
    except Exception:
        logger.exception("Qwen TTS segment call failed")
        return None


async def _generate_qwen_throttled(client, chunks: list[dict], rpm: int = 180) -> list[dict]:
    """Generate Qwen TTS across all chunks, throttling between each API call at rpm."""
    min_interval = 60.0 / rpm
    results = []
    last_start: float | None = None

    for chunk in chunks:
        segments = _parse_chunk_segments(chunk["text"], chunk["voice_map"])
        segments = _merge_qwen_segments(segments)
        segments = _flatten_split_qwen_segments(segments)

        wav_parts = []
        chunk_error = False
        for seg in segments:
            if last_start is not None:
                elapsed = asyncio.get_event_loop().time() - last_start
                wait = min_interval - elapsed
                if wait > 0:
                    await asyncio.sleep(wait)
            last_start = asyncio.get_event_loop().time()

            part = await _call_qwen_segment(client, seg)
            if part is None:
                chunk_error = True
                break
            wav_parts.append(part)

        if chunk_error or not wav_parts:
            results.append({"index": chunk["index"], "status": "error", "duration_ms": 0})
        else:
            combined = AudioSegment.from_wav(io.BytesIO(wav_parts[0]))
            for part in wav_parts[1:]:
                combined += AudioSegment.from_wav(io.BytesIO(part))
            buf = io.BytesIO()
            combined.export(buf, format="wav")
            wav_bytes = buf.getvalue()
            wav_with_silence = _append_silence(wav_bytes, "wav")
            duration_ms = _wav_duration_ms(wav_with_silence)
            results.append({
                "index": chunk["index"],
                "status": "ready",
                "audio_b64": base64.b64encode(wav_with_silence).decode(),
                "duration_ms": duration_ms,
            })

    return results
```

- [ ] **Step 4: Update `generate_audio` signature and add Qwen branch**

In `backend/services/tts_service.py`, update `generate_audio`:

```python
async def generate_audio(
    chunks: list[dict],
    tts_provider: str,
    openai_api_key: str,
    google_api_key: str,
    qwen_api_key: str = "",
) -> list[dict]:
    """Generate TTS audio for all chunks; returns results sorted by index."""
    if tts_provider == "gemini":
        client = genai.Client(api_key=google_api_key)
        results = await _generate_gemini_throttled(client, chunks)
    elif tts_provider == "qwen":
        client = AsyncOpenAI(
            api_key=qwen_api_key,
            base_url="https://dashscope.aliyuncs.com/compatible-mode/v1",
        )
        results = await _generate_qwen_throttled(client, chunks)
    else:
        client = AsyncOpenAI(api_key=openai_api_key)
        tasks = [_generate_chunk_openai(client, chunk) for chunk in chunks]
        results = list(await asyncio.gather(*tasks))
    return sorted(results, key=lambda r: r["index"])
```

- [ ] **Step 5: Update `TtsRequest` and router**

In `backend/routers/tts.py`, add `qwen_api_key` to the request model and pass it through:

```python
class TtsRequest(BaseModel):
    chunks: list[TtsChunk]
    tts_provider: str = "openai"
    openai_api_key: str = ""
    google_api_key: str = ""
    qwen_api_key: str = ""


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
            qwen_api_key=req.qwen_api_key,
        )
    except Exception as exc:
        logger.exception("Error in /tts")
        raise HTTPException(status_code=500, detail=f"{type(exc).__name__}: {exc}") from exc
```

- [ ] **Step 6: Run all tests**

```bash
cd backend && python -m pytest tests/test_tts_service.py tests/test_tts_router.py -v
```
Expected: ALL PASS

- [ ] **Step 7: Commit**

```bash
git add backend/services/tts_service.py backend/routers/tts.py backend/tests/test_tts_service.py
git commit -m "feat: add Qwen TTS provider with DashScope integration and 180 RPM throttle"
```

---

## Task 4: Flutter — settings service and providers

**Files:**
- Modify: `lib/services/settings_service.dart`
- Modify: `lib/providers/settings_provider.dart`
- Modify: `lib/services/api_service.dart`

`SettingsService.getKeys()` returns a named record `({String openAi, String google})`. Adding `qwenKey` changes this record type. All consumers of `getKeys()` must be updated in the same task to avoid a compilation error.

- [ ] **Step 1: Update `SettingsService`**

Replace `lib/services/settings_service.dart` entirely:

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SettingsService {
  static const _openAiKey = 'openai_api_key';
  static const _googleKey = 'google_api_key';
  static const _qwenKey = 'qwen_api_key';

  final FlutterSecureStorage _storage;

  SettingsService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  Future<bool> hasKeys() async {
    final openAi = await _storage.read(key: _openAiKey);
    final google = await _storage.read(key: _googleKey);
    return openAi != null &&
        openAi.isNotEmpty &&
        google != null &&
        google.isNotEmpty;
  }

  Future<({String openAi, String google, String qwen})> getKeys() async {
    final openAi = await _storage.read(key: _openAiKey) ?? '';
    final google = await _storage.read(key: _googleKey) ?? '';
    final qwen = await _storage.read(key: _qwenKey) ?? '';
    return (openAi: openAi, google: google, qwen: qwen);
  }

  Future<void> saveKeys({
    required String openAiKey,
    required String googleKey,
    String qwenKey = '',
  }) async {
    await _storage.write(key: _openAiKey, value: openAiKey);
    await _storage.write(key: _googleKey, value: googleKey);
    await _storage.write(key: _qwenKey, value: qwenKey);
  }

  Future<void> clearKeys() async {
    await _storage.delete(key: _openAiKey);
    await _storage.delete(key: _googleKey);
    await _storage.delete(key: _qwenKey);
  }
}
```

- [ ] **Step 2: Update `settings_provider.dart`**

Replace `lib/providers/settings_provider.dart` entirely:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/settings_service.dart';
import '../services/api_service.dart';

/// Singleton SettingsService instance.
final settingsServiceProvider = Provider<SettingsService>((ref) {
  return SettingsService();
});

/// Loads all API keys from secure storage.
/// Invalidate this after saveKeys() to rebuild apiServiceProvider.
final apiKeysProvider =
    FutureProvider<({String openAi, String google, String qwen})>((ref) async {
  return ref.watch(settingsServiceProvider).getKeys();
});

/// Builds ApiService pre-loaded with the saved API keys.
final apiServiceProvider = FutureProvider<ApiService>((ref) async {
  final keys = await ref.watch(apiKeysProvider.future);
  return ApiService(
    baseUrl: 'http://localhost:8088',
    openAiKey: keys.openAi,
    googleKey: keys.google,
    qwenKey: keys.qwen,
  );
});

/// Initial GoRouter location — overridden in main.dart based on hasKeys().
final initialLocationProvider = Provider<String>((_) => '/');
```

- [ ] **Step 3: Update `ApiService`**

In `lib/services/api_service.dart`, add `qwenKey` as a constructor field and pass it in `generateAudio`:

```dart
class ApiService {
  final String baseUrl;
  final String openAiKey;
  final String googleKey;
  final String qwenKey;          // new
  final http.Client client;

  ApiService({
    required this.baseUrl,
    required this.openAiKey,
    required this.googleKey,
    this.qwenKey = '',           // new, optional
    http.Client? client,
  }) : client = client ?? http.Client();
```

In `generateAudio`, add `qwen_api_key` to the request body:

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
        'qwen_api_key': qwenKey,   // new
      }),
    );
    _checkStatus(response);
    return List<Map<String, dynamic>>.from(jsonDecode(response.body) as List);
  }
```

- [ ] **Step 4: Verify Flutter compiles**

```bash
cd D:/developer_tools/bookactor && flutter analyze lib/services/ lib/providers/
```
Expected: No issues found

- [ ] **Step 5: Commit**

```bash
git add lib/services/settings_service.dart lib/providers/settings_provider.dart lib/services/api_service.dart
git commit -m "feat: add qwenKey to SettingsService, ApiService, and providers"
```

---

## Task 5: Flutter — Settings screen (Qwen API Key field)

> **Depends on Task 4** — `saveKeys` and `getKeys` must already have the `qwenKey` parameter before this task compiles.

**Files:**
- Modify: `lib/screens/settings_screen.dart`

Add a Qwen API Key text field below the Google field, matching the existing pattern.

- [ ] **Step 1: Implement**

In `lib/screens/settings_screen.dart`:

Add controller and visibility state alongside the existing ones:
```dart
final _qwenController = TextEditingController();
bool _showQwen = false;
```

In `_loadExistingKeys`, add:
```dart
_qwenController.text = keys.qwen;
```

In `dispose`, add:
```dart
_qwenController.dispose();
```

In `_save`, pass qwenKey:
```dart
await ref.read(settingsServiceProvider).saveKeys(
  openAiKey: _openAiController.text.trim(),
  googleKey: _googleController.text.trim(),
  qwenKey: _qwenController.text.trim(),   // new
);
```

In `build`, after the Google key field and `SizedBox(height: 16)`, add:
```dart
const SizedBox(height: 16),
TextField(
  controller: _qwenController,
  obscureText: !_showQwen,
  onChanged: (_) => setState(() {}),
  decoration: InputDecoration(
    labelText: 'Qwen API Key (DashScope)',
    border: const OutlineInputBorder(),
    suffixIcon: IconButton(
      icon: Icon(_showQwen ? Icons.visibility_off : Icons.visibility),
      onPressed: () => setState(() => _showQwen = !_showQwen),
    ),
  ),
),
```

Note: `canSave` guard is unchanged — Qwen key is optional.

- [ ] **Step 2: Verify Flutter compiles**

```bash
cd D:/developer_tools/bookactor && flutter analyze lib/screens/settings_screen.dart
```
Expected: No issues

- [ ] **Step 3: Commit**

```bash
git add lib/screens/settings_screen.dart
git commit -m "feat: add Qwen API Key field to SettingsScreen"
```

---

## Task 6: Flutter — UI locking (UploadScreen + _NewLanguageSheet)

**Files:**
- Modify: `lib/screens/upload_screen.dart`
- Modify: `lib/screens/book_detail_screen.dart`

Both screens need: (a) a Qwen item in the TTS dropdown, (b) locking `_ttsProvider = "qwen"` and disabling the dropdown when Chinese is selected, and (c) restoring to `"openai"` when language changes away from Chinese. `_NewLanguageSheetState` also needs to write `ttsProvider` to the `AudioVersion` insert.

### Part A: `UploadScreen`

- [ ] **Step 1: Add Chinese detection and locking to `UploadScreen`**

In `lib/screens/upload_screen.dart`, the state class has `String _language = 'en'` and `String _ttsProvider = 'openai'`. The language dropdown `onChanged` currently does:
```dart
onChanged: (v) => setState(() => _language = v!),
```

Replace with:
```dart
onChanged: (v) => setState(() {
  _language = v!;
  if (const {'zh', 'zh-TW'}.contains(_language)) {
    _ttsProvider = 'qwen';
  } else if (_ttsProvider == 'qwen') {
    _ttsProvider = 'openai';
  }
}),
```

Replace the TTS dropdown widget with a version that adds the Qwen item and disables when Chinese:
```dart
DropdownButtonFormField<String>(
  value: _ttsProvider,
  decoration: const InputDecoration(
      labelText: 'Text-to-Speech (TTS)',
      border: OutlineInputBorder()),
  items: const [
    DropdownMenuItem(value: 'openai', child: Text('OpenAI TTS')),
    DropdownMenuItem(value: 'gemini', child: Text('Gemini TTS')),
    DropdownMenuItem(value: 'qwen', child: Text('Qwen TTS (Chinese)')),
  ],
  onChanged: const {'zh', 'zh-TW'}.contains(_language)
      ? null
      : (v) => setState(() => _ttsProvider = v!),
),
```

Note: `_language = 'en'` by default so the initial state is not Chinese — no `initState` change needed for `UploadScreen`. The spec defines an `_isChineseSelected` getter; this plan inlines `const {'zh', 'zh-TW'}.contains(_language)` at each site (two per screen) for simplicity — the logic is identical.

### Part B: `_NewLanguageSheetState`

- [ ] **Step 2: Update `_NewLanguageSheetState` field initialisers**

In `lib/screens/book_detail_screen.dart`, `_NewLanguageSheetState` has:
```dart
String _language = 'zh';
String _ttsProvider = 'openai';
```

The default language is `'zh'` so the initial `_ttsProvider` must be `'qwen'`. Change to:
```dart
String _language = 'zh';
String _ttsProvider = 'qwen';   // locked because default language is zh
```

- [ ] **Step 3: Update the language dropdown `onChanged` in `_NewLanguageSheetState`**

Replace:
```dart
onChanged: (v) => setState(() => _language = v!),
```
With:
```dart
onChanged: (v) => setState(() {
  _language = v!;
  if (const {'zh', 'zh-TW'}.contains(_language)) {
    _ttsProvider = 'qwen';
  } else if (_ttsProvider == 'qwen') {
    _ttsProvider = 'openai';
  }
}),
```

- [ ] **Step 4: Update TTS dropdown in `_NewLanguageSheetState`**

Add the Qwen item and lock when Chinese. Replace the existing `DropdownButtonFormField` for TTS (currently at lines ~296–306):

```dart
DropdownButtonFormField<String>(
  value: _ttsProvider,
  decoration: const InputDecoration(
      labelText: 'Text-to-Speech (TTS)',
      border: OutlineInputBorder()),
  items: const [
    DropdownMenuItem(value: 'openai', child: Text('OpenAI TTS')),
    DropdownMenuItem(value: 'gemini', child: Text('Gemini TTS')),
    DropdownMenuItem(value: 'qwen', child: Text('Qwen TTS (Chinese)')),
  ],
  onChanged: const {'zh', 'zh-TW'}.contains(_language)
      ? null
      : (v) => setState(() => _ttsProvider = v!),
),
```

- [ ] **Step 5: Write `ttsProvider` into the `AudioVersion` row**

In the `Generate` button `onPressed` (around line ~314), the `insertAudioVersion` call currently does NOT pass `ttsProvider`. Add it:

```dart
await AppDatabase.instance.insertAudioVersion(AudioVersion(
  versionId: versionId,
  bookId: widget.book.bookId,
  language: _language,
  llmProvider: _llmProvider,
  ttsProvider: _ttsProvider,   // new — was missing
  scriptJson: '{}',
  audioDir: '',
  status: 'generating',
  lastGeneratedLine: 0,
  lastPlayedLine: 0,
  createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
));
```

- [ ] **Step 6: Verify Flutter compiles**

```bash
cd D:/developer_tools/bookactor && flutter analyze lib/screens/upload_screen.dart lib/screens/book_detail_screen.dart
```
Expected: No issues

- [ ] **Step 7: Commit**

```bash
git add lib/screens/upload_screen.dart lib/screens/book_detail_screen.dart
git commit -m "feat: lock TTS dropdown to Qwen when Chinese selected; write ttsProvider to AudioVersion"
```

---

## Task 7: Smoke test end-to-end

- [ ] **Step 1: Run full backend test suite**

```bash
cd D:/developer_tools/bookactor/backend && python -m pytest tests/ -v
```
Expected: ALL PASS

- [ ] **Step 2: Run Flutter analysis**

```bash
cd D:/developer_tools/bookactor && flutter analyze
```
Expected: No issues found

- [ ] **Step 3: Run Flutter unit tests**

```bash
cd D:/developer_tools/bookactor && flutter test
```
Expected: ALL PASS

- [ ] **Step 4: Final commit if any fixups were made**

```bash
git add -p  # stage only intended changes
git commit -m "fix: post-integration fixups for Qwen TTS"
```
