import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:bookactor/db/database.dart';
import 'package:bookactor/models/book.dart';
import 'package:bookactor/models/audio_version.dart';
import 'package:bookactor/models/processing_mode.dart';
import 'package:bookactor/screens/loading_screen.dart';
import 'package:bookactor/services/api_service.dart';

class _RecordingApiService extends ApiService {
  final List<String> calls = [];
  final List<List<Uint8List>> analyzeCalls = [];
  _RecordingApiService() : super(baseUrl: 'http://fake', openAiKey: 'test', googleKey: 'test');

  @override
  Future<List<Map<String, dynamic>>> analyzePages({
    required List<Uint8List> imageBytesList,
    required String vlmProvider,
    required ProcessingMode processingMode,
  }) async {
    calls.add('analyze');
    analyzeCalls.add(imageBytesList);
    return [{'page': 1, 'text': 'test'}];
  }

  @override
  Future<Map<String, dynamic>> generateScript({
    required List<Map<String, dynamic>> vlmOutput,
    required String language,
    required String llmProvider,
    String ttsProvider = 'openai',
  }) async {
    calls.add('script');
    return {
      'characters': [{'name': 'Narrator', 'voice': 'alloy'}],
      'chunks': [
        {
          'index': 0,
          'speakers': ['Narrator'],
          'text': 'Hi',
          'duration_ms': 0,
          'status': 'pending',
        }
      ],
    };
  }

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

  @override
  Future<List<Map<String, dynamic>>> designVoices({
    required List<Map<String, dynamic>> characters,
    required String language,
  }) async {
    calls.add('designVoices');
    return characters
        .map((c) => {...c, 'voice_id': 'v_${(c['name'] as String).toLowerCase()}'})
        .toList();
  }
}

class _QwenApiService extends _RecordingApiService {
  @override
  Future<Map<String, dynamic>> generateScript({
    required List<Map<String, dynamic>> vlmOutput,
    required String language,
    required String llmProvider,
    String ttsProvider = 'openai',
  }) async {
    calls.add('script');
    return {
      'characters': [
        {'name': 'Narrator', 'voice_prompt': 'calm narrator', 'voice_id': null}
      ],
      'chunks': [
        {
          'index': 0,
          'speakers': ['Narrator'],
          'text': 'Narrator: Hi',
          'duration_ms': 0,
          'status': 'pending',
        }
      ],
    };
  }

  @override
  Future<List<Map<String, dynamic>>> generateAudio({
    required List<Map<String, dynamic>> chunks,
    String ttsProvider = 'openai',
  }) async {
    calls.add('tts');
    return chunks
        .map((c) => {
              'index': c['index'] as int,
              'status': 'ready',
              'audio_b64': base64Encode([1, 2, 3]),
              'duration_ms': 1200,
            })
        .toList();
  }
}

class _QwenNullVoiceIdApiService extends _QwenApiService {
  @override
  Future<List<Map<String, dynamic>>> designVoices({
    required List<Map<String, dynamic>> characters,
    required String language,
  }) async {
    calls.add('designVoices');
    return characters.map((c) => {...c, 'voice_id': null}).toList();
  }
}

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

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;

    final db = AppDatabase.instance;
    await db.init();

    // Ensure we have a clean slate for this test
    await db.insertBook(const Book(
      bookId: 'test_book_live',
      title: 'Test',
      coverPath: null,
      pagesDir: 'test/assets',
      vlmOutput: '',
      vlmProvider: 'gemini',
      createdAt: 0,
    ));
    await db.insertAudioVersion(const AudioVersion(
      versionId: 'test_book_live_en',
      bookId: 'test_book_live',
      language: 'en',
      llmProvider: 'gpt4o',
      scriptJson: '{}',
      audioDir: '',
      status: 'generating',
      lastGeneratedLine: 0,
      lastPlayedLine: 0,
      createdAt: 0,
    ));
  });

  tearDownAll(() async {
    await AppDatabase.instance.close();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('LoadingScreen calls analyze->script->tts in order for new book',
      (tester) async {
    final fakeApi = _RecordingApiService();
    final tempAudioDir = Directory.systemTemp.createTempSync('bookactor_test_');
    addTearDown(() => tempAudioDir.deleteSync(recursive: true));
    final fakeImage = File('${tempAudioDir.path}/fake.png')
      ..writeAsBytesSync([1, 2, 3]);

    final params = LoadingParams(
      bookId: 'test_book_live',
      versionId: 'test_book_live_en',
      filePath: fakeImage.path,
      language: 'en',
      vlmProvider: 'gemini',
      llmProvider: 'gpt4o',
      ttsProvider: 'openai',
      processingMode: ProcessingMode.textHeavy,
      isNewBook: true,
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

    // Use runAsync for the whole widget pump + settle to allow real async I/O
    await tester.runAsync(() async {
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp.router(routerConfig: router),
      ));
      // Give the pipeline time to complete all real async I/O steps
      await Future<void>.delayed(const Duration(seconds: 5));
    });
    await tester.pump();

    expect(fakeApi.calls, equals(['analyze', 'script', 'tts']));
  });

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
      filePath: img1.path,
      imageFilePaths: [img1.path, img2.path],
      language: 'en',
      vlmProvider: 'gemini',
      llmProvider: 'gpt4o',
      ttsProvider: 'openai',
      processingMode: ProcessingMode.textHeavy,
      isNewBook: true,
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
    expect(fakeApi.analyzeCalls.single.length, equals(2));
  });

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
    addTearDown(() async {
      // Small delay on Windows to allow file handles to close before deletion
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (tempAudioDir.existsSync()) tempAudioDir.deleteSync(recursive: true);
    });

    const scriptJson = '{"characters":[{"name":"Narrator","voice":"alloy"}],'
        '"chunks":['
        '{"index":0,"speakers":["Narrator"],"text":"Hello","duration_ms":1000,"status":"ready"},'
        '{"index":1,"speakers":["Narrator"],"text":"World","duration_ms":0,"status":"error"}'
        ']}';

    final fakeApi = _RecordingApiService();
    late File existingChunkFile;

    await tester.runAsync(() async {
      // chunk 0 is already done — file exists on disk
      existingChunkFile = File('${tempAudioDir.path}/chunk_000.wav');
      await existingChunkFile.writeAsBytes([1, 2, 3]);

      // DB setup inside runAsync to stay in the same async zone as the pipeline
      await AppDatabase.instance.updateBookVlmOutput(
        'test_book_live', '[{"page":1,"text":"hello"}]');
      await AppDatabase.instance.updateAudioVersionStatus(
        'test_book_live_en', 'error', scriptJson: scriptJson);

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
        scriptJsonForResume: scriptJson,
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

      await tester.pumpWidget(ProviderScope(
        child: MaterialApp.router(routerConfig: router),
      ));
      await Future<void>.delayed(const Duration(seconds: 5));
    });
    await tester.pump();
    await tester.pump(); // second pump needed for GoRouter to complete navigation

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

    test('ResumeStage enum has vlm, llm, voiceDesign, tts values', () {
      expect(ResumeStage.values, containsAll([
        ResumeStage.vlm, ResumeStage.llm, ResumeStage.voiceDesign, ResumeStage.tts,
      ]));
    });
  });

  testWidgets('Qwen: calls analyze->script->designVoices->tts in order',
      (tester) async {
    final qwenApi = _QwenApiService();
    final tempDir = Directory.systemTemp.createTempSync('bookactor_qwen_');
    addTearDown(() { if (tempDir.existsSync()) tempDir.deleteSync(recursive: true); });
    final fakeImage = File('${tempDir.path}/fake.png')..writeAsBytesSync([1, 2, 3]);

    final params = LoadingParams(
      bookId: 'test_book_live',
      versionId: 'test_book_live_en',
      filePath: fakeImage.path,
      language: 'zh',
      vlmProvider: 'gemini',
      llmProvider: 'gpt4o',
      ttsProvider: 'qwen',
      processingMode: ProcessingMode.textHeavy,
      isNewBook: true,
      audioDirOverride: tempDir.path,
    );

    final router = GoRouter(initialLocation: '/loading', routes: [
      GoRoute(path: '/loading', builder: (_, __) =>
          LoadingScreen(params: params, apiService: qwenApi)),
      GoRoute(path: '/player/:versionId', builder: (_, __) =>
          const Scaffold(body: Text('player'))),
    ]);

    await tester.runAsync(() async {
      await tester.pumpWidget(ProviderScope(child: MaterialApp.router(routerConfig: router)));
      await Future<void>.delayed(const Duration(seconds: 5));
    });
    await tester.pump();

    expect(qwenApi.calls, equals(['analyze', 'script', 'designVoices', 'tts']));
  });

  testWidgets('OpenAI: designVoices not called',
      (tester) async {
    final api = _RecordingApiService();
    final tempDir = Directory.systemTemp.createTempSync('bookactor_openai_');
    addTearDown(() { if (tempDir.existsSync()) tempDir.deleteSync(recursive: true); });
    final fakeImage = File('${tempDir.path}/fake.png')..writeAsBytesSync([1, 2, 3]);

    final params = LoadingParams(
      bookId: 'test_book_live',
      versionId: 'test_book_live_en',
      filePath: fakeImage.path,
      language: 'en',
      vlmProvider: 'gemini',
      llmProvider: 'gpt4o',
      ttsProvider: 'openai',
      processingMode: ProcessingMode.textHeavy,
      isNewBook: true,
      audioDirOverride: tempDir.path,
    );

    final router = GoRouter(initialLocation: '/loading', routes: [
      GoRoute(path: '/loading', builder: (_, __) =>
          LoadingScreen(params: params, apiService: api)),
      GoRoute(path: '/player/:versionId', builder: (_, __) =>
          const Scaffold(body: Text('player'))),
    ]);

    await tester.runAsync(() async {
      await tester.pumpWidget(ProviderScope(child: MaterialApp.router(routerConfig: router)));
      await Future<void>.delayed(const Duration(seconds: 5));
    });
    await tester.pump();

    expect(api.calls, containsAll(['analyze', 'script', 'tts']));
    expect(api.calls, isNot(contains('designVoices')));
  });

  testWidgets('Qwen Voice Design failure: shows error screen, does not call tts',
      (tester) async {
    final api = _QwenNullVoiceIdApiService();
    final tempDir = Directory.systemTemp.createTempSync('bookactor_qwen_fail_');
    addTearDown(() { if (tempDir.existsSync()) tempDir.deleteSync(recursive: true); });
    final fakeImage = File('${tempDir.path}/fake.png')..writeAsBytesSync([1, 2, 3]);

    final params = LoadingParams(
      bookId: 'test_book_live',
      versionId: 'test_book_live_en',
      filePath: fakeImage.path,
      language: 'zh',
      vlmProvider: 'gemini',
      llmProvider: 'gpt4o',
      ttsProvider: 'qwen',
      processingMode: ProcessingMode.textHeavy,
      isNewBook: true,
      audioDirOverride: tempDir.path,
    );

    final router = GoRouter(initialLocation: '/loading', routes: [
      GoRoute(path: '/loading', builder: (_, __) =>
          LoadingScreen(params: params, apiService: api)),
      GoRoute(path: '/player/:versionId', builder: (_, __) =>
          const Scaffold(body: Text('player'))),
    ]);

    await tester.runAsync(() async {
      await tester.pumpWidget(ProviderScope(child: MaterialApp.router(routerConfig: router)));
      await Future<void>.delayed(const Duration(seconds: 5));
    });
    await tester.pump();

    expect(find.text('Something went wrong'), findsOneWidget);
    expect(find.text('player'), findsNothing);
    expect(api.calls, isNot(contains('tts')));
  });

  testWidgets('Qwen VD resume: startStage=voiceDesign skips VLM+LLM, runs designVoices+tts',
      (tester) async {
    const scriptJson = '{"characters":['
        '{"name":"Narrator","voice_prompt":"calm","voice_id":null}'
        '],"chunks":['
        '{"index":0,"speakers":["Narrator"],"text":"Narrator: Hi",'
        '"duration_ms":0,"status":"pending"}'
        ']}';
    await AppDatabase.instance.updateAudioVersionStatus(
      'test_book_live_en', 'error', scriptJson: scriptJson);

    final api = _QwenApiService();
    final tempDir = Directory.systemTemp.createTempSync('bookactor_vd_resume_');
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final params = LoadingParams(
      bookId: 'test_book_live',
      versionId: 'test_book_live_en',
      filePath: '',
      language: 'zh',
      vlmProvider: 'gemini',
      llmProvider: 'gpt4o',
      ttsProvider: 'qwen',
      processingMode: ProcessingMode.textHeavy,
      isNewBook: false,
      startStage: ResumeStage.voiceDesign,
      audioDirOverride: tempDir.path,
      scriptJsonForResume: scriptJson,
    );

    final router = GoRouter(initialLocation: '/loading', routes: [
      GoRoute(path: '/loading', builder: (_, __) =>
          LoadingScreen(params: params, apiService: api)),
      GoRoute(path: '/player/:versionId', builder: (_, __) =>
          const Scaffold(body: Text('player'))),
    ]);

    await tester.runAsync(() async {
      await tester.pumpWidget(ProviderScope(child: MaterialApp.router(routerConfig: router)));
      await Future<void>.delayed(const Duration(seconds: 5));
    });
    await tester.pump();
    await tester.pump();

    expect(api.calls, equals(['designVoices', 'tts']));
  });
}
