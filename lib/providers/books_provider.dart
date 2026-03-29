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

final singleBookProvider =
    FutureProvider.family<Book?, String>((ref, bookId) async {
  return AppDatabase.instance.getBook(bookId);
});

final singleVersionProvider =
    FutureProvider.family<AudioVersion?, String>((ref, versionId) async {
  return AppDatabase.instance.getAudioVersion(versionId);
});
