# Book Deletion from Library Screen Design

## Goal

Allow users to delete a book (and all its generated audio versions) directly from the library grid screen via long-press on a book card.

## Architecture

**Files changed:**
- `lib/db/database.dart` — add `deleteBook(bookId)` method
- `lib/widgets/book_card.dart` — add optional `onLongPress` callback, passed through to `InkWell`
- `lib/screens/library_screen.dart` — convert to `ConsumerStatefulWidget`; add `_confirmDeleteBook` dialog logic; wire `onLongPress` on each `BookCard`

## Interaction Design

**Trigger:** Long-press on a `BookCard` in the library grid, only when no version for that book has `status == 'generating'`. The grid item already watches `audioVersionsProvider(book.bookId)` for the language count, so the version list is available — disable `onLongPress` when any version is generating.

**Confirmation dialog:**
```
Delete "[book title]"?
This will permanently delete the book and all its audio versions. This cannot be undone.

[Cancel]  [Delete]
```

- Dialog uses the same `StatefulBuilder` + `deleting` bool pattern as the existing audio-version delete in `book_detail_screen.dart`.
- While deleting: both buttons are disabled; "Delete" shows a `CircularProgressIndicator` (16×16, strokeWidth 2).
- On failure: `deleting` is reset to `false` (dialog stays open so user can retry or cancel). Snackbar is shown using the **outer scaffold context** (`screenContext`), not `dialogContext` — same as the existing `_confirmDelete` in `book_detail_screen.dart`.

## Deletion Sequence

1. Load all audio versions: `AppDatabase.instance.getVersionsForBook(bookId)`
2. For each version with a non-empty `audioDir`: delete directory recursively; catch `FileSystemException` (already gone → continue).
3. If `book.pagesDir.isNotEmpty`: delete `pagesDir` directory recursively; catch `FileSystemException`.
4. If `book.coverPath != null && book.coverPath!.isNotEmpty`: delete the cover file; catch `FileSystemException`.
5. DB: `deleteAudioVersion(v.versionId)` for each version, then `deleteBook(bookId)`.
6. Invalidate `booksProvider` and `audioVersionsProvider(bookId)` → library grid refreshes; stale family cache cleared.

## Database Change

Add to `AppDatabase`:

```dart
Future<void> deleteBook(String bookId) async {
  final db = await database;
  await db.delete('books', where: 'book_id = ?', whereArgs: [bookId]);
}
```

No cascade — Flutter code explicitly cleans up audio versions before calling this.

## LibraryScreen Change

Convert `LibraryScreen` from `ConsumerWidget` to `ConsumerStatefulWidget` so `ref` is accessible in `_confirmDeleteBook`. The `build` method body is unchanged; only the widget class declaration and `_confirmDeleteBook` method are added.

Add `import 'dart:io';` for `Directory` and `File` usage.

## BookCard Change

Add optional `onLongPress` to `BookCard`:

```dart
final VoidCallback? onLongPress;

// In InkWell:
InkWell(onTap: onTap, onLongPress: onLongPress, ...)
```

## Out of Scope

- No change to the book detail screen's per-language delete.
- No batch/multi-select deletion.
- No undo.
