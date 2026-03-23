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

- **No default** — both cards start unselected (`_processingMode` is `null`). The user must explicitly tap one.
- The **Generate button** is disabled until both `_processingMode != null` AND `_selectedFilePath != null`. The existing `if (_selectedFilePath == null) return;` guard inside `_generate()` may be retained as defense in depth; its presence does not contradict the button-disabled logic.
- Tapping a card sets `_processingMode` to `ProcessingMode.textHeavy` or `ProcessingMode.pictureBook`.
- No error toast on missing selection — the disabled button and unselected card state communicate this visually.
- **Picking a new file does not reset `_processingMode`.** The user's mode choice persists across file re-selections within the same upload session.

---

## Processing Mode Type

`processingMode` is represented as a Dart enum to prevent string-mismatch bugs:

```dart
enum ProcessingMode {
  textHeavy,
  pictureBook;

  String toApiValue() => switch (this) {
    ProcessingMode.textHeavy  => 'text_heavy',
    ProcessingMode.pictureBook => 'picture_book',
  };
}
```

The `.toApiValue()` result is what is sent to the backend. This enum lives in a new small file `lib/models/processing_mode.dart`.

---

## Data Flow

`_processingMode` is ephemeral state in `_UploadScreenState`. It is never written to the database or any model.

### Changes

1. **`lib/models/processing_mode.dart`** — new file defining the `ProcessingMode` enum with `.toApiValue()`.
2. **`lib/screens/upload_screen.dart`** — add `ProcessingMode? _processingMode` state + two selection cards + update Generate button guard.
3. **`lib/screens/loading_screen.dart`** — add `final ProcessingMode processingMode` (required) to `LoadingParams`; pass `p.processingMode` into `api.analyzePages()`.
4. **`lib/services/api_service.dart`** — add `required ProcessingMode processingMode` to `analyzePages()`; include `processingMode.toApiValue()` as the `processing_mode` form field in the multipart POST to `/analyze`.
5. **`test/screens/loading_screen_live_test.dart`** — add `processingMode: ProcessingMode.textHeavy` to all existing `LoadingParams(...)` constructor calls; update the `_RecordingApiService.analyzePages()` override signature to include `required ProcessingMode processingMode`.
6. **`test/services/api_service_test.dart`** — add `processingMode: ProcessingMode.textHeavy` to all existing `analyzePages()` call sites.

No DB migration. No other model changes.

---

## VLM Prompt Strategies

### `text_heavy` (`'text_heavy'`)
- Focus: accurate OCR and text extraction.
- Ignore background illustrations.
- Output: the verbatim text found on each page.

### `picture_book` (`'picture_book'`)
- Focus: visual narrative — illustrations, character emotions, scene composition.
- Also extract any visible text on the page as a supporting signal.
- Combine illustration analysis and visible text to generate a cohesive, imaginative story.
- Output: a generated narrative that reflects both what is drawn and what is written.

---

## Error Handling

- Missing or unrecognized `processing_mode` on the backend request → 400 response → caught by existing `ApiException` → existing error UI shown. The enum on the client ensures only valid values (`'text_heavy'`, `'picture_book'`) are ever sent.
- `processingMode` is `required` on `LoadingParams` — compile-time guarantee, no null checks needed downstream.

---

## Files Changed

| File | Change |
|------|--------|
| `lib/models/processing_mode.dart` | **New file** — `ProcessingMode` enum with `.toApiValue()` |
| `lib/screens/upload_screen.dart` | Add `ProcessingMode? _processingMode` state + two selection cards + update Generate button guard |
| `lib/screens/loading_screen.dart` | Add `processingMode` to `LoadingParams`; pass it into `analyzePages()` |
| `lib/services/api_service.dart` | Add `processingMode` parameter to `analyzePages()`; include `.toApiValue()` in multipart POST |
| `test/screens/loading_screen_live_test.dart` | Add `processingMode` to `LoadingParams` constructor calls; update `_RecordingApiService.analyzePages()` override signature |
| `test/services/api_service_test.dart` | Add `processingMode` to all `analyzePages()` call sites |

---

## Out of Scope

- Persisting processing mode on the `Book` or `AudioVersion` model.
- Any DB migration.
- Changing the player, library, or book detail screens.
- Widget tests for the new mode-selection card UI (deferred).
