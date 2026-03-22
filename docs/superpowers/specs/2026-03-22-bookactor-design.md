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

1. User uploads PDF or images of a children's book
2. Backend sends pages to VLM (Gemini or GPT-4o Vision) → extracts story/text per page
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
        │ HTTPS/REST (only for new books / new languages)
        ▼
FastAPI Backend Proxy
  ├── POST /analyze   — sends pages to VLM, returns extracted text
  ├── POST /script    — sends VLM output to LLM, returns JSON script
  └── POST /tts       — calls OpenAI TTS per line, returns audio files
        │
        │ via LiteLLM (VLM/LLM) + OpenAI SDK (TTS)
        ▼
AI Services
  ├── Gemini Vision / GPT-4o Vision  (user picks)
  ├── GPT-4o / Gemini                (LLM script + translation)
  └── OpenAI TTS                     (6 voices: alloy, echo, fable, onyx, nova, shimmer)
```

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
| `version_id` | TEXT PK | `{book_id}_{language}` e.g. `abc123_zh` |
| `book_id` | TEXT FK | References `books` |
| `language` | TEXT | ISO code: `en`, `zh`, `fr`… |
| `script_json` | TEXT | Characters, voice assignments, ordered dialogue lines |
| `audio_dir` | TEXT | Local path to folder of .mp3 files |
| `status` | TEXT | `generating` / `ready` / `error` |
| `created_at` | INTEGER | Unix timestamp |

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
    { "index": 0, "character": "Narrator", "voice": "alloy", "text": "Once upon a time...", "page": 1 },
    { "index": 1, "character": "Little Girl", "voice": "nova", "text": "What is that?", "page": 2 },
    { "index": 2, "character": "Old Man", "voice": "onyx", "text": "Come and see.", "page": 2 }
  ]
}
```

Audio files: `{audio_dir}/line_000.mp3`, `line_001.mp3`… matched by index.

---

## 7. Flutter App Screens

1. **Library** — grid of saved books; each shows available language badges; "+ Add Book" button
2. **Book Detail** — cover, list of ready audio versions (tap to play), "+ New Language" button
3. **Upload** *(new books only)* — file picker (PDF/images), language selector, VLM picker, Generate button. New language requests skip this screen and go directly to Loading.
4. **Loading** — child-friendly animated steps: "Reading pages…" → "Writing script…" → "Recording voices…"
5. **Player** — current page image, highlighted karaoke line + character name, prev/pause/next controls, progress bar. Auto-advances page on `page` field change between lines.

---

## 8. Audio Playback

- Player loads full `script_json` on open, builds queue of `{index, character, text, audio_path, page}`
- Each line plays its `.mp3`; on completion the next line starts automatically
- When `page` changes between consecutive lines, the page image updates
- Karaoke: full current line highlighted (no word-level timing — OpenAI TTS does not provide word timestamps)
- Prev/next controls skip by line; long-press skips by page
- Last-played line index saved to SQLite for resume

---

## 9. Error Handling

| Scenario | Behavior |
|---|---|
| API failure mid-generation | `status` stays `generating`; partial audio saved; resume from last successful line index on retry |
| Network drop during generation | Friendly retry screen shown |
| Corrupted file on upload | Validate before any API call; show error immediately |
| Single TTS line fails | Mark line as `error` in script JSON; skip during playback; available for retry |

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
