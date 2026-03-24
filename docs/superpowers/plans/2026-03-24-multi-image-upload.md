# Multi-Image Upload Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow users to upload multiple images as book pages, reorder them with drag-and-drop, and send them in order to the VLM.

**Architecture:** `LoadingParams` gains a nullable `imageFilePaths` field; when set, `LoadingScreen` reads those files instead of the single `filePath`. `UploadScreen` replaces single-path state with a union (`_pdfPath` / `_imagePaths`), shows a `ReorderableListView` when images are selected, and computes the book ID from all image bytes concatenated.

**Tech Stack:** Flutter, Riverpod, `file_picker`, `ReorderableListView` (Flutter built-in), `crypto` (sha256), `sqflite`.

---

## File Map

| File | Change |
|------|--------|
| `lib/screens/loading_screen.dart` | Add `imageFilePaths` to `LoadingParams`; update image-reading block in `_runLivePipeline()` |
| `lib/screens/upload_screen.dart` | Replace single-path state; update `_pickFile()`, `_generate()`, `build()` |
| `test/screens/loading_screen_live_test.dart` | Add multi-image pipeline test |
| `test/screens/upload_screen_hash_test.dart` | Add multi-image hash test |

---

## Task 1: Add `imageFilePaths` to `LoadingParams` and update `LoadingScreen` pipeline

**Files:**
- Modify: `lib/screens/loading_screen.dart`
- Modify: `test/screens/loading_screen_live_test.dart`

---

- [ ] **Step 1.1: Write the failing multi-image pipeline test**

Add this test case to `test/screens/loading_screen_live_test.dart`, after the existing `setUpAll` / `tearDownAll` (inside `main()`), after the existing test:

```dart
testWidgets('LoadingScreen uses imageFilePaths when provided',
    (tester) async {
  // Create two real temp image files (1-byte PNG-like content is fine —
  // the mock ApiService ignores the actual bytes)
  final tempDir = Directory.systemTemp.createTempSync('bookactor_multi_');
  addTearDown(() => tempDir.deleteSync(recursive: true));
  final img1 = File('${tempDir.path}/p1.png')..writeAsBytesSync([1, 2, 3]);
  final img2 = File('${tempDir.path}/p2.png')..writeAsBytesSync([4, 5, 6]);

  final fakeApi = _RecordingApiService();
  final tempAudioDir = Directory.systemTemp.createTempSync('bookactor_audio_');
  addTearDown(() => tempAudioDir.deleteSync(recursive: true));

  final params = LoadingParams(
    bookId: 'test_book_live',
    versionId: 'test_book_live_en',
    filePath: img1.path,             // first image as filePath (display only)
    imageFilePaths: [img1.path, img2.path],
    language: 'en',
    vlmProvider: 'gemini',
    llmProvider: 'gpt4o',
    processingMode: ProcessingMode.textHeavy,
    isNewBook: true,
    lastGeneratedLine: -1,
    audioDirOverride: tempAudioDir.path,
  );

  final router = GoRouter(
    initialLocation: '/loading',
    routes: [
      GoRoute(
        path: '/loading',
        builder: (context, state) => LoadingScreen(
          params: params,
          apiService: fakeApi,
        ),
      ),
      GoRoute(
          path: '/player/:versionId',
          builder: (_, __) => const Scaffold(body: Text('player'))),
    ],
  );

  await tester.runAsync(() async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp.router(routerConfig: router),
    ));
    await Future<void>.delayed(const Duration(seconds: 5));
  });
  await tester.pump();

  expect(fakeApi.calls, equals(['analyze', 'script', 'tts']));
});
```

- [ ] **Step 1.2: Run the test — verify it fails with a compile error** (field does not exist yet)

```
flutter test test/screens/loading_screen_live_test.dart
```

Expected: compile error mentioning `imageFilePaths`.

- [ ] **Step 1.3: Add `imageFilePaths` to `LoadingParams`**

In `lib/screens/loading_screen.dart`, add the field to `LoadingParams`:

```dart
/// Optional list of image paths for multi-image mode.
/// When non-null, these files are read in order instead of [filePath].
final List<String>? imageFilePaths;

const LoadingParams({
  required this.bookId,
  required this.versionId,
  required this.filePath,
  required this.language,
  required this.vlmProvider,
  required this.llmProvider,
  required this.processingMode,
  required this.isNewBook,
  required this.lastGeneratedLine,
  this.audioDirOverride,
  this.imageFilePaths,        // ← add this line
});
```

- [ ] **Step 1.4: Replace the image-reading block in `_runLivePipeline()`**

Locate this block in `_LoadingScreenState._runLivePipeline()` (around line 108–113):

```dart
final List<Uint8List> imageBytes;
if (p.filePath.toLowerCase().endsWith('.pdf')) {
  imageBytes = await PdfService.pdfToJpegBytes(p.filePath);
} else {
  imageBytes = [await File(p.filePath).readAsBytes()];
}
```

Replace with:

```dart
final List<Uint8List> imageBytes;
if (p.imageFilePaths != null) {
  imageBytes = await Future.wait(
    p.imageFilePaths!.map((path) => File(path).readAsBytes()),
  );
} else if (p.filePath.toLowerCase().endsWith('.pdf')) {
  imageBytes = await PdfService.pdfToJpegBytes(p.filePath);
} else {
  imageBytes = [await File(p.filePath).readAsBytes()];
}
```

- [ ] **Step 1.5: Run the test — verify it passes**

```
flutter test test/screens/loading_screen_live_test.dart
```

Expected: both tests PASS.

- [ ] **Step 1.6: Run full test suite**

```
flutter test
```

Expected: all tests PASS (no regressions).

- [ ] **Step 1.7: Commit**

```bash
git add lib/screens/loading_screen.dart test/screens/loading_screen_live_test.dart
git commit -m "feat: add imageFilePaths to LoadingParams; update LoadingScreen to read multi-image"
```

---

## Task 2: Update `UploadScreen` state, `_pickFile()`, and `_generate()`

**Files:**
- Modify: `lib/screens/upload_screen.dart`
- Modify: `test/screens/upload_screen_hash_test.dart`

---

- [ ] **Step 2.1: Write the failing multi-image hash test**

Add these two tests to `test/screens/upload_screen_hash_test.dart`, inside `main()`:

```dart
test('SHA-256 of concatenated multi-image bytes differs from single image', () {
  final img1 = Uint8List.fromList([1, 2, 3]);
  final img2 = Uint8List.fromList([4, 5, 6]);
  final combined = Uint8List.fromList([...img1, ...img2]);
  final multiHash = sha256.convert(combined).toString();
  final singleHash = sha256.convert(img1).toString();
  expect(multiHash, isNot(equals(singleHash)));
});

test('SHA-256 of concatenated multi-image bytes is deterministic', () {
  final img1 = Uint8List.fromList([1, 2, 3]);
  final img2 = Uint8List.fromList([4, 5, 6]);
  final combined = Uint8List.fromList([...img1, ...img2]);
  final hash1 = sha256.convert(combined).toString();
  final hash2 = sha256.convert(combined).toString();
  expect(hash1, equals(hash2));
});
```

- [ ] **Step 2.2: Run the hash tests — verify they pass immediately** (pure logic, no implementation change needed)

```
flutter test test/screens/upload_screen_hash_test.dart
```

Expected: all 5 tests PASS (3 existing + 2 new).

- [ ] **Step 2.3: Replace state fields in `_UploadScreenState`**

In `lib/screens/upload_screen.dart`, replace:

```dart
String? _selectedFileName;
String? _selectedFilePath;
```

with:

```dart
String? _pdfPath;
List<String> _imagePaths = [];
```

- [ ] **Step 2.4: Add missing imports to `upload_screen.dart`**

At the top of `lib/screens/upload_screen.dart`, add these imports (after the existing ones):

```dart
import 'dart:convert';
import 'package:path/path.dart' as path_pkg;
```

- [ ] **Step 2.5: Replace `_pickFile()`**

Replace the existing `_pickFile()` method with:

```dart
Future<void> _pickFile() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
    allowMultiple: true,
  );
  if (result == null || result.files.isEmpty) return;

  final hasPdf = result.files.any(
    (f) => f.name.toLowerCase().endsWith('.pdf'),
  );

  setState(() {
    if (hasPdf) {
      // Use first PDF; ignore any other files in this pick.
      final pdfFile = result.files.firstWhere(
        (f) => f.name.toLowerCase().endsWith('.pdf'),
      );
      _pdfPath = pdfFile.path;
      _imagePaths = [];
    } else {
      _pdfPath = null;
      final newPaths = result.files
          .where((f) => f.path != null)
          .map((f) => f.path!)
          .toList();
      // Append, deduplicating by absolute path.
      final seen = Set<String>.from(_imagePaths);
      for (final p in newPaths) {
        if (seen.add(p)) _imagePaths.add(p);
      }
      // Enforce 50-image cap.
      if (_imagePaths.length > 50) {
        _imagePaths = _imagePaths.sublist(0, 50);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Maximum 50 images supported. Extra images were removed.',
                ),
              ),
            );
          }
        });
      }
    }
  });
}
```

- [ ] **Step 2.6: Replace `_generate()`**

Replace the existing `_generate()` method with:

```dart
Future<void> _generate() async {
  final isMultiImage = _imagePaths.isNotEmpty;
  if ((!isMultiImage && _pdfPath == null) || _processingMode == null) return;
  setState(() => _isGenerating = true);
  try {
    // ── Build primary path and pagesDir ─────────────────────────────────
    final String primaryPath;
    final String bookTitle;
    final String pagesDir;
    if (isMultiImage) {
      primaryPath = _imagePaths.first;
      bookTitle = path_pkg.basename(_imagePaths.first);
      pagesDir = jsonEncode(_imagePaths);
    } else {
      primaryPath = _pdfPath!;
      bookTitle = path_pkg.basename(_pdfPath!);
      pagesDir = _pdfPath!;
    }

    // ── Compute book ID ──────────────────────────────────────────────────
    final List<Uint8List> allBytes;
    if (isMultiImage) {
      allBytes = await Future.wait(
        _imagePaths.map((p) => File(p).readAsBytes()),
      );
    } else {
      allBytes = [await File(_pdfPath!).readAsBytes()];
    }
    final combined =
        Uint8List.fromList(allBytes.expand((b) => b).toList());
    final bookId = sha256.convert(combined).toString();

    // ── Persist book row ─────────────────────────────────────────────────
    await AppDatabase.instance.insertBook(Book(
      bookId: bookId,
      title: bookTitle,
      coverPath: null,
      pagesDir: pagesDir,
      vlmOutput: '',
      vlmProvider: _vlmProvider,
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    ));

    // ── Cover extraction (non-fatal) ─────────────────────────────────────
    try {
      final dir = await getApplicationDocumentsDirectory();
      final coverFile = File('${dir.path}/${bookId}_cover.jpg');
      if (isMultiImage) {
        await coverFile.writeAsBytes(allBytes.first);
        await AppDatabase.instance.updateBookCoverPath(
            bookId, coverFile.path);
      } else {
        final pages = await PdfService.pdfToJpegBytes(_pdfPath!);
        if (pages.isNotEmpty) {
          await coverFile.writeAsBytes(pages.first);
          await AppDatabase.instance.updateBookCoverPath(
              bookId, coverFile.path);
        }
      }
    } catch (e) {
      debugPrint('Cover extraction failed (non-fatal): $e');
    }

    // ── Insert audio version placeholder ─────────────────────────────────
    final versionId = '${bookId}_$_language';
    await AppDatabase.instance.insertAudioVersion(AudioVersion(
      versionId: versionId,
      bookId: bookId,
      language: _language,
      llmProvider: _llmProvider,
      scriptJson: '{}',
      audioDir: '',
      status: 'generating',
      lastGeneratedLine: 0,
      lastPlayedLine: 0,
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    ));

    if (!mounted) return;
    context.push(
      '/loading',
      extra: LoadingParams(
        bookId: bookId,
        versionId: versionId,
        filePath: primaryPath,
        language: _language,
        vlmProvider: _vlmProvider,
        llmProvider: _llmProvider,
        processingMode: _processingMode!,
        isNewBook: true,
        lastGeneratedLine: -1,
        imageFilePaths: isMultiImage ? _imagePaths : null,
      ),
    );
  } finally {
    if (mounted) setState(() => _isGenerating = false);
  }
}
```

- [ ] **Step 2.7: Fix `build()` — update Generate button guard and file name display**

In `build()`, replace the Generate button `onPressed` guard:

Old:
```dart
onPressed: (!hasKeys || _selectedFilePath == null || _processingMode == null || _isGenerating)
    ? null
    : _generate,
```

New:
```dart
onPressed: (!hasKeys ||
        (_pdfPath == null && _imagePaths.isEmpty) ||
        _processingMode == null ||
        _isGenerating)
    ? null
    : _generate,
```

- [ ] **Step 2.8: Run tests — verify no compile errors**

```
flutter test
```

Expected: all tests PASS (the upload area still renders, state wiring compiles).

- [ ] **Step 2.9: Commit**

```bash
git add lib/screens/upload_screen.dart test/screens/upload_screen_hash_test.dart
git commit -m "feat: update UploadScreen state, picker, and generate for multi-image"
```

---

## Task 3: Update `UploadScreen.build()` — upload area UI

**Files:**
- Modify: `lib/screens/upload_screen.dart`

This task replaces the single upload box in `build()` with a tri-state widget that handles empty / PDF / multi-image states.

---

- [ ] **Step 3.1: Replace the upload area in `build()`**

Locate the `GestureDetector` block (lines ~155–179) in `build()`:

```dart
GestureDetector(
  onTap: _pickFile,
  child: Container(
    height: 140,
    ...
    child: Center(
      child: Column(
        ...
        children: [
          const Icon(Icons.upload_file, size: 40),
          const SizedBox(height: 8),
          Text(_selectedFileName ?? 'Tap to select PDF or images'),
        ],
      ),
    ),
  ),
),
```

Replace it with:

```dart
_buildUploadArea(),
```

Then add the `_buildUploadArea()` method to `_UploadScreenState` (outside `build`, before the closing `}`):

```dart
Widget _buildUploadArea() {
  // ── Multi-image state ────────────────────────────────────────────────
  if (_imagePaths.isNotEmpty) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 300),
          child: ReorderableListView(
            shrinkWrap: true,
            onReorder: (oldIndex, newIndex) {
              setState(() {
                if (newIndex > oldIndex) newIndex--;
                final item = _imagePaths.removeAt(oldIndex);
                _imagePaths.insert(newIndex, item);
              });
            },
            children: [
              for (int i = 0; i < _imagePaths.length; i++)
                _ImageRow(
                  key: ValueKey(_imagePaths[i]),
                  index: i,
                  path: _imagePaths[i],
                  onDelete: () =>
                      setState(() => _imagePaths.removeAt(i)),
                ),
            ],
          ),
        ),
        TextButton.icon(
          onPressed: _pickFile,
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: const Text('Add more images'),
        ),
      ],
    );
  }

  // ── PDF selected / empty state ───────────────────────────────────────
  return GestureDetector(
    onTap: _pickFile,
    child: Container(
      height: 140,
      decoration: BoxDecoration(
        border: Border.all(
            color: Theme.of(context).colorScheme.primary, width: 2),
        borderRadius: BorderRadius.circular(12),
        color: Theme.of(context)
            .colorScheme
            .primaryContainer
            .withValues(alpha: 0.3),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.upload_file, size: 40),
            const SizedBox(height: 8),
            Text(
              _pdfPath != null
                  ? path_pkg.basename(_pdfPath!)
                  : 'Tap to select PDF or images',
            ),
          ],
        ),
      ),
    ),
  );
}
```

- [ ] **Step 3.2: Add the `_ImageRow` widget**

Add this private widget class at the bottom of `upload_screen.dart` (after `_ModeCard`):

```dart
class _ImageRow extends StatelessWidget {
  final int index;
  final String path;
  final VoidCallback onDelete;

  const _ImageRow({
    required super.key,
    required this.index,
    required this.path,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Page number badge
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${index + 1}',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
          const SizedBox(width: 8),
          // Thumbnail
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.file(
              File(path),
              width: 50,
              height: 50,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 50,
                height: 50,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const Icon(Icons.broken_image, size: 24),
              ),
            ),
          ),
        ],
      ),
      title: Text(
        path_pkg.basename(path),
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            onPressed: onDelete,
            tooltip: 'Remove',
          ),
          const Icon(Icons.drag_handle),
        ],
      ),
    );
  }
}
```

- [ ] **Step 3.3: Run tests**

```
flutter test
```

Expected: all tests PASS.

- [ ] **Step 3.4: Commit**

```bash
git add lib/screens/upload_screen.dart
git commit -m "feat: show ReorderableListView for multi-image upload in UploadScreen"
```

---

## Task 4: Verify and clean up

- [ ] **Step 4.1: Run full test suite**

```
flutter test
```

Expected: all tests PASS.

- [ ] **Step 4.2: Build app to check for compile-time issues**

```
flutter build windows --debug 2>&1 | head -40
```

Expected: no errors (warnings about unused variables are acceptable).

- [ ] **Step 4.3: Smoke-test manually** (if device/emulator available)

1. Open the app → Add Book screen
2. Tap upload area → pick 3 images → verify list shows with thumbnails and page numbers
3. Drag row 3 above row 1 → verify order updates
4. Tap delete on a row → verify it's removed
5. Tap "Add more images" → pick 1 more → verify it appends
6. Tap "Generate Audiobook" → verify it navigates to loading screen

- [ ] **Step 4.4: Final commit if any fixes were needed**

```bash
git add -p
git commit -m "fix: address issues found during smoke test"
```
