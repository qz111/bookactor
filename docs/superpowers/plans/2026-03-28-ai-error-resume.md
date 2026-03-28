# AI Error Resume Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the library-screen resume banner with per-version Retry/Resume buttons in `BookDetailScreen`, re-entering the pipeline at the correct stage (VLM / LLM / TTS) based on what data is already persisted.

**Architecture:** Add `ResumeStage` enum and optional `startStage` to `LoadingParams`. Gate VLM/LLM execution via `runVlm`/`runLlm` booleans. Skip already-complete TTS chunks (status='ready' + file exists on disk). On cold start, flip any stuck `'generating'` versions to `'error'` before the UI renders.

**Tech Stack:** Flutter/Dart, Riverpod, sqflite, go_router. Tests use `flutter test`, `AppDatabase.forTesting()` (in-memory SQLite), Riverpod provider overrides, and `_RecordingApiService` mock.

**Spec:** `docs/superpowers/specs/2026-03-28-ai-error-resume-design.md`

---

### File Map

| File | Change |
|---|---|
| `lib/screens/loading_screen.dart` | Add `ResumeStage` enum; add `startStage` to `LoadingParams`; replace `isNewBook` gate with `runVlm`/`runLlm`; clear `scriptJson`+delete `audioDir` on VLM retry; TTS skip with file check; read `scriptJson` from DB when skipping LLM; surface TTS chunk errors via `_hasError` |
| `lib/db/database.dart` | Add `resetGeneratingVersions()`; remove `getGeneratingVersions()` |
| `lib/main.dart` | Call `resetGeneratingVersions()` after `_seedMockData()`, before `runApp()` |
| `lib/screens/book_detail_screen.dart` | Add `inferResumeStage()` top-level function; add `_hasTtsPartialProgress()` helper; add `_buildVersionTrailing()` method showing Retry/Resume on error cards |
| `lib/screens/library_screen.dart` | Remove `MaterialBanner` resume UI; remove `generatingVersionsProvider` watch |
| `lib/providers/books_provider.dart` | Remove `generatingVersionsProvider` |
| `test/screens/loading_screen_live_test.dart` | Update `_RecordingApiService` to return dynamic results; add LLM retry, TTS resume, and TTS error tests |
| `test/db/database_test.dart` | Add `resetGeneratingVersions` test; remove `getGeneratingVersions` test |
| `test/screens/book_detail_screen_test.dart` | Add `inferResumeStage` unit tests; add Retry/Resume button widget tests |
| `test/screens/library_screen_test.dart` | Remove `generatingVersionsProvider` overrides and banner-related tests |

---

### Task 1: Add `ResumeStage` enum and `startStage` to `LoadingParams`

**Files:**
- Modify: `lib/screens/loading_screen.dart`
- Modify: `test/screens/loading_screen_live_test.dart`

- [ ] **Step 1: Write failing tests**

Add to the bottom of `test/screens/loading_screen_live_test.dart` (inside `main()`):

```dart
group('LoadingParams.startStage', () {
  test('defaults to null', () {
    const p = LoadingParams(
      bookId: 'b', versionId: 'v', filePath: '', language: 'en',
      vlmProvider: 'gemini', llmProvider: 'gpt4o', ttsProvider: 'openai',
      processingMode: ProcessingMode.textHeavy, isNewBook: false,
    );
    expect(p.startStage, isNull);
  });

  test('accepts explicit ResumeStage.tts', () {
    const p = LoadingParams(
      bookId: 'b', versionId: 'v', filePath: '', language: 'en',
      vlmProvider: 'gemini', llmProvider: 'gpt4o', ttsProvider: 'openai',
      processingMode: ProcessingMode.textHeavy, isNewBook: false,
      startStage: ResumeStage.tts,
    );
    expect(p.startStage, ResumeStage.tts);
  });

  test('ResumeStage enum has vlm, llm, tts values', () {
    expect(ResumeStage.values, containsAll([ResumeStage.vlm, ResumeStage.llm, ResumeStage.tts]));
  });
});
```

- [ ] **Step 2: Run tests to confirm compile failure**

```
flutter test test/screens/loading_screen_live_test.dart
```
Expected: compile error — `ResumeStage` and `startStage` not yet defined.

- [ ] **Step 3: Add enum and field to `loading_screen.dart`**

In `lib/screens/loading_screen.dart`, add immediately before `class LoadingParams`:

```dart
enum ResumeStage { vlm, llm, tts }
```

Add field to `LoadingParams`:

```dart
/// When non-null, the pipeline skips stages before this stage.
/// null = run all stages from the beginning.
final ResumeStage? startStage;
```

Add to `LoadingParams` constructor as an optional named parameter:

```dart
this.startStage,
```

- [ ] **Step 4: Run tests to confirm pass**

```
flutter test test/screens/loading_screen_live_test.dart
```
Expected: all pass.

- [ ] **Step 5: Run full suite**

```
flutter test
```
Expected: all pass (existing callers compile because `startStage` is optional with a null default).

- [ ] **Step 6: Commit**

```bash
git add lib/screens/loading_screen.dart test/screens/loading_screen_live_test.dart
git commit -m "feat: add ResumeStage enum and startStage to LoadingParams"
```

---

### Task 2: Add `resetGeneratingVersions()` to database and call on cold start

**Files:**
- Modify: `lib/db/database.dart`
- Modify: `lib/main.dart`
- Modify: `test/db/database_test.dart`

- [ ] **Step 1: Write failing test**

Add to the `AudioVersions` group in `test/db/database_test.dart`:

```dart
test('resetGeneratingVersions flips generating to error, preserves scriptJson', () async {
  await db.insertAudioVersion(const AudioVersion(
    versionId: 'test123_en',
    bookId: 'test123',
    language: 'en',
    scriptJson: '{"chunks":[{"index":0,"status":"ready"}]}',
    audioDir: '',
    status: 'generating',
    lastGeneratedLine: 2,
    lastPlayedLine: 0,
    createdAt: 0,
  ));
  await db.insertAudioVersion(const AudioVersion(
    versionId: 'test123_fr',
    bookId: 'test123',
    language: 'fr',
    scriptJson: '{}',
    audioDir: '',
    status: 'ready',
    lastGeneratedLine: 0,
    lastPlayedLine: 0,
    createdAt: 0,
  ));

  await db.resetGeneratingVersions();

  final en = await db.getAudioVersion('test123_en');
  final fr = await db.getAudioVersion('test123_fr');
  expect(en!.status, 'error');   // generating → error
  expect(fr!.status, 'ready');   // ready → unchanged
  // scriptJson preserved — per-chunk statuses survive the reset
  expect(en.scriptJson, '{"chunks":[{"index":0,"status":"ready"}]}');
});
```

- [ ] **Step 2: Run test to confirm failure**

```
flutter test test/db/database_test.dart
```
Expected: fail — `resetGeneratingVersions` not defined.

- [ ] **Step 3: Add `resetGeneratingVersions()` to `database.dart`**

Add after `getGeneratingVersions()` in `lib/db/database.dart`:

```dart
/// Resets all versions with status='generating' to status='error'.
/// Called on cold start to surface interrupted runs as recoverable errors.
/// Does NOT modify scriptJson — per-chunk statuses are intentionally preserved
/// so TTS resume can skip already-completed chunks.
Future<void> resetGeneratingVersions() async {
  final db = await database;
  await db.update(
    'audio_versions',
    {'status': 'error'},
    where: 'status = ?',
    whereArgs: ['generating'],
  );
}
```

- [ ] **Step 4: Run DB tests to confirm pass**

```
flutter test test/db/database_test.dart
```
Expected: all pass.

- [ ] **Step 5: Add startup call to `main.dart`**

In `lib/main.dart`, update `main()` — add one line after `_seedMockData()`:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  await _seedMockData();
  await AppDatabase.instance.resetGeneratingVersions(); // ← add this line

  final hasKeys = await SettingsService().hasKeys();

  runApp(ProviderScope(
    overrides: [
      initialLocationProvider.overrideWithValue(hasKeys ? '/' : '/settings'),
    ],
    child: const BookActorApp(),
  ));
}
```

- [ ] **Step 6: Run full suite**

```
flutter test
```
Expected: all pass.

- [ ] **Step 7: Commit**

```bash
git add lib/db/database.dart lib/main.dart test/db/database_test.dart
git commit -m "feat: add resetGeneratingVersions and call on cold start"
```

---

### Task 3: Refactor `_runLivePipeline` with stage gates and TTS resume logic

**Files:**
- Modify: `lib/screens/loading_screen.dart`
- Modify: `test/screens/loading_screen_live_test.dart`

The pipeline gains `runVlm`/`runLlm` boolean gates, reads `scriptJson` from DB before TTS when LLM was skipped, skips TTS chunks that are already ready with files on disk, and surfaces per-chunk TTS errors via `_hasError` instead of silently marking the version ready.

- [ ] **Step 1: Update `_RecordingApiService.generateAudio` to return dynamic results**

In `test/screens/loading_screen_live_test.dart`, replace the `generateAudio` override in `_RecordingApiService` so it responds to whatever chunks it receives (not always index 0):

```dart
@override
Future<List<Map<String, dynamic>>> generateAudio({
  required List<Map<String, dynamic>> chunks,
  String ttsProvider = 'openai',
}) async {
  calls.add('tts');
  return chunks.map((c) => {
    'index': c['index'] as int,
    'status': 'ready',
    'audio_b64': base64Encode([1, 2, 3]),
    'duration_ms': 1200,
  }).toList();
}
```

Run existing tests to confirm they still pass:
```
flutter test test/screens/loading_screen_live_test.dart
```
Expected: still pass (dynamic results include index 0 as before).

- [ ] **Step 2: Add `_ErrorTtsApiService` mock class**

Add after `_RecordingApiService` in `test/screens/loading_screen_live_test.dart`:

```dart
/// Returns status='error' for every chunk — used to test TTS failure handling.
class _ErrorTtsApiService extends _RecordingApiService {
  @override
  Future<List<Map<String, dynamic>>> generateAudio({
    required List<Map<String, dynamic>> chunks,
    String ttsProvider = 'openai',
  }) async {
    calls.add('tts');
    return chunks
        .map((c) => {'index': c['index'] as int, 'status': 'error'})
        .toList();
  }
}
```

- [ ] **Step 3: Write failing tests**

Add to `main()` in `test/screens/loading_screen_live_test.dart`:

```dart
testWidgets('LLM retry: skips VLM, runs LLM+TTS using stored vlmOutput',
    (tester) async {
  // Set up stored vlmOutput; version has empty scriptJson (LLM previously failed)
  await AppDatabase.instance.updateBookVlmOutput(
    'test_book_live', '[{"page":1,"text":"hello"}]');
  await AppDatabase.instance.updateAudioVersionStatus(
    'test_book_live_en', 'error', scriptJson: '{}');

  final fakeApi = _RecordingApiService();
  final tempAudioDir = Directory.systemTemp.createTempSync('bookactor_llm_retry_');
  addTearDown(() => tempAudioDir.deleteSync(recursive: true));

  final params = LoadingParams(
    bookId: 'test_book_live',
    versionId: 'test_book_live_en',
    filePath: '',
    language: 'en',
    vlmProvider: 'gemini',
    llmProvider: 'gpt4o',
    ttsProvider: 'openai',
    processingMode: ProcessingMode.textHeavy,
    isNewBook: false,
    startStage: ResumeStage.llm,
    audioDirOverride: tempAudioDir.path,
  );

  final router = GoRouter(
    initialLocation: '/loading',
    routes: [
      GoRoute(
        path: '/loading',
        builder: (_, __) => LoadingScreen(params: params, apiService: fakeApi),
      ),
      GoRoute(
        path: '/player/:versionId',
        builder: (_, __) => const Scaffold(body: Text('player')),
      ),
    ],
  );

  await tester.runAsync(() async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp.router(routerConfig: router),
    ));
    await Future<void>.delayed(const Duration(seconds: 5));
  });
  await tester.pump();

  // VLM must NOT be called; LLM and TTS must be called in order
  expect(fakeApi.calls, equals(['script', 'tts']));
});

testWidgets('TTS resume: skips VLM+LLM, skips ready chunk with file, regenerates errored chunk',
    (tester) async {
  final tempAudioDir = Directory.systemTemp.createTempSync('bookactor_tts_resume_');
  addTearDown(() => tempAudioDir.deleteSync(recursive: true));

  // chunk 0 is already done — file exists on disk
  final existingChunkFile = File('${tempAudioDir.path}/chunk_000.wav');
  await existingChunkFile.writeAsBytes([1, 2, 3]);

  const scriptJson = '{"characters":[{"name":"Narrator","voice":"alloy"}],'
      '"chunks":['
      '{"index":0,"speakers":["Narrator"],"text":"Hello","duration_ms":1000,"status":"ready"},'
      '{"index":1,"speakers":["Narrator"],"text":"World","duration_ms":0,"status":"error"}'
      ']}';

  await AppDatabase.instance.updateBookVlmOutput(
    'test_book_live', '[{"page":1,"text":"hello"}]');
  await AppDatabase.instance.updateAudioVersionStatus(
    'test_book_live_en', 'error', scriptJson: scriptJson);

  final fakeApi = _RecordingApiService();
  final params = LoadingParams(
    bookId: 'test_book_live',
    versionId: 'test_book_live_en',
    filePath: '',
    language: 'en',
    vlmProvider: 'gemini',
    llmProvider: 'gpt4o',
    ttsProvider: 'openai',
    processingMode: ProcessingMode.textHeavy,
    isNewBook: false,
    startStage: ResumeStage.tts,
    audioDirOverride: tempAudioDir.path,
  );

  final router = GoRouter(
    initialLocation: '/loading',
    routes: [
      GoRoute(
        path: '/loading',
        builder: (_, __) => LoadingScreen(params: params, apiService: fakeApi),
      ),
      GoRoute(
        path: '/player/:versionId',
        builder: (_, __) => const Scaffold(body: Text('player')),
      ),
    ],
  );

  await tester.runAsync(() async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp.router(routerConfig: router),
    ));
    await Future<void>.delayed(const Duration(seconds: 5));
  });
  await tester.pump();

  // Neither VLM nor LLM called — only TTS
  expect(fakeApi.calls, equals(['tts']));
  // chunk_000.wav untouched (skipped)
  expect(existingChunkFile.existsSync(), isTrue);
  // chunk_001.wav written by TTS
  expect(File('${tempAudioDir.path}/chunk_001.wav').existsSync(), isTrue);
  // Player screen reached (all chunks now ready)
  expect(find.text('player'), findsOneWidget);
});

testWidgets('TTS chunk error: shows error screen, does not navigate to player',
    (tester) async {
  final tempAudioDir = Directory.systemTemp.createTempSync('bookactor_tts_err_');
  addTearDown(() => tempAudioDir.deleteSync(recursive: true));

  final errorApi = _ErrorTtsApiService();

  await AppDatabase.instance.updateBookVlmOutput(
    'test_book_live', '');
  await AppDatabase.instance.updateAudioVersionStatus(
    'test_book_live_en', 'error', scriptJson: '{}');

  final params = LoadingParams(
    bookId: 'test_book_live',
    versionId: 'test_book_live_en',
    filePath: 'test/assets/fake_image.png',
    language: 'en',
    vlmProvider: 'gemini',
    llmProvider: 'gpt4o',
    ttsProvider: 'openai',
    processingMode: ProcessingMode.textHeavy,
    isNewBook: true,  // full run so VLM+LLM fire, then TTS errors
    audioDirOverride: tempAudioDir.path,
  );

  final router = GoRouter(
    initialLocation: '/loading',
    routes: [
      GoRoute(
        path: '/loading',
        builder: (_, __) => LoadingScreen(params: params, apiService: errorApi),
      ),
      GoRoute(
        path: '/player/:versionId',
        builder: (_, __) => const Scaffold(body: Text('player')),
      ),
    ],
  );

  await tester.runAsync(() async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp.router(routerConfig: router),
    ));
    await Future<void>.delayed(const Duration(seconds: 5));
  });
  await tester.pump();

  expect(find.text('Something went wrong'), findsOneWidget);
  expect(find.text('player'), findsNothing);
});
```

- [ ] **Step 4: Run tests to confirm they fail**

```
flutter test test/screens/loading_screen_live_test.dart
```
Expected: new tests fail (LLM retry still calls VLM; TTS resume still calls LLM; TTS error still navigates to player).

- [ ] **Step 5: Rewrite `_runLivePipeline` in `loading_screen.dart`**

Replace the entire `_runLivePipeline` method body with:

```dart
Future<void> _runLivePipeline() async {
  final p = widget.params!;
  final ApiService api;
  if (widget.apiService != null) {
    api = widget.apiService!;
  } else {
    api = await ref.read(apiServiceProvider.future);
  }

  try {
    setState(() => _step = 0);

    final bool runVlm = p.isNewBook || p.startStage == ResumeStage.vlm;
    // startStage==null means new-language run (isNewBook=false): skip VLM, run LLM.
    final bool runLlm =
        runVlm || p.startStage == null || p.startStage == ResumeStage.llm;

    // ── 1. Analyze (VLM) ────────────────────────────────────────────────
    List<Map<String, dynamic>> vlmOutput;
    if (runVlm) {
      final List<Uint8List> imageBytes;
      final imagePaths = p.imageFilePaths;
      if (imagePaths != null && imagePaths.isNotEmpty) {
        imageBytes = await Future.wait(
          imagePaths.map((path) => File(path).readAsBytes()),
        );
      } else if (p.filePath.toLowerCase().endsWith('.pdf')) {
        imageBytes = await PdfService.pdfToJpegBytes(p.filePath);
      } else {
        imageBytes = [await File(p.filePath).readAsBytes()];
      }
      if (!mounted) return;

      final pages = await api.analyzePages(
        imageBytesList: imageBytes,
        vlmProvider: p.vlmProvider,
        processingMode: p.processingMode,
      );
      if (!mounted) return;

      await AppDatabase.instance.updateBookVlmOutput(p.bookId, jsonEncode(pages));
      // Clear stale script so LLM writes a fresh one
      await AppDatabase.instance.updateAudioVersionStatus(
        p.versionId, 'generating', scriptJson: '{}');
      // Delete stale audio files — new LLM may produce a different chunk count
      final String audioDirToDelete;
      if (p.audioDirOverride != null) {
        audioDirToDelete = p.audioDirOverride!;
      } else {
        final docsDir = await getApplicationDocumentsDirectory();
        audioDirToDelete = path_pkg.join(docsDir.path, 'audio', p.versionId);
      }
      final deleteDir = Directory(audioDirToDelete);
      if (deleteDir.existsSync()) {
        await deleteDir.delete(recursive: true);
      }
      vlmOutput = pages;
    } else {
      final book = await AppDatabase.instance.getBook(p.bookId);
      vlmOutput = List<Map<String, dynamic>>.from(
          jsonDecode(book!.vlmOutput) as List);
    }
    if (!mounted) return;
    setState(() => _step = 1);

    // ── 2. Script (LLM) ─────────────────────────────────────────────────
    Map<String, dynamic> scriptMap;
    if (runLlm) {
      scriptMap = await api.generateScript(
        vlmOutput: vlmOutput,
        language: p.language,
        llmProvider: p.llmProvider,
        ttsProvider: p.ttsProvider,
      );
      if (!mounted) return;
      await AppDatabase.instance.updateAudioVersionStatus(
        p.versionId, 'generating',
        scriptJson: jsonEncode(scriptMap),
      );
    } else {
      // Read chunk list fresh from DB after all prior stage writes
      final version = await AppDatabase.instance.getAudioVersion(p.versionId);
      scriptMap = jsonDecode(version!.scriptJson) as Map<String, dynamic>;
    }
    if (!mounted) return;
    setState(() => _step = 2);

    // ── 3. TTS ──────────────────────────────────────────────────────────
    // Compute audioDir independently — DB value may be '' if version never completed
    final String audioDir;
    if (p.audioDirOverride != null) {
      audioDir = p.audioDirOverride!;
    } else {
      final docsDir = await getApplicationDocumentsDirectory();
      audioDir = path_pkg.join(docsDir.path, 'audio', p.versionId);
    }
    await Directory(audioDir).create(recursive: true);
    if (!mounted) return;

    final script = Script.fromJson(jsonEncode(scriptMap));
    final allChunks =
        List<Map<String, dynamic>>.from(scriptMap['chunks'] as List);

    // Build list of chunks that actually need generating.
    // Chunks with status='ready' and an existing file on disk are skipped.
    final chunksToGenerate = <Map<String, dynamic>>[];
    for (final c in allChunks) {
      if (c['status'] == 'ready') {
        final fileName =
            'chunk_${(c['index'] as int).toString().padLeft(3, '0')}.wav';
        if (File(path_pkg.join(audioDir, fileName)).existsSync()) {
          continue; // already done
        }
      }
      chunksToGenerate.add(c);
    }

    final pendingChunks = chunksToGenerate.map((c) {
      final speakers = List<String>.from(c['speakers'] as List);
      final voiceMap = {for (final s in speakers) s: script.voiceFor(s)};
      return {
        'index': c['index'],
        'text': c['text'],
        'voice_map': voiceMap,
      };
    }).toList();

    final audioResults = await api.generateAudio(
      chunks: pendingChunks,
      ttsProvider: p.ttsProvider,
    );

    // scriptChunks is the mutable working copy — starts from allChunks
    // so already-ready skipped chunks are preserved in the final JSON
    final scriptChunks = List<Map<String, dynamic>>.from(allChunks);

    for (final result in audioResults) {
      final idx = result['index'] as int;
      final chunkIdx = scriptChunks.indexWhere((c) => c['index'] == idx);
      if (chunkIdx == -1) continue;

      if (result['status'] == 'ready') {
        final audioBytes = base64Decode(result['audio_b64'] as String);
        final fileName = 'chunk_${idx.toString().padLeft(3, '0')}.wav';
        await File(path_pkg.join(audioDir, fileName)).writeAsBytes(audioBytes);
        scriptChunks[chunkIdx] = {
          ...scriptChunks[chunkIdx],
          'status': 'ready',
          'duration_ms': result['duration_ms'] as int,
        };
      } else {
        scriptChunks[chunkIdx] = {
          ...scriptChunks[chunkIdx],
          'status': 'error',
        };
      }
      await AppDatabase.instance.updateAudioVersionStatus(
        p.versionId, 'generating',
        scriptJson: jsonEncode({...scriptMap, 'chunks': scriptChunks}),
      );
    }

    // If any chunk failed, show error screen.
    // AudioVersion.status stays 'generating' — cold restart will flip it to 'error'
    // so the Retry/Resume button appears on the version card.
    if (scriptChunks.any((c) => c['status'] == 'error')) {
      if (!mounted) return;
      setState(() => _hasError = true);
      return;
    }

    // All chunks ready — mark version complete
    final existing = await AppDatabase.instance.getAudioVersion(p.versionId);
    if (existing != null) {
      await AppDatabase.instance.insertAudioVersion(
        AudioVersion(
          versionId: existing.versionId,
          bookId: existing.bookId,
          language: existing.language,
          llmProvider: existing.llmProvider,
          scriptJson: jsonEncode({...scriptMap, 'chunks': scriptChunks}),
          audioDir: audioDir,
          status: 'ready',
          lastGeneratedLine: existing.lastGeneratedLine,
          lastPlayedLine: existing.lastPlayedLine,
          createdAt: existing.createdAt,
        ),
      );
    }
    if (!mounted) return;
    context.go('/player/${p.versionId}', extra: p.isNewBook);
  } on ApiException catch (_) {
    if (!mounted) return;
    setState(() => _hasError = true);
  } on PdfException catch (_) {
    if (!mounted) return;
    setState(() => _hasError = true);
  } catch (_) {
    if (!mounted) return;
    setState(() => _hasError = true);
  }
}
```

- [ ] **Step 6: Run new tests to confirm they pass**

```
flutter test test/screens/loading_screen_live_test.dart
```
Expected: all pass including the three new tests.

- [ ] **Step 7: Run full suite**

```
flutter test
```
Expected: all pass.

- [ ] **Step 8: Commit**

```bash
git add lib/screens/loading_screen.dart test/screens/loading_screen_live_test.dart
git commit -m "feat: refactor pipeline with stage gates and TTS resume skip logic"
```

---

### Task 4: Add `inferResumeStage` and Retry/Resume buttons to `BookDetailScreen`

**Files:**
- Modify: `lib/screens/book_detail_screen.dart`
- Modify: `test/screens/book_detail_screen_test.dart`

- [ ] **Step 1: Write failing tests**

Add to `test/screens/book_detail_screen_test.dart` (inside `main()`):

```dart
group('inferResumeStage', () {
  const bookNoVlm = Book(
    bookId: 'b', title: 'T', pagesDir: '', vlmOutput: '',
    vlmProvider: 'gemini', createdAt: 0,
  );
  const bookEmptyVlm = Book(
    bookId: 'b', title: 'T', pagesDir: '', vlmOutput: '[]',
    vlmProvider: 'gemini', createdAt: 0,
  );
  const bookWithVlm = Book(
    bookId: 'b', title: 'T', pagesDir: '',
    vlmOutput: '[{"page":1,"text":"hello"}]',
    vlmProvider: 'gemini', createdAt: 0,
  );
  const errorVersion = AudioVersion(
    versionId: 'b_en', bookId: 'b', language: 'en',
    scriptJson: '{}', audioDir: '', status: 'error',
    lastGeneratedLine: 0, lastPlayedLine: 0, createdAt: 0,
  );

  test('returns vlm when vlmOutput is empty string', () {
    expect(inferResumeStage(bookNoVlm, errorVersion), ResumeStage.vlm);
  });

  test('returns vlm when vlmOutput is empty array', () {
    expect(inferResumeStage(bookEmptyVlm, errorVersion), ResumeStage.vlm);
  });

  test('returns llm when vlmOutput exists but scriptJson is {}', () {
    expect(inferResumeStage(bookWithVlm, errorVersion), ResumeStage.llm);
  });

  test('returns llm when scriptJson is empty string', () {
    const v = AudioVersion(
      versionId: 'b_en', bookId: 'b', language: 'en',
      scriptJson: '', audioDir: '', status: 'error',
      lastGeneratedLine: 0, lastPlayedLine: 0, createdAt: 0,
    );
    expect(inferResumeStage(bookWithVlm, v), ResumeStage.llm);
  });

  test('returns llm when scriptJson is invalid JSON', () {
    const v = AudioVersion(
      versionId: 'b_en', bookId: 'b', language: 'en',
      scriptJson: 'not-valid-json', audioDir: '', status: 'error',
      lastGeneratedLine: 0, lastPlayedLine: 0, createdAt: 0,
    );
    expect(inferResumeStage(bookWithVlm, v), ResumeStage.llm);
  });

  test('returns llm when chunks list is empty', () {
    const v = AudioVersion(
      versionId: 'b_en', bookId: 'b', language: 'en',
      scriptJson: '{"characters":[],"chunks":[]}', audioDir: '',
      status: 'error', lastGeneratedLine: 0, lastPlayedLine: 0, createdAt: 0,
    );
    expect(inferResumeStage(bookWithVlm, v), ResumeStage.llm);
  });

  test('returns tts when chunks exist but none are ready', () {
    const v = AudioVersion(
      versionId: 'b_en', bookId: 'b', language: 'en',
      scriptJson: '{"characters":[],"chunks":['
          '{"index":0,"status":"error"},{"index":1,"status":"pending"}]}',
      audioDir: '', status: 'error',
      lastGeneratedLine: 0, lastPlayedLine: 0, createdAt: 0,
    );
    expect(inferResumeStage(bookWithVlm, v), ResumeStage.tts);
  });

  test('returns tts when at least one chunk is ready (partial)', () {
    const v = AudioVersion(
      versionId: 'b_en', bookId: 'b', language: 'en',
      scriptJson: '{"characters":[],"chunks":['
          '{"index":0,"status":"ready"},{"index":1,"status":"error"}]}',
      audioDir: '', status: 'error',
      lastGeneratedLine: 0, lastPlayedLine: 0, createdAt: 0,
    );
    expect(inferResumeStage(bookWithVlm, v), ResumeStage.tts);
  });
});
```

Also add widget tests:

```dart
testWidgets('shows Retry button on error version with LLM failure',
    (tester) async {
  const errorVersion = AudioVersion(
    versionId: 'detail_test_book_en', bookId: 'detail_test_book',
    language: 'en', scriptJson: '{}', audioDir: '', status: 'error',
    lastGeneratedLine: 0, lastPlayedLine: 0, createdAt: 0,
  );
  // testBook has vlmOutput='[]' so inferResumeStage → vlm → "Retry"
  await tester.pumpWidget(ProviderScope(
    overrides: [
      singleBookProvider('detail_test_book').overrideWith((_) async => testBook),
      audioVersionsProvider('detail_test_book').overrideWith(
        (_) async => [errorVersion],
      ),
    ],
    child: const MaterialApp(home: BookDetailScreen(bookId: 'detail_test_book')),
  ));
  await tester.pumpAndSettle();
  expect(find.text('Retry'), findsOneWidget);
  expect(find.text('Resume'), findsNothing);
});

testWidgets('shows Resume button on error version with partial TTS',
    (tester) async {
  const partialVersion = AudioVersion(
    versionId: 'detail_test_book_en', bookId: 'detail_test_book',
    language: 'en',
    scriptJson: '{"characters":[],"chunks":['
        '{"index":0,"status":"ready"},{"index":1,"status":"error"}]}',
    audioDir: '', status: 'error',
    lastGeneratedLine: 0, lastPlayedLine: 0, createdAt: 0,
  );
  final bookWithVlm = Book(
    bookId: 'detail_test_book', title: 'Detail Test Book', coverPath: null,
    pagesDir: '/tmp/test.pdf', vlmOutput: '[{"page":1,"text":"hi"}]',
    vlmProvider: 'gemini', createdAt: 1711065600,
  );
  await tester.pumpWidget(ProviderScope(
    overrides: [
      singleBookProvider('detail_test_book').overrideWith((_) async => bookWithVlm),
      audioVersionsProvider('detail_test_book').overrideWith(
        (_) async => [partialVersion],
      ),
    ],
    child: const MaterialApp(home: BookDetailScreen(bookId: 'detail_test_book')),
  ));
  await tester.pumpAndSettle();
  expect(find.text('Resume'), findsOneWidget);
  expect(find.text('Retry'), findsNothing);
});

testWidgets('no Retry/Resume button for ready version', (tester) async {
  const readyVersion = AudioVersion(
    versionId: 'detail_test_book_en', bookId: 'detail_test_book',
    language: 'en', scriptJson: '{}', audioDir: '', status: 'ready',
    lastGeneratedLine: 0, lastPlayedLine: 0, createdAt: 0,
  );
  await tester.pumpWidget(ProviderScope(
    overrides: [
      singleBookProvider('detail_test_book').overrideWith((_) async => testBook),
      audioVersionsProvider('detail_test_book').overrideWith(
        (_) async => [readyVersion],
      ),
    ],
    child: const MaterialApp(home: BookDetailScreen(bookId: 'detail_test_book')),
  ));
  await tester.pumpAndSettle();
  expect(find.text('Retry'), findsNothing);
  expect(find.text('Resume'), findsNothing);
});
```

- [ ] **Step 2: Run tests to confirm they fail**

```
flutter test test/screens/book_detail_screen_test.dart
```
Expected: compile errors — `inferResumeStage` not found.

- [ ] **Step 3: Add `inferResumeStage` and helper functions to `book_detail_screen.dart`**

Add `import 'dart:convert';` to the imports at the top of `lib/screens/book_detail_screen.dart`.

Add these top-level functions immediately after all imports:

```dart
/// Infers which pipeline stage failed, so resume re-enters at the right point.
/// Only call when [version.status] == 'error'.
ResumeStage inferResumeStage(Book book, AudioVersion version) {
  if (book.vlmOutput.isEmpty || book.vlmOutput == '[]') {
    return ResumeStage.vlm;
  }
  if (version.scriptJson.isEmpty || version.scriptJson == '{}') {
    return ResumeStage.llm;
  }
  try {
    final decoded = jsonDecode(version.scriptJson) as Map<String, dynamic>;
    final chunks = decoded['chunks'] as List?;
    if (chunks == null || chunks.isEmpty) return ResumeStage.llm;
    return ResumeStage.tts; // TTS stage — partial or total failure
  } catch (_) {
    return ResumeStage.llm;
  }
}

/// Returns true if ≥1 TTS chunk completed successfully.
/// Determines whether to show "Resume" vs "Retry" label for TTS-stage errors.
bool _hasTtsPartialProgress(AudioVersion version) {
  try {
    final decoded = jsonDecode(version.scriptJson) as Map<String, dynamic>;
    final chunks = decoded['chunks'] as List? ?? [];
    return chunks.any(
        (c) => (c as Map<String, dynamic>)['status'] == 'ready');
  } catch (_) {
    return false;
  }
}
```

- [ ] **Step 4: Add `_buildVersionTrailing` helper method to `_BookDetailScreenState`**

Add as an instance method of `_BookDetailScreenState`:

```dart
Widget? _buildVersionTrailing(BuildContext context, Book book, AudioVersion version) {
  if (version.status == 'ready') {
    return IconButton(
      icon: const Icon(Icons.play_circle_filled),
      onPressed: () => context.push('/player/${version.versionId}'),
    );
  }
  if (version.status == 'error') {
    final stage = inferResumeStage(book, version);
    final isPartialTts =
        stage == ResumeStage.tts && _hasTtsPartialProgress(version);
    final label = isPartialTts ? 'Resume' : 'Retry';
    return TextButton(
      onPressed: () => context.push(
        '/loading',
        extra: LoadingParams(
          bookId: book.bookId,
          versionId: version.versionId,
          filePath: book.pagesDir,
          language: version.language,
          vlmProvider: book.vlmProvider,
          llmProvider: version.llmProvider ?? 'gpt4o',
          ttsProvider: version.ttsProvider ?? 'openai',
          // processingMode not stored on Book — default to textHeavy.
          // Only matters if startStage==vlm; other stages ignore it.
          processingMode: ProcessingMode.textHeavy,
          isNewBook: false,
          startStage: stage,
        ),
      ),
      child: Text(label),
    );
  }
  return null; // generating — no action button
}
```

- [ ] **Step 5: Update version `ListTile` in `build` to use `_buildVersionTrailing`**

In `_BookDetailScreenState.build`, replace:

```dart
trailing: v.status == 'ready'
    ? IconButton(
        icon: const Icon(Icons.play_circle_filled),
        onPressed: () =>
            context.push('/player/${v.versionId}'),
      )
    : null,
```

With:

```dart
trailing: _buildVersionTrailing(context, book, v),
```

The `book` variable is already in scope from the outer `bookAsync.when(data: (book) { ... })` closure.

- [ ] **Step 6: Run tests to confirm pass**

```
flutter test test/screens/book_detail_screen_test.dart
```
Expected: all pass.

- [ ] **Step 7: Run full suite**

```
flutter test
```
Expected: all pass.

- [ ] **Step 8: Commit**

```bash
git add lib/screens/book_detail_screen.dart test/screens/book_detail_screen_test.dart
git commit -m "feat: add inferResumeStage and Retry/Resume buttons on error version cards"
```

---

### Task 5: Remove library resume banner, `generatingVersionsProvider`, and `getGeneratingVersions()`

Do this task last — earlier tasks don't depend on the removal, and removing first would break the compiler while other tasks are in progress.

**Files:**
- Modify: `test/screens/library_screen_test.dart`  ← update tests first
- Modify: `lib/screens/library_screen.dart`
- Modify: `lib/providers/books_provider.dart`
- Modify: `lib/db/database.dart`
- Modify: `test/db/database_test.dart`

- [ ] **Step 1: Update `library_screen_test.dart` — remove `generatingVersionsProvider` overrides**

In `test/screens/library_screen_test.dart`:

1. Remove every line `generatingVersionsProvider.overrideWith((_) async => []),` from all `ProviderScope` override blocks.
2. Delete the entire test `'Dismiss button is absent when no generating versions exist'`.

Run to confirm it still compiles (provider still exists at this point):
```
flutter test test/screens/library_screen_test.dart
```
Expected: all pass.

- [ ] **Step 2: Remove `generatingVersionsProvider` from `books_provider.dart`**

In `lib/providers/books_provider.dart`, delete:

```dart
final generatingVersionsProvider =
    FutureProvider<List<AudioVersion>>((ref) async {
  return AppDatabase.instance.getGeneratingVersions();
});
```

- [ ] **Step 3: Remove `getGeneratingVersions()` from `database.dart`**

In `lib/db/database.dart`, delete the `getGeneratingVersions()` method entirely.

- [ ] **Step 4: Remove `getGeneratingVersions` test from `database_test.dart`**

In `test/db/database_test.dart`, delete the test:

```dart
test('getGeneratingVersions returns only generating rows', () async {
  ...
});
```

- [ ] **Step 5: Remove resume banner from `library_screen.dart`**

Replace the entire `build` method of `_LibraryScreenState` with:

```dart
@override
Widget build(BuildContext context) {
  final screenContext = context;
  final booksAsync = ref.watch(booksProvider);

  return Scaffold(
    appBar: AppBar(
      title: const Text('My Books'),
      actions: [
        IconButton(
          icon: const Icon(Icons.settings),
          onPressed: () => context.push('/settings'),
          tooltip: 'API Keys',
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => context.push('/upload'),
      icon: const Icon(Icons.add),
      label: const Text('Add Book'),
    ),
    body: booksAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (books) {
        if (books.isEmpty) {
          return const Center(child: Text('No books yet'));
        }
        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio: 0.7,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: books.length,
          itemBuilder: (context, index) {
            final book = books[index];
            return Consumer(
              builder: (context, ref, _) {
                final versionsAsync =
                    ref.watch(audioVersionsProvider(book.bookId));
                final versions = versionsAsync.value ?? [];
                final isGenerating =
                    versions.any((v) => v.status == 'generating');
                return BookCard(
                  book: book,
                  languageCount: versions.length,
                  onTap: () => context.push('/book/${book.bookId}'),
                  onLongPress: isGenerating
                      ? () {}
                      : () => _confirmDeleteBook(screenContext, book),
                );
              },
            );
          },
        );
      },
    ),
  );
}
```

Also remove unused imports from `library_screen.dart`:
- `'../models/audio_version.dart'` (only used by the banner)
- `'../models/processing_mode.dart'` (only used by the banner's Resume button)
- `'../screens/loading_screen.dart'` (only used by the banner's Resume button)

Keep: `'../db/database.dart'` (still used by `_confirmDeleteBook`).

- [ ] **Step 6: Run full test suite**

```
flutter test
```
Expected: all pass. No reference to `generatingVersionsProvider` or `getGeneratingVersions` remains.

- [ ] **Step 7: Commit**

```bash
git add lib/screens/library_screen.dart lib/providers/books_provider.dart lib/db/database.dart test/screens/library_screen_test.dart test/db/database_test.dart
git commit -m "feat: remove library resume banner and generatingVersionsProvider"
```
