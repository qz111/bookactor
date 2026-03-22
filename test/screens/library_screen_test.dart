import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:bookactor/models/book.dart';
import 'package:bookactor/providers/books_provider.dart';
import 'package:bookactor/screens/library_screen.dart';

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
}
