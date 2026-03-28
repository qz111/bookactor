# Book Deletion from Library Screen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow long-pressing a book card in the library grid to delete the book and all its audio versions.

**Architecture:** Three files change — `database.dart` gets `deleteBook`, `book_card.dart` gets an optional `onLongPress`, and `library_screen.dart` is converted from `ConsumerWidget` to `ConsumerStatefulWidget` and gains a `_confirmDeleteBook` dialog. The deletion sequence cleans up audio dirs, pagesDir, coverPath, then DB rows (versions first, then book).

**Tech Stack:** Flutter, Riverpod, sqflite, dart:io

**Spec:** `docs/superpowers/specs/2026-03-28-book-deletion-design.md`

---

## File Map

| File | Change |
|------|--------|
| `lib/db/database.dart` | Add `deleteBook(bookId)` method |
| `lib/widgets/book_card.dart` | Add optional `onLongPress` callback |
| `lib/screens/library_screen.dart` | Convert to `ConsumerStatefulWidget`; add `_confirmDeleteBook`; wire `onLongPress` |
| `test/db/database_test.dart` | Add `deleteBook` tests |
| `test/screens/library_screen_test.dart` | Add `onLongPress` and deletion dialog tests |

---

### Task 1: Add `deleteBook` to the database layer

**Files:**
- Modify: `lib/db/database.dart` (add after `deleteAudioVersion`, ~line 175)
- Modify: `test/db/database_test.dart` (add at end of `group('Books', ...)`)

- [ ] **Step 1: Write the failing tests**

Add inside the `group('Books', ...)` block in `test/db/database_test.dart`, after the last existing test:

```dart
test('deleteBook removes the book row', () async {
  await db.insertBook(testBook);

  final before = await db.getBook('test123');
  expect(before, isNotNull);

  await db.deleteBook('test123');

  final after = await db.getBook('test123');
  expect(after, isNull);
});

test('deleteBook on missing id is a no-op', () async {
  await expectLater(
    db.deleteBook('nonexistent_id'),
    completes,
  );
});

test('deleteBook after deleteAudioVersion leaves no orphan rows', () async {
  // Validates the intended usage order: delete versions first, then the book.
  await db.insertBook(testBook);
  await db.insertAudioVersion(const AudioVersion(
    versionId: 'test123_en',
    bookId: 'test123',
    language: 'en',
    scriptJson: '{}',
    audioDir: '',
    status: 'ready',
    lastGeneratedLine: 0,
    lastPlayedLine: 0,
    createdAt: 1711065600,
  ));

  await db.deleteAudioVersion('test123_en');
  await db.deleteBook('test123');

  expect(await db.getBook('test123'), isNull);
  expect(await db.getAudioVersion('test123_en'), isNull);
});
```

- [ ] **Step 2: Run tests to verify they fail**

```
flutter test test/db/database_test.dart -v
```

Expected: FAIL — `The method 'deleteBook' isn't defined for the type 'AppDatabase'`

- [ ] **Step 3: Implement `deleteBook` in `lib/db/database.dart`**

Add after the existing `deleteAudioVersion` method (~line 175):

```dart
Future<void> deleteBook(String bookId) async {
  final db = await database;
  await db.delete('books', where: 'book_id = ?', whereArgs: [bookId]);
}
```

- [ ] **Step 4: Run tests to verify they pass**

```
flutter test test/db/database_test.dart -v
```

Expected: All tests PASS (including the 3 new ones)

- [ ] **Step 5: Commit**

```bash
git add lib/db/database.dart test/db/database_test.dart
git commit -m "feat: add deleteBook to AppDatabase"
```

---

### Task 2: Add `onLongPress` to `BookCard`

**Files:**
- Modify: `lib/widgets/book_card.dart`
- Modify: `test/screens/library_screen_test.dart` (add before the closing `}` of `main()`)

- [ ] **Step 1: Write the failing test**

Add inside `main()` in `test/screens/library_screen_test.dart`, before the closing `}`:

```dart
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
```

- [ ] **Step 2: Run test to verify it fails**

```
flutter test test/screens/library_screen_test.dart -v
```

Expected: FAIL — `No named parameter with the name 'onLongPress'`

- [ ] **Step 3: Add `onLongPress` to `BookCard`**

In `lib/widgets/book_card.dart`, update the class fields and constructor:

```dart
class BookCard extends StatelessWidget {
  final Book book;
  final int languageCount;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const BookCard({
    super.key,
    required this.book,
    required this.languageCount,
    required this.onTap,
    this.onLongPress,
  });
```

And in `build`, pass `onLongPress` through to `InkWell`:

```dart
child: InkWell(
  onTap: onTap,
  onLongPress: onLongPress,
  child: Column(
```

- [ ] **Step 4: Run tests to verify they pass**

```
flutter test test/screens/library_screen_test.dart -v
```

Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/book_card.dart test/screens/library_screen_test.dart
git commit -m "feat: add optional onLongPress to BookCard"
```

---

### Task 3: Book deletion dialog in LibraryScreen

**Files:**
- Modify: `lib/screens/library_screen.dart` (full replacement)
- Modify: `test/screens/library_screen_test.dart` (add 2 more tests before closing `}` of `main()`)

**Context — read before implementing:**
- Study `lib/screens/book_detail_screen.dart` `_confirmDelete` (lines 44–105). The library screen deletion mirrors it exactly.
- The `_confirmDeleteBook` method takes `BuildContext screenContext` (the outer Scaffold context captured in `build`) and `Book book`. It must NOT use the `Consumer` builder's inner `context` — that would resolve `ScaffoldMessenger` incorrectly. The outer context must be captured explicitly before the `GridView.builder` closure.
- `dialogContext` (from `showDialog` builder) is used only for `Navigator.pop(dialogContext)`.
- `screenContext` is used for `ScaffoldMessenger.of(screenContext).showSnackBar(...)`.
- On failure: `deleting` is reset to `false` in `finally` so the dialog stays open for retry.

- [ ] **Step 1: Write the failing tests**

First, add the `AudioVersion` import at the top of `test/screens/library_screen_test.dart` (it is not currently present):

```dart
import 'package:bookactor/models/audio_version.dart';
```

Then add both tests inside `main()` before the closing `}`:

```dart
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
```

- [ ] **Step 2: Run tests — the first new test fails, the second passes vacuously**

```
flutter test test/screens/library_screen_test.dart -v
```

Expected: The "shows delete dialog" test FAILS (dialog not found). The "disabled when generating" test PASSES (no dialog before feature exists either). This is expected — the first test is the TDD gate.

- [ ] **Step 3: Replace `lib/screens/library_screen.dart`**

Replace the entire file with:

```dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../db/database.dart';
import '../models/audio_version.dart';
import '../models/book.dart';
import '../models/processing_mode.dart';
import '../providers/books_provider.dart';
import '../screens/loading_screen.dart';
import '../widgets/book_card.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  void _confirmDeleteBook(BuildContext screenContext, Book book) {
    showDialog(
      context: screenContext,
      builder: (dialogContext) {
        bool deleting = false;
        return StatefulBuilder(
          builder: (_, setDialogState) => AlertDialog(
            title: Text('Delete "${book.title}"?'),
            content: const Text(
              'This will permanently delete the book and all its audio versions. This cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed:
                    deleting ? null : () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: deleting
                    ? null
                    : () async {
                        setDialogState(() => deleting = true);
                        bool success = false;
                        try {
                          final versions = await AppDatabase.instance
                              .getVersionsForBook(book.bookId);
                          for (final v in versions) {
                            if (v.audioDir.isNotEmpty) {
                              try {
                                await Directory(v.audioDir)
                                    .delete(recursive: true);
                              } on FileSystemException {
                                // already gone — continue
                              }
                            }
                          }
                          if (book.pagesDir.isNotEmpty) {
                            try {
                              await Directory(book.pagesDir)
                                  .delete(recursive: true);
                            } on FileSystemException {
                              // already gone
                            }
                          }
                          if (book.coverPath != null &&
                              book.coverPath!.isNotEmpty) {
                            try {
                              await File(book.coverPath!).delete();
                            } on FileSystemException {
                              // already gone
                            }
                          }
                          for (final v in versions) {
                            await AppDatabase.instance
                                .deleteAudioVersion(v.versionId);
                          }
                          await AppDatabase.instance.deleteBook(book.bookId);
                          success = true;
                        } finally {
                          if (!success && mounted) {
                            setDialogState(() => deleting = false);
                          }
                        }
                        if (success && mounted) {
                          ref.invalidate(booksProvider);
                          ref.invalidate(audioVersionsProvider(book.bookId));
                          Navigator.pop(dialogContext);
                        } else if (!success && mounted) {
                          ScaffoldMessenger.of(screenContext).showSnackBar(
                            const SnackBar(
                                content: Text('Could not delete book.')),
                          );
                        }
                      },
                child: deleting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Delete'),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Capture scaffold context before any nested Consumer closures to avoid
    // the inner Consumer builder's `context` parameter shadowing this one.
    final screenContext = context;
    final booksAsync = ref.watch(booksProvider);
    final generatingAsync = ref.watch(generatingVersionsProvider);

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
      body: Column(
        children: [
          // Cold-start resume banner
          generatingAsync.when(
            data: (versions) {
              if (versions.isEmpty) return const SizedBox.shrink();
              return MaterialBanner(
                content: Text(
                    '${versions.length} audiobook(s) were interrupted. Resume?'),
                actions: [
                  TextButton(
                    onPressed: () async {
                      for (final v in versions) {
                        final book =
                            await AppDatabase.instance.getBook(v.bookId);
                        if (book == null) continue;
                        if (!context.mounted) return;
                        context.push(
                          '/loading',
                          extra: LoadingParams(
                            bookId: v.bookId,
                            versionId: v.versionId,
                            filePath: book.pagesDir,
                            language: v.language,
                            vlmProvider: book.vlmProvider,
                            llmProvider: v.llmProvider ?? 'gpt4o',
                            ttsProvider: v.ttsProvider ?? 'openai',
                            processingMode: ProcessingMode.textHeavy,
                            isNewBook: false,
                          ),
                        );
                      }
                    },
                    child: const Text('Resume'),
                  ),
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
                ],
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          // Book grid
          Expanded(
            child: booksAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (books) {
                if (books.isEmpty) {
                  return const Center(child: Text('No books yet'));
                }
                return GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
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
                          onTap: () =>
                              context.push('/book/${book.bookId}'),
                          onLongPress: isGenerating
                              ? null
                              : () => _confirmDeleteBook(screenContext, book),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run all tests to verify they pass**

```
flutter test test/screens/library_screen_test.dart -v
```

Expected: All tests PASS (including both new dialog tests)

Run the full test suite to check for regressions:

```
flutter test -v
```

Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add lib/screens/library_screen.dart test/screens/library_screen_test.dart
git commit -m "feat: book deletion from library screen via long-press"
```
