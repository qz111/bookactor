# TTS Batching & Multi-Speaker Redesign

**Date:** 2026-03-26
**Status:** Approved

## Problem

Gemini TTS has a limit of 50 RPD (requests per day). The current architecture sends one API request per character utterance — short lines of a few words each — wasting the 4KB input capacity and burning through the daily quota rapidly. Audio quality suffers because narrator and character transitions are handled as disconnected single-voice requests.

## Goals

- Use near-full 4KB input per Gemini TTS request
- Reduce RPD consumption by 5–10x
- Enable multi-speaker audio per request (distinct voices in one audio file)
- Real seekable audio timeline in the player
- Audio quality first; text display is a nice-to-have

## Constraints

- Gemini TTS input limit: 4KB per request
- Gemini TTS output limit: 655 seconds of audio (exceeded inputs are cut off)
- At ~150 wpm / ~5 chars per word, 3000 chars ≈ 600 words ≈ ~4 minutes = ~240s — well within limits
- Chunk text target: **2000–3000 characters** (safe margin on both sides)
- Old audio versions: deleted and regenerated (no backward compatibility)

## Voice Name Casing

Gemini voice names use **title case** throughout: `Aoede`, `Charon`, `Fenrir`, `Kore`, `Puck`, `Zephyr`, `Leda`, `Orus`. This matches the existing `GEMINI_VOICES` constant. The LLM prompt specifies voices in title case. **At the point of building `voice_map` in the backend, normalize any stored voice name to title case** (`voice.capitalize()`) before passing to the Gemini API — this handles any legacy lowercase values that may exist in the DB. The `_OPENAI_TO_GEMINI` fallback map values must also be updated to title case.

## Data Model

### Script JSON (new format)

```json
{
  "characters": [
    {"name": "Narrator", "voice": "Aoede",  "traits": "calm, warm"},
    {"name": "Bear",     "voice": "Charon", "traits": "deep, slow"},
    {"name": "Rabbit",   "voice": "Puck",   "traits": "quick, bright"}
  ],
  "chunks": [
    {
      "index": 0,
      "text": "Narrator: The forest was quiet that morning.\nBear: I'm hungry. What shall we eat?\nRabbit: Carrots! I know just the place.\nNarrator: They set off through the trees together.",
      "speakers": ["Narrator", "Bear", "Rabbit"],
      "duration_ms": 0,
      "status": "pending"
    }
  ]
}
```

**Removed fields:** `page`, per-line `voice`, `lines[]` array
**Added fields:** `chunks[]` array, `speakers[]` per chunk, `duration_ms` per chunk
**`duration_ms`** is always `0` from the LLM; filled in by the backend during TTS generation and returned in the TTS response. The frontend writes it into the stored script JSON after generation.

## LLM Prompt

System prompt instructs the LLM to:

- Output `characters[]` and `chunks[]` (not `lines[]`)
- Each chunk `text` is formatted as `Character: utterance\n` lines
- Chunk text must be **2000–3000 characters** — never cut mid-sentence; end at natural pause points
- `speakers` lists every character name appearing in that chunk's text
- Character names in `text` must exactly match names in `characters[]`
- Each character keeps the **same voice throughout the entire story** — never reassigned
- Narrator and characters flow naturally together (Narrator sets scene, characters speak)
- `duration_ms` is always `0` (placeholder, filled by backend after generation)
- All dialogue in the language specified by the user
- Voice names must use title case: `Aoede|Charon|Fenrir|Kore|Puck|Zephyr|Leda|Orus`

## TTS Service (Backend)

### Request model

```python
class TtsChunk(BaseModel):
    index: int
    text: str
    voice_map: dict[str, str]  # {"Narrator": "Aoede", "Bear": "Charon"}

class TtsRequest(BaseModel):
    chunks: list[TtsChunk]
    tts_provider: str
    openai_api_key: str
    google_api_key: str
```

### Gemini multi-speaker path

Normalize each voice name to title case before use: `voice = voice.capitalize()`.

When `len(voice_map) > 1`, use `MultiSpeakerVoiceConfig`. The `speaker` field must match the `Character:` prefix used in the chunk text exactly:

```python
speech_config = types.SpeechConfig(
    multi_speaker_voice_config=types.MultiSpeakerVoiceConfig(
        speaker_voice_configs=[
            types.SpeakerVoiceConfig(
                speaker=name,
                voice_config=types.VoiceConfig(
                    prebuilt_voice_config=types.PrebuiltVoiceConfig(voice_name=voice.capitalize())
                )
            )
            for name, voice in voice_map.items()
        ]
    )
)
```

When `len(voice_map) == 1`, use existing single-speaker `VoiceConfig` with `list(voice_map.values())[0].capitalize()` as the voice name. The `_OPENAI_TO_GEMINI` normalization still applies in this path (handle case where a legacy OpenAI voice name was stored).

### OpenAI path

OpenAI TTS has no multi-speaker API. For each chunk:
1. Parse `Character: text\n` into individual speaker segments (split on newlines, extract character name and utterance)
2. Call OpenAI TTS once per segment with `response_format="wav"` (not `"mp3"`) — WAV is required so pydub can decode the segments without ffmpeg
3. Concatenate resulting WAV bytes using `pydub` (`AudioSegment.from_wav`) into a single WAV file
4. Return as one result for the chunk

**Audio files for OpenAI path:** saved as `chunk_000.wav` (same as Gemini — unified naming).

**Note:** `_generate_one_openai` must be updated to accept a `response_format` parameter defaulting to `"wav"` for chunk generation. The existing `"mp3"` format and `_append_silence` with `fmt="mp3"` are replaced for this path.

### `duration_ms` measurement (backend)

**For WAV** (both Gemini and OpenAI paths), measure duration using Python's `wave` module:

```python
with wave.open(io.BytesIO(wav_bytes)) as w:
    duration_ms = int(w.getnframes() / w.getframerate() * 1000)
```

Include `duration_ms` in every TTS result:

```python
{"index": 0, "status": "ready", "audio_b64": "...", "duration_ms": 8400}
```

### Audio files

All chunks saved as `chunk_000.wav`, `chunk_001.wav`, etc. (both providers).

### Rate limiting

Unchanged — one Gemini call per chunk, throttled at 10 RPM. Each call now covers 5–10x more content.

## Frontend

### API service (`api_service.dart`)

`generateAudio` signature changes from `lines` to `chunks`:

```dart
Future<List<Map<String, dynamic>>> generateAudio({
  required List<Map<String, dynamic>> chunks,  // was: lines
  required String ttsProvider,
});
```

HTTP body field changes from `"lines"` to `"chunks"`. Each element: `{index, text, voice_map: {name: voice}}`.

### Model (`script.dart`)

`ScriptLine` replaced by `ScriptChunk`:

```dart
class ScriptChunk {
  final int index;
  final String text;         // "Narrator: ...\nBear: ..."
  final List<String> speakers;
  final int durationMs;      // 0 until generated, then actual ms
  final String status;       // pending / ready / error
}
```

`Script.voiceFor(characterName)` method is **kept unchanged** — it looks up voice from `characters[]`, which is unchanged in the new format.

### Loading screen (`loading_screen.dart`)

- **Resume filter:** `status == 'pending'` only — purely status-based, no index comparison. This ensures already-generated chunks are never re-processed or overwritten after an interruption.
- `LoadingParams.lastGeneratedLine` is **removed** — the field is no longer needed since resume is driven entirely by `status` flags. The DB `lastGeneratedLine` column is preserved but unused in loading logic (kept to avoid schema change).
- Build `voice_map` per chunk by looking up each speaker in `characters[]` via `Script.voiceFor()`
- Send `{index, text, voice_map}` per chunk to the TTS API
- After generation: save `chunk_XXX.wav`, update the chunk's `status` **and `duration_ms`** in the in-memory script map, then persist the full updated script JSON (including `duration_ms`) to DB via `updateAudioVersionStatus(..., scriptJson: jsonEncode({...scriptMap, 'chunks': updatedChunks}))`. Both fields must be written to DB so the player's seekbar is correct on any subsequent session (script is loaded from DB, not recomputed).

### Player (`player_screen.dart` + `player_provider.dart`)

**Timeline:**
- Total duration = `sum(chunk.durationMs)` across all ready chunks (read from script JSON — no file I/O needed)
- UI: a `Slider` widget spanning `[0, totalDurationMs]`
- During playback: subscribe to `AudioService.positionStream` (wraps `audioplayers` position stream); update slider value as `cumulativeOffsetOfCurrentChunk + currentPosition`
- `onChangeEnd` on slider: map target ms → chunk index (find chunk where cumulative offset contains target ms) + offset within that chunk; stop current audio, load target chunk file, call `AudioService.seek(offsetWithinChunk)`
- At natural chunk boundary: stop current file, load next `chunk_XXX.wav`, seek to `Duration.zero`

**`AudioService` additions:**
- `seek(Duration position)` method wrapping `audioplayers` seek
- `positionStream` property wrapping `audioplayers` `onPositionChanged` stream

**Display:**
- Current chunk's `text` rendered as a scrollable `Text` widget — `\n`-separated `Character: utterance` lines
- No per-character highlighting, no page display, no line index display
- Provider tracks `currentChunkIndex`

### Database

No schema change. `lastPlayedLine` repurposed as `lastPlayedChunk`. `lastGeneratedLine` column preserved but unused in new logic.

| DB field | Old meaning | New meaning |
|---|---|---|
| `lastGeneratedLine` | last line index generated | unused (preserved) |
| `lastPlayedLine` | last line index played | last chunk index played |

## Deletions

Code to remove as part of this change:

- `karaoke_text.dart` widget
- `ScriptLine` model
- `TtsLine` model and `TtsRequest.lines` field
- `page` field from LLM prompt and model
- `LoadingParams.lastGeneratedLine` parameter

## Error Handling

- Chunk generation failure: mark chunk `status: error`, skip saving audio — same pattern as current line error handling
- Null Gemini content (safety filter): existing `finish_reason` check applies unchanged
- JSON parse failure on LLM output: existing retry-once logic applies unchanged
- Resume after interruption: `status == 'pending'` filter ensures already-generated chunks are not re-processed or overwritten
