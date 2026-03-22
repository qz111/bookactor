import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:io';
import 'app.dart';
import 'db/database.dart';
import 'mock/mock_data.dart';

Future<void> _seedMockData() async {
  final db = AppDatabase.instance;
  final existing = await db.getBook('mock_book_001');
  if (existing != null) return; // already seeded
  await db.insertBook(createMockBook());
  await db.insertAudioVersion(createMockAudioVersion());
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  await _seedMockData();
  runApp(const ProviderScope(child: BookActorApp()));
}
