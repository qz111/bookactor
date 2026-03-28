import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:bookactor/models/audio_version.dart';
import 'package:bookactor/models/book.dart';
import 'package:bookactor/providers/books_provider.dart';
import 'package:bookactor/screens/library_screen.dart';
import 'package:bookactor/widgets/book_card.dart';

void main() {
  testWidgets('shows book title when books exist', (tester) async {
    final mockBooks = [
      const Book(
        bookId: 'b1',
        title: 'The Very Hungry Caterpillar',
        pagesDir: '',
        vlmOutput: '[]',
        vlmProvider: 'gemini',
        createdAt: 1711065600,
      ),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          booksProvider.overrideWith((_) async => mockBooks),
          generatingVersionsProvider.overrideWith((_) async => []),
          audioVersionsProvider('b1').overrideWith((_) async => []),
        ],
        child: const MaterialApp(home: LibraryScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('The Very Hungry Caterpillar'), findsOneWidget);
  });

  testWidgets('shows empty state when no books', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          booksProvider.overrideWith((_) async => <Book>[]),
          generatingVersionsProvider.overrideWith((_) async => []),
        ],
        child: const MaterialApp(home: LibraryScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No books yet'), findsOneWidget);
  });

  testWidgets('Dismiss button is absent when no generating versions exist',
      (tester) async {
    // The banner (and its Dismiss button) only appears when generatingVersionsProvider
    // returns a non-empty list. With an empty list, no banner should show.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          booksProvider.overrideWith((_) async => <Book>[]),
          generatingVersionsProvider.overrideWith((_) async => []),
        ],
        child: const MaterialApp(home: LibraryScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Dismiss'), findsNothing);
  });

  testWidgets('Add Book FAB navigates to upload', (tester) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, __) => const LibraryScreen()),
        GoRoute(
            path: '/upload',
            builder: (_, __) =>
                const Scaffold(body: Text('Upload Screen'))),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          booksProvider.overrideWith((_) async => <Book>[]),
          generatingVersionsProvider.overrideWith((_) async => []),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add Book'));
    await tester.pumpAndSettle();
    expect(find.text('Upload Screen'), findsOneWidget);
  });

  testWidgets('BookCard shows icon fallback when coverPath is null', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookCard(
            book: const Book(
              bookId: 'b1',
              title: 'Test',
              coverPath: null,
              pagesDir: '',
              vlmOutput: '[]',
              vlmProvider: 'gemini',
              createdAt: 0,
            ),
            languageCount: 1,
            onTap: () {},
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.menu_book), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('BookCard shows Image.file when coverPath is set', (tester) async {
    // Use the pre-existing valid PNG from test assets
    final file = File('test/assets/fake_image.png');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookCard(
            book: Book(
              bookId: 'b2',
              title: 'Covered',
              coverPath: file.path,
              pagesDir: '',
              vlmOutput: '[]',
              vlmProvider: 'gemini',
              createdAt: 0,
            ),
            languageCount: 0,
            onTap: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    // Image widget present (even if not fully decoded)
    expect(find.byType(Image), findsOneWidget);
    expect(find.byIcon(Icons.menu_book), findsNothing);
  });

  testWidgets('BookCard onLongPress callback is invoked on long press',
      (tester) async {
    bool longPressed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookCard(
            book: const Book(
              bookId: 'b1',
              title: 'Test',
              coverPath: null,
              pagesDir: '',
              vlmOutput: '[]',
              vlmProvider: 'gemini',
              createdAt: 0,
            ),
            languageCount: 1,
            onTap: () {},
            onLongPress: () => longPressed = true,
          ),
        ),
      ),
    );
    await tester.longPress(find.byType(BookCard));
    await tester.pumpAndSettle();
    expect(longPressed, isTrue);
  });

  testWidgets('long-press on book card shows delete dialog', (tester) async {
    final mockBooks = [
      const Book(
        bookId: 'b1',
        title: 'The Very Hungry Caterpillar',
        pagesDir: '',
        vlmOutput: '[]',
        vlmProvider: 'gemini',
        createdAt: 1711065600,
      ),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          booksProvider.overrideWith((_) async => mockBooks),
          generatingVersionsProvider.overrideWith((_) async => []),
          audioVersionsProvider('b1').overrideWith((_) async => []),
        ],
        child: const MaterialApp(home: LibraryScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.text('The Very Hungry Caterpillar'));
    await tester.pumpAndSettle();

    expect(
      find.text('Delete "The Very Hungry Caterpillar"?'),
      findsOneWidget,
    );
    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });

  // NOTE: This second test passes vacuously before implementation (long-press
  // does nothing at all → no dialog). It becomes a meaningful regression guard
  // after the feature is wired: confirms the generating guard blocks the dialog.
  testWidgets(
      'long-press on book card is disabled when a version is generating',
      (tester) async {
    final mockBooks = [
      const Book(
        bookId: 'b1',
        title: 'The Very Hungry Caterpillar',
        pagesDir: '',
        vlmOutput: '[]',
        vlmProvider: 'gemini',
        createdAt: 1711065600,
      ),
    ];
    const generatingVersion = AudioVersion(
      versionId: 'b1_en',
      bookId: 'b1',
      language: 'en',
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
          booksProvider.overrideWith((_) async => mockBooks),
          generatingVersionsProvider.overrideWith((_) async => []),
          audioVersionsProvider('b1')
              .overrideWith((_) async => [generatingVersion]),
        ],
        child: const MaterialApp(home: LibraryScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.text('The Very Hungry Caterpillar'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
  });
}
