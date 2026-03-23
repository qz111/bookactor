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

  testWidgets('shows amber highlight when isPlaying is true', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: KaraokeText(
            text: 'Hello',
            character: 'Bunny',
            isPlaying: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final container = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer),
    );
    final decoration = container.decoration as BoxDecoration;
    expect(decoration.color, Colors.amber.withValues(alpha: 0.15));
  });

  testWidgets('shows no highlight when isPlaying is false', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: KaraokeText(
            text: 'Hello',
            character: 'Bunny',
            isPlaying: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final container = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer),
    );
    final decoration = container.decoration as BoxDecoration;
    expect(decoration.color, Colors.transparent);
  });
}
