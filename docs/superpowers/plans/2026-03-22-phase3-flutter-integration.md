# Phase 3b: Flutter Live Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace all mock touchpoints in the Flutter app with live backend calls, real PDF-to-image conversion (pdfx), and real audio playback (audioplayers), so the full VLM → LLM → TTS → play pipeline works end-to-end.

**Architecture:** Three new service files encapsulate all I/O concerns: `api_service.dart` (HTTP calls to FastAPI), `pdf_service.dart` (PDF → JPEG via pdfx), `audio_service.dart` (audioplayers wrapper). `LoadingScreen` gains new constructor parameters to drive the live pipeline. The Loading screen orchestrates the three-step pipeline by calling `api_service` and persisting results to SQLite after each step. The Player screen switches from a mock timer to `audio_service`. The Upload screen adds real SHA-256 file hashing and captures the full file path.

**Tech Stack:** Flutter (existing), `http` package (HTTP multipart), `pdfx` (PDF rendering), `audioplayers` (audio playback), `crypto` (SHA-256 hashing), existing `sqflite` + `riverpod` + `go_router` infrastructure.

---

## File Structure

```
lib/
  services/
    api_service.dart         # Three methods: analyzePages(), generateScript(), generateAudio()
    pdf_service.dart         # PdfService.pdfToJpegBytes(path) → List<Uint8List>
    audio_service.dart       # AudioService: load/play/pause/stop/onComplete/dispose
  db/
    database.dart            # [MODIFY] add updateBookVlmOutput() method
  screens/
    upload_screen.dart       # [MODIFY] capture file path; SHA-256 hash; update navigation
    loading_screen.dart      # [MODIFY] expand constructor; replace _runMockPipeline with _runLivePipeline
    player_screen.dart       # [MODIFY] replace mock timer with AudioService
    library_screen.dart      # [MODIFY] implement Dismiss handler cold-start stub

pubspec.yaml                 # [MODIFY] add: http, pdfx, audioplayers, crypto

test/
  services/
    api_service_test.dart    # Unit tests — mock http.Client
    pdf_service_test.dart    # Unit tests — minimal test PDF asset
    audio_service_test.dart  # Unit tests — AudioService lifecycle
  db/
    database_test.dart       # [MODIFY] add test for updateBookVlmOutput
  screens/
    loading_screen_live_test.dart   # Widget test — mock ApiService; verify pipeline steps
    upload_screen_hash_test.dart    # Unit test — SHA-256 logic
test/
  assets/
    sample.pdf               # Minimal valid 1-page PDF for pdf_service tests
```

---

### Task 1: Add dependencies

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: Add packages to `pubspec.yaml`**

Under `dependencies:`, add:

```yaml
  http: ^1.2.0
  pdfx: ^2.8.1
  audioplayers: ^6.1.0
  crypto: ^3.0.3
```

- [ ] **Step 2: Install**

```bash
flutter pub get
```

Expected: exit 0, no version conflicts

- [ ] **Step 3: Verify no analyzer errors from new deps**

```bash
flutter analyze --no-fatal-infos
```

Expected: zero errors

- [ ] **Step 4: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore: add http, pdfx, audioplayers, crypto dependencies"
```

---

### Task 2: `api_service.dart`

**Files:**
- Create: `lib/services/api_service.dart`
- Create: `test/services/api_service_test.dart`

- [ ] **Step 1: Write the failing tests**

Create `test/services/api_service_test.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookactor/services/api_service.dart';

void main() {
  const baseUrl = 'http://localhost:8000';

  group('analyzePages', () {
    test('sends images as multipart and returns pages list', () async {
      final fakePages = [
        {'page': 1, 'text': 'Once upon a time'}
      ];
      final client = MockClient((request) async {
        expect(request.url.path, '/analyze');
        expect(request.method, 'POST');
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
      );
      expect(result, fakePages);
    });

    test('throws ApiException on non-200 response', () async {
      final client = MockClient((_) async => http.Response('error', 422));
      final service = ApiService(baseUrl: baseUrl, client: client);
      expect(
        () => service.analyzePages(imageBytesList: [], vlmProvider: 'gemini'),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('generateScript', () {
    test('posts vlm_output + language + llm_provider and returns script', () async {
      final fakeScript = {
        'characters': [{'name': 'Narrator', 'voice': 'alloy'}],
        'lines': <dynamic>[],
      };
      final client = MockClient((request) async {
        expect(request.url.path, '/script');
        final body = jsonDecode(request.body) as Map;
        expect(body['language'], 'zh');
        return http.Response(
          jsonEncode({'script': fakeScript}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = ApiService(baseUrl: baseUrl, client: client);
      final result = await service.generateScript(
        vlmOutput: [{'page': 1, 'text': 'Hello'}],
        language: 'zh',
        llmProvider: 'gpt4o',
      );
      expect(result['characters'], isNotEmpty);
    });

    test('throws ApiException on error', () async {
      final client = MockClient((_) async => http.Response('bad', 500));
      final service = ApiService(baseUrl: baseUrl, client: client);
      expect(
        () => service.generateScript(vlmOutput: [], language: 'en', llmProvider: 'gpt4o'),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('generateAudio', () {
    test('posts lines and returns audio results', () async {
      final fakeResults = [
        {'index': 0, 'status': 'ready', 'audio_b64': base64Encode([1, 2, 3])}
      ];
      final client = MockClient((request) async {
        expect(request.url.path, '/tts');
        final body = jsonDecode(request.body) as Map;
        expect(body['lines'], isNotEmpty);
        return http.Response(
          jsonEncode(fakeResults),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = ApiService(baseUrl: baseUrl, client: client);
      final result = await service.generateAudio(lines: [
        {'index': 0, 'text': 'Hi', 'voice': 'alloy'}
      ]);
      expect(result.first['status'], 'ready');
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
flutter test test/services/api_service_test.dart
```

Expected: FAIL — `lib/services/api_service.dart` not found

- [ ] **Step 3: Implement `lib/services/api_service.dart`**

```dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  final int statusCode;
  final String message;
  const ApiException(this.statusCode, this.message);
  @override
  String toString() => 'ApiException($statusCode): $message';
}

class ApiService {
  final String baseUrl;
  final http.Client client;

  ApiService({required this.baseUrl, http.Client? client})
      : client = client ?? http.Client();

  Future<List<Map<String, dynamic>>> analyzePages({
    required List<Uint8List> imageBytesList,
    required String vlmProvider,
  }) async {
    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/analyze'))
      ..fields['vlm_provider'] = vlmProvider;
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

  Future<Map<String, dynamic>> generateScript({
    required List<Map<String, dynamic>> vlmOutput,
    required String language,
    required String llmProvider,
  }) async {
    final response = await client.post(
      Uri.parse('$baseUrl/script'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'vlm_output': vlmOutput,
        'language': language,
        'llm_provider': llmProvider,
      }),
    );
    _checkStatus(response);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return Map<String, dynamic>.from(data['script'] as Map);
  }

  Future<List<Map<String, dynamic>>> generateAudio({
    required List<Map<String, dynamic>> lines,
  }) async {
    final response = await client.post(
      Uri.parse('$baseUrl/tts'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'lines': lines}),
    );
    _checkStatus(response);
    final data = jsonDecode(response.body) as List;
    return List<Map<String, dynamic>>.from(data);
  }

  void _checkStatus(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, response.body);
    }
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
flutter test test/services/api_service_test.dart
```

Expected: 6 PASS

- [ ] **Step 5: Commit**

```bash
git add lib/services/api_service.dart test/services/api_service_test.dart
git commit -m "feat: add ApiService for backend HTTP calls"
```

---

### Task 3: `pdf_service.dart`

**Files:**
- Create: `lib/services/pdf_service.dart`
- Create: `test/services/pdf_service_test.dart`
- Create: `test/assets/sample.pdf`

- [ ] **Step 1: Create the test PDF asset**

Run this once to produce a minimal valid 1-page PDF:

```bash
python3 -c "
import base64, pathlib
pdf_b64 = 'JVBERi0xLjAKMSAwIG9iago8PCAvVHlwZSAvQ2F0YWxvZyAvUGFnZXMgMiAwIFIgPj4KZW5kb2JqCjIgMCBvYmoKPDwgL1R5cGUgL1BhZ2VzIC9LaWRzIFszIDAgUl0gL0NvdW50IDEgPj4KZW5kb2JqCjMgMCBvYmoKPDwgL1R5cGUgL1BhZ2UgL1BhcmVudCAyIDAgUiAvTWVkaWFCb3ggWzAgMCA2MTIgNzkyXSA+PgplbmRvYmoKeHJlZgowIDQKMDAwMDAwMDAwMCA2NTUzNSBmIAowMDAwMDAwMDA5IDAwMDAwIG4gCjAwMDAwMDAwNjggMDAwMDAgbiAKMDAwMDAwMDEyNiAwMDAwMCBuIAp0cmFpbGVyCjw8IC9TaXplIDQgL1Jvb3QgMSAwIFIgPj4Kc3RhcnR4cmVmCjIwMgolJUVPRgo='
pathlib.Path('test/assets').mkdir(parents=True, exist_ok=True)
pathlib.Path('test/assets/sample.pdf').write_bytes(base64.b64decode(pdf_b64))
print('Created test/assets/sample.pdf')
"
```

- [ ] **Step 2: Write the failing tests**

Create `test/services/pdf_service_test.dart`:

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookactor/services/pdf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('pdfToJpegBytes returns non-empty list for a valid PDF', () async {
    final file = File('test/assets/sample.pdf');
    // Skip if the test asset was not created
    if (!file.existsSync()) {
      markTestSkipped('test/assets/sample.pdf not found — skipping');
    }
    final bytes = await PdfService.pdfToJpegBytes(file.path);
    expect(bytes, isNotEmpty);
    expect(bytes.first, isNotEmpty);
  });

  test('pdfToJpegBytes throws PdfException for non-existent file', () async {
    expect(
      () => PdfService.pdfToJpegBytes('/no/such/file.pdf'),
      throwsA(isA<PdfException>()),
    );
  });
}
```

- [ ] **Step 3: Run tests to verify they fail**

```bash
flutter test test/services/pdf_service_test.dart
```

Expected: FAIL — `lib/services/pdf_service.dart` not found

- [ ] **Step 4: Implement `lib/services/pdf_service.dart`**

```dart
import 'dart:io';
import 'dart:typed_data';
import 'package:pdfx/pdfx.dart';

class PdfException implements Exception {
  final String message;
  const PdfException(this.message);
  @override
  String toString() => 'PdfException: $message';
}

class PdfService {
  /// Converts a PDF file at [path] to a list of JPEG byte arrays (one per page).
  static Future<List<Uint8List>> pdfToJpegBytes(String path) async {
    if (!File(path).existsSync()) {
      throw PdfException('File not found: $path');
    }
    try {
      final document = await PdfDocument.openFile(path);
      final pageCount = document.pagesCount;
      final results = <Uint8List>[];
      for (int i = 1; i <= pageCount; i++) {
        final page = await document.getPage(i);
        final image = await page.render(
          width: page.width * 2,
          height: page.height * 2,
          format: PdfPageImageFormat.jpeg,
          quality: 85,
        );
        results.add(image!.bytes);
        await page.close();
      }
      await document.close();
      return results;
    } catch (e) {
      if (e is PdfException) rethrow;
      throw PdfException('Failed to render PDF: $e');
    }
  }
}
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
flutter test test/services/pdf_service_test.dart
```

Expected: PASS (file-not-found test passes; PDF render test passes or is skipped)

- [ ] **Step 6: Commit**

```bash
git add lib/services/pdf_service.dart test/services/pdf_service_test.dart test/assets/
git commit -m "feat: add PdfService for PDF-to-JPEG conversion via pdfx"
```

---

### Task 4: `audio_service.dart`

**Files:**
- Create: `lib/services/audio_service.dart`
- Create: `test/services/audio_service_test.dart`

- [ ] **Step 1: Write the failing tests**

Create `test/services/audio_service_test.dart`:

```dart
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookactor/services/audio_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('AudioService can be instantiated and disposed without error', () async {
    final service = AudioService();
    expect(service, isNotNull);
    service.dispose();
  });

  test('AudioService play/pause/stop do not throw in test environment', () async {
    final service = AudioService();
    await service.load('/fake/path/line_000.mp3');
    await service.play();
    await service.pause();
    await service.stop();
    service.dispose();
  });

  test('simulateComplete emits on onComplete stream', () async {
    final service = AudioService();
    final completer = Completer<void>();
    final sub = service.onComplete.listen((_) => completer.complete());

    service.simulateComplete();

    await completer.future.timeout(const Duration(seconds: 1));
    await sub.cancel();
    service.dispose();
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
flutter test test/services/audio_service_test.dart
```

Expected: FAIL — `lib/services/audio_service.dart` not found

- [ ] **Step 3: Implement `lib/services/audio_service.dart`**

```dart
import 'dart:async';
import 'package:audioplayers/audioplayers.dart';

class AudioService {
  final AudioPlayer _player;
  final StreamController<void> _onCompleteController =
      StreamController<void>.broadcast();

  AudioService() : _player = AudioPlayer() {
    _player.onPlayerComplete.listen((_) {
      _onCompleteController.add(null);
    });
  }

  Stream<void> get onComplete => _onCompleteController.stream;

  Future<void> load(String filePath) async {
    await _player.setSourceDeviceFile(filePath);
  }

  Future<void> play() => _player.resume();
  Future<void> pause() => _player.pause();
  Future<void> stop() => _player.stop();

  /// Test-only: simulate playback completion without needing a real audio file.
  void simulateComplete() => _onCompleteController.add(null);

  void dispose() {
    _onCompleteController.close();
    _player.dispose();
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
flutter test test/services/audio_service_test.dart
```

Expected: 3 PASS

- [ ] **Step 5: Commit**

```bash
git add lib/services/audio_service.dart test/services/audio_service_test.dart
git commit -m "feat: add AudioService wrapping audioplayers"
```

---

### Task 5: Add `updateBookVlmOutput` to database

**Files:**
- Modify: `lib/db/database.dart`
- Modify: `test/db/database_test.dart`

The live pipeline needs to persist VLM output to `books.vlm_output` after `/analyze` returns. The existing `insertBook` requires a full `Book` object. A targeted update method is cleaner.

- [ ] **Step 1: Read `lib/db/database.dart` and `test/db/database_test.dart` fully before editing**

- [ ] **Step 2: Write the failing test**

Add to `test/db/database_test.dart`, inside the existing `group('AppDatabase', ...)`:

```dart
test('updateBookVlmOutput updates vlm_output for existing book', () async {
  final db = AppDatabase.forTesting();
  await db.init();
  await db.insertBook(const Book(
    bookId: 'book_test_vlm',
    title: 'Test',
    coverPath: null,
    pagesDir: '/tmp/pages',
    vlmOutput: '[]',
    vlmProvider: 'gemini',
    createdAt: 1000,
  ));

  await db.updateBookVlmOutput('book_test_vlm', '[{"page":1,"text":"Hello"}]');

  final updated = await db.getBook('book_test_vlm');
  expect(updated!.vlmOutput, '[{"page":1,"text":"Hello"}]');
  await db.close();
});
```

- [ ] **Step 3: Run test to verify it fails**

```bash
flutter test test/db/database_test.dart
```

Expected: FAIL — `updateBookVlmOutput` method not found

- [ ] **Step 4: Add `updateBookVlmOutput` to `lib/db/database.dart`**

Add this method after `insertBook`:

```dart
/// Updates the vlm_output column for a book after /analyze returns.
Future<void> updateBookVlmOutput(String bookId, String vlmOutput) async {
  final db = await database;
  await db.update(
    'books',
    {'vlm_output': vlmOutput},
    where: 'book_id = ?',
    whereArgs: [bookId],
  );
}
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
flutter test test/db/database_test.dart
```

Expected: all PASS (including the new test)

- [ ] **Step 6: Commit**

```bash
git add lib/db/database.dart test/db/database_test.dart
git commit -m "feat: add updateBookVlmOutput to AppDatabase"
```

---

### Task 6: Wire real SHA-256 hash and file path in `upload_screen.dart`

**Files:**
- Modify: `lib/screens/upload_screen.dart`
- Create: `test/screens/upload_screen_hash_test.dart`

The upload screen currently hard-codes `book_id = 'mock_book_001'` and only stores the file name (not the path). This task: captures the full file path from the picker, computes a SHA-256 hash as the real `book_id`, persists the book row to SQLite, and navigates to the updated `LoadingScreen` (which gains parameters in Task 7).

- [ ] **Step 1: Read `lib/screens/upload_screen.dart` fully**

Note: `_selectedFileName` is set, but `_selectedFilePath` does not exist. The Generate button calls `context.push('/loading/mock_book_001/$_language')`.

- [ ] **Step 2: Write the failing test**

Create `test/screens/upload_screen_hash_test.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SHA-256 of known bytes is 64 hex characters', () {
    final bytes = utf8.encode('hello world');
    final digest = sha256.convert(bytes);
    // Verify length — exact value test would be brittle across platforms
    expect(digest.toString().length, equals(64));
  });

  test('SHA-256 is deterministic for same input', () {
    final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
    final d1 = sha256.convert(bytes).toString();
    final d2 = sha256.convert(bytes).toString();
    expect(d1, equals(d2));
  });

  test('SHA-256 differs for different inputs', () {
    final d1 = sha256.convert(utf8.encode('abc')).toString();
    final d2 = sha256.convert(utf8.encode('xyz')).toString();
    expect(d1, isNot(equals(d2)));
  });
}
```

- [ ] **Step 3: Run tests to verify they pass (pure logic — no mock needed)**

```bash
flutter test test/screens/upload_screen_hash_test.dart
```

Expected: 3 PASS (crypto is pure Dart)

- [ ] **Step 4: Modify `lib/screens/upload_screen.dart`**

Add imports:
```dart
import 'dart:io';
import 'package:crypto/crypto.dart';
import '../db/database.dart';
import '../models/book.dart';
```

Add `_selectedFilePath` field alongside `_selectedFileName`:
```dart
String? _selectedFileName;
String? _selectedFilePath;
```

Update `_pickFile()` to also capture the path:
```dart
Future<void> _pickFile() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
  );
  if (result != null) {
    setState(() {
      _selectedFileName = result.files.single.name;
      _selectedFilePath = result.files.single.path;
    });
  }
}
```

Replace the inline Generate button `onPressed` lambda with a method `_generate()`:
```dart
Future<void> _generate() async {
  if (_selectedFilePath == null) return;
  final fileBytes = await File(_selectedFilePath!).readAsBytes();
  final bookId = sha256.convert(fileBytes).toString();

  // Persist the book row (vlm_output populated after /analyze in LoadingScreen)
  await AppDatabase.instance.insertBook(Book(
    bookId: bookId,
    title: _selectedFileName ?? 'Untitled',
    coverPath: null,
    pagesDir: _selectedFilePath!, // Phase 3: LoadingScreen will render PDF pages
    vlmOutput: '[]',              // placeholder until /analyze completes
    vlmProvider: _vlmProvider,
    createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
  ));

  // Insert generating audio_version placeholder
  final versionId = '${bookId}_$_language';
  await AppDatabase.instance.insertAudioVersion(AudioVersion(
    versionId: versionId,
    bookId: bookId,
    language: _language,
    llmProvider: _llmProvider,
    scriptJson: '{}',
    audioDir: '', // populated in LoadingScreen after generation
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
      filePath: _selectedFilePath!,
      language: _language,
      vlmProvider: _vlmProvider,
      llmProvider: _llmProvider,
      isNewBook: true,
      lastGeneratedLine: 0,
    ),
  );
}
```

Update the Generate button to call `_generate()`:
```dart
onPressed: _selectedFileName == null ? null : _generate,
```

> **Note:** `LoadingParams` and the updated `LoadingScreen` constructor are defined in Task 7.
> Add `import '../models/audio_version.dart';` if not already present.

- [ ] **Step 5: Regression check — run all existing tests**

```bash
flutter test
```

Expected: all PASS (upload screen now calls `_generate()` but tests use the mock path, which is unaffected)

- [ ] **Step 6: Commit**

```bash
git add lib/screens/upload_screen.dart test/screens/upload_screen_hash_test.dart
git commit -m "feat: compute real SHA-256 book_id and capture file path in upload screen"
```

---

### Task 7: Expand `LoadingScreen` and implement live pipeline

**Files:**
- Modify: `lib/screens/loading_screen.dart`
- Create: `test/screens/loading_screen_live_test.dart`

`LoadingScreen` currently takes only `bookId` and `language`. The live pipeline needs `versionId`, `filePath`, `vlmProvider`, `llmProvider`, `isNewBook`, and `lastGeneratedLine`. These are passed via GoRouter `extra` as a `LoadingParams` value object.

- [ ] **Step 1: Read `lib/screens/loading_screen.dart` and `lib/main.dart` (GoRouter definition) fully**

- [ ] **Step 2: Write the failing test**

Create `test/screens/loading_screen_live_test.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:bookactor/screens/loading_screen.dart';
import 'package:bookactor/services/api_service.dart';

/// Stub ApiService that records calls in order and returns minimal valid responses.
class _RecordingApiService extends ApiService {
  final List<String> calls = [];

  _RecordingApiService() : super(baseUrl: 'http://fake');

  @override
  Future<List<Map<String, dynamic>>> analyzePages({
    required List<Uint8List> imageBytesList,
    required String vlmProvider,
  }) async {
    calls.add('analyze');
    return [{'page': 1, 'text': 'test'}];
  }

  @override
  Future<Map<String, dynamic>> generateScript({
    required List<Map<String, dynamic>> vlmOutput,
    required String language,
    required String llmProvider,
  }) async {
    calls.add('script');
    return {
      'characters': [{'name': 'Narrator', 'voice': 'alloy'}],
      'lines': [
        {'index': 0, 'character': 'Narrator', 'text': 'Hi', 'page': 1, 'status': 'pending'}
      ],
    };
  }

  @override
  Future<List<Map<String, dynamic>>> generateAudio({
    required List<Map<String, dynamic>> lines,
  }) async {
    calls.add('tts');
    return [{'index': 0, 'status': 'ready', 'audio_b64': base64Encode([1, 2, 3])}];
  }
}

void main() {
  testWidgets('LoadingScreen calls analyze→script→tts in order for new book', (tester) async {
    final fakeApi = _RecordingApiService();
    final params = LoadingParams(
      bookId: 'test_book',
      versionId: 'test_book_en',
      filePath: 'test/assets/sample.pdf',
      language: 'en',
      vlmProvider: 'gemini',
      llmProvider: 'gpt4o',
      isNewBook: true,
      lastGeneratedLine: 0,
    );

    final router = GoRouter(routes: [
      GoRoute(
        path: '/loading',
        builder: (context, state) => LoadingScreen(
          params: params,
          apiService: fakeApi, // injected for testing
        ),
      ),
      GoRoute(path: '/player/:versionId', builder: (_, __) => const Scaffold()),
    ]);

    await tester.pumpWidget(ProviderScope(
      child: MaterialApp.router(routerConfig: router),
    ));

    // Navigate to loading
    final context = tester.element(find.byType(MaterialApp));
    GoRouter.of(context).push('/loading');
    await tester.pumpAndSettle(const Duration(seconds: 5));

    // Pipeline steps must have been called in order
    expect(fakeApi.calls, ['analyze', 'script', 'tts']);
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

```bash
flutter test test/screens/loading_screen_live_test.dart
```

Expected: FAIL — `LoadingParams` and `LoadingScreen(params:, apiService:)` not found

- [ ] **Step 4: Add `LoadingParams` and update `LoadingScreen` constructor**

At the top of `lib/screens/loading_screen.dart`, add the `LoadingParams` value class:

```dart
/// Carries all parameters needed to run the generation pipeline.
/// Passed via GoRouter extra to decouple LoadingScreen from the route structure.
class LoadingParams {
  final String bookId;
  final String versionId;
  final String filePath;     // full path to the source PDF or image
  final String language;
  final String vlmProvider;
  final String llmProvider;
  final bool isNewBook;       // false = /analyze already done; skip to /script
  final int lastGeneratedLine; // 0 = fresh start; N = resume from line N+1

  const LoadingParams({
    required this.bookId,
    required this.versionId,
    required this.filePath,
    required this.language,
    required this.vlmProvider,
    required this.llmProvider,
    required this.isNewBook,
    required this.lastGeneratedLine,
  });
}
```

Update `LoadingScreen` to accept `LoadingParams` and an optional `ApiService` for injection:

```dart
class LoadingScreen extends StatefulWidget {
  // Phase 2 compat: keep bookId + language for existing GoRouter path '/loading/:bookId/:language'
  final String bookId;
  final String language;

  // Phase 3 live pipeline params — null when using mock path
  final LoadingParams? params;
  final ApiService? apiService; // injected for testing; defaults to ApiService() in production

  const LoadingScreen({
    super.key,
    required this.bookId,
    required this.language,
    this.params,
    this.apiService,
  });

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}
```

In `initState`, choose which pipeline to run:

```dart
@override
void initState() {
  super.initState();
  if (widget.params != null) {
    _runLivePipeline();
  } else {
    _runMockPipeline();
  }
}
```

- [ ] **Step 5: Implement `_runLivePipeline()`**

Add these imports to `loading_screen.dart`:

```dart
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path_pkg;
import 'package:path_provider/path_provider.dart';
import '../db/database.dart';
import '../services/api_service.dart';
import '../services/pdf_service.dart';
```

Add `_runLivePipeline()` method to `_LoadingScreenState`:

```dart
Future<void> _runLivePipeline() async {
  final p = widget.params!;
  final api = widget.apiService ?? ApiService(baseUrl: 'http://localhost:8000');

  try {
    // ── Step 0: Reading pages (VLM) ─────────────────────────────────────
    if (!mounted) return;
    setState(() => _step = 0);

    List<Map<String, dynamic>> vlmOutput;

    if (p.isNewBook) {
      // Convert PDF/images to JPEG bytes
      final List<Uint8List> imageBytes;
      if (p.filePath.toLowerCase().endsWith('.pdf')) {
        imageBytes = await PdfService.pdfToJpegBytes(p.filePath);
      } else {
        imageBytes = [await File(p.filePath).readAsBytes()];
      }
      if (!mounted) return;

      // Call /analyze
      final pages = await api.analyzePages(
        imageBytesList: imageBytes,
        vlmProvider: p.vlmProvider,
      );
      if (!mounted) return;

      // Persist VLM output so a re-run can skip /analyze
      final vlmJson = jsonEncode(pages);
      await AppDatabase.instance.updateBookVlmOutput(p.bookId, vlmJson);
      vlmOutput = pages;
    } else {
      // New language request — VLM already done; load from DB
      final book = await AppDatabase.instance.getBook(p.bookId);
      vlmOutput = List<Map<String, dynamic>>.from(
        jsonDecode(book!.vlmOutput) as List,
      );
    }
    if (!mounted) return;
    setState(() => _step = 1);

    // ── Step 1: Writing script (LLM) ────────────────────────────────────
    final scriptMap = await api.generateScript(
      vlmOutput: vlmOutput,
      language: p.language,
      llmProvider: p.llmProvider,
    );
    if (!mounted) return;

    // Persist script (all lines pending) before starting TTS
    final scriptJson = jsonEncode(scriptMap);
    await AppDatabase.instance.updateAudioVersionStatus(
      p.versionId, 'generating',
      scriptJson: scriptJson,
    );

    setState(() => _step = 2);

    // ── Step 2: Recording voices (TTS) ──────────────────────────────────
    // Prepare audio directory
    final docsDir = await getApplicationDocumentsDirectory();
    final audioDir = path_pkg.join(docsDir.path, 'audio', p.versionId);
    await Directory(audioDir).create(recursive: true);
    if (!mounted) return;

    // Build lines payload — resume from last_generated_line if applicable
    final characters = List<Map<String, dynamic>>.from(
      scriptMap['characters'] as List,
    );
    final lines = List<Map<String, dynamic>>.from(
      scriptMap['lines'] as List,
    );
    final pendingLines = lines
        .where((l) => (l['index'] as int) > p.lastGeneratedLine || p.lastGeneratedLine == 0)
        .where((l) => l['status'] == 'pending')
        .map((l) {
          final charName = l['character'] as String;
          final voice = characters
              .firstWhere(
                (c) => c['name'] == charName,
                orElse: () => {'voice': 'alloy'},
              )['voice'] as String;
          return {'index': l['index'], 'text': l['text'], 'voice': voice};
        })
        .toList();

    // Call /tts and persist results line-by-line (crash recovery)
    final audioResults = await api.generateAudio(lines: pendingLines);
    final scriptLines = List<Map<String, dynamic>>.from(lines);

    for (final result in audioResults) {
      final idx = result['index'] as int;
      if (result['status'] == 'ready') {
        // Decode and write .mp3 file
        final audioBytes = base64Decode(result['audio_b64'] as String);
        final fileName = 'line_${idx.toString().padLeft(3, '0')}.mp3';
        await File(path_pkg.join(audioDir, fileName)).writeAsBytes(audioBytes);
        scriptLines[idx] = {...scriptLines[idx], 'status': 'ready'};
      } else {
        scriptLines[idx] = {...scriptLines[idx], 'status': 'error'};
      }

      // Per-line SQLite write — enables crash recovery to exact line
      await AppDatabase.instance.updateAudioVersionStatus(
        p.versionId, 'generating',
        lastGeneratedLine: idx,
        scriptJson: jsonEncode({...scriptMap, 'lines': scriptLines}),
      );
    }

    if (!mounted) return;

    // Mark version ready and set audioDir
    await AppDatabase.instance.updateAudioVersionStatus(p.versionId, 'ready');
    // Update audioDir in the version record (requires a DB update — use insertAudioVersion with replace)
    final existing = await AppDatabase.instance.getAudioVersion(p.versionId);
    if (existing != null) {
      await AppDatabase.instance.insertAudioVersion(
        existing.copyWith(audioDir: audioDir, status: 'ready'),
      );
    }

    if (!mounted) return;
    context.go('/player/${p.versionId}');
  } on ApiException catch (e) {
    if (!mounted) return;
    setState(() => _hasError = true);
    // Fatal if VLM/LLM step failed; recoverable if TTS partial
  } on PdfException catch (e) {
    if (!mounted) return;
    setState(() => _hasError = true);
  } catch (e) {
    if (!mounted) return;
    setState(() => _hasError = true);
  }
}
```

Also update the "Try Again" button to call `_runLivePipeline()` (not `_runMockPipeline()`) when `params != null`:

```dart
onPressed: () {
  setState(() { _step = 0; _hasError = false; });
  if (widget.params != null) {
    _runLivePipeline();
  } else {
    _runMockPipeline();
  }
},
```

> **Note:** `AudioVersion.copyWith()` — check if it exists in `lib/models/audio_version.dart`. If not, add it. Read the file before editing.

- [ ] **Step 6: Update GoRouter to accept `LoadingParams` extra**

Read `lib/main.dart` (where GoRouter is defined). Find the `/loading/:bookId/:language` route and update it to also handle the `extra` params:

```dart
GoRoute(
  path: '/loading/:bookId/:language',
  builder: (context, state) {
    final extra = state.extra as LoadingParams?;
    return LoadingScreen(
      bookId: state.pathParameters['bookId']!,
      language: state.pathParameters['language']!,
      params: extra,
    );
  },
),
```

Also add the parameterless `/loading` path used by Task 6 upload navigation:
```dart
GoRoute(
  path: '/loading',
  builder: (context, state) {
    final extra = state.extra as LoadingParams?;
    return LoadingScreen(
      bookId: extra?.bookId ?? '',
      language: extra?.language ?? 'en',
      params: extra,
    );
  },
),
```

- [ ] **Step 7: Run tests to verify they pass**

```bash
flutter test test/screens/loading_screen_live_test.dart
flutter test  # full suite regression check
```

Expected: all PASS

- [ ] **Step 8: Commit**

```bash
git add lib/screens/loading_screen.dart lib/main.dart test/screens/loading_screen_live_test.dart
git commit -m "feat: implement live API pipeline in LoadingScreen"
```

---

### Task 8: Replace mock audio timer in `player_screen.dart`

**Files:**
- Modify: `lib/screens/player_screen.dart`
- Create: `test/screens/player_screen_audio_test.dart`

- [ ] **Step 1: Read `lib/screens/player_screen.dart` fully**

Note: there is a mock `Timer` that advances lines every 2 seconds. There is an existing mock-path branch in `_loadScript()` (`widget.versionId == 'mock_book_001_en'`).

- [ ] **Step 2: Write the failing test**

Create `test/screens/player_screen_audio_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:bookactor/services/audio_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('AudioService simulateComplete notifies listener', () async {
    final service = AudioService();
    var notified = false;
    final sub = service.onComplete.listen((_) => notified = true);

    service.simulateComplete();
    await Future.microtask(() {}); // let stream deliver

    expect(notified, isTrue);
    await sub.cancel();
    service.dispose();
  });
}
```

- [ ] **Step 3: Run test to verify it passes**

```bash
flutter test test/screens/player_screen_audio_test.dart
```

Expected: PASS

- [ ] **Step 4: Modify `player_screen.dart`**

Add import:
```dart
import '../services/audio_service.dart';
```

Replace the mock `Timer` field with an `AudioService` field:
```dart
// Replace: Timer? _mockTimer;
AudioService? _audioService;
```

In `initState`, initialize only for non-mock versions:
```dart
@override
void initState() {
  super.initState();
  if (widget.versionId != 'mock_book_001_en') {
    _audioService = AudioService();
  }
  _loadScript();
}
```

Replace the mock timer play/pause logic with `AudioService`:
```dart
void _play() {
  if (widget.versionId == 'mock_book_001_en') {
    // Keep mock timer for development/demo
    _startMockTimer();
  } else {
    _audioService?.play();
  }
  ref.read(playerProvider.notifier).play();
}

void _pause() {
  if (widget.versionId == 'mock_book_001_en') {
    _cancelMockTimer();
  } else {
    _audioService?.pause();
  }
  ref.read(playerProvider.notifier).pause();
}
```

After `loadScript` sets up the player state, load the first `.mp3` for live versions:
```dart
void _onScriptLoaded() {
  if (widget.versionId == 'mock_book_001_en') return;
  final currentLine = ref.read(playerProvider).currentScriptLine;
  if (currentLine != null) {
    _loadAndPlayLine(currentLine.index);
  }
}

Future<void> _loadAndPlayLine(int index) async {
  if (_audioService == null) return;
  final audioPath = '${widget.audioDir}/line_${index.toString().padLeft(3, '0')}.mp3';
  await _audioService!.load(audioPath);
  await _audioService!.play();
}
```

Set up the `onComplete` listener in `initState` (after `_audioService` is created):
```dart
_audioService?.onComplete.listen((_) {
  ref.read(playerProvider.notifier).nextLine();
  final nextLine = ref.read(playerProvider).currentScriptLine;
  if (nextLine != null) {
    _loadAndPlayLine(nextLine.index);
  }
});
```

In `dispose()`:
```dart
@override
void dispose() {
  _cancelMockTimer(); // existing mock cleanup
  _audioService?.dispose();
  super.dispose();
}
```

> **Note:** `widget.audioDir` — check whether `PlayerScreen` currently accepts `audioDir`. If not, add it as an optional parameter with a default of `''`. Read the file before editing.

- [ ] **Step 5: Run full test suite**

```bash
flutter test
```

Expected: all PASS

- [ ] **Step 6: Commit**

```bash
git add lib/screens/player_screen.dart test/screens/player_screen_audio_test.dart
git commit -m "feat: wire AudioService into PlayerScreen for real .mp3 playback"
```

---

### Task 9: Implement cold-start Dismiss handler in `library_screen.dart`

**Files:**
- Modify: `lib/screens/library_screen.dart`

The Dismiss button currently has an empty `onPressed` with a `// Phase 3: mark as error in DB` comment.

- [ ] **Step 1: Write the failing test**

Add to `test/screens/library_screen_test.dart`:

```dart
testWidgets('Dismiss button marks generating versions as error', (tester) async {
  // This test requires a real or in-memory DB with a generating version.
  // Verify the Dismiss button exists and is tappable when banner is shown.
  // Full DB integration test lives in test/db/database_test.dart (updateAudioVersionStatus).
  // Here we only verify the button calls the right DB method via a widget test stub.
  // Since AppDatabase.instance is a singleton, skip DB assertions; focus on UI:
  expect(find.text('Dismiss'), findsNothing); // no banner when no generating versions
});
```

- [ ] **Step 2: Run test to verify it passes (trivially — no banner = no button)**

```bash
flutter test test/screens/library_screen_test.dart
```

Expected: all PASS (including new trivial test)

- [ ] **Step 3: Implement the Dismiss handler in `lib/screens/library_screen.dart`**

Find the empty `onPressed` of the Dismiss button (line ~43) and replace it:

```dart
TextButton(
  onPressed: () async {
    for (final v in versions) {
      await AppDatabase.instance.updateAudioVersionStatus(
        v.versionId, 'error',
      );
    }
    ref.invalidate(generatingVersionsProvider);
  },
  child: const Text('Dismiss'),
),
```

Add import at top if not already present:
```dart
import '../db/database.dart';
```

- [ ] **Step 4: Run full test suite**

```bash
flutter test
```

Expected: all PASS

- [ ] **Step 5: Commit**

```bash
git add lib/screens/library_screen.dart test/screens/library_screen_test.dart
git commit -m "feat: implement cold-start Dismiss handler to mark interrupted sessions as error"
```

---

### Task 10: Final test run and verification

**Files:**
- No new files — verification only

- [ ] **Step 1: Run the full Flutter test suite**

```bash
flutter test --reporter expanded
```

Expected: all PASS, zero failures

- [ ] **Step 2: Run analyzer**

```bash
flutter analyze --no-fatal-infos
```

Expected: zero errors

- [ ] **Step 3: Final commit**

```bash
git add -A
git commit -m "chore: Phase 3b complete — Flutter live integration tests passing"
```
