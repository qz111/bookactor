import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:io';
import 'app.dart';
import 'db/database.dart';
import 'mock/mock_data.dart';
import 'providers/settings_provider.dart';
import 'services/settings_service.dart';

Future<void> _seedMockData() async {
  final db = AppDatabase.instance;
  final existing = await db.getBook('mock_book_001');
  if (existing != null) return;
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

  // Determine initial route before building the widget tree.
  // SettingsService() is constructed once here — safe because flutter_secure_storage
  // has no in-memory state; both this instance and the one in settingsServiceProvider
  // read from the same OS credential store.
  final hasKeys = await SettingsService().hasKeys();

  runApp(ProviderScope(
    overrides: [
      initialLocationProvider.overrideWithValue(hasKeys ? '/' : '/settings'),
    ],
    child: const BookActorApp(),
  ));
}
