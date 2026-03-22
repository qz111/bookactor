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
