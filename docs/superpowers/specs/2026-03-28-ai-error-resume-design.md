# AI Error Resume Design

**Date:** 2026-03-28
**Status:** Approved

## Overview

Replace the library-screen resume banner with per-version Retry/Resume buttons on the book detail screen. Resume logic infers the failed stage from existing persisted data and re-enters the pipeline at the correct stage, skipping already-completed work.

## Stage Inference

Top-level function defined in `book_detail_screen.dart`, importing `ResumeStage` from `loading_screen.dart`:

```dart
ResumeStage? inferResumeStage(Book book, AudioVersion version) { ... }
```

Only called when `version.status == 'error'`. Rules applied in order:

| Condition | Inferred Stage | Button |
|---|---|---|
| `book.vlmOutput.isEmpty \|\| book.vlmOutput == '[]'` | VLM failed | Retry |
| `version.scriptJson.isEmpty \|\| version.scriptJson == '{}'` | LLM failed | Retry |
| Script fails JSON parsing | LLM failed | Retry |
| Script parses but `chunks` list is empty | LLM failed | Retry |
| Script has chunks, none with `status='ready'` | TTS failed (no audio) | Retry |
| Script has chunks, ≥1 with `status='ready'` | TTS partial | Resume |

Both `''` and `'[]'` are treated as VLM not completed. `'[]'` means VLM returned zero pages, which is a failure requiring full restart.

Note: A brand-new language version created by `_NewLanguageSheet` starts with `scriptJson='{}'` and after crash-reset becomes `status='error'` with `scriptJson='{}'`. `inferResumeStage` correctly classifies this as LLM failed (VLM output already exists on `Book`) and shows **Retry** — re-runs LLM+TTS using stored `vlmOutput`.

## Data Model

`ResumeStage` enum is defined in `loading_screen.dart` alongside `LoadingParams`:

```dart
enum ResumeStage { vlm, llm, tts }
```

`LoadingParams` gains one new nullable optional field:

```dart
final ResumeStage? startStage; // defaults to null
```

All existing callers compile unchanged. Retry/Resume buttons pass a non-null value.

- Retry/Resume navigations: `isNewBook = false`, `startStage = inferResumeStage(book, version)`, `versionId = version.versionId` (taken directly from the DB row — never recomputed)
- `LoadingScreen` reads `params.startStage` directly and does NOT call `inferResumeStage` (avoids circular import: `book_detail_screen.dart` imports `loading_screen.dart`, not the reverse)

## Pipeline Stage Gates

```dart
final bool runVlm = params.isNewBook || params.startStage == ResumeStage.vlm;
final bool runLlm = runVlm
    || params.startStage == null   // new-language run: isNewBook=false, startStage=null → skip VLM, run LLM
    || params.startStage == ResumeStage.llm;
```

The `startStage == null` term is intentional and required for `_NewLanguageSheet` (`isNewBook=false, startStage=null`). This is the only reachable path where `runVlm=false` and `startStage=null` — `LoadingScreen` is only navigated to from three flows (new book, new language, retry/resume) and all are listed below. There is no flow that reaches `LoadingScreen` with `isNewBook=false, startStage=null` on a version that already has a good script.

All reachable combinations:
- New book: `isNewBook=true, startStage=null` → `runVlm=true, runLlm=true`
- New language: `isNewBook=false, startStage=null` → `runVlm=false, runLlm=true`
- LLM retry: `isNewBook=false, startStage=llm` → `runVlm=false, runLlm=true`
- TTS resume: `isNewBook=false, startStage=tts` → `runVlm=false, runLlm=false` ← both stages skipped, TTS runs directly using the persisted `scriptJson`
- VLM retry: `isNewBook=false, startStage=vlm` → `runVlm=true, runLlm=true`

## App Startup

```dart
// main.dart — unconditional call after _seedMockData(), before runApp()
await AppDatabase.instance.resetGeneratingVersions();
// UPDATE audio_versions SET status='error' WHERE status='generating'
```

`resetGeneratingVersions()` is called unconditionally every cold start — it is not inside `_seedMockData()`. It resets only `AudioVersion.status` to `'error'`; per-chunk statuses inside `scriptJson` are intentionally preserved.

This intentionally treats all `'generating'` versions the same on cold start — whether the app crashed, was force-quit, or was killed by the OS. The app cannot distinguish these cases, so any incomplete run is surfaced as `'error'` requiring user action.

After the reset, providers re-fetch from DB on first `ref.watch` when `BookDetailScreen` is opened. Since the reset runs before `runApp()`, the updated status is always visible before the user can navigate to any book.

## LoadingScreen Pipeline

```
if runVlm:
  → run VLM (/analyze), overwrite Book.vlmOutput
  → clear AudioVersion.scriptJson to '{}'
  → delete all files in audioDir (if it exists) — old chunks are now stale

if runLlm:
  → run LLM (/script), overwrite AudioVersion.scriptJson

// TTS always runs
// Compute audioDir from getApplicationDocumentsDirectory() — do NOT read from DB
// (DB value may be '' if the version never completed)
audioDir = await _computeAudioDir(params.versionId);

for each chunk in index order:
  // File-existence check is a new guard added inside the loop,
  // in addition to the existing 'pending' filter:
  if chunk.status == 'ready' AND File('$audioDir/chunk_${chunk.index.toString().padLeft(3,'0')}.wav').existsSync() → skip
  else → generate, write chunk_NNN.wav, mark chunk status='ready', update lastGeneratedLine

all chunks done → set AudioVersion.status = 'ready', persist audioDir to DB
```

**`lastGeneratedLine`:** Updated only on generated chunks (not skipped). The player uses per-chunk `status` and file existence for playback — non-sequential values across resume runs are acceptable.

**VLM retry and stale audio:** Before TTS begins, delete the contents of `audioDir` if it exists. The new LLM run may produce a different chunk count; leftover files from a prior run would cause incorrect playback.

**Chunk storage:** Chunks are NOT separate DB rows — they are embedded inside `AudioVersion.scriptJson` as a JSON array. When LLM re-runs and overwrites `scriptJson`, the entire old chunk list (including all prior `status='ready'` markers) is replaced by the new script. There are no stale chunk rows to clean up.

**Chunk list read timing:** The chunk list for the TTS loop must be read from the DB-persisted `scriptJson` immediately before the loop begins — after all prior stages (`runVlm`, `runLlm`) have had the opportunity to write their updates. The chunk list must NOT be loaded once at pipeline entry and cached in memory. This ensures TTS resume correctly reads the live `scriptJson` (from a prior run) and VLM/LLM retry correctly reads the freshly generated script.

**Per-chunk TTS errors:** Mark chunk `status='error'`, continue remaining chunks. After all chunks: `_hasError = true`, show error screen. `AudioVersion.status` is NOT written to `'error'` — it stays `'generating'` (already persisted by per-chunk DB writes). Cold restart will flip it to `'error'`.

**"Try Again" mechanism:** `_buildError()` calls `_runLivePipeline()`. No change to `_buildError()` is needed — `_runLivePipeline()` already re-reads `widget.params`, which now carries `startStage`. The gate logic (`runVlm`/`runLlm`) inside `_runLivePipeline()` handles the correct entry point automatically. The existing retry button wiring is correct once `startStage` is threaded through `LoadingParams`.

During a "Try Again" retry, `AudioVersion.status` remains `'generating'` in the DB (set by per-chunk writes from the previous attempt). `_runLivePipeline` does not need to reset it — the first successful chunk write will persist `'generating'` again, and final success writes `'ready'`. A concurrent cold restart during an active "Try Again" run is theoretically possible but treated as out-of-scope: the app does not support multi-process access to the DB.

**`versionId` and `AudioVersion` row timing:** `versionId` is a deterministic computed string (`"${bookId}_${language}"`), not a DB-auto-generated ID. It is always known before navigation — `params.versionId` is valid when `LoadingScreen` first reads it, before any DB write occurs. For new books, the `AudioVersion` row is inserted inside `LoadingScreen` using this pre-computed ID. `_computeAudioDir(params.versionId)` is therefore always valid regardless of row insertion timing.

## BookDetailScreen UI

Retry/Resume buttons are shown only when `version.status == 'error'`.

The button label is a UX distinction only. Both map to `startStage` values as follows:

| `inferResumeStage` result | Button label | `startStage` passed |
|---|---|---|
| `ResumeStage.vlm` | Retry | `ResumeStage.vlm` |
| `ResumeStage.llm` | Retry | `ResumeStage.llm` |
| `ResumeStage.tts` (no audio) | Retry | `ResumeStage.tts` |
| `ResumeStage.tts` (partial) | Resume | `ResumeStage.tts` |

All TTS-stage failures — whether every chunk failed or only some — pass `startStage=ResumeStage.tts`. The pipeline skips VLM and LLM, preserves the existing `scriptJson`, and only regenerates chunks that are not already `status='ready'` with a file on disk. "Retry" vs "Resume" affects the button label only, not the pipeline entry point.

Taps pass `versionId=version.versionId`, `isNewBook=false`, and the `startStage` from the table above.

## LibraryScreen

Remove the `MaterialBanner` resume UI entirely. Remove `generatingVersionsProvider` from `books_provider.dart`. Remove `getGeneratingVersions()` from `database.dart` (dead code once the provider is removed).

**Deletion guard:** The existing `onLongPress` guard blocks deletion only when `version.status == 'generating'`. After this change, error versions have `status='error'` — this is intentional. Users can delete books with errored versions. The guard remains narrow: only live in-progress generation blocks deletion.

## Affected Files

| File | Change |
|---|---|
| `lib/screens/loading_screen.dart` | Add `ResumeStage` enum; add `startStage` to `LoadingParams`; replace `isNewBook` gate with `runVlm`/`runLlm` boolean logic; clear `scriptJson` + delete `audioDir` on VLM retry; TTS skip with file-existence guard; compute `audioDir` independently of DB |
| `lib/db/database.dart` | Add `resetGeneratingVersions()`; remove `getGeneratingVersions()` |
| `main.dart` | Call `resetGeneratingVersions()` unconditionally after `_seedMockData()`, before `runApp()` |
| `lib/screens/book_detail_screen.dart` | Add `inferResumeStage` top-level function; show Retry/Resume buttons on `status='error'` version cards; pass `version.versionId` directly |
| `lib/screens/library_screen.dart` | Remove resume banner |
| `lib/providers/books_provider.dart` | Remove `generatingVersionsProvider` |
