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
String? _pdfPath;           // set when user picks a .pdf
List<String> _imagePaths = []; // set when user picks images
```

The two fields are mutually exclusive. Picking a PDF clears `_imagePaths`; picking images clears `_pdfPath`.

### LoadingParams

Add one new nullable field:

```dart
final List<String>? imageFilePaths;
```

- `null` → PDF mode (use existing `filePath`)
- non-null → multi-image mode (ignore `filePath` for reading; `filePath` may hold first image path for display)

### Book.pagesDir (DB)

For PDF: unchanged (single path string).
For images: JSON-encoded list of image paths, e.g. `'["path1.jpg","path2.jpg"]'`. This is metadata only — not read back by the processing pipeline.

### Book ID

SHA-256 of all image bytes concatenated in selection order. This is deterministic and content-addressed, consistent with the existing PDF approach.

---

## UI (UploadScreen)

### File picker

One `FilePicker` call with `allowMultiple: true`, accepting `['pdf', 'jpg', 'jpeg', 'png']`.

- If any picked file is `.pdf` → store as `_pdfPath`, clear `_imagePaths`
- Otherwise → **append** picked files to `_imagePaths` (supports multi-batch picking), clear `_pdfPath`

### Upload area

**Empty state:** existing tap zone — "Tap to select PDF or images"

**PDF selected:** existing display — shows filename in the fixed-height box

**Images selected:** the fixed-height box is replaced by a `ReorderableListView`:
- Each row: page-number badge | small thumbnail | truncated filename | drag handle (`Icons.drag_handle`)
- Below the list: "Add more images" `TextButton` that re-invokes the picker and appends
- Individual images can be removed via a delete icon or swipe (optional, keep simple)

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
  imageBytes = [await File(p.filePath).readAsBytes()]; // fallback
}
```

### Cover extraction

For multi-image mode: copy first image bytes directly to the cover file (no PDF conversion).

```dart
if (p.imageFilePaths != null && p.imageFilePaths!.isNotEmpty) {
  final coverBytes = await File(p.imageFilePaths!.first).readAsBytes();
  await coverFile.writeAsBytes(coverBytes);
}
```

### ApiService.analyzePages()

No changes — already accepts `List<Uint8List>`.

---

## Error Handling

- Empty image list: Generate button is disabled, so this cannot be reached.
- File read failure for one image: propagates as an unhandled exception → `_hasError = true` → user sees "Try Again" screen (existing behaviour).
- Mixed PDF + image selection: prevented by picker logic (PDF clears images, images clear PDF).

---

## Out of Scope

- Drag-to-reorder persistence across app restarts
- Image cropping or rotation
- Progress per-image during VLM analysis
- Resume flow for multi-image books (resume re-uses cached VLM output; no image re-reading needed)
