# Phase 4 Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add karaoke line-level text highlighting, book cover images auto-extracted from the PDF first page, and fix the BookDetail "Add Language" route bug that runs the mock pipeline instead of the live one.

**Architecture:** `KaraokeText` gains an `isPlaying` bool that drives an `AnimatedContainer` color transition — `PlayerScreen` passes `playerState.isPlaying` through. Cover images are extracted via the existing `PdfService` in `UploadScreen._generate()`, saved to the app documents dir, and stored via a new `AppDatabase.updateBookCoverPath()` method. `BookCard` and `BookDetailScreen` display the cover with an icon fallback. The `_NewLanguageSheet` bug is fixed by passing the `Book` object so it can construct a real `LoadingParams` and navigate to `/loading` with `extra`.

**Tech Stack:** Flutter, `AnimatedContainer` (built-in), `Image.file` (built-in), `path_provider ^2.1.4` (already in pubspec), `PdfService` (existing), `AppDatabase` (existing), `sqflite_common_ffi` for tests.

---

## File Map

| File | Change |
|---|---|
| `lib/db/database.dart` | Add `updateBookCoverPath()` method |
| `lib/widgets/karaoke_text.dart` | Add `isPlaying` param + `AnimatedContainer` |
| `lib/screens/player_screen.dart` | Pass `playerState.isPlaying` to `KaraokeText` |
| `lib/widgets/book_card.dart` | Replace icon placeholder with `Image.file` + fallback |
| `lib/screens/upload_screen.dart` | Extract cover in `_generate()` after `insertBook` |
| `lib/screens/book_detail_screen.dart` | Cover image at top; fix `_NewLanguageSheet` |
| `test/widgets/karaoke_text_test.dart` | Add highlight state tests |
| `test/db/database_test.dart` | Add `updateBookCoverPath` test |
| `test/screens/library_screen_test.dart` | Add cover image / fallback tests for `BookCard` |
| `test/screens/book_detail_screen_test.dart` | New file: cover + Add Language route fix test |

**Already done — no changes needed:**
- `lib/models/book.dart` — `coverPath String?` field already exists
- `lib/db/database.dart` schema — `cover_path TEXT` column already in `_createDb`
- `pubspec.yaml` — `path_provider` already present

---

## Task 1: KaraokeText animated highlight

**Files:**
- Modify: `lib/widgets/karaoke_text.dart`
- Modify: `lib/screens/player_screen.dart`
- Modify: `test/widgets/karaoke_text_test.dart`

- [ ] **Step 1: Write failing tests for `isPlaying` highlight states**

Add two new `testWidgets` cases to `test/widgets/karaoke_text_test.dart`. The existing test stays untouched:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookactor/widgets/karaoke_text.dart';

void main() {
  testWidgets('displays text and character name', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: KaraokeText(
            text: 'Once upon a time',
            character: 'Narrator',
          ),
        ),
      ),
    );
    expect(find.text('Once upon a time'), findsOneWidget);
    expect(find.text('Narrator'), findsOneWidget);
  });

  testWidgets('shows amber highlight when isPlaying is true', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: KaraokeText(
            text: 'Hello',
            character: 'Bunny',
            isPlaying: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final container = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer),
    );
    final decoration = container.decoration as BoxDecoration;
    // Color should be amber with opacity (non-zero alpha)
    expect(decoration.color, isNotNull);
    expect((decoration.color!.a * 255).round(), isNonZero);
  });

  testWidgets('shows no highlight when isPlaying is false', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: KaraokeText(
            text: 'Hello',
            character: 'Bunny',
            isPlaying: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final container = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer),
    );
    final decoration = container.decoration as BoxDecoration;
    expect(decoration.color, Colors.transparent);
  });
}
```

- [ ] **Step 2: Run tests — confirm new tests FAIL**

```
flutter test test/widgets/karaoke_text_test.dart -v
```

Expected: 1 PASS (existing), 2 FAIL (new — `AnimatedContainer` doesn't exist yet)

- [ ] **Step 3: Implement `isPlaying` in `KaraokeText`**

Replace `lib/widgets/karaoke_text.dart` entirely:

```dart
import 'package:flutter/material.dart';

class KaraokeText extends StatelessWidget {
  final String text;
  final String character;
  final bool isPlaying;

  const KaraokeText({
    super.key,
    required this.text,
    required this.character,
    this.isPlaying = false,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isPlaying
            ? Colors.amber.withValues(alpha: 0.15)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isPlaying
              ? Colors.amber.withValues(alpha: 0.5)
              : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          Text(
            character,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: isPlaying
                      ? Colors.amber
                      : Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            text,
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Wire `isPlaying` in `PlayerScreen`**

In `lib/screens/player_screen.dart`, find the `KaraokeText` call around line 168 and add the `isPlaying` parameter:

```dart
// Before:
KaraokeText(text: line.text, character: line.character),

// After:
KaraokeText(
  text: line.text,
  character: line.character,
  isPlaying: playerState.isPlaying,
),
```

- [ ] **Step 5: Run all tests — confirm 3 pass**

```
flutter test test/widgets/karaoke_text_test.dart -v
```

Expected: 3 PASS, 0 FAIL

- [ ] **Step 6: Run full suite — confirm no regressions**

```
flutter test --reporter compact
```

Expected: all tests pass (was 46 passing + 1 skip before this task)

- [ ] **Step 7: Commit**

```bash
git add lib/widgets/karaoke_text.dart lib/screens/player_screen.dart test/widgets/karaoke_text_test.dart
git commit -m "feat: add karaoke line highlight animation with AnimatedContainer"
```

---

## Task 2: Database cover path method + cover extraction on upload

**Files:**
- Modify: `lib/db/database.dart`
- Modify: `lib/screens/upload_screen.dart`
- Modify: `test/db/database_test.dart`

**Context:** The `cover_path TEXT` column and `Book.coverPath` field already exist. We only need to add the `updateBookCoverPath()` method and call it from `UploadScreen._generate()` after PdfService renders page 1.

**Note on `AudioVersion` model:** `AudioVersion` has NO `vlmProvider` field. VLM provider is stored on `Book.vlmProvider`. `LoadingParams` receives `vlmProvider` from `Book.vlmProvider` — not from `AudioVersion`.

**Note on UploadScreen cover tests:** `PdfService.pdfToJpegBytes` is a static method that calls a native PDF renderer. It cannot be meaningfully mocked in a widget test without dependency injection. The DB method is covered by the DB test. The try/catch error path is verified conceptually — a thrown exception is caught, logged, and does not affect the book insert or navigation. No widget test is added for this code path; the native renderer is tested (with a skip tag) in `test/services/pdf_service_test.dart`.

- [ ] **Step 1: Write failing test for `updateBookCoverPath`**

Add to the `'Books'` group in `test/db/database_test.dart`:

```dart
test('updateBookCoverPath persists cover_path for existing book', () async {
  await db.insertBook(testBook);
  await db.updateBookCoverPath('test123', '/app/docs/test123_cover.jpg');
  final updated = await db.getBook('test123');
  expect(updated?.coverPath, '/app/docs/test123_cover.jpg');
});
```

- [ ] **Step 2: Run test — confirm it FAILS**

```
flutter test test/db/database_test.dart -v
```

Expected: FAIL with `NoSuchMethodError: updateBookCoverPath`

- [ ] **Step 3: Add `updateBookCoverPath()` to `AppDatabase`**

In `lib/db/database.dart`, after the `updateBookVlmOutput` method (around line 76), add:

```dart
Future<void> updateBookCoverPath(String bookId, String path) async {
  final db = await database;
  await db.update(
    'books',
    {'cover_path': path},
    where: 'book_id = ?',
    whereArgs: [bookId],
  );
}
```

- [ ] **Step 4: Run DB tests — confirm all pass**

```
flutter test test/db/database_test.dart -v
```

Expected: all PASS

- [ ] **Step 5: Add cover extraction to `UploadScreen._generate()`**

In `lib/screens/upload_screen.dart`, add the import at the top:

```dart
import 'package:path_provider/path_provider.dart';
import '../services/pdf_service.dart';
```

Then in `_generate()`, after `await AppDatabase.instance.insertBook(...)` and before the `if (!mounted) return;` guard (around line 57), add:

```dart
// Extract cover from first PDF page (non-fatal if it fails)
try {
  final pages = await PdfService.pdfToJpegBytes(_selectedFilePath!);
  if (pages.isNotEmpty) {
    final dir = await getApplicationDocumentsDirectory();
    final coverFile = File('${dir.path}/${bookId}_cover.jpg');
    await coverFile.writeAsBytes(pages.first);
    await AppDatabase.instance.updateBookCoverPath(bookId, coverFile.path);
  }
} catch (e) {
  debugPrint('Cover extraction failed (non-fatal): $e');
}
```

- [ ] **Step 6: Run full test suite — confirm no regressions**

```
flutter test --reporter compact
```

Expected: all tests pass. Note: the PDF cover extraction is tested indirectly via the DB test; a real PdfService call requires a native renderer (skip tag on PDF tests is expected).

- [ ] **Step 7: Commit**

```bash
git add lib/db/database.dart lib/screens/upload_screen.dart test/db/database_test.dart
git commit -m "feat: add updateBookCoverPath and extract cover on PDF import"
```

---

## Task 3: BookCard cover image

**Files:**
- Modify: `lib/widgets/book_card.dart`
- Modify: `test/screens/library_screen_test.dart`

**Context:** `BookCard` currently shows `Icon(Icons.menu_book, size: 48)`. Replace with `Image.file` when `book.coverPath != null`, fallback to the icon.

- [ ] **Step 1: Write failing tests for cover/fallback in `BookCard`**

Add two `testWidgets` cases to `test/screens/library_screen_test.dart`:

**Important:** `test/screens/library_screen_test.dart` already has 4 passing tests. **ADD** the two new test cases below to the existing file — do NOT replace the file. Keep all existing tests intact. Add `import 'dart:io';` and `import 'package:bookactor/widgets/book_card.dart';` to the import block at the top.

Add these two new `testWidgets` cases inside the existing `main()` block:

```dart

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
  // Create a real temp JPEG so Image.file has something to load
  final dir = Directory.systemTemp;
  final file = File('${dir.path}/test_cover.jpg');
  // Write minimal valid JPEG bytes (SOI + EOI markers)
  await file.writeAsBytes([0xFF, 0xD8, 0xFF, 0xD9]);

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

  await file.delete();
});
```

Note: add `import 'dart:io';` at the top of the test file.

- [ ] **Step 2: Run tests — confirm new tests FAIL**

```
flutter test test/screens/library_screen_test.dart -v
```

Expected: existing tests PASS, new BookCard tests FAIL

- [ ] **Step 3: Implement cover image in `BookCard`**

Replace `lib/widgets/book_card.dart` entirely:

```dart
import 'dart:io';
import 'package:flutter/material.dart';
import '../models/book.dart';

class BookCard extends StatelessWidget {
  final Book book;
  final int languageCount;
  final VoidCallback onTap;

  const BookCard({
    super.key,
    required this.book,
    required this.languageCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: book.coverPath != null
                  ? Image.file(
                      File(book.coverPath!),
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _iconPlaceholder(context),
                    )
                  : _iconPlaceholder(context),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    style: Theme.of(context).textTheme.titleSmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$languageCount language${languageCount != 1 ? 's' : ''}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconPlaceholder(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: const Center(child: Icon(Icons.menu_book, size: 48)),
    );
  }
}
```

- [ ] **Step 4: Run tests — confirm all pass**

```
flutter test test/screens/library_screen_test.dart -v
```

Expected: all PASS

- [ ] **Step 5: Run full suite**

```
flutter test --reporter compact
```

Expected: all tests pass

- [ ] **Step 6: Commit**

```bash
git add lib/widgets/book_card.dart test/screens/library_screen_test.dart
git commit -m "feat: show cover image in BookCard with icon fallback"
```

---

## Task 4: BookDetailScreen — cover image + Add Language bug fix

**Files:**
- Modify: `lib/screens/book_detail_screen.dart`
- Create: `test/screens/book_detail_screen_test.dart`

**Context:** Two things to fix in `book_detail_screen.dart`:
1. Replace the `Icon(Icons.menu_book)` placeholder at the top with `Image.file` (same pattern as `BookCard`).
2. `_NewLanguageSheet` currently calls `context.push('/loading/${widget.bookId}/$_language')` which goes to a non-existent route. Fix: pass the full `Book` object to the sheet, insert an `AudioVersion` row, then navigate to `/loading` with `LoadingParams`.

**`lastGeneratedLine` convention:** The DB insert uses `lastGeneratedLine: 0` and `LoadingParams` uses `lastGeneratedLine: -1`. This matches `UploadScreen`'s existing pattern. The `-1` sentinel in `LoadingParams` signals "fresh start, process all lines" to the pipeline filter. The DB value of `0` is what gets read on cold-start resume (same as UploadScreen behavior).

**`status: 'generating'`** is correct and matches `UploadScreen`. The `'pending'` status is not used anywhere in the app.

- [ ] **Step 1: Create `test/screens/book_detail_screen_test.dart` with failing tests**

```dart
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
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
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
    final file = File('${Directory.systemTemp.path}/detail_cover.jpg');
    await file.writeAsBytes([0xFF, 0xD8, 0xFF, 0xD9]);

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
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);

    await file.delete();
  });

  testWidgets('Add Language navigates to /loading with LoadingParams',
      (tester) async {
    // Set up in-memory DB with the test book
    final db = AppDatabase.forTesting();
    await db.init();
    await db.insertBook(testBook);

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

    await db.close();
  });
}
```

- [ ] **Step 2: Run tests — confirm they FAIL**

```
flutter test test/screens/book_detail_screen_test.dart -v
```

Expected: FAIL (cover test fails because `Image` widget is not present; Add Language test fails because it navigates to old path-based route)

- [ ] **Step 3: Implement cover image + fix `_NewLanguageSheet`**

Replace `lib/screens/book_detail_screen.dart` entirely:

```dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../db/database.dart';
import '../mock/mock_data.dart';
import '../models/audio_version.dart';
import '../models/book.dart';
import '../providers/books_provider.dart';
import '../screens/loading_screen.dart';
import '../widgets/language_badge.dart';

class BookDetailScreen extends ConsumerWidget {
  final String bookId;
  const BookDetailScreen({super.key, required this.bookId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookAsync = ref.watch(singleBookProvider(bookId));
    final versionsAsync = ref.watch(audioVersionsProvider(bookId));

    return Scaffold(
      appBar: AppBar(title: const Text('Book')),
      body: bookAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (book) {
          if (book == null) {
            return const Center(child: Text('Book not found'));
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Cover image or placeholder
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  height: 200,
                  child: book.coverPath != null
                      ? Image.file(
                          File(book.coverPath!),
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              _coverPlaceholder(context),
                        )
                      : _coverPlaceholder(context),
                ),
              ),
              const SizedBox(height: 16),
              Text(book.title,
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 24),
              const Text('Audio Versions',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              versionsAsync.when(
                loading: () => const CircularProgressIndicator(),
                error: (e, _) => Text('Error: $e'),
                data: (versions) => Column(
                  children: [
                    ...versions.map((v) => ListTile(
                          leading: LanguageBadge(
                              language: v.language, status: v.status),
                          title: Text(_languageName(v.language)),
                          subtitle: Text(v.status),
                          trailing: v.status == 'ready'
                              ? IconButton(
                                  icon: const Icon(Icons.play_circle_filled),
                                  onPressed: () =>
                                      context.push('/player/${v.versionId}'),
                                )
                              : null,
                        )),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () =>
                          _showNewLanguageSheet(context, book),
                      icon: const Icon(Icons.add),
                      label: const Text('New Language'),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _coverPlaceholder(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: const Center(child: Icon(Icons.menu_book, size: 72)),
    );
  }

  String _languageName(String code) =>
      supportedLanguages.firstWhere(
        (l) => l['code'] == code,
        orElse: () => {'code': code, 'name': code},
      )['name']!;

  void _showNewLanguageSheet(BuildContext context, Book book) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _NewLanguageSheet(book: book),
    );
  }
}

class _NewLanguageSheet extends StatefulWidget {
  final Book book;
  const _NewLanguageSheet({required this.book});

  @override
  State<_NewLanguageSheet> createState() => _NewLanguageSheetState();
}

class _NewLanguageSheetState extends State<_NewLanguageSheet> {
  String _language = 'zh';
  String _llmProvider = 'gpt4o';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Add New Language',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _language,
            decoration: const InputDecoration(
                labelText: 'Language', border: OutlineInputBorder()),
            items: supportedLanguages
                .map((l) =>
                    DropdownMenuItem(value: l['code'], child: Text(l['name']!)))
                .toList(),
            onChanged: (v) => setState(() => _language = v!),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _llmProvider,
            decoration: const InputDecoration(
                labelText: 'LLM Provider', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'gpt4o', child: Text('GPT-4o')),
              DropdownMenuItem(value: 'gemini', child: Text('Gemini')),
            ],
            onChanged: (v) => setState(() => _llmProvider = v!),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () async {
                final versionId =
                    AudioVersion.makeVersionId(widget.book.bookId, _language);
                await AppDatabase.instance.insertAudioVersion(AudioVersion(
                  versionId: versionId,
                  bookId: widget.book.bookId,
                  language: _language,
                  llmProvider: _llmProvider,
                  scriptJson: '{}',
                  audioDir: '',
                  status: 'generating',
                  lastGeneratedLine: 0,
                  lastPlayedLine: 0,
                  createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
                ));
                if (!context.mounted) return;
                Navigator.pop(context);
                if (!context.mounted) return;
                context.push(
                  '/loading',
                  extra: LoadingParams(
                    bookId: widget.book.bookId,
                    versionId: versionId,
                    filePath: widget.book.pagesDir,
                    language: _language,
                    vlmProvider: widget.book.vlmProvider,
                    llmProvider: _llmProvider,
                    isNewBook: false,
                    lastGeneratedLine: -1,
                  ),
                );
              },
              child: const Text('Generate'),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run new tests — confirm all pass**

```
flutter test test/screens/book_detail_screen_test.dart -v
```

Expected: 3 PASS, 0 FAIL

- [ ] **Step 5: Run full test suite — confirm no regressions**

```
flutter test --reporter compact
```

Expected: all tests pass (46 + new tests passing, 1 skip)

- [ ] **Step 6: Commit**

```bash
git add lib/screens/book_detail_screen.dart test/screens/book_detail_screen_test.dart
git commit -m "feat: show cover image in BookDetailScreen and fix Add Language to use live pipeline"
```

---

## Final Verification

- [ ] **Run full test suite one last time**

```
flutter test --reporter compact
```

Expected output: all tests pass, 1 skip (PDF native renderer test)

- [ ] **Verify no analysis errors**

```
flutter analyze
```

Expected: no issues found (or only pre-existing infos)
