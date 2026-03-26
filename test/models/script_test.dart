import 'package:flutter_test/flutter_test.dart';
import 'package:bookactor/models/script.dart';

void main() {
  const scriptJson = '''
{
  "characters": [
    {"name": "Narrator", "voice": "Aoede"},
    {"name": "Bear", "voice": "Charon", "traits": "deep"}
  ],
  "chunks": [
    {
      "index": 0,
      "text": "Narrator: Hello.\\nBear: Hi!",
      "speakers": ["Narrator", "Bear"],
      "duration_ms": 5000,
      "status": "ready"
    },
    {
      "index": 1,
      "text": "Narrator: The end.",
      "speakers": ["Narrator"],
      "duration_ms": 2000,
      "status": "pending"
    }
  ]
}
''';

  group('Script', () {
    late Script script;
    setUp(() => script = Script.fromJson(scriptJson));

    test('parses characters', () {
      expect(script.characters.length, 2);
      expect(script.characters[0].name, 'Narrator');
      expect(script.characters[0].voice, 'Aoede');
    });

    test('parses chunks', () {
      expect(script.chunks.length, 2);
      expect(script.chunks[0].index, 0);
      expect(script.chunks[0].speakers, ['Narrator', 'Bear']);
      expect(script.chunks[0].durationMs, 5000);
      expect(script.chunks[0].status, 'ready');
    });

    test('voiceFor returns correct voice', () {
      expect(script.voiceFor('Narrator'), 'Aoede');
      expect(script.voiceFor('Bear'), 'Charon');
    });

    test('voiceFor unknown defaults to alloy', () {
      expect(script.voiceFor('Unknown'), 'alloy');
    });

    test('toJson/fromJson round-trips', () {
      final restored = Script.fromJson(script.toJson());
      expect(restored.chunks.length, 2);
      expect(restored.chunks[0].durationMs, 5000);
      expect(restored.characters[0].voice, 'Aoede');
    });

    test('ScriptChunk.copyWith updates status', () {
      final updated = script.chunks[1].copyWith(status: 'ready', durationMs: 3000);
      expect(updated.status, 'ready');
      expect(updated.durationMs, 3000);
      expect(updated.index, 1);
    });
  });
}
