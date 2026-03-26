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
    return [
      {'index': 0, 'status': 'ready', 'audio_b64': base64Encode([1, 2, 3]), 'duration_ms': 1200}
    ];
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

    final params = LoadingParams(
      bookId: 'test_book_live',
      versionId: 'test_book_live_en',
      filePath: 'test/assets/fake_image.png',
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
}
