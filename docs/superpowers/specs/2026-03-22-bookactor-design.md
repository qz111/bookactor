# BookActor — Design Spec
**Date:** 2026-03-22
**Status:** Approved

---

## 1. Project Overview

BookActor is a cross-platform children's audiobook app (iOS, iPadOS, Windows Desktop) that turns picture books (PDFs or images) into immersive, multi-character audiobooks using a VLM → LLM → TTS pipeline.

---

## 2. Tech Stack

| Layer | Choice | Rationale |
|---|---|---|
| Frontend | Flutter | Single codebase for iOS/iPadOS/Windows; developer has existing Flutter + Codemagic workflow |
| Backend proxy | Python + FastAPI | Best AI ecosystem; async; clean API design |
| LLM/VLM routing | LiteLLM | Unified interface for Gemini and GPT-4o; swap providers via config, no code changes |
| VLM | Gemini Vision or GPT-4o Vision | User-selectable per book |
| LLM | GPT-4o or Gemini (via LiteLLM) | Script generation + translation |
| TTS | OpenAI TTS | Multilingual, 6 voices, deterministic per voice ID |
| Local DB | SQLite (via sqflite on Flutter) | Book index + audio version metadata |
| iOS builds | Codemagic CI + Sideloadly | Developer is Windows-only; cloud Mac build |

---

## 3. Core Workflow

1. User uploads PDF or images of a children's book. **PDF-to-image conversion happens on the Flutter client** (using a Flutter PDF rendering library, e.g., `pdfx`) before upload. The backend only ever receives image files.
2. Flutter sends page images to `/analyze`; backend calls VLM (Gemini or GPT-4o Vision) → extracts story/text per page
3. LLM translates text into the chosen language, identifies characters, assigns voice IDs, and outputs a structured JSON script
4. Backend calls OpenAI TTS once per dialogue line, using the assigned voice for each character
5. Audio files returned to Flutter, saved locally with the JSON script
6. Flutter plays audio in sequence with karaoke text highlighting and auto page-advance

---

## 4. Architecture

```
Flutter Client
  ├── Library screen
  ├── Book Detail screen
  ├── Upload screen (new books only)
  ├── Loading screen
  └── Player screen
        │
        │ HTTPS/REST — Flutter orchestrates the three calls below
        │ (new book: all 3; new language: /script + /tts only)
        ▼
FastAPI Backend Proxy
  ├── POST /analyze   — receives page images (multipart), calls VLM, returns extracted text per page
  │                     Request: multipart form — images[] + vlm_provider ("gemini"|"gpt4o")
  │                     Response: { "pages": [{"page": 1, "text": "..."}] }
  │
  ├── POST /script    — receives VLM output + language + llm_provider, calls LLM, returns JSON script
  │                     Request: { "vlm_output": [...], "language": "zh", "llm_provider": "gpt4o" }
  │                     Response: { "script": { "characters": [...], "lines": [...] } }
  │
  └── POST /tts       — receives full lines array, calls OpenAI TTS in parallel for all lines,
                        returns JSON manifest with base64-encoded mp3 per line
                        Request: { "lines": [{"index": 0, "text": "...", "voice": "alloy"}] }
                        (client resolves voice per line from characters[] before sending — voice is a transient
                        field in this API payload only, not stored on lines in script_json)
                        Response: [{"index": 0, "status": "ready", "audio_b64": "..."}, {"index": 1, "status": "error"}]
        │
        │ via LiteLLM (VLM/LLM) + OpenAI SDK (TTS)
        ▼
AI Services
  ├── Gemini Vision / GPT-4o Vision  (user picks)
  ├── GPT-4o / Gemini                (LLM script + translation)
  └── OpenAI TTS                     (6 voices: alloy, echo, fable, onyx, nova, shimmer)
```

**Orchestration:** The Flutter client drives the pipeline — it calls `/analyze`, saves the result, calls `/script`, saves the result, then calls `/tts`. This keeps the backend stateless and lets the client save intermediate results to SQLite as each step completes, enabling granular resume.

API keys live on the backend only — never on the client.

---

## 5. Local Persistence — Two-Layer Model

### Layer 1: `books` table
One row per uploaded book. VLM runs once per book and is never repeated.

| Column | Type | Notes |
|---|---|---|
| `book_id` | TEXT PK | SHA-256 hash of original file |
| `title` | TEXT | Extracted or user-supplied |
| `cover_path` | TEXT | Local path to cover thumbnail |
| `pages_dir` | TEXT | Local path to folder of page images |
| `vlm_output` | TEXT | JSON — extracted story/text per page |
| `vlm_provider` | TEXT | `gemini` or `gpt4o` |
| `created_at` | INTEGER | Unix timestamp |

### Layer 2: `audio_versions` table
One row per book + language combo. LLM + TTS run once per language.

| Column | Type | Notes |
|---|---|---|
| `version_id` | TEXT PK | `{book_id}_{language}` e.g. `abc123_zh`, `abc123_zh-TW`. BCP 47 uses hyphens (not underscores), so the `_` separator is unambiguous. |
| `book_id` | TEXT FK | References `books` |
| `language` | TEXT | BCP 47 language tag: `en`, `zh`, `zh-TW`, `fr`… The LLM prompt explicitly instructs the model to use BCP 47 tags in its output. |
| `llm_provider` | TEXT | `gpt4o` or `gemini` — stored at generation time, informational |
| `script_json` | TEXT | Characters, voice assignments, ordered dialogue lines |
| `audio_dir` | TEXT | Local path to folder of .mp3 files |
| `status` | TEXT | `generating` / `ready` / `error` |
| `last_generated_line` | INTEGER | Index of last successfully generated TTS line; used to resume partial generation. Updated in SQLite after every individual TTS line result (success or error), so crash recovery can reconstruct exact state. |
| `last_played_line` | INTEGER | Index of last played line; used to resume playback (default 0) |
| `created_at` | INTEGER | Unix timestamp |

### Cold-start behavior for `generating` rows
On app launch, the Library screen queries for any `audio_versions` with `status = 'generating'`. For each found row, the app shows a prompt: "This audiobook was interrupted. Resume generation?" — Yes resumes from `last_generated_line + 1`; No marks the row as `error`.

### Cache-first logic
| Scenario | What runs |
|---|---|
| New book upload | VLM + LLM + TTS (full pipeline) |
| Same book, new language | LLM + TTS only (VLM output reused from Layer 1) |
| Book + language already exists | Play instantly — zero API calls |

---

## 6. JSON Script Format

```json
{
  "characters": [
    { "name": "Narrator", "voice": "alloy" },
    { "name": "Little Girl", "voice": "nova", "traits": "curious, cheerful" },
    { "name": "Old Man", "voice": "onyx", "traits": "gentle, wise" }
  ],
  "lines": [
    { "index": 0, "character": "Narrator", "text": "Once upon a time...", "page": 1, "status": "ready" },
    { "index": 1, "character": "Little Girl", "text": "What is that?", "page": 2, "status": "ready" },
    { "index": 2, "character": "Old Man", "text": "Come and see.", "page": 2, "status": "error" }
  ]
}
```

- `voice` is **not** stored on lines in `script_json` — the player and the `/tts` caller both resolve voice by matching `character` to `characters[].name`. This is the authoritative rule for `script_json` storage; the `/tts` API payload is a separate transient structure that does carry `voice` for convenience.
- `lines[].status` values: `"ready"` (mp3 exists), `"error"` (TTS failed, skip during playback), `"pending"` (not yet generated)
- `script_json` write schedule: written once to SQLite after `/script` returns (all lines `"pending"`), then updated incrementally after each TTS line result to set `lines[n].status` to `"ready"` or `"error"`. This means `script_json` is rewritten to SQLite once per TTS line during generation.
- Audio files: `{audio_dir}/line_000.mp3`, `line_001.mp3`… matched by `index`. Only `ready` lines have a corresponding file.

---

## 7. Flutter App Screens

1. **Library** — grid of saved books; each shows available language badges; "+ Add Book" button
2. **Book Detail** — cover, list of ready audio versions (tap to play), "+ New Language" button
3. **Upload** *(new books only)* — file picker (PDF/images), language selector, VLM picker, LLM picker, Generate button. New language requests skip this screen and show a minimal sheet: language selector + LLM picker (VLM is not re-run), then go directly to Loading.
4. **Loading** — child-friendly animated steps: "Reading pages…" → "Writing script…" → "Recording voices…". Error states:
   - Fatal error (VLM fails; LLM returns malformed JSON after 1 automatic retry with a stricter prompt): show error message + "Go Back" button → returns to Book Detail
   - Recoverable error (network drop, API timeout): show "Something went wrong" + "Try Again" button → resumes from last saved line
   - Partial TTS failure (some lines errored but generation completes): proceed to Player automatically (error lines are silently skipped)
5. **Player** — current page image, highlighted karaoke line + character name, prev/pause/next controls, progress bar. Auto-advances page on `page` field change between lines.

---

## 8. Audio Playback

- Player loads full `script_json` on open, builds queue of `{index, character, text, audio_path, page}`
- Each line plays its `.mp3`; on completion the next line starts automatically
- When `page` changes between consecutive lines, the page image updates
- Karaoke: full current line highlighted (no word-level timing — OpenAI TTS does not provide word timestamps)
- Prev/next controls skip by line; long-press skips by page
- Last-played line index saved to `audio_versions.last_played_line` in SQLite; updated on every line change (not debounced — SQLite handles this write frequency without issue, and immediate writes ensure accurate resume on crash)

---

## 9. Error Handling

| Scenario | Behavior |
|---|---|
| API failure mid-generation | `status` stays `generating`; `last_generated_line` and `script_json` updated in SQLite after each TTS line result; resume from `last_generated_line + 1` on retry |
| Network drop during generation | Treated identically to API failure — state is preserved in SQLite; Loading screen shows retry button; tapping resume resumes from `last_generated_line + 1` |
| Corrupted file on upload | Validate before any API call; show error immediately |
| Single TTS line fails | Set `lines[n].status = "error"` in `script_json`; skip during playback; `last_generated_line` advances past it so the rest of generation continues |

---

## 10. Development Phases (from PRD)

| Phase | Scope |
|---|---|
| 1 (current) | Tech stack proposal — **this document** |
| 2 | Flutter project init, mock UI, static JSON, mock audio player |
| 3 | FastAPI backend, VLM + LLM + TTS integration |
| 4 | Audio stitching polish, karaoke sync, final UI |

---

## 11. Out of Scope (for now)

- More than 6 TTS voices / custom voice cloning
- Cloud sync or multi-device support
- Book sharing between users
- Word-level karaoke timing
