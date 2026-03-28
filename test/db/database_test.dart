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

  const testBook = Book(
    bookId: 'test123',
    title: 'Test Book',
    pagesDir: '/test/pages',
    vlmOutput: '[]',
    vlmProvider: 'gemini',
    createdAt: 1711065600,
  );

  const testVersion = AudioVersion(
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

    test('updateBookCoverPath persists cover_path for existing book', () async {
      await db.insertBook(testBook);
      await db.updateBookCoverPath('test123', '/app/docs/test123_cover.jpg');
      final updated = await db.getBook('test123');
      expect(updated?.coverPath, '/app/docs/test123_cover.jpg');
    });

    test('updateBookVlmOutput updates vlm_output for existing book', () async {
      final db = AppDatabase.forTesting();
      await db.init();
      await db.insertBook(const Book(
        bookId: 'book_test_vlm',
        title: 'Test',
        coverPath: null,
        pagesDir: '/tmp/pages',
        vlmOutput: '[]',
        vlmProvider: 'gemini',
        createdAt: 1000,
      ));

      await db.updateBookVlmOutput('book_test_vlm', '[{"page":1,"text":"Hello"}]');

      final updated = await db.getBook('book_test_vlm');
      expect(updated!.vlmOutput, '[{"page":1,"text":"Hello"}]');
      await db.close();
    });

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

    test('deleteBook and deleteAudioVersion each remove their respective rows', () async {
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

    test('updateAudioVersionStatus persists status and optional fields', () async {
      await db.insertAudioVersion(testVersion);

      // status only
      await db.updateAudioVersionStatus('test123_en', 'generating');
      var updated = await db.getAudioVersion('test123_en');
      expect(updated?.status, 'generating');
      expect(updated?.lastGeneratedLine, 4); // unchanged

      // status + lastGeneratedLine
      await db.updateAudioVersionStatus('test123_en', 'generating',
          lastGeneratedLine: 5);
      updated = await db.getAudioVersion('test123_en');
      expect(updated?.lastGeneratedLine, 5);

      // status + scriptJson
      await db.updateAudioVersionStatus('test123_en', 'ready',
          scriptJson: '{"updated":true}');
      updated = await db.getAudioVersion('test123_en');
      expect(updated?.status, 'ready');
      expect(updated?.scriptJson, '{"updated":true}');
    });

    test('getGeneratingVersions returns only generating rows', () async {
      const generatingVersion = AudioVersion(
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

    test('deleteAudioVersion removes the row', () async {
      await db.insertAudioVersion(testVersion);

      // Verify it exists
      final before = await db.getAudioVersion('test123_en');
      expect(before, isNotNull);

      await db.deleteAudioVersion('test123_en');

      final after = await db.getAudioVersion('test123_en');
      expect(after, isNull);
    });

    test('deleteAudioVersion on missing id is a no-op', () async {
      // Should not throw
      await expectLater(
        db.deleteAudioVersion('nonexistent_id'),
        completes,
      );
    });
  });
}
