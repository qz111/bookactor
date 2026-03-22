import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:bookactor/providers/books_provider.dart';
import 'package:bookactor/screens/player_screen.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

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
