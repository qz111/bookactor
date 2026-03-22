# BookActor Phase 2 — Flutter Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build all 5 Flutter app screens with mock data — fully navigable, no live AI calls.

**Architecture:** Flutter app with Riverpod state management, SQLite via sqflite, and go_router navigation. All AI pipeline calls are replaced with mock JSON and simulated delays. The file structure mirrors production exactly — Phase 3 only adds live API calls without restructuring.

**Tech Stack:** Flutter 3.x, flutter_riverpod 2.x, go_router, sqflite, file_picker, pdfx (stub), flutter_test, mocktail

---

## File Map

| File | Responsibility |
|---|---|
| `pubspec.yaml` | All dependencies |
| `lib/main.dart` | Entry point, ProviderScope, mock data seeding |
| `lib/app.dart` | GoRouter config, MaterialApp.router |
| `lib/models/book.dart` | Book data model + SQLite serialization |
| `lib/models/audio_version.dart` | AudioVersion model + SQLite serialization + copyWith |
| `lib/models/script.dart` | Script, ScriptCharacter, ScriptLine — parsed from JSON; `voiceFor()` |
| `lib/db/database.dart` | AppDatabase singleton — all SQLite CRUD |
| `lib/mock/mock_data.dart` | Static mock Book, AudioVersion, supported languages list |
| `lib/providers/books_provider.dart` | FutureProviders for books, versions, single lookups |
| `lib/providers/player_provider.dart` | PlayerState + PlayerNotifier for playback state |
| `lib/screens/library_screen.dart` | Book grid + cold-start resume banner |
| `lib/screens/book_detail_screen.dart` | Per-book language list + new language bottom sheet |
| `lib/screens/upload_screen.dart` | File picker + language/VLM/LLM selectors |
| `lib/screens/loading_screen.dart` | Mock generation steps + error/retry states |
| `lib/screens/player_screen.dart` | Page placeholder + karaoke text + mock timer playback |
| `lib/widgets/book_card.dart` | Book grid tile |
| `lib/widgets/language_badge.dart` | Coloured chip showing language + status |
| `lib/widgets/karaoke_text.dart` | Highlighted current line + character name |
| `lib/widgets/audio_controls.dart` | Prev/pause/next + progress bar |
| `assets/mock/script.json` | Static 7-line mock script |
| `test/models/book_test.dart` | Book toMap/fromMap unit tests |
| `test/models/audio_version_test.dart` | AudioVersion unit tests |
| `test/models/script_test.dart` | Script parsing + voiceFor unit tests |
| `test/db/database_test.dart` | SQLite CRUD integration tests (sqflite_common_ffi) |
| `test/widgets/karaoke_text_test.dart` | KaraokeText widget test |
| `test/screens/library_screen_test.dart` | Library screen widget tests |
| `test/screens/player_screen_test.dart` | PlayerScreen not-found state test |

---

## Task 1: Flutter Project Initialization

**Files:**
- Create: `pubspec.yaml`
- Create: `lib/main.dart`
- Create: `lib/app.dart`
- Create: stub files for all 5 screens

- [ ] **Step 1: Initialize Flutter project**

```bash
cd D:/developer_tools/bookactor
flutter create . --org com.bookactor --project-name bookactor --platforms ios,windows
```

Expected: Flutter project scaffolded. `lib/main.dart` and `test/widget_test.dart` created.

- [ ] **Step 2: Replace pubspec.yaml**

```yaml
name: bookactor
description: Children's AI Audiobook App
publish_to: 'none'
version: 1.0.0+1

environment:
  sdk: '>=3.3.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter
  sqflite: ^2.3.3
  sqflite_common_ffi: ^2.3.3
  path_provider: ^2.1.4
  path: ^1.9.0
  file_picker: ^8.1.2
  pdfx: ^2.6.0
  flutter_riverpod: ^2.5.1
  riverpod_annotation: ^2.3.5
  go_router: ^13.2.0
  uuid: ^4.4.0
  crypto: ^3.0.3

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^4.0.0
  riverpod_generator: ^2.4.0
  build_runner: ^2.4.9
  mocktail: ^1.0.3

flutter:
  uses-material-design: true
  assets:
    - assets/mock/
```

- [ ] **Step 3: Create assets directory**

```bash
mkdir -p assets/mock
```

- [ ] **Step 4: Install dependencies**

```bash
flutter pub get
```

Expected: All packages resolved, no errors.

- [ ] **Step 5: Write lib/main.dart**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'db/database.dart';
import 'mock/mock_data.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _seedMockData();
  runApp(const ProviderScope(child: BookActorApp()));
}

Future<void> _seedMockData() async {
  final db = AppDatabase.instance;
  final existing = await db.getBook('mock_book_001');
  if (existing != null) return;
  await db.insertBook(createMockBook());
  await db.insertAudioVersion(createMockAudioVersion());
}
```

- [ ] **Step 6: Write lib/app.dart**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'screens/library_screen.dart';
import 'screens/book_detail_screen.dart';
import 'screens/upload_screen.dart';
import 'screens/loading_screen.dart';
import 'screens/player_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, __) => const LibraryScreen()),
      GoRoute(
        path: '/book/:bookId',
        builder: (_, state) =>
            BookDetailScreen(bookId: state.pathParameters['bookId']!),
      ),
      GoRoute(path: '/upload', builder: (_, __) => const UploadScreen()),
      GoRoute(
        path: '/loading/:bookId/:language',
        builder: (_, state) => LoadingScreen(
          bookId: state.pathParameters['bookId']!,
          language: state.pathParameters['language']!,
        ),
      ),
      GoRoute(
        path: '/player/:versionId',
        builder: (_, state) =>
            PlayerScreen(versionId: state.pathParameters['versionId']!),
      ),
    ],
  );
});

class BookActorApp extends ConsumerWidget {
  const BookActorApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'BookActor',
      routerConfig: router,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6C63FF)),
        useMaterial3: true,
      ),
    );
  }
}
```

- [ ] **Step 7: Create stub screens so the project compiles**

`lib/screens/library_screen.dart`:
```dart
import 'package:flutter/material.dart';
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('Library')));
}
```

`lib/screens/book_detail_screen.dart`:
```dart
import 'package:flutter/material.dart';
class BookDetailScreen extends StatelessWidget {
  final String bookId;
  const BookDetailScreen({super.key, required this.bookId});
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('Book Detail')));
}
```

`lib/screens/upload_screen.dart`:
```dart
import 'package:flutter/material.dart';
class UploadScreen extends StatelessWidget {
  const UploadScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('Upload')));
}
```

`lib/screens/loading_screen.dart`:
```dart
import 'package:flutter/material.dart';
class LoadingScreen extends StatelessWidget {
  final String bookId;
  final String language;
  const LoadingScreen({super.key, required this.bookId, required this.language});
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('Loading')));
}
```

`lib/screens/player_screen.dart`:
```dart
import 'package:flutter/material.dart';
class PlayerScreen extends StatelessWidget {
  final String versionId;
  const PlayerScreen({super.key, required this.versionId});
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('Player')));
}
```

- [ ] **Step 8: Verify the app compiles and runs**

```bash
flutter run -d windows
```

Expected: App launches showing "Library" text.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "feat: initialize Flutter project with routing skeleton"
```

---

## Task 2: Data Models

**Files:**
- Create: `lib/models/book.dart`
- Create: `lib/models/audio_version.dart`
- Create: `lib/models/script.dart`
- Create: `test/models/book_test.dart`
- Create: `test/models/audio_version_test.dart`
- Create: `test/models/script_test.dart`

- [ ] **Step 1: Write failing tests for Book model**

`test/models/book_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:bookactor/models/book.dart';

void main() {
  group('Book', () {
    final book = Book(
      bookId: 'abc123',
      title: 'Little Bear',
      coverPath: '/path/cover.jpg',
      pagesDir: '/path/pages',
      vlmOutput: '[{"page":1,"text":"Once upon a time"}]',
      vlmProvider: 'gemini',
      createdAt: 1711065600,
    );

    test('toMap produces correct keys', () {
      final map = book.toMap();
      expect(map['book_id'], 'abc123');
      expect(map['title'], 'Little Bear');
      expect(map['vlm_provider'], 'gemini');
    });

    test('fromMap round-trips correctly', () {
      final restored = Book.fromMap(book.toMap());
      expect(restored.bookId, book.bookId);
      expect(restored.title, book.title);
      expect(restored.vlmProvider, book.vlmProvider);
    });
  });
}
```

- [ ] **Step 2: Run test to confirm it fails**

```bash
flutter test test/models/book_test.dart
```

Expected: FAIL — "Target of URI doesn't exist"

- [ ] **Step 3: Implement Book model**

`lib/models/book.dart`:
```dart
class Book {
  final String bookId;
  final String title;
  final String? coverPath;
  final String pagesDir;
  final String vlmOutput;
  final String vlmProvider;
  final int createdAt;

  const Book({
    required this.bookId,
    required this.title,
    this.coverPath,
    required this.pagesDir,
    required this.vlmOutput,
    required this.vlmProvider,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'book_id': bookId,
        'title': title,
        'cover_path': coverPath,
        'pages_dir': pagesDir,
        'vlm_output': vlmOutput,
        'vlm_provider': vlmProvider,
        'created_at': createdAt,
      };

  factory Book.fromMap(Map<String, dynamic> map) => Book(
        bookId: map['book_id'] as String,
        title: map['title'] as String,
        coverPath: map['cover_path'] as String?,
        pagesDir: map['pages_dir'] as String,
        vlmOutput: map['vlm_output'] as String,
        vlmProvider: map['vlm_provider'] as String,
        createdAt: map['created_at'] as int,
      );
}
```

- [ ] **Step 4: Run test to confirm it passes**

```bash
flutter test test/models/book_test.dart
```

Expected: PASS

- [ ] **Step 5: Write failing tests for AudioVersion model**

`test/models/audio_version_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:bookactor/models/audio_version.dart';

void main() {
  group('AudioVersion', () {
    final version = AudioVersion(
      versionId: 'abc123_en',
      bookId: 'abc123',
      language: 'en',
      llmProvider: 'gpt4o',
      scriptJson: '{}',
      audioDir: '/path/audio',
      status: 'ready',
      lastGeneratedLine: 4,
      lastPlayedLine: 2,
      createdAt: 1711065600,
    );

    test('versionId matches book_id + language', () {
      expect(version.versionId, '${version.bookId}_${version.language}');
    });

    test('toMap/fromMap round-trip', () {
      final restored = AudioVersion.fromMap(version.toMap());
      expect(restored.versionId, version.versionId);
      expect(restored.status, version.status);
      expect(restored.lastGeneratedLine, version.lastGeneratedLine);
      expect(restored.lastPlayedLine, version.lastPlayedLine);
    });

    test('copyWith updates only specified fields', () {
      final updated = version.copyWith(status: 'generating', lastGeneratedLine: 2);
      expect(updated.status, 'generating');
      expect(updated.lastGeneratedLine, 2);
      expect(updated.bookId, version.bookId);
    });
  });
}
```

- [ ] **Step 6: Implement AudioVersion model**

`lib/models/audio_version.dart`:
```dart
class AudioVersion {
  final String versionId;
  final String bookId;
  final String language;
  final String? llmProvider;
  final String scriptJson;
  final String audioDir;
  final String status;
  final int lastGeneratedLine;
  final int lastPlayedLine;
  final int createdAt;

  const AudioVersion({
    required this.versionId,
    required this.bookId,
    required this.language,
    this.llmProvider,
    required this.scriptJson,
    required this.audioDir,
    required this.status,
    required this.lastGeneratedLine,
    required this.lastPlayedLine,
    required this.createdAt,
  });

  static String makeVersionId(String bookId, String language) =>
      '${bookId}_$language';

  Map<String, dynamic> toMap() => {
        'version_id': versionId,
        'book_id': bookId,
        'language': language,
        'llm_provider': llmProvider,
        'script_json': scriptJson,
        'audio_dir': audioDir,
        'status': status,
        'last_generated_line': lastGeneratedLine,
        'last_played_line': lastPlayedLine,
        'created_at': createdAt,
      };

  factory AudioVersion.fromMap(Map<String, dynamic> map) => AudioVersion(
        versionId: map['version_id'] as String,
        bookId: map['book_id'] as String,
        language: map['language'] as String,
        llmProvider: map['llm_provider'] as String?,
        scriptJson: map['script_json'] as String,
        audioDir: map['audio_dir'] as String,
        status: map['status'] as String,
        lastGeneratedLine: map['last_generated_line'] as int,
        lastPlayedLine: map['last_played_line'] as int,
        createdAt: map['created_at'] as int,
      );

  AudioVersion copyWith({
    String? status,
    int? lastGeneratedLine,
    int? lastPlayedLine,
    String? scriptJson,
  }) =>
      AudioVersion(
        versionId: versionId,
        bookId: bookId,
        language: language,
        llmProvider: llmProvider,
        scriptJson: scriptJson ?? this.scriptJson,
        audioDir: audioDir,
        status: status ?? this.status,
        lastGeneratedLine: lastGeneratedLine ?? this.lastGeneratedLine,
        lastPlayedLine: lastPlayedLine ?? this.lastPlayedLine,
        createdAt: createdAt,
      );
}
```

- [ ] **Step 7: Run AudioVersion tests**

```bash
flutter test test/models/audio_version_test.dart
```

Expected: PASS

- [ ] **Step 8: Write failing tests for Script model**

`test/models/script_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:bookactor/models/script.dart';

void main() {
  const scriptJson = '''
{
  "characters": [
    {"name": "Narrator", "voice": "alloy"},
    {"name": "Little Bear", "voice": "nova", "traits": "curious"}
  ],
  "lines": [
    {"index": 0, "character": "Narrator", "text": "Once upon a time", "page": 1, "status": "ready"},
    {"index": 1, "character": "Little Bear", "text": "Hello!", "page": 1, "status": "ready"}
  ]
}
''';

  group('Script', () {
    late Script script;

    setUp(() => script = Script.fromJson(scriptJson));

    test('parses characters correctly', () {
      expect(script.characters.length, 2);
      expect(script.characters[0].name, 'Narrator');
      expect(script.characters[0].voice, 'alloy');
    });

    test('parses lines correctly', () {
      expect(script.lines.length, 2);
      expect(script.lines[1].character, 'Little Bear');
      expect(script.lines[1].page, 1);
      expect(script.lines[1].status, 'ready');
    });

    test('voiceFor returns correct voice', () {
      expect(script.voiceFor('Narrator'), 'alloy');
      expect(script.voiceFor('Little Bear'), 'nova');
    });

    test('voiceFor unknown character defaults to alloy', () {
      expect(script.voiceFor('Unknown'), 'alloy');
    });

    test('toJson/fromJson round-trips', () {
      final restored = Script.fromJson(script.toJson());
      expect(restored.lines.length, script.lines.length);
      expect(restored.characters[0].voice, 'alloy');
    });
  });
}
```

- [ ] **Step 9: Implement Script model**

`lib/models/script.dart`:
```dart
import 'dart:convert';

class ScriptCharacter {
  final String name;
  final String voice;
  final String? traits;

  const ScriptCharacter({required this.name, required this.voice, this.traits});

  factory ScriptCharacter.fromJson(Map<String, dynamic> json) =>
      ScriptCharacter(
        name: json['name'] as String,
        voice: json['voice'] as String,
        traits: json['traits'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'voice': voice,
        if (traits != null) 'traits': traits,
      };
}

class ScriptLine {
  final int index;
  final String character;
  final String text;
  final int page;
  final String status;

  const ScriptLine({
    required this.index,
    required this.character,
    required this.text,
    required this.page,
    required this.status,
  });

  factory ScriptLine.fromJson(Map<String, dynamic> json) => ScriptLine(
        index: json['index'] as int,
        character: json['character'] as String,
        text: json['text'] as String,
        page: json['page'] as int,
        status: json['status'] as String,
      );

  Map<String, dynamic> toJson() => {
        'index': index,
        'character': character,
        'text': text,
        'page': page,
        'status': status,
      };

  ScriptLine copyWith({String? status}) => ScriptLine(
        index: index,
        character: character,
        text: text,
        page: page,
        status: status ?? this.status,
      );
}

class Script {
  final List<ScriptCharacter> characters;
  final List<ScriptLine> lines;

  const Script({required this.characters, required this.lines});

  /// Looks up the OpenAI voice for a character by name.
  /// voice is NOT stored on lines — always resolved from this method.
  /// Defaults to 'alloy' if character not found.
  String voiceFor(String characterName) {
    final match =
        characters.where((c) => c.name == characterName).firstOrNull;
    return match?.voice ?? 'alloy';
  }

  factory Script.fromJson(String jsonStr) {
    final map = jsonDecode(jsonStr) as Map<String, dynamic>;
    return Script(
      characters: (map['characters'] as List)
          .map((c) => ScriptCharacter.fromJson(c as Map<String, dynamic>))
          .toList(),
      lines: (map['lines'] as List)
          .map((l) => ScriptLine.fromJson(l as Map<String, dynamic>))
          .toList(),
    );
  }

  String toJson() => jsonEncode({
        'characters': characters.map((c) => c.toJson()).toList(),
        'lines': lines.map((l) => l.toJson()).toList(),
      });
}
```

- [ ] **Step 10: Run all model tests**

```bash
flutter test test/models/
```

Expected: All PASS

- [ ] **Step 11: Commit**

```bash
git add lib/models/ test/models/
git commit -m "feat: add Book, AudioVersion, Script data models with tests"
```

---

## Task 3: SQLite Database Layer

**Files:**
- Create: `lib/db/database.dart`
- Create: `test/db/database_test.dart`

- [ ] **Step 1: Write failing database tests**

`test/db/database_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:bookactor/db/database.dart';
import 'package:bookactor/models/book.dart';
import 'package:bookactor/models/audio_version.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.init();
  });

  tearDown(() async => db.close());

  final testBook = Book(
    bookId: 'test123',
    title: 'Test Book',
    pagesDir: '/test/pages',
    vlmOutput: '[]',
    vlmProvider: 'gemini',
    createdAt: 1711065600,
  );

  final testVersion = AudioVersion(
    versionId: 'test123_en',
    bookId: 'test123',
    language: 'en',
    scriptJson: '{}',
    audioDir: '/test/audio',
    status: 'ready',
    lastGeneratedLine: 4,
    lastPlayedLine: 0,
    createdAt: 1711065600,
  );

  group('Books', () {
    test('insert and retrieve book', () async {
      await db.insertBook(testBook);
      final retrieved = await db.getBook('test123');
      expect(retrieved?.title, 'Test Book');
      expect(retrieved?.vlmProvider, 'gemini');
    });

    test('getAllBooks returns inserted books', () async {
      await db.insertBook(testBook);
      final books = await db.getAllBooks();
      expect(books.length, 1);
    });
  });

  group('AudioVersions', () {
    setUp(() async => db.insertBook(testBook));

    test('insert and retrieve version', () async {
      await db.insertAudioVersion(testVersion);
      final retrieved = await db.getAudioVersion('test123_en');
      expect(retrieved?.language, 'en');
      expect(retrieved?.status, 'ready');
    });

    test('getVersionsForBook returns correct versions', () async {
      await db.insertAudioVersion(testVersion);
      final versions = await db.getVersionsForBook('test123');
      expect(versions.length, 1);
    });

    test('updateLastPlayedLine persists correctly', () async {
      await db.insertAudioVersion(testVersion);
      await db.updateLastPlayedLine('test123_en', 3);
      final updated = await db.getAudioVersion('test123_en');
      expect(updated?.lastPlayedLine, 3);
    });

    test('getGeneratingVersions returns only generating rows', () async {
      final generatingVersion = AudioVersion(
        versionId: 'test123_zh',
        bookId: 'test123',
        language: 'zh',
        scriptJson: '{}',
        audioDir: '',
        status: 'generating',
        lastGeneratedLine: 2,
        lastPlayedLine: 0,
        createdAt: 1711065600,
      );
      await db.insertAudioVersion(testVersion);
      await db.insertAudioVersion(generatingVersion);
      final generating = await db.getGeneratingVersions();
      expect(generating.length, 1);
      expect(generating[0].language, 'zh');
    });
  });
}
```

- [ ] **Step 2: Run test to confirm it fails**

```bash
flutter test test/db/database_test.dart
```

Expected: FAIL — "Target of URI doesn't exist"

- [ ] **Step 3: Implement AppDatabase**

`lib/db/database.dart`:
```dart
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/book.dart';
import '../models/audio_version.dart';

class AppDatabase {
  AppDatabase._();
  AppDatabase._testing() : _isTest = true;

  static final AppDatabase instance = AppDatabase._();
  static AppDatabase forTesting() => AppDatabase._testing();

  Database? _db;
  final bool _isTest = false;

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

  Future<void> close() async => _db?.close();

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
```

- [ ] **Step 4: Run database tests**

```bash
flutter test test/db/database_test.dart
```

Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add lib/db/ test/db/
git commit -m "feat: add SQLite database layer with CRUD for books and audio_versions"
```

---

## Task 4: Mock Data & Assets

**Files:**
- Create: `assets/mock/script.json`
- Create: `lib/mock/mock_data.dart`

- [ ] **Step 1: Create mock script JSON asset**

`assets/mock/script.json`:
```json
{
  "characters": [
    {"name": "Narrator", "voice": "alloy"},
    {"name": "Little Bear", "voice": "nova", "traits": "curious, playful"},
    {"name": "Mother Bear", "voice": "shimmer", "traits": "warm, gentle"}
  ],
  "lines": [
    {"index": 0, "character": "Narrator", "text": "Once upon a time, in a cozy little den...", "page": 1, "status": "ready"},
    {"index": 1, "character": "Little Bear", "text": "Good morning, Mama!", "page": 1, "status": "ready"},
    {"index": 2, "character": "Mother Bear", "text": "Good morning, my little one. Did you sleep well?", "page": 2, "status": "ready"},
    {"index": 3, "character": "Narrator", "text": "Little Bear looked out the window and saw the world covered in snow.", "page": 2, "status": "ready"},
    {"index": 4, "character": "Little Bear", "text": "Mama, can we go play outside? Please?", "page": 3, "status": "ready"},
    {"index": 5, "character": "Mother Bear", "text": "After breakfast, my dear.", "page": 3, "status": "ready"},
    {"index": 6, "character": "Narrator", "text": "And so they had a warm breakfast together before their snowy adventure.", "page": 4, "status": "ready"}
  ]
}
```

- [ ] **Step 2: Create lib/mock/mock_data.dart**

```dart
import '../models/book.dart';
import '../models/audio_version.dart';

Book createMockBook() => const Book(
      bookId: 'mock_book_001',
      title: 'Little Bear',
      pagesDir: '',
      vlmOutput: '[]',
      vlmProvider: 'gemini',
      createdAt: 1711065600,
    );

AudioVersion createMockAudioVersion() => const AudioVersion(
      versionId: 'mock_book_001_en',
      bookId: 'mock_book_001',
      language: 'en',
      llmProvider: 'gpt4o',
      scriptJson: '',  // loaded from assets/mock/script.json at runtime
      audioDir: '',
      status: 'ready',
      lastGeneratedLine: 6,
      lastPlayedLine: 0,
      createdAt: 1711065600,
    );

/// BCP 47 language codes with display names shown in dropdowns.
const supportedLanguages = [
  {'code': 'en', 'name': 'English'},
  {'code': 'zh', 'name': 'Chinese (Simplified)'},
  {'code': 'zh-TW', 'name': 'Chinese (Traditional)'},
  {'code': 'fr', 'name': 'French'},
  {'code': 'es', 'name': 'Spanish'},
  {'code': 'de', 'name': 'German'},
  {'code': 'ja', 'name': 'Japanese'},
  {'code': 'ko', 'name': 'Korean'},
];
```

- [ ] **Step 3: Commit**

```bash
git add assets/mock/ lib/mock/
git commit -m "feat: add mock script asset and mock data factory"
```

---

## Task 5: Riverpod Providers

**Files:**
- Create: `lib/providers/books_provider.dart`
- Create: `lib/providers/player_provider.dart`

- [ ] **Step 1: Implement books_provider.dart**

`lib/providers/books_provider.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../db/database.dart';
import '../models/book.dart';
import '../models/audio_version.dart';

final booksProvider = FutureProvider<List<Book>>((ref) async {
  return AppDatabase.instance.getAllBooks();
});

final audioVersionsProvider =
    FutureProvider.family<List<AudioVersion>, String>((ref, bookId) async {
  return AppDatabase.instance.getVersionsForBook(bookId);
});

final generatingVersionsProvider =
    FutureProvider<List<AudioVersion>>((ref) async {
  return AppDatabase.instance.getGeneratingVersions();
});

final singleBookProvider =
    FutureProvider.family<Book?, String>((ref, bookId) async {
  return AppDatabase.instance.getBook(bookId);
});

final singleVersionProvider =
    FutureProvider.family<AudioVersion?, String>((ref, versionId) async {
  return AppDatabase.instance.getAudioVersion(versionId);
});
```

- [ ] **Step 2: Implement player_provider.dart**

`lib/providers/player_provider.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/script.dart';

class PlayerState {
  final Script? script;
  final int currentLine;
  final bool isPlaying;

  const PlayerState({
    this.script,
    this.currentLine = 0,
    this.isPlaying = false,
  });

  PlayerState copyWith({Script? script, int? currentLine, bool? isPlaying}) =>
      PlayerState(
        script: script ?? this.script,
        currentLine: currentLine ?? this.currentLine,
        isPlaying: isPlaying ?? this.isPlaying,
      );

  /// Returns the current ready line, or null if script not loaded or done.
  ScriptLine? get currentScriptLine {
    if (script == null) return null;
    final readyLines =
        script!.lines.where((l) => l.status == 'ready').toList();
    if (currentLine >= readyLines.length) return null;
    return readyLines[currentLine];
  }
}

class PlayerNotifier extends Notifier<PlayerState> {
  @override
  PlayerState build() => const PlayerState();

  void loadScript(Script script, {int startLine = 0}) {
    state = PlayerState(script: script, currentLine: startLine);
  }

  void play() => state = state.copyWith(isPlaying: true);
  void pause() => state = state.copyWith(isPlaying: false);

  void nextLine() {
    if (script == null) return;
    final readyCount =
        state.script!.lines.where((l) => l.status == 'ready').length;
    if (state.currentLine < readyCount - 1) {
      state = state.copyWith(currentLine: state.currentLine + 1);
    }
  }

  void prevLine() {
    if (state.currentLine > 0) {
      state = state.copyWith(currentLine: state.currentLine - 1);
    }
  }

  Script? get script => state.script;
}

final playerProvider =
    NotifierProvider<PlayerNotifier, PlayerState>(PlayerNotifier.new);
```

- [ ] **Step 3: Commit**

```bash
git add lib/providers/
git commit -m "feat: add Riverpod providers for books list and player state"
```

---

## Task 6: Library Screen

**Files:**
- Create: `lib/widgets/book_card.dart`
- Create: `lib/widgets/language_badge.dart`
- Modify: `lib/screens/library_screen.dart`
- Create: `test/screens/library_screen_test.dart`

- [ ] **Step 1: Write failing widget tests**

`test/screens/library_screen_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bookactor/models/book.dart';
import 'package:bookactor/models/audio_version.dart';
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
}
```

- [ ] **Step 2: Run test to confirm it fails**

```bash
flutter test test/screens/library_screen_test.dart
```

Expected: FAIL

- [ ] **Step 3: Implement BookCard widget**

`lib/widgets/book_card.dart`:
```dart
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
              child: Container(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: const Center(child: Icon(Icons.menu_book, size: 48)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(book.title,
                      style: Theme.of(context).textTheme.titleSmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(
                      '$languageCount language${languageCount != 1 ? 's' : ''}',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Implement LanguageBadge widget**

`lib/widgets/language_badge.dart`:
```dart
import 'package:flutter/material.dart';

class LanguageBadge extends StatelessWidget {
  final String language;
  final String status;

  const LanguageBadge(
      {super.key, required this.language, required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'ready' => Colors.green,
      'generating' => Colors.orange,
      'error' => Colors.red,
      _ => Colors.grey,
    };
    return Chip(
      label: Text(language.toUpperCase()),
      side: BorderSide(color: color),
      backgroundColor: color.withOpacity(0.1),
      labelStyle: TextStyle(color: color, fontSize: 11),
      padding: EdgeInsets.zero,
    );
  }
}
```

- [ ] **Step 5: Implement LibraryScreen**

`lib/screens/library_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/books_provider.dart';
import '../widgets/book_card.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final booksAsync = ref.watch(booksProvider);
    final generatingAsync = ref.watch(generatingVersionsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My Books')),
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
                    onPressed: () {
                      for (final v in versions) {
                        context.push('/loading/${v.bookId}/${v.language}');
                      }
                    },
                    child: const Text('Resume'),
                  ),
                  TextButton(
                    onPressed: () {
                      // Phase 3: mark as error in DB
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
                        return BookCard(
                          book: book,
                          languageCount: versionsAsync.value?.length ?? 0,
                          onTap: () =>
                              context.push('/book/${book.bookId}'),
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

- [ ] **Step 6: Run library screen tests**

```bash
flutter test test/screens/library_screen_test.dart
```

Expected: PASS

- [ ] **Step 7: Run app and verify Library screen shows mock book**

```bash
flutter run -d windows
```

Expected: "Little Bear" card visible in grid, "Add Book" FAB present.

- [ ] **Step 8: Commit**

```bash
git add lib/screens/library_screen.dart lib/widgets/book_card.dart lib/widgets/language_badge.dart test/screens/
git commit -m "feat: implement Library screen with book grid and cold-start resume banner"
```

---

## Task 7: Book Detail Screen

**Files:**
- Modify: `lib/screens/book_detail_screen.dart`

- [ ] **Step 1: Implement BookDetailScreen**

`lib/screens/book_detail_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/books_provider.dart';
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
              Container(
                height: 200,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(child: Icon(Icons.menu_book, size: 72)),
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
                                  onPressed: () => context
                                      .push('/player/${v.versionId}'),
                                )
                              : null,
                        )),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () =>
                          _showNewLanguageSheet(context, bookId),
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

  String _languageName(String code) => const {
        'en': 'English',
        'zh': 'Chinese (Simplified)',
        'zh-TW': 'Chinese (Traditional)',
        'fr': 'French',
        'es': 'Spanish',
        'de': 'German',
        'ja': 'Japanese',
        'ko': 'Korean',
      }[code] ??
      code;

  void _showNewLanguageSheet(BuildContext context, String bookId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _NewLanguageSheet(bookId: bookId),
    );
  }
}

class _NewLanguageSheet extends StatefulWidget {
  final String bookId;
  const _NewLanguageSheet({required this.bookId});

  @override
  State<_NewLanguageSheet> createState() => _NewLanguageSheetState();
}

class _NewLanguageSheetState extends State<_NewLanguageSheet> {
  String _language = 'zh';
  String _llmProvider = 'gpt4o';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
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
            items: const [
              DropdownMenuItem(value: 'zh', child: Text('Chinese (Simplified)')),
              DropdownMenuItem(value: 'zh-TW', child: Text('Chinese (Traditional)')),
              DropdownMenuItem(value: 'fr', child: Text('French')),
              DropdownMenuItem(value: 'es', child: Text('Spanish')),
              DropdownMenuItem(value: 'de', child: Text('German')),
              DropdownMenuItem(value: 'ja', child: Text('Japanese')),
              DropdownMenuItem(value: 'ko', child: Text('Korean')),
            ],
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
              onPressed: () {
                Navigator.pop(context);
                context.push('/loading/${widget.bookId}/$_language');
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

- [ ] **Step 2: Run app and verify Library → Book Detail navigation**

```bash
flutter run -d windows
```

Expected: Tap "Little Bear" → Book Detail shows cover, title, "English (ready)" with play button.

- [ ] **Step 3: Commit**

```bash
git add lib/screens/book_detail_screen.dart
git commit -m "feat: implement Book Detail screen with language list and new language sheet"
```

---

## Task 8: Upload Screen

**Files:**
- Modify: `lib/screens/upload_screen.dart`

- [ ] **Step 1: Implement UploadScreen**

`lib/screens/upload_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../mock/mock_data.dart';

class UploadScreen extends ConsumerStatefulWidget {
  const UploadScreen({super.key});

  @override
  ConsumerState<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends ConsumerState<UploadScreen> {
  String? _selectedFileName;
  String _language = 'en';
  String _vlmProvider = 'gemini';
  String _llmProvider = 'gpt4o';

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
    );
    if (result != null) {
      setState(() => _selectedFileName = result.files.single.name);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Book')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          GestureDetector(
            onTap: _pickFile,
            child: Container(
              height: 140,
              decoration: BoxDecoration(
                border: Border.all(
                    color: Theme.of(context).colorScheme.primary, width: 2),
                borderRadius: BorderRadius.circular(12),
                color: Theme.of(context)
                    .colorScheme
                    .primaryContainer
                    .withOpacity(0.3),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.upload_file, size: 40),
                    const SizedBox(height: 8),
                    Text(_selectedFileName ?? 'Tap to select PDF or images'),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          DropdownButtonFormField<String>(
            value: _language,
            decoration: const InputDecoration(
                labelText: 'Audio Language', border: OutlineInputBorder()),
            items: supportedLanguages
                .map((l) => DropdownMenuItem(
                    value: l['code'], child: Text(l['name']!)))
                .toList(),
            onChanged: (v) => setState(() => _language = v!),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _vlmProvider,
            decoration: const InputDecoration(
                labelText: 'Vision Model (VLM)', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'gemini', child: Text('Gemini Vision')),
              DropdownMenuItem(value: 'gpt4o', child: Text('GPT-4o Vision')),
            ],
            onChanged: (v) => setState(() => _vlmProvider = v!),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _llmProvider,
            decoration: const InputDecoration(
                labelText: 'Language Model (LLM)',
                border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'gpt4o', child: Text('GPT-4o')),
              DropdownMenuItem(value: 'gemini', child: Text('Gemini')),
            ],
            onChanged: (v) => setState(() => _llmProvider = v!),
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            // Phase 2: always uses mock book ID; Phase 3 will hash the real file
            onPressed: _selectedFileName == null
                ? null
                : () => context.push('/loading/mock_book_001/$_language'),
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Generate Audiobook'),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Run app and verify Upload screen**

```bash
flutter run -d windows
```

Expected: Tap "Add Book" → Upload screen renders with file picker area, 3 dropdowns, disabled Generate button. Selecting a file enables the button.

- [ ] **Step 3: Commit**

```bash
git add lib/screens/upload_screen.dart
git commit -m "feat: implement Upload screen with file picker and provider selectors"
```

---

## Task 9: Loading Screen

**Files:**
- Modify: `lib/screens/loading_screen.dart`

- [ ] **Step 1: Implement LoadingScreen with mock pipeline**

`lib/screens/loading_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class LoadingScreen extends StatefulWidget {
  final String bookId;
  final String language;

  const LoadingScreen(
      {super.key, required this.bookId, required this.language});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen> {
  int _step = 0; // 0=not started, 1=reading done, 2=scripting done, 3=done
  bool _hasError = false;

  static const _steps = [
    (icon: '📖', label: 'Reading pages...'),
    (icon: '✍️', label: 'Writing script...'),
    (icon: '🎙️', label: 'Recording voices...'),
  ];

  @override
  void initState() {
    super.initState();
    _runMockPipeline();
  }

  Future<void> _runMockPipeline() async {
    for (int i = 0; i < _steps.length; i++) {
      await Future.delayed(const Duration(milliseconds: 1200));
      if (!mounted) return;
      setState(() => _step = i + 1);
    }
    if (!mounted) return;
    // Phase 2: always navigates to mock English version
    context.go('/player/mock_book_001_en');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: _hasError ? _buildError() : _buildProgress(),
        ),
      ),
    );
  }

  Widget _buildProgress() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('✨', style: TextStyle(fontSize: 64)),
        const SizedBox(height: 24),
        Text('Creating your audiobook...',
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center),
        const SizedBox(height: 40),
        ..._steps.asMap().entries.map((entry) {
          final i = entry.key;
          final step = entry.value;
          final isDone = _step > i;
          final isCurrent = _step == i;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 32,
                  child: isCurrent
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child:
                              CircularProgressIndicator(strokeWidth: 2))
                      : Icon(
                          isDone
                              ? Icons.check_circle
                              : Icons.circle_outlined,
                          color: isDone ? Colors.green : Colors.grey),
                ),
                const SizedBox(width: 12),
                Text(
                  '${step.icon} ${step.label}',
                  style: TextStyle(
                    color: isDone
                        ? Colors.green
                        : (isCurrent ? null : Colors.grey),
                    fontWeight: isCurrent ? FontWeight.bold : null,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  /// Shown for recoverable errors (network drop, API timeout).
  /// Fatal errors (VLM fail, LLM malformed output after 1 retry) use context.pop() instead.
  Widget _buildError() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.error_outline, size: 64, color: Colors.red),
        const SizedBox(height: 16),
        const Text('Something went wrong',
            style: TextStyle(fontSize: 20)),
        const SizedBox(height: 8),
        const Text('Your progress was saved.',
            style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () {
            setState(() {
              _step = 0;
              _hasError = false;
            });
            _runMockPipeline();
          },
          child: const Text('Try Again'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () => context.pop(),
          child: const Text('Go Back'),
        ),
      ],
    );
  }
}
```

- [ ] **Step 2: Run app and verify loading animation**

```bash
flutter run -d windows
```

Expected: Upload → select file → Generate → Loading screen animates through 3 steps with checkmarks → navigates to Player.

- [ ] **Step 3: Commit**

```bash
git add lib/screens/loading_screen.dart
git commit -m "feat: implement Loading screen with mock generation animation and error states"
```

---

## Task 10: Player Screen

**Files:**
- Create: `lib/widgets/karaoke_text.dart`
- Create: `lib/widgets/audio_controls.dart`
- Modify: `lib/screens/player_screen.dart`
- Create: `test/widgets/karaoke_text_test.dart`
- Create: `test/screens/player_screen_test.dart`

- [ ] **Step 1: Write failing KaraokeText test**

`test/widgets/karaoke_text_test.dart`:
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
}
```

- [ ] **Step 2: Run test to confirm it fails**

```bash
flutter test test/widgets/karaoke_text_test.dart
```

Expected: FAIL

- [ ] **Step 3: Implement KaraokeText widget**

`lib/widgets/karaoke_text.dart`:
```dart
import 'package:flutter/material.dart';

class KaraokeText extends StatelessWidget {
  final String text;
  final String character;

  const KaraokeText({super.key, required this.text, required this.character});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            character,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Text(text,
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run KaraokeText test**

```bash
flutter test test/widgets/karaoke_text_test.dart
```

Expected: PASS

- [ ] **Step 5: Implement AudioControls widget**

`lib/widgets/audio_controls.dart`:
```dart
import 'package:flutter/material.dart';

class AudioControls extends StatelessWidget {
  final bool isPlaying;
  final int currentLine;
  final int totalLines;
  final VoidCallback onPlay;
  final VoidCallback onPause;
  final VoidCallback onNext;
  final VoidCallback onPrev;

  const AudioControls({
    super.key,
    required this.isPlaying,
    required this.currentLine,
    required this.totalLines,
    required this.onPlay,
    required this.onPause,
    required this.onNext,
    required this.onPrev,
  });

  @override
  Widget build(BuildContext context) {
    final progress = totalLines > 0 ? (currentLine + 1) / totalLines : 0.0;
    return Column(
      children: [
        LinearProgressIndicator(value: progress),
        const SizedBox(height: 8),
        Text('${currentLine + 1} / $totalLines',
            style: Theme.of(context).textTheme.bodySmall),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
                iconSize: 36,
                onPressed: onPrev,
                icon: const Icon(Icons.skip_previous)),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: isPlaying ? onPause : onPlay,
              child: Icon(isPlaying ? Icons.pause : Icons.play_arrow,
                  size: 32),
            ),
            const SizedBox(width: 8),
            IconButton(
                iconSize: 36,
                onPressed: onNext,
                icon: const Icon(Icons.skip_next)),
          ],
        ),
      ],
    );
  }
}
```

- [ ] **Step 6: Write failing PlayerScreen test**

`test/screens/player_screen_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bookactor/providers/books_provider.dart';
import 'package:bookactor/screens/player_screen.dart';

void main() {
  testWidgets('shows not-found message for unknown versionId', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          singleVersionProvider('bad_id').overrideWith((_) async => null),
        ],
        child: const MaterialApp(home: PlayerScreen(versionId: 'bad_id')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Version not found'), findsOneWidget);
  });
}
```

- [ ] **Step 7: Implement PlayerScreen**

`lib/screens/player_screen.dart`:
```dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../db/database.dart';
import '../models/script.dart';
import '../providers/books_provider.dart';
import '../providers/player_provider.dart';
import '../widgets/karaoke_text.dart';
import '../widgets/audio_controls.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  final String versionId;
  const PlayerScreen({super.key, required this.versionId});

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  Timer? _mockTimer;

  @override
  void initState() {
    super.initState();
    _loadScript();
  }

  Future<void> _loadScript() async {
    // Phase 2: mock version loads from asset; real versions load from DB
    final String scriptJson;
    if (widget.versionId == 'mock_book_001_en') {
      scriptJson =
          await rootBundle.loadString('assets/mock/script.json');
    } else {
      final version =
          await AppDatabase.instance.getAudioVersion(widget.versionId);
      if (version == null || !mounted) return;
      scriptJson = version.scriptJson;
    }

    final script = Script.fromJson(scriptJson);
    final version =
        await AppDatabase.instance.getAudioVersion(widget.versionId);
    final startLine = version?.lastPlayedLine ?? 0;
    if (!mounted) return;
    ref
        .read(playerProvider.notifier)
        .loadScript(script, startLine: startLine);
  }

  void _startMockPlayback() {
    _mockTimer?.cancel();
    _mockTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      final state = ref.read(playerProvider);
      if (!state.isPlaying) return;
      final readyCount =
          state.script?.lines.where((l) => l.status == 'ready').length ?? 0;
      if (state.currentLine < readyCount - 1) {
        ref.read(playerProvider.notifier).nextLine();
        _saveProgress(state.currentLine + 1);
      } else {
        ref.read(playerProvider.notifier).pause();
        _mockTimer?.cancel();
      }
    });
  }

  void _saveProgress(int line) {
    AppDatabase.instance.updateLastPlayedLine(widget.versionId, line);
  }

  @override
  void dispose() {
    _mockTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final versionAsync = ref.watch(singleVersionProvider(widget.versionId));
    final playerState = ref.watch(playerProvider);

    return versionAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) =>
          Scaffold(body: Center(child: Text('Error: $e'))),
      data: (version) {
        if (version == null) {
          return const Scaffold(
              body: Center(child: Text('Version not found')));
        }

        final line = playerState.currentScriptLine;
        final readyLines = playerState.script?.lines
                .where((l) => l.status == 'ready')
                .toList() ??
            [];

        return Scaffold(
          appBar: AppBar(title: Text(version.language.toUpperCase())),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Page image placeholder (Phase 3 will show real page images)
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(
                      child: Text(
                        'Page ${line?.page ?? 1}',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (line != null)
                  KaraokeText(
                      text: line.text, character: line.character),
                const SizedBox(height: 24),
                AudioControls(
                  isPlaying: playerState.isPlaying,
                  currentLine: playerState.currentLine,
                  totalLines: readyLines.length,
                  onPlay: () {
                    ref.read(playerProvider.notifier).play();
                    _startMockPlayback();
                  },
                  onPause: () {
                    ref.read(playerProvider.notifier).pause();
                    _mockTimer?.cancel();
                  },
                  onNext: () {
                    ref.read(playerProvider.notifier).nextLine();
                    _saveProgress(playerState.currentLine + 1);
                  },
                  onPrev: () =>
                      ref.read(playerProvider.notifier).prevLine(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
```

- [ ] **Step 8: Run all tests**

```bash
flutter test
```

Expected: All tests PASS

- [ ] **Step 9: Run app and verify full end-to-end flow**

```bash
flutter run -d windows
```

Verify:
1. Library → "Little Bear" card visible
2. Tap card → Book Detail with English (ready) + play button
3. Tap play → Player shows "Page 1", "Once upon a time...", Narrator
4. Tap play button → lines advance every 3 seconds, page number updates
5. Prev/Next skip lines correctly
6. "Add Book" FAB → Upload screen → select file → Generate button enables
7. Generate → Loading animates 3 steps → Player opens

- [ ] **Step 10: Commit**

```bash
git add lib/screens/player_screen.dart lib/widgets/karaoke_text.dart lib/widgets/audio_controls.dart test/screens/player_screen_test.dart test/widgets/karaoke_text_test.dart
git commit -m "feat: implement Player screen with mock timer playback and karaoke text"
```

---

## Task 11: Final Checks

- [ ] **Step 1: Run full test suite**

```bash
flutter test --reporter expanded
```

Expected: All tests PASS, no failures.

- [ ] **Step 2: Run static analysis**

```bash
flutter analyze
```

Expected: No errors. Warnings about deprecated APIs are OK.

- [ ] **Step 3: Final commit**

```bash
git add -A
git commit -m "chore: phase 2 complete — Flutter foundation with mock UI, all tests passing"
```
