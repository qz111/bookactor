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

## Data Model

### Script JSON (new format)

```json
{
  "characters": [
    {"name": "Narrator", "voice": "aoede",  "traits": "calm, warm"},
    {"name": "Bear",     "voice": "charon", "traits": "deep, slow"},
    {"name": "Rabbit",   "voice": "puck",   "traits": "quick, bright"}
  ],
  "chunks": [
    {
      "index": 0,
      "text": "Narrator: The forest was quiet that morning.\nBear: I'm hungry. What shall we eat?\nRabbit: Carrots! I know just the place.\nNarrator: They set off through the trees together.",
      "speakers": ["Narrator", "Bear", "Rabbit"],
      "duration_ms": 8400,
      "status": "pending"
    }
  ]
}
```

**Removed fields:** `page`, per-line `voice`, `lines[]` array
**Added fields:** `chunks[]` array, `speakers[]` per chunk, `duration_ms` per chunk
**`duration_ms`** is always `0` from the LLM; filled in by the frontend after TTS generation from the WAV file header.

## LLM Prompt

System prompt instructs the LLM to:

- Output `characters[]` and `chunks[]` (not `lines[]`)
- Each chunk `text` is formatted as `Character: utterance\n` lines
- Chunk text must be **2000–3000 characters** — never cut mid-sentence; end at natural pause points
- `speakers` lists every character name appearing in that chunk's text
- Character names in `text` must exactly match names in `characters[]`
- Each character keeps the **same voice throughout the entire story** — never reassigned
- Narrator and characters flow naturally together (Narrator sets scene, characters speak)
- `duration_ms` is always `0` (placeholder)
- All dialogue in the language specified by the user

## TTS Service (Backend)

### Request model

```python
class TtsChunk(BaseModel):
    index: int
    text: str
    voice_map: dict[str, str]  # {"Narrator": "aoede", "Bear": "charon"}

class TtsRequest(BaseModel):
    chunks: list[TtsChunk]
    tts_provider: str
    openai_api_key: str
    google_api_key: str
```

### Gemini multi-speaker path

When `len(voice_map) > 1`, use `MultiSpeakerVoiceConfig`:

```python
speech_config = types.SpeechConfig(
    multi_speaker_voice_config=types.MultiSpeakerVoiceConfig(
        speaker_voice_configs=[
            types.SpeakerVoiceConfig(
                speaker=name,
                voice_config=types.VoiceConfig(
                    prebuilt_voice_config=types.PrebuiltVoiceConfig(voice_name=voice)
                )
            )
            for name, voice in voice_map.items()
        ]
    )
)
```

When `len(voice_map) == 1`, fall back to existing single-speaker `VoiceConfig`.

### Response

Each result includes `duration_ms` measured from the WAV header after generation:

```python
{"index": 0, "status": "ready", "audio_b64": "...", "duration_ms": 8400}
```

### Audio files

Saved as `chunk_000.wav`, `chunk_001.wav`, etc.

### Rate limiting

Unchanged — one Gemini call per chunk, throttled at 10 RPM. Each call now covers 5–10x more content.

## Frontend

### Model (`script.dart`)

`ScriptLine` replaced by `ScriptChunk`:

```dart
class ScriptChunk {
  final int index;
  final String text;         // "Narrator: ...\nBear: ..."
  final List<String> speakers;
  final int durationMs;      // 0 until generated
  final String status;       // pending / ready / error
}
```

### Loading screen (`loading_screen.dart`)

- Build `voice_map` by looking up each speaker in `characters[]`
- Send `{index, text, voice_map}` per chunk to the TTS API
- After generation: save `chunk_XXX.wav`, write `duration_ms` from response into chunk, update status

### Player (`player_screen.dart` + `player_provider.dart`)

- **Timeline:** total duration = `sum(chunk.durationMs)`; seek position maps to chunk index + byte offset within that chunk
- **Display:** current chunk's `text` rendered as a scrollable `Text` widget — `\n`-separated lines, no per-character highlighting
- **No page display**, no line index display
- Tracks `currentChunkIndex` instead of `currentLineIndex`

### Database

No schema change. Field semantics repurposed:

| DB field | Old meaning | New meaning |
|---|---|---|
| `lastGeneratedLine` | last line index generated | last chunk index generated |
| `lastPlayedLine` | last line index played | last chunk index played |

## Deletions

Code to remove as part of this change:

- `karaoke_text.dart` widget
- `ScriptLine` model
- `TtsLine` model
- `page` field from LLM prompt, model, and DB logic

## Error Handling

- Chunk generation failure: mark chunk `status: error`, skip saving audio — same pattern as current line error handling
- Null Gemini content (safety filter): existing `finish_reason` check applies unchanged
- JSON parse failure on LLM output: existing retry-once logic applies unchanged
