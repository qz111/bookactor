import 'package:flutter_test/flutter_test.dart';
import 'package:bookactor/models/script.dart';

void main() {
  const scriptJson = '''
{
  "characters": [
    {"name": "Narrator", "voice": "alloy"},
    {"name": "Little Bear", "voice": "nova", "traits": "curious"}
  ],
  "lines": [
    {"index": 0, "character": "Narrator", "text": "Once upon a time", "page": 1, "status": "ready"},
    {"index": 1, "character": "Little Bear", "text": "Hello!", "page": 1, "status": "ready"}
  ]
}
''';

  group('Script', () {
    late Script script;

    setUp(() => script = Script.fromJson(scriptJson));

    test('parses characters correctly', () {
      expect(script.characters.length, 2);
      expect(script.characters[0].name, 'Narrator');
      expect(script.characters[0].voice, 'alloy');
    });

    test('parses lines correctly', () {
      expect(script.lines.length, 2);
      expect(script.lines[1].character, 'Little Bear');
      expect(script.lines[1].page, 1);
      expect(script.lines[1].status, 'ready');
    });

    test('voiceFor returns correct voice', () {
      expect(script.voiceFor('Narrator'), 'alloy');
      expect(script.voiceFor('Little Bear'), 'nova');
    });

    test('voiceFor unknown character defaults to alloy', () {
      expect(script.voiceFor('Unknown'), 'alloy');
    });

    test('toJson/fromJson round-trips', () {
      final restored = Script.fromJson(script.toJson());
      expect(restored.lines.length, script.lines.length);
      expect(restored.characters[0].voice, 'alloy');
    });
  });
}
