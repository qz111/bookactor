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
