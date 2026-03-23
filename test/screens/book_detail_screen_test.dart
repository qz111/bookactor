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
    // Initialize the production singleton so the sheet's DB insert works.
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
    expect(params.lastGeneratedLine, -1);
  });
}
