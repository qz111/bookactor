# Multi-Image Upload Design

**Date:** 2026-03-24
**Status:** Approved

## Problem

The upload screen only allows a single file to be picked. When a user selects image files (JPG/PNG) instead of a PDF, they can only upload one image. The app should accept multiple images representing book pages, let the user reorder them, and send them in order to the VLM.

## Scope

Three files change: `upload_screen.dart`, `loading_screen.dart` (including `LoadingParams`). No changes to `api_service.dart`, `pdf_service.dart`, or the database schema.

---

## Data Model

### UploadScreen state

Replace the single-path fields with a union:

```dart
String? _pdfPath;              // set when user picks a .pdf
List<String> _imagePaths = []; // set when user picks images
```

The two fields are mutually exclusive. Picking a PDF clears `_imagePaths`; picking images clears `_pdfPath`.

**Book title:** `Book.title` is set to the first image's filename (e.g. `"page1.jpg"`) for multi-image mode.

### LoadingParams

`filePath` remains `required String` and non-nullable. For multi-image mode, pass `_imagePaths.first` as `filePath`.

Add one new nullable field:

```dart
final List<String>? imageFilePaths;
```

- `null` → PDF mode (use existing `filePath` for reading), or resume mode (VLM output already cached)
- non-null → multi-image new-book mode (read bytes from `imageFilePaths` in order)

**Resume flow (`isNewBook = false`):** pass `imageFilePaths = null`. Image bytes are not re-read — VLM output is loaded from the DB.

### Book.pagesDir (DB)

For PDF: unchanged (single path string).
For images: JSON-encoded list of image paths, e.g. `'["path1.jpg","path2.jpg"]'`. Metadata only — not read back by the processing pipeline.

### Book ID

SHA-256 of all image bytes concatenated in selection order. Computed in `UploadScreen._generate()`. If a `bookId` already exists in the DB (`insertBook` is an upsert-or-ignore by existing app convention), the pre-existing book row is left untouched and the new audio version is inserted. This behaviour is identical to the existing PDF path.

---

## UI (UploadScreen)

### File picker

One `FilePicker` call with `allowMultiple: true`, accepting `['pdf', 'jpg', 'jpeg', 'png']`.

Post-pick logic:
1. Collect all returned files.
2. If **any** file ends in `.pdf`: take the **first** PDF only, store as `_pdfPath`, clear `_imagePaths`. Any other files in the pick are silently ignored.
3. Otherwise: append all returned image paths to `_imagePaths`, clear `_pdfPath`.
4. Deduplicate `_imagePaths` by absolute path after appending.
5. If `_imagePaths.length > 50` after appending, trim to 50 and show a `SnackBar`: _"Maximum 50 images supported. Extra images were removed."_

### Upload area

**Empty state:** `GestureDetector(onTap: _pickFile)` — "Tap to select PDF or images"

**PDF selected:** existing `GestureDetector` display — shows filename in the fixed-height box

**Images selected:** the `GestureDetector` is **removed**. Replace the fixed-height container with:

```
ConstrainedBox(
  constraints: BoxConstraints(maxHeight: 300),
  child: ReorderableListView(...)
)
```

Each row: page-number badge | small thumbnail (50×50, decoded with `Image.file`) | truncated filename | delete icon | drag handle (`Icons.drag_handle`)

Below the `ConstrainedBox`: an "Add more images" `TextButton` that invokes `_pickFile` and appends (deduplicating, cap enforced). The outer `GestureDetector` is absent in this state, so there is no tap-handler conflict.

When all images are removed (list empties), revert to the empty-state `GestureDetector`.

### Cover extraction (UploadScreen)

For multi-image mode, cover extraction is done in `UploadScreen._generate()` before navigation:

```dart
final coverBytes = await File(_imagePaths.first).readAsBytes();
final coverFile = File('${dir.path}/${bookId}_cover.jpg');
await coverFile.writeAsBytes(coverBytes);
await AppDatabase.instance.updateBookCoverPath(bookId, coverFile.path);
```

`LoadingScreen` does **not** perform cover extraction for multi-image mode.

### Generate button enablement

Enabled when:
- `(_pdfPath != null || _imagePaths.isNotEmpty)` AND
- `_processingMode != null` AND
- API keys present AND
- `!_isGenerating`

---

## Pipeline (LoadingScreen)

### Image reading in `_runLivePipeline()`

```dart
final List<Uint8List> imageBytes;
if (p.imageFilePaths != null) {
  imageBytes = await Future.wait(
    p.imageFilePaths!.map((path) => File(path).readAsBytes()),
  );
} else if (p.filePath.toLowerCase().endsWith('.pdf')) {
  imageBytes = await PdfService.pdfToJpegBytes(p.filePath);
} else {
  imageBytes = [await File(p.filePath).readAsBytes()]; // fallback: single image
}
```

### Cover extraction

Not performed in `LoadingScreen` for multi-image mode (already done in `UploadScreen`). Existing PDF cover extraction in `LoadingScreen` is unchanged.

### ApiService.analyzePages()

No changes — already accepts `List<Uint8List>`.

---

## Error Handling

- **Empty image list:** Generate button is disabled — cannot be reached.
- **> 50 images:** Trimmed to 50 with a SnackBar in `UploadScreen` before `_generate()` is reachable.
- **File read failure:** Propagates as an unhandled exception → `_hasError = true` → "Try Again" screen. Retry re-reads from `p.imageFilePaths`; if files are no longer accessible the retry fails again — known limitation, out of scope.
- **Mixed PDF + image pick:** First PDF wins; image files in the same pick are silently ignored.
- **Multiple PDFs in one pick:** First PDF is used; others are ignored.
- **Duplicate images on append:** Deduplicated by absolute path; silent skip.
- **Book ID collision:** Existing `insertBook` upsert-or-ignore behaviour applies; audio version is still inserted. Same as PDF path.

---

## Out of Scope

- Drag-to-reorder persistence across app restarts
- Image cropping or rotation
- Progress per-image during VLM analysis
- Stale file URI handling on retry after picker session expiry
