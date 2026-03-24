import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookactor/screens/upload_screen.dart';

void main() {
  testWidgets('UploadScreen shows ReorderableListView when images are selected',
      (tester) async {
    // Create temp image files the widget can reference
    final tempDir = Directory.systemTemp.createTempSync('bookactor_ui_');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final img1 = File('${tempDir.path}/page1.png')
      ..writeAsBytesSync([137, 80, 78, 71]); // PNG magic bytes
    final img2 = File('${tempDir.path}/page2.png')
      ..writeAsBytesSync([137, 80, 78, 71]);

    // Build UploadScreen with pre-seeded image paths using the test constructor
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: UploadScreen.withImages(initialImagePaths: [img1.path, img2.path]),
        ),
      ),
    );
    await tester.pump();

    // ReorderableListView should be present
    expect(find.byType(ReorderableListView), findsOneWidget);
    // "Add more images" button should be visible
    expect(find.text('Add more images'), findsOneWidget);
    // Should NOT show the "Tap to select PDF or images" placeholder
    expect(find.text('Tap to select PDF or images'), findsNothing);
    // Page number badges should be visible
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    // Delete buttons should be present
    expect(find.byIcon(Icons.delete_outline), findsNWidgets(2));
  });

  testWidgets('UploadScreen renders without error in default state',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: UploadScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Tap to select PDF or images'), findsOneWidget);
    expect(find.byType(ReorderableListView), findsNothing);
  });
}
