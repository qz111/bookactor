# Qwen TTS for Chinese — Design Spec

**Date:** 2026-03-29
**Status:** Approved

---

## Overview

OpenAI and Gemini TTS produce poor quality audio for Chinese. When the user selects Chinese (Simplified `zh` or Traditional `zh-TW`) as the audio language, the app automatically uses Alibaba's `qwen-tts-instruct-flash` model via DashScope for TTS generation. The switch is automatic and visible in the UI (provider locked to "Qwen").

---

## Architecture

Four layers change: Flutter settings/state, Flutter UI, the LLM script service, and the TTS service.

---

## 1. Flutter — Settings & API key

`qwenKey` is added as a **constructor field** on `ApiService`, exactly like `openAiKey` and `googleKey`:
- `SettingsService`: add `qwenKey` to `saveKeys` / `getKeys`. The `getKeys()` return type is currently a named record `({String openAi, String google})`; this becomes `({String openAi, String google, String qwen})`. Update all destructuring call sites: `apiServiceProvider`, `SettingsScreen`, and any tests that call `getKeys()`.
- `SettingsScreen`: add a Qwen API Key text field; `canSave` guard does **not** require `qwenKey` — it is optional and only needed when Chinese is selected
- `apiServiceProvider` constructs `ApiService` with `qwenKey` from stored settings
- `ApiService.generateAudio`: includes `"qwen_api_key": qwenKey` in the request body (always sent; empty string when not configured)
- `LoadingScreen`: no change needed — `ApiService` is already constructed via provider with all keys

---

## 2. Flutter — UI locking

**Both `UploadScreen` and `_NewLanguageSheetState`:**

The TTS provider dropdown must be locked on **initial state AND on change**:
- `initState` / field initialiser: if the initial `_language` is `zh` or `zh-TW`, set `_ttsProvider = "qwen"` immediately
- `onChanged` for language dropdown: if new value is `zh` or `zh-TW`, set `_ttsProvider = "qwen"` and disable dropdown; otherwise re-enable and restore `_ttsProvider = "openai"`

`_NewLanguageSheet` also has `_language = 'zh'` as its default — so the initial state must already have `_ttsProvider = "qwen"` and the dropdown disabled.

**Language code strings** match exactly the values in `supportedLanguages` in `mock_data.dart`:
```dart
const _chineseCodes = {'zh', 'zh-TW'};
bool get _isChineseSelected => _chineseCodes.contains(_language);
```

**`_NewLanguageSheet` must write `ttsProvider`** into the `AudioVersion` row on insert (currently missing at `book_detail_screen.dart` line ~314). Without this, a Qwen-generated version that errors would resume using `ttsProvider = null ?? 'openai'`, routing TTS incorrectly.

---

## 3. Flutter — `hasKeys` guard

`SettingsService.hasKeys()` continues to require only `openAiKey` and `googleKey`. The Qwen key is **optional** — users who only use Chinese will still need at least one key for VLM/LLM (Google or OpenAI). The guard is not changed.

---

## 4. Backend — LLM service (`llm_service.py`)

### Voice names

Add `"qwen"` entry to `_VOICES`:
```python
"qwen": "Cherry|Ethan|Serena|Dylan"
```
- Female: Cherry, Serena
- Male: Ethan, Dylan

### System prompt

The Gemini-specific gender guidance (`"Female voices: Aoede... Male voices: Charon..."`) is currently hardcoded unconditionally. Make it **provider-conditional**:

```python
# Only emit gender guidance for Gemini voices
if tts_provider == "gemini":
    prompt += "- Female voices: Aoede, Kore, Zephyr, Leda. Male voices: Charon, Fenrir, Puck, Orus.\n"
elif tts_provider == "qwen":
    prompt += "- Female voices: Cherry, Serena. Male voices: Ethan, Dylan.\n"
    prompt += (
        "- For Qwen TTS (Chinese): keep each individual character utterance under "
        "250 Chinese characters. Split long speeches into multiple lines if needed.\n"
    )
```

This ensures the LLM receives correct gender guidance and the utterance length constraint only for the Qwen provider.

---

## 5. Backend — TTS service (`tts_service.py`)

### Request model

```python
class TtsRequest(BaseModel):
    chunks: list[TtsChunk]
    tts_provider: str = "openai"
    openai_api_key: str = ""
    google_api_key: str = ""
    qwen_api_key: str = ""      # new
```

### `generate_audio`

Add `qwen_api_key` parameter and new branch:

```python
elif tts_provider == "qwen":
    client = AsyncOpenAI(
        api_key=qwen_api_key,
        base_url="https://dashscope.aliyuncs.com/compatible-mode/v1",
    )
    results = await _generate_qwen_throttled(client, chunks)
```

### `_generate_qwen_throttled`

Mirrors `_generate_gemini_throttled` exactly, but throttles between **individual segment API calls** (not between chunks), because 180 RPM governs calls to `audio.speech.create`. A chunk with N merged segments makes N API calls — all must respect the rate limit.

```python
async def _generate_qwen_throttled(client, chunks: list[dict], rpm: int = 180) -> list[dict]:
    """Generate Qwen TTS one segment at a time across all chunks, respecting RPM."""
    min_interval = 60.0 / rpm
    results_by_index: dict[int, dict] = {}
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
            results_by_index[chunk["index"]] = {
                "index": chunk["index"], "status": "error", "duration_ms": 0
            }
        else:
            combined = AudioSegment.from_wav(io.BytesIO(wav_parts[0]))
            for part in wav_parts[1:]:
                combined += AudioSegment.from_wav(io.BytesIO(part))
            buf = io.BytesIO()
            combined.export(buf, format="wav")
            wav_bytes = buf.getvalue()
            wav_with_silence = _append_silence(wav_bytes, "wav")
            duration_ms = _wav_duration_ms(wav_with_silence)
            results_by_index[chunk["index"]] = {
                "index": chunk["index"],
                "status": "ready",
                "audio_b64": base64.b64encode(wav_with_silence).decode(),
                "duration_ms": duration_ms,
            }

    return list(results_by_index.values())
```

### `_call_qwen_segment`

Single segment call to DashScope. Returns WAV bytes or `None` on error:

```python
async def _call_qwen_segment(client: AsyncOpenAI, seg: dict) -> bytes | None:
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
```

### `_merge_qwen_segments`

Merges consecutive same-voice segments within the 300-char limit. When merging, joins texts with `"，"` as a natural pause separator (counts as 1 character toward the limit):

```python
def _merge_qwen_segments(segments: list[dict]) -> list[dict]:
    if not segments:
        return []
    merged = [segments[0].copy()]
    for seg in segments[1:]:
        last = merged[-1]
        if seg["voice"] == last["voice"]:
            # +1 for the separator character
            if len(last["text"]) + 1 + len(seg["text"]) <= 300:
                last["text"] = last["text"] + "，" + seg["text"]
                continue
        merged.append(seg.copy())
    return merged
```

### `_split_qwen_segment` / `_flatten_split_qwen_segments`

Splits a single segment exceeding 300 characters:
- Try sentence-end boundaries: `。`, `！`, `？` — find the **last** such punctuation at or before index 300
- Fall back to `，` — find the **last** `，` at or before index 300
- Hard-split at index 300 if no punctuation found (guarantees progress, prevents infinite loop)

```python
def _split_qwen_segment(seg: dict) -> list[dict]:
    text, voice = seg["text"], seg["voice"]
    if len(text) <= 300:
        return [seg]
    results = []
    while len(text) > 300:
        window = text[:300]
        # Find last sentence-end in window
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

---

## Data Flow

```
Flutter: user picks zh / zh-TW
  → _ttsProvider locked to "qwen" (initial state + onChanged)
  → _NewLanguageSheet writes ttsProvider="qwen" to AudioVersion row

generateScript(ttsProvider: "qwen")
  → LLM sees Qwen voice names (Cherry/Ethan/Serena/Dylan)
  → LLM sees utterance length rule (≤250 Chinese chars)

generateAudio(ttsProvider: "qwen", qwenApiKey: ...)
  → POST /tts {qwen_api_key, ...}
  → generate_audio(tts_provider="qwen")
  → _generate_qwen_throttled (rpm=180, per-segment throttle)
      → _parse_chunk_segments
      → _merge_qwen_segments (same-voice consecutive merge ≤300 chars)
      → _flatten_split_qwen_segments (split oversized at punctuation)
      → _call_qwen_segment × N (DashScope audio.speech.create)
      → pydub concatenate → _append_silence → base64 WAV
```

---

## What Does NOT Change

- Gemini and OpenAI TTS paths are untouched
- `_collapse_to_two_speakers` is not called for the Qwen path
- `_parse_chunk_segments`, `_append_silence`, `_pcm_to_wav`, `_wav_duration_ms` reused as-is
- VLM service and routing unchanged
- `hasKeys` guard unchanged (Qwen key is optional)

## Implementation Notes

**`asyncio.get_event_loop().time()`** — `_generate_qwen_throttled` uses the same pattern as the existing `_generate_gemini_throttled` for consistency. Both should eventually be updated to `asyncio.get_running_loop().time()` (preferred in Python 3.10+), but that is out of scope here.

**`_generate_qwen_throttled` result accumulation** — use a plain `list` with `.append()`, matching `_generate_gemini_throttled`. The `break` on segment failure only exits the inner `for seg` loop; the outer `for chunk` loop always processes every chunk, so a dict keyed by index is unnecessary.

**`UploadScreen` versionId** — `UploadScreen` uses `'${bookId}_$_language'` (no provider suffix). `_NewLanguageSheet` uses `'${bookId}_${_language}_$_ttsProvider'`. This pre-existing inconsistency is out of scope; do not change `UploadScreen`'s versionId format as part of this feature.

---

## Testing

### Backend — `tts_service.py`
- `_merge_qwen_segments`: merges consecutive same-voice within 300 chars; does not merge different voices; separator counts toward limit; segment at exactly 300 chars is not split
- `_split_qwen_segment`: splits at last `。/！/？` before 300; falls back to last `，`; hard-splits at 300 when no punctuation; single-element result when text ≤ 300
- `_call_qwen_segment`: mock client; returns `None` on empty response and on exception
- `_generate_qwen_throttled`: mock `_call_qwen_segment`; verify WAV concatenation, silence appended, chunk `status="error"` on segment failure
- `generate_audio` with `tts_provider="qwen"`: verify `AsyncOpenAI` instantiated with DashScope `base_url`

### Backend — `llm_service.py`
- `_system_prompt("qwen")`: Qwen voice names present; utterance length rule present; Gemini voice names absent
- `_system_prompt("gemini")`: Gemini voice names present; Qwen voice names absent

### Flutter
- Dropdown disabled when `zh` or `zh-TW` selected (both via initial state and `onChanged`)
- Dropdown re-enabled when switching to non-Chinese language
- `_NewLanguageSheet` initial state (`_language = 'zh'`): dropdown already disabled, `_ttsProvider = "qwen"`
- `qwen_api_key` present in request body sent by `ApiService.generateAudio`
