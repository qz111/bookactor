import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:bookactor/db/database.dart';
import 'package:bookactor/models/book.dart';
import 'package:bookactor/models/audio_version.dart';
import 'package:bookactor/providers/books_provider.dart';
import 'package:bookactor/screens/book_detail_screen.dart';
import 'package:bookactor/screens/loading_screen.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    // _NewLanguageSheet calls AppDatabase.instance directly (no DI injection point),
    // so we must initialize the production singleton here. A future refactor to
    // inject the DB via a provider would let us use AppDatabase.forTesting() instead.
    await AppDatabase.instance.init();
  });

  tearDownAll(() async {
    await AppDatabase.instance.close();
  });

  final testBook = Book(
    bookId: 'detail_test_book',
    title: 'Detail Test Book',
    coverPath: null,
    pagesDir: '/tmp/test.pdf',
    vlmOutput: '[]',
    vlmProvider: 'gemini',
    createdAt: 1711065600,
  );

  testWidgets('shows icon placeholder when coverPath is null', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          singleBookProvider('detail_test_book').overrideWith(
            (_) async => testBook,
          ),
          audioVersionsProvider('detail_test_book').overrideWith(
            (_) async => <AudioVersion>[],
          ),
        ],
        child: const MaterialApp(
          home: BookDetailScreen(bookId: 'detail_test_book'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.menu_book), findsOneWidget);
  });

  testWidgets('shows cover image when coverPath is set', (tester) async {
    final file = File('test/assets/fake_image.png');

    final bookWithCover = Book(
      bookId: 'detail_test_book',
      title: 'Detail Test Book',
      coverPath: file.path,
      pagesDir: '/tmp/test.pdf',
      vlmOutput: '[]',
      vlmProvider: 'gemini',
      createdAt: 1711065600,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          singleBookProvider('detail_test_book').overrideWith(
            (_) async => bookWithCover,
          ),
          audioVersionsProvider('detail_test_book').overrideWith(
            (_) async => <AudioVersion>[],
          ),
        ],
        child: const MaterialApp(
          home: BookDetailScreen(bookId: 'detail_test_book'),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('Add Language navigates to /loading with LoadingParams',
      (tester) async {
    // Seed the singleton (which _NewLanguageSheet uses)
    await AppDatabase.instance.insertBook(testBook);

    String? pushedPath;
    Object? pushedExtra;

    final router = GoRouter(
      initialLocation: '/book/detail_test_book',
      routes: [
        GoRoute(
          path: '/book/:bookId',
          builder: (context, state) =>
              BookDetailScreen(bookId: state.pathParameters['bookId']!),
        ),
        GoRoute(
          path: '/loading',
          builder: (context, state) {
            pushedPath = '/loading';
            pushedExtra = state.extra;
            return const Scaffold(body: Text('Loading'));
          },
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          singleBookProvider('detail_test_book').overrideWith(
            (_) async => testBook,
          ),
          audioVersionsProvider('detail_test_book').overrideWith(
            (_) async => <AudioVersion>[],
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    // Tap "New Language" button
    await tester.tap(find.text('New Language'));
    await tester.pumpAndSettle();

    // Tap "Generate" in the sheet
    await tester.tap(find.text('Generate'));
    await tester.pumpAndSettle();

    expect(pushedPath, '/loading');
    expect(pushedExtra, isA<LoadingParams>());
    final params = pushedExtra as LoadingParams;
    expect(params.bookId, 'detail_test_book');
    expect(params.isNewBook, false);
  });

  testWidgets('long-press on ready version shows delete dialog', (tester) async {
    final version = AudioVersion(
      versionId: 'detail_test_book_en',
      bookId: 'detail_test_book',
      language: 'en',
      scriptJson: '{}',
      audioDir: '',
      status: 'ready',
      lastGeneratedLine: 0,
      lastPlayedLine: 0,
      createdAt: 1711065600,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          singleBookProvider('detail_test_book').overrideWith((_) async => testBook),
          audioVersionsProvider('detail_test_book').overrideWith(
            (_) async => [version],
          ),
        ],
        child: const MaterialApp(
          home: BookDetailScreen(bookId: 'detail_test_book'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Long-press the English language tile
    await tester.longPress(find.text('English'));
    await tester.pumpAndSettle();

    expect(find.text('Delete audio version?'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });

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

  testWidgets('long-press on generating version does NOT show delete dialog', (tester) async {
    final version = AudioVersion(
      versionId: 'detail_test_book_zh',
      bookId: 'detail_test_book',
      language: 'zh',
      scriptJson: '{}',
      audioDir: '',
      status: 'generating',
      lastGeneratedLine: 0,
      lastPlayedLine: 0,
      createdAt: 1711065600,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          singleBookProvider('detail_test_book').overrideWith((_) async => testBook),
          audioVersionsProvider('detail_test_book').overrideWith(
            (_) async => [version],
          ),
        ],
        child: const MaterialApp(
          home: BookDetailScreen(bookId: 'detail_test_book'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Chinese (Simplified)'));
    await tester.pumpAndSettle();

    expect(find.text('Delete audio version?'), findsNothing);
  });
}
