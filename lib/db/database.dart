import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/book.dart';
import '../models/audio_version.dart';

class AppDatabase {
  AppDatabase._(this._isTest);

  static final AppDatabase instance = AppDatabase._(false);
  static AppDatabase forTesting() => AppDatabase._(true);

  Database? _db;
  final bool _isTest;

  Future<void> init() async {
    final path = _isTest
        ? inMemoryDatabasePath
        : join(await getDatabasesPath(), 'bookactor.db');
    _db = await openDatabase(path, version: 1, onCreate: _createDb);
  }

  Future<Database> get database async {
    if (_db == null) await init();
    return _db!;
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  Future<void> _createDb(Database db, int version) async {
    await db.execute('''
      CREATE TABLE books (
        book_id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        cover_path TEXT,
        pages_dir TEXT NOT NULL,
        vlm_output TEXT NOT NULL,
        vlm_provider TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE audio_versions (
        version_id TEXT PRIMARY KEY,
        book_id TEXT NOT NULL,
        language TEXT NOT NULL,
        llm_provider TEXT,
        script_json TEXT NOT NULL,
        audio_dir TEXT NOT NULL,
        status TEXT NOT NULL,
        last_generated_line INTEGER NOT NULL DEFAULT 0,
        last_played_line INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (book_id) REFERENCES books (book_id)
      )
    ''');
  }

  Future<void> insertBook(Book book) async {
    final db = await database;
    await db.insert('books', book.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Updates the vlm_output column for a book after /analyze returns.
  Future<void> updateBookVlmOutput(String bookId, String vlmOutput) async {
    final db = await database;
    await db.update(
      'books',
      {'vlm_output': vlmOutput},
      where: 'book_id = ?',
      whereArgs: [bookId],
    );
  }

  /// Updates the cover_path column for a book after cover extraction on import.
  /// Called after PdfService renders the first PDF page; treat as best-effort
  /// (caller catches failures and continues without cover).
  Future<void> updateBookCoverPath(String bookId, String path) async {
    final db = await database;
    await db.update(
      'books',
      {'cover_path': path},
      where: 'book_id = ?',
      whereArgs: [bookId],
    );
  }

  Future<Book?> getBook(String bookId) async {
    final db = await database;
    final rows =
        await db.query('books', where: 'book_id = ?', whereArgs: [bookId]);
    return rows.isEmpty ? null : Book.fromMap(rows.first);
  }

  Future<List<Book>> getAllBooks() async {
    final db = await database;
    final rows = await db.query('books', orderBy: 'created_at DESC');
    return rows.map(Book.fromMap).toList();
  }

  Future<void> insertAudioVersion(AudioVersion version) async {
    final db = await database;
    await db.insert('audio_versions', version.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<AudioVersion?> getAudioVersion(String versionId) async {
    final db = await database;
    final rows = await db.query('audio_versions',
        where: 'version_id = ?', whereArgs: [versionId]);
    return rows.isEmpty ? null : AudioVersion.fromMap(rows.first);
  }

  Future<List<AudioVersion>> getVersionsForBook(String bookId) async {
    final db = await database;
    final rows = await db
        .query('audio_versions', where: 'book_id = ?', whereArgs: [bookId]);
    return rows.map(AudioVersion.fromMap).toList();
  }

  /// Called after each TTS line result during generation.
  /// Updates status, lastGeneratedLine, and scriptJson atomically.
  Future<void> updateAudioVersionStatus(
    String versionId,
    String status, {
    int? lastGeneratedLine,
    String? scriptJson,
  }) async {
    final db = await database;
    final values = <String, dynamic>{'status': status};
    if (lastGeneratedLine != null) {
      values['last_generated_line'] = lastGeneratedLine;
    }
    if (scriptJson != null) values['script_json'] = scriptJson;
    await db.update('audio_versions', values,
        where: 'version_id = ?', whereArgs: [versionId]);
  }

  /// Called on every line change during playback (not debounced —
  /// SQLite handles this frequency; immediate writes ensure accurate resume on crash).
  Future<void> updateLastPlayedLine(String versionId, int line) async {
    final db = await database;
    await db.update('audio_versions', {'last_played_line': line},
        where: 'version_id = ?', whereArgs: [versionId]);
  }

  /// Returns all versions with status='generating'. Used on cold start
  /// to prompt the user to resume interrupted generation.
  Future<List<AudioVersion>> getGeneratingVersions() async {
    final db = await database;
    final rows = await db.query('audio_versions',
        where: 'status = ?', whereArgs: ['generating']);
    return rows.map(AudioVersion.fromMap).toList();
  }
}
