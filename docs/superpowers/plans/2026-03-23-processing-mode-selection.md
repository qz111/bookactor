# Processing Mode Selection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Text-Heavy / Picture Book mode selector to the upload screen, routing the VLM `/analyze` call with a different `processing_mode` field based on the user's choice.

**Architecture:** A new `ProcessingMode` enum provides type-safe wire values. It threads from `UploadScreen` state → `LoadingParams` → `ApiService.analyzePages()` → backend as a multipart form field. Nothing is persisted to the DB or any model.

**Tech Stack:** Flutter, Dart enums, sqflite (unchanged), `http` multipart (existing pattern in `ApiService`)

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `lib/models/processing_mode.dart` | **Create** | `ProcessingMode` enum with `.toApiValue()` |
| `lib/services/api_service.dart` | **Modify** | Add `processingMode` param to `analyzePages()`, send as form field |
| `lib/screens/loading_screen.dart` | **Modify** | Add `processingMode` to `LoadingParams`, pass into `analyzePages()` |
| `lib/screens/upload_screen.dart` | **Modify** | Add mode state + two selection cards + update Generate button guard |
| `test/services/api_service_test.dart` | **Modify** | Add `processingMode` to all `analyzePages()` call sites; assert form field sent |
| `test/screens/loading_screen_live_test.dart` | **Modify** | Add `processingMode` to `LoadingParams` constructor + `_RecordingApiService` override |

---

## Task 1: Add the ProcessingMode enum

**Files:**
- Create: `lib/models/processing_mode.dart`

- [ ] **Step 1: Create the enum file**

Create `lib/models/processing_mode.dart` with this exact content:

```dart
enum ProcessingMode {
  textHeavy,
  pictureBook;

  String toApiValue() => switch (this) {
        ProcessingMode.textHeavy => 'text_heavy',
        ProcessingMode.pictureBook => 'picture_book',
      };
}
```

- [ ] **Step 2: Verify it compiles**

Run:
```bash
flutter analyze lib/models/processing_mode.dart
```
Expected: no errors, no warnings.

- [ ] **Step 3: Commit**

```bash
git add lib/models/processing_mode.dart
git commit -m "feat: add ProcessingMode enum with toApiValue()"
```

---

## Task 2: Update ApiService to accept and send processingMode (TDD)

**Files:**
- Modify: `lib/services/api_service.dart`
- Modify: `test/services/api_service_test.dart`

The existing `analyzePages()` signature is:
```dart
Future<List<Map<String, dynamic>>> analyzePages({
  required List<Uint8List> imageBytesList,
  required String vlmProvider,
})
```
It posts to `/analyze` as multipart. We add `required ProcessingMode processingMode` and include it as a form field.

- [ ] **Step 1: Update the existing passing tests to add processingMode**

In `test/services/api_service_test.dart`, update both `analyzePages` call sites to pass `processingMode: ProcessingMode.textHeavy`. Also update the `MockClient` callback in the first test to assert the `processing_mode` field is present in the multipart body.

The `analyzePages` group should look like this after the edit:

```dart
group('analyzePages', () {
  test('sends images as multipart and returns pages list', () async {
    final fakePages = [
      {'page': 1, 'text': 'Once upon a time'}
    ];
    final client = MockClient((request) async {
      expect(request.url.path, '/analyze');
      expect(request.method, 'POST');
      // Verify the processing_mode field is present in the multipart body
      final bodyStr = await request.finalize().bytesToString();
      expect(bodyStr, contains('processing_mode'));
      expect(bodyStr, contains('text_heavy'));
      return http.Response(
        jsonEncode({'pages': fakePages}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final service = ApiService(baseUrl: baseUrl, client: client);
    final result = await service.analyzePages(
      imageBytesList: [Uint8List.fromList([0, 1, 2])],
      vlmProvider: 'gemini',
      processingMode: ProcessingMode.textHeavy,
    );
    expect(result, fakePages);
  });

  test('throws ApiException on non-200 response', () async {
    final client = MockClient((_) async => http.Response('error', 422));
    final service = ApiService(baseUrl: baseUrl, client: client);
    await expectLater(
      () => service.analyzePages(
        imageBytesList: [],
        vlmProvider: 'gemini',
        processingMode: ProcessingMode.textHeavy,
      ),
      throwsA(isA<ApiException>()),
    );
  });
});
```

Also add the import at the top of the test file:
```dart
import 'package:bookactor/models/processing_mode.dart';
```

- [ ] **Step 2: Run the updated tests — expect compile error**

```bash
flutter test test/services/api_service_test.dart
```
Expected: compile error — `processingMode` is not a named parameter on `analyzePages` yet.

- [ ] **Step 3: Update ApiService.analyzePages()**

In `lib/services/api_service.dart`, update `analyzePages()`:

```dart
import '../models/processing_mode.dart'; // add at top of file

Future<List<Map<String, dynamic>>> analyzePages({
  required List<Uint8List> imageBytesList,
  required String vlmProvider,
  required ProcessingMode processingMode,
}) async {
  final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/analyze'))
    ..fields['vlm_provider'] = vlmProvider
    ..fields['processing_mode'] = processingMode.toApiValue();
  for (int i = 0; i < imageBytesList.length; i++) {
    request.files.add(http.MultipartFile.fromBytes(
      'images',
      imageBytesList[i],
      filename: 'page_${i + 1}.jpg',
    ));
  }
  final streamed = await client.send(request);
  final response = await http.Response.fromStream(streamed);
  _checkStatus(response);
  final data = jsonDecode(response.body) as Map<String, dynamic>;
  return List<Map<String, dynamic>>.from(data['pages'] as List);
}
```

- [ ] **Step 4: Run the tests — expect pass**

```bash
flutter test test/services/api_service_test.dart
```
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/services/api_service.dart test/services/api_service_test.dart
git commit -m "feat: pass processing_mode to /analyze endpoint"
```

---

## Task 3: Update LoadingParams and LoadingScreen

**Files:**
- Modify: `lib/screens/loading_screen.dart`
- Modify: `test/screens/loading_screen_live_test.dart`

`LoadingParams` currently has 8 named required fields. We add `processingMode`. Then `_runLivePipeline()` passes it to `api.analyzePages()`.

- [ ] **Step 1: Add processingMode to LoadingParams**

In `lib/screens/loading_screen.dart`, add `final ProcessingMode processingMode;` to `LoadingParams` and add the import:

```dart
import '../models/processing_mode.dart';
```

The updated `LoadingParams` class:

```dart
class LoadingParams {
  final String bookId;
  final String versionId;
  final String filePath;
  final String language;
  final String vlmProvider;
  final String llmProvider;
  final ProcessingMode processingMode;   // ← new
  final bool isNewBook;
  final int lastGeneratedLine;
  final String? audioDirOverride;

  const LoadingParams({
    required this.bookId,
    required this.versionId,
    required this.filePath,
    required this.language,
    required this.vlmProvider,
    required this.llmProvider,
    required this.processingMode,         // ← new
    required this.isNewBook,
    required this.lastGeneratedLine,
    this.audioDirOverride,
  });
}
```

- [ ] **Step 2: Pass processingMode into analyzePages() in _runLivePipeline()**

In `_LoadingScreenState._runLivePipeline()`, the existing `api.analyzePages()` call is:

```dart
final pages = await api.analyzePages(
  imageBytesList: imageBytes,
  vlmProvider: p.vlmProvider,
);
```

Update it to:

```dart
final pages = await api.analyzePages(
  imageBytesList: imageBytes,
  vlmProvider: p.vlmProvider,
  processingMode: p.processingMode,
);
```

- [ ] **Step 3: Run flutter analyze — expect compile errors in test file**

```bash
flutter analyze
```
Expected: errors in `test/screens/loading_screen_live_test.dart` — missing `processingMode` in `LoadingParams` constructor and mismatched `analyzePages` override signature.

- [ ] **Step 4: Fix the test file**

In `test/screens/loading_screen_live_test.dart`:

1. Add the import at the top:
```dart
import 'package:bookactor/models/processing_mode.dart';
```

2. Update the `_RecordingApiService.analyzePages()` override signature to include `processingMode`:
```dart
@override
Future<List<Map<String, dynamic>>> analyzePages({
  required List<Uint8List> imageBytesList,
  required String vlmProvider,
  required ProcessingMode processingMode,
}) async {
  calls.add('analyze');
  return [{'page': 1, 'text': 'test'}];
}
```

3. Add `processingMode: ProcessingMode.textHeavy` to the `LoadingParams(...)` constructor call at line ~96:
```dart
final params = LoadingParams(
  bookId: 'test_book_live',
  versionId: 'test_book_live_en',
  filePath: 'test/assets/fake_image.png',
  language: 'en',
  vlmProvider: 'gemini',
  llmProvider: 'gpt4o',
  processingMode: ProcessingMode.textHeavy,   // ← new
  isNewBook: true,
  lastGeneratedLine: -1,
  audioDirOverride: tempAudioDir.path,
);
```

- [ ] **Step 5: Run tests — expect pass**

```bash
flutter test test/screens/loading_screen_live_test.dart
```
Expected: `LoadingScreen calls analyze->script->tts in order for new book` passes.

- [ ] **Step 6: Run full test suite**

```bash
flutter test
```
Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add lib/screens/loading_screen.dart test/screens/loading_screen_live_test.dart
git commit -m "feat: thread processingMode through LoadingParams to analyzePages"
```

---

## Task 4: Add mode selection UI to UploadScreen

**Files:**
- Modify: `lib/screens/upload_screen.dart`

No automated widget test for this UI (deferred per spec). Manual verification steps are included.

- [ ] **Step 1: Add ProcessingMode import and state variable**

In `lib/screens/upload_screen.dart`, add the import:
```dart
import '../models/processing_mode.dart';
```

Add `_processingMode` to `_UploadScreenState`:
```dart
ProcessingMode? _processingMode;
```

- [ ] **Step 2: Update the Generate button guard**

The existing `onPressed` on the `FilledButton.icon`:
```dart
onPressed: (_selectedFilePath == null || _isGenerating) ? null : _generate,
```

Update to also require `_processingMode`:
```dart
onPressed: (_selectedFilePath == null || _processingMode == null || _isGenerating)
    ? null
    : _generate,
```

- [ ] **Step 3: Pass processingMode into LoadingParams inside _generate()**

In `_generate()`, the existing `context.push('/loading', extra: LoadingParams(...))` call is missing `processingMode`. Add it:

```dart
context.push(
  '/loading',
  extra: LoadingParams(
    bookId: bookId,
    versionId: versionId,
    filePath: _selectedFilePath!,
    language: _language,
    vlmProvider: _vlmProvider,
    llmProvider: _llmProvider,
    processingMode: _processingMode!,   // ← new
    isNewBook: true,
    lastGeneratedLine: -1,
  ),
);
```

- [ ] **Step 4: Add the mode selection UI to the ListView**

At the top of the `ListView`'s `children` list, before the existing file-picker `GestureDetector`, add:

```dart
Text(
  'What kind of book is this?',
  style: Theme.of(context).textTheme.titleMedium,
),
const SizedBox(height: 12),
Row(
  children: [
    Expanded(
      child: _ModeCard(
        icon: '📝',
        label: 'Text-Heavy',
        subtitle: 'Story told through words',
        selected: _processingMode == ProcessingMode.textHeavy,
        onTap: () => setState(() => _processingMode = ProcessingMode.textHeavy),
      ),
    ),
    const SizedBox(width: 12),
    Expanded(
      child: _ModeCard(
        icon: '🖼️',
        label: 'Picture Book',
        subtitle: 'Story told through illustrations',
        selected: _processingMode == ProcessingMode.pictureBook,
        onTap: () => setState(() => _processingMode = ProcessingMode.pictureBook),
      ),
    ),
  ],
),
const SizedBox(height: 24),
```

- [ ] **Step 5: Add the _ModeCard widget at the bottom of the file**

After the closing `}` of `_UploadScreenState`, add a private widget:

```dart
class _ModeCard extends StatelessWidget {
  final String icon;
  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _ModeCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? color : Theme.of(context).dividerColor,
            width: selected ? 2 : 1,
          ),
          color: selected
              ? color.withValues(alpha: 0.1)
              : Theme.of(context).colorScheme.surface,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(icon, style: const TextStyle(fontSize: 28)),
            const SizedBox(height: 8),
            Text(label,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(subtitle,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 6: Run flutter analyze**

```bash
flutter analyze
```
Expected: no errors.

- [ ] **Step 7: Run full test suite**

```bash
flutter test
```
Expected: all tests pass.

- [ ] **Step 8: Manual smoke test**

Run the app (`flutter run`). On the upload screen:
1. Confirm both mode cards render unselected.
2. Confirm the Generate button is disabled.
3. Tap "Text-Heavy" — card highlights, Generate button remains disabled (no file selected).
4. Pick a file — Generate button becomes enabled.
5. Tap "Picture Book" — mode switches, Text-Heavy unhighlights.
6. Tap Generate — proceeds to LoadingScreen with correct params.

- [ ] **Step 9: Commit**

```bash
git add lib/screens/upload_screen.dart
git commit -m "feat: add Text-Heavy / Picture Book mode selector to upload screen"
```
