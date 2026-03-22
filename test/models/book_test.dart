import 'package:flutter_test/flutter_test.dart';
import 'package:bookactor/models/book.dart';

void main() {
  group('Book', () {
    final book = const Book(
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
