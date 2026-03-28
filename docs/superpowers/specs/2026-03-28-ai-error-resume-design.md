# AI Error Resume Design

**Date:** 2026-03-28
**Status:** Approved

## Overview

Replace the library-screen resume banner with per-version Retry/Resume buttons on the book detail screen. Resume logic infers the failed stage from existing persisted data and re-enters the pipeline at the correct stage, skipping already-completed work.

## Stage Inference

The failed stage is inferred from the version's persisted data — no new database fields required.

| Condition | Inferred Stage | Button |
|---|---|---|
| `Book.vlmOutput` is empty | VLM failed | Retry |
| `scriptJson` is `'{}'` or empty | LLM failed | Retry |
| Script has chunks, none `status='ready'` | TTS failed before producing audio | Retry |
| Script has chunks, at least one `status='ready'` | TTS partially succeeded | Resume |

## Data Model

```dart
enum ResumeStage { vlm, llm, tts }
```

Added to `LoadingParams`:

```dart
class LoadingParams {
  final String versionId;
  final bool isNewBook;
  final ResumeStage? startStage; // null = full run from beginning
}
```

No changes to `AudioVersion` schema. Stage inference is computed inline in `BookDetailScreen` using both the `Book` and `AudioVersion` objects.

## App Startup

On app start, before the UI renders, reset any versions stuck mid-generation from a previous crash:

```dart
await AppDatabase.instance.resetGeneratingVersions();
// UPDATE audio_versions SET status='error' WHERE status='generating'
```

This ensures all interrupted versions surface as `status='error'` and show the Retry/Resume button consistently.

## LoadingScreen Pipeline

```
if startStage is null or vlm:
  → run VLM (/analyze), store vlmOutput on Book

if startStage is null or vlm or llm:
  → run LLM (/script), store scriptJson on AudioVersion

run TTS (/tts):
  → for each chunk:
      if chunk.status == 'ready' → skip (audio file already on disk)
      else → generate, write chunk_NNN.wav, mark chunk status='ready'
  → all chunks done → set AudioVersion.status = 'ready'
```

- Existing TTS error handling is unchanged: per-chunk failures mark `status='error'`, processing continues for remaining chunks
- On any unhandled exception: `_hasError = true`, error screen shown with "Try Again" button that re-triggers from the same `startStage`

## BookDetailScreen UI

Each language version card in error state (`status='error'`) shows:

- **Retry** button — for VLM failures, LLM failures, or TTS failures with no saved audio
- **Resume** button — for TTS partial failures where at least one chunk is `status='ready'`

Tapping either button navigates to `LoadingScreen` with the inferred `startStage`.

## LibraryScreen

Remove the `MaterialBanner` resume UI entirely (`generatingVersionsProvider` banner). The library screen becomes a clean grid of books with no recovery logic. The `generatingVersionsProvider` Riverpod provider can also be removed if no longer used elsewhere.

## Affected Files

| File | Change |
|---|---|
| `lib/models/loading_params.dart` | Add `ResumeStage` enum and `startStage` field |
| `lib/db/database.dart` | Add `resetGeneratingVersions()` method |
| `main.dart` | Call `resetGeneratingVersions()` on startup |
| `lib/screens/loading_screen.dart` | Skip stages before `startStage`; skip `ready` TTS chunks |
| `lib/screens/book_detail_screen.dart` | Show Retry/Resume buttons on error version cards with stage inference |
| `lib/screens/library_screen.dart` | Remove resume banner |
| `lib/providers/books_provider.dart` | Remove `generatingVersionsProvider` if unused |
