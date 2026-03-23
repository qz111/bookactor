# Phase 4: Audio Polish — Design Spec

## Goal

Add karaoke line-level text highlighting, book cover images auto-extracted from the PDF, and fix the BookDetail "Add Language" bug that bypasses the live pipeline.

## Scope

**In scope:**
- Karaoke line-level highlight animation in the player
- Book cover extraction from PDF page 1, stored as JPEG, displayed in library and book detail
- BookDetail "Add Language" bug fix (old mock route → live pipeline via `LoadingParams`)

**Out of scope:**
- Word-level karaoke (no TTS timestamp support in current pipeline)
- Page image display in the player
- New backend changes

---

## Architecture

Four components change. No new services needed.

### 1. Database — `books` table migration

Add a nullable `cover_path TEXT` column via `onUpgrade` with a version bump:

```sql
ALTER TABLE books ADD COLUMN cover_path TEXT;
```

New `AppDatabase` method:
```dart
Future<void> updateBookCoverPath(String bookId, String path) async {
  final db = await database;
  await db.update('books', {'cover_path': path},
      where: 'book_id = ?', whereArgs: [bookId]);
}
```

The `Book` model gets a nullable `String? coverPath` field.

### 2. UploadScreen — Cover extraction on import

In `_generate()`, after inserting the book row, extract the first PDF page using the existing `PdfService`, save to app documents directory, and call `updateBookCoverPath()`.

```dart
// After insertBook():
try {
  final pages = await PdfService.pdfToJpegBytes(_selectedFilePath!);
  if (pages.isNotEmpty) {
    final dir = await getApplicationDocumentsDirectory();
    final coverFile = File('${dir.path}/${bookId}_cover.jpg');
    await coverFile.writeAsBytes(pages.first);
    await AppDatabase.instance.updateBookCoverPath(bookId, coverFile.path);
  }
} catch (e) {
  debugPrint('Cover extraction failed: $e');
  // Non-fatal — book imports successfully without a cover
}
```

Cover file path: `<appDocumentsDir>/<bookId>_cover.jpg`

### 3. KaraokeText widget — Animated line highlight

Add `isPlaying` bool parameter. Wrap content in `AnimatedContainer` that transitions between a highlighted state (amber background + border) and transparent when not playing.

```dart
class KaraokeText extends StatelessWidget {
  final String text;
  final String character;
  final bool isPlaying;  // NEW

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
      decoration: BoxDecoration(
        color: isPlaying
            ? Colors.amber.withOpacity(0.15)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isPlaying
              ? Colors.amber.withOpacity(0.5)
              : Colors.transparent,
          width: 1.5,
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(character, style: ...),
          Text(text, style: ...),
        ],
      ),
    );
  }
}
```

`PlayerScreen` renders exactly one `KaraokeText` at a time (the current line only). It passes `playerState.isPlaying` to that single widget, so the highlight reflects whether the current line is actively playing — not all lines simultaneously.

### 4. LibraryScreen + BookDetailScreen — Cover display

Both screens already receive `Book` objects. Replace icon placeholders with:

```dart
Widget _buildCover(Book book, {double? width, double? height}) {
  if (book.coverPath != null) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.file(
        File(book.coverPath!),
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            Icon(Icons.menu_book, size: (height ?? 48) * 0.6),
      ),
    );
  }
  return Icon(Icons.menu_book, size: (height ?? 48) * 0.6);
}
```

**LibraryScreen card redesign:** Cover image fills the top portion of the card (height: 110px, aspect ratio preserved via `BoxFit.cover`); title and language badges below. Card width: fixed at 160px in a horizontal scroll list.

**BookDetailScreen:** Cover image shown prominently at the top of the detail view.

### 5. BookDetailScreen — "Add Language" bug fix

Current broken code:
```dart
context.push('/loading/${widget.bookId}/$_language');
```

Fixed code:
```dart
final version = AudioVersion(
  versionId: '${widget.bookId}_${_language}_${DateTime.now().millisecondsSinceEpoch}',
  bookId: widget.bookId,
  language: _language,
  vlmProvider: _vlmProvider,
  llmProvider: _llmProvider,
  status: 'pending',
  scriptJson: '',
  audioDir: '',
  lastPlayedLine: 0,
  lastGeneratedLine: -1,
);
await AppDatabase.instance.insertAudioVersion(version);
if (!context.mounted) return;
context.push('/loading', extra: LoadingParams(
  bookId: widget.bookId,
  versionId: version.versionId,
  filePath: book.filePath,
  language: _language,
  vlmProvider: _vlmProvider,
  llmProvider: _llmProvider,
  isNewBook: false,
  lastGeneratedLine: -1,
));
```

---

## Data Flow

```
UploadScreen._generate()
  → PdfService.pdfToJpegBytes() [page 1 only]
  → File.writeAsBytes() → <appDir>/<bookId>_cover.jpg
  → AppDatabase.updateBookCoverPath()

PlayerScreen
  → playerState.isPlaying
  → KaraokeText(isPlaying: playerState.isPlaying)
  → AnimatedContainer highlight

LibraryScreen / BookDetailScreen
  → book.coverPath != null → Image.file()
  → book.coverPath == null → Icon fallback
```

---

## Error Handling

| Scenario | Behavior |
|---|---|
| PdfService throws during cover extraction | Catch, log, continue — book imports without cover |
| Cover JPEG file missing at display time | `Image.file` error builder shows icon fallback |
| DB migration on existing install | `ALTER TABLE` adds nullable column; existing rows unaffected |
| BookDetail "Add Language" DB insert fails | Propagate error, show snackbar |

---

## Testing

| Test | File | What it verifies |
|---|---|---|
| `KaraokeText` with `isPlaying: true` | `test/widgets/karaoke_text_test.dart` | Amber background and border visible |
| `KaraokeText` with `isPlaying: false` | same | Transparent background |
| `UploadScreen` cover extraction success | `test/screens/upload_screen_test.dart` | `updateBookCoverPath` called with correct path |
| `UploadScreen` cover extraction failure | same | Book inserts, no error thrown, `updateBookCoverPath` not called |
| `LibraryScreen` with cover | `test/screens/library_screen_test.dart` | `Image.file` widget present |
| `LibraryScreen` without cover | same | Fallback icon present |
| `BookDetailScreen` Add Language route | `test/screens/book_detail_screen_test.dart` | Navigates to `/loading` with `LoadingParams` extra |

All 46 existing tests remain green — no breaking interface changes.

---

## Files Changed

| File | Change |
|---|---|
| `lib/db/database.dart` | Version bump, migration, `updateBookCoverPath()`, `Book.coverPath` field |
| `lib/screens/upload_screen.dart` | Cover extraction in `_generate()` |
| `lib/widgets/karaoke_text.dart` | `isPlaying` param + `AnimatedContainer` |
| `lib/screens/player_screen.dart` | Pass `playerState.isPlaying` to `KaraokeText` |
| `lib/screens/library_screen.dart` | Card redesign with cover image |
| `lib/screens/book_detail_screen.dart` | Cover display + Add Language bug fix |
| `test/widgets/karaoke_text_test.dart` | New widget tests |
| `test/screens/upload_screen_test.dart` | Cover extraction tests |
| `test/screens/library_screen_test.dart` | Cover display tests |
| `test/screens/book_detail_screen_test.dart` | Add Language route fix test |
