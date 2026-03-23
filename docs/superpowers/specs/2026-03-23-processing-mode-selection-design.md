# Processing Mode Selection — Design Spec

**Date:** 2026-03-23
**Status:** Approved

---

## Overview

Users uploading a book to BookActor must choose between two processing modes before generation begins. The mode determines which VLM prompt strategy is used during the `/analyze` step, routing the book through either an OCR-focused pipeline or a visual-narrative pipeline.

---

## UI (UploadScreen)

A "What kind of book is this?" label is added at the top of the existing `UploadScreen` `ListView`, before the file picker. Below the label, two horizontally-arranged tap-to-select cards are rendered:

| | 📝 Text-Heavy | 🖼️ Picture Book |
|---|---|---|
| **Subtitle** | "Story told through words" | "Story told through illustrations" |
| **Selected** | filled border + primary color tint | same |
| **Unselected** | outlined border, no tint | same |

- **No default** — both cards start unselected. The user must explicitly tap one.
- The **Generate button** is disabled until both `_processingMode != null` AND `_selectedFilePath != null`.
- Tapping a card sets `_processingMode` to `'text_heavy'` or `'picture_book'`.
- No error toast on missing selection — the disabled button and unselected card state communicate this visually.

---

## Data Flow

`_processingMode` is ephemeral state in `_UploadScreenState`. It is never written to the database or any model.

### Changes

1. **`LoadingParams`** — add `final String processingMode` (required).
2. **`LoadingScreen._runLivePipeline()`** — pass `p.processingMode` into `api.analyzePages()`.
3. **`ApiService.analyzePages()`** — add `required String processingMode` parameter; include it as a `processing_mode` form field in the multipart POST to `/analyze`.
4. **Backend `/analyze`** — reads `processing_mode` and selects the VLM prompt strategy accordingly (see below).

No DB migration. No model changes. No new files.

---

## VLM Prompt Strategies

### `text_heavy`
- Focus: accurate OCR and text extraction.
- Ignore background illustrations.
- Output: the verbatim text found on each page.

### `picture_book`
- Focus: visual narrative — illustrations, character emotions, scene composition.
- Also extract any visible text on the page as a supporting signal.
- Combine illustration analysis and visible text to generate a cohesive, imaginative story.
- Output: a generated narrative that reflects both what is drawn and what is written.

---

## Error Handling

- Missing `processing_mode` on the backend request → 400 response → caught by existing `ApiException` → existing error UI shown.
- `processingMode` is `required` on `LoadingParams` → compile-time guarantee, no null checks needed downstream.

---

## Files Changed

| File | Change |
|------|--------|
| `lib/screens/upload_screen.dart` | Add `_processingMode` state + two selection cards + update Generate button guard |
| `lib/screens/loading_screen.dart` | Add `processingMode` to `LoadingParams`; pass it into `analyzePages()` |
| `lib/services/api_service.dart` | Add `processingMode` parameter to `analyzePages()`; include in multipart POST |

---

## Out of Scope

- Persisting processing mode on the `Book` or `AudioVersion` model.
- Any DB migration.
- Changing the player, library, or book detail screens.
