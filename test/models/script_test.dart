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

  group('ScriptCharacter - Qwen VD schema', () {
    test('fromJson parses voice_prompt and null voice_id', () {
      final char = ScriptCharacter.fromJson({
        'name': 'Bear',
        'voice_prompt': 'A gentle elderly grandfather, warm deep voice',
        'voice_id': null,
      });
      expect(char.name, 'Bear');
      expect(char.voicePrompt, 'A gentle elderly grandfather, warm deep voice');
      expect(char.voiceId, isNull);
      expect(char.voice, isNull);
    });

    test('fromJson parses filled voice_id', () {
      final char = ScriptCharacter.fromJson({
        'name': 'Rabbit',
        'voice_prompt': 'A cheerful young rabbit',
        'voice_id': 'v_rabbit_abc123',
      });
      expect(char.voiceId, 'v_rabbit_abc123');
    });

    test('toJson always emits voice_prompt key even when null', () {
      final char = ScriptCharacter(name: 'Bear', voicePrompt: null, voiceId: null);
      final map = char.toJson();
      expect(map.containsKey('voice_prompt'), isTrue);
      expect(map['voice_prompt'], isNull);
    });

    test('toJson round-trips voice_prompt and voice_id', () {
      final original = ScriptCharacter(
        name: 'Bear',
        voicePrompt: 'A gentle bear',
        voiceId: 'v_bear',
      );
      final restored = ScriptCharacter.fromJson(original.toJson());
      expect(restored.voicePrompt, 'A gentle bear');
      expect(restored.voiceId, 'v_bear');
    });
  });

  group('ScriptCharacter - OpenAI/Gemini schema', () {
    test('fromJson parses voice and traits', () {
      final char = ScriptCharacter.fromJson({
        'name': 'Narrator',
        'voice': 'alloy',
        'traits': 'calm',
      });
      expect(char.voice, 'alloy');
      expect(char.traits, 'calm');
      expect(char.voicePrompt, isNull);
      expect(char.voiceId, isNull);
    });

    test('fromJson old schema without voice_prompt is safe', () {
      final char = ScriptCharacter.fromJson({'name': 'Bear', 'voice': 'echo'});
      expect(char.voice, 'echo');
      expect(char.voicePrompt, isNull);
    });

    test('toJson emits voice_prompt key unconditionally', () {
      // Per spec: voice_prompt key always present in serialised output
      final char = ScriptCharacter(name: 'Narrator', voice: 'alloy');
      expect(char.toJson().containsKey('voice_prompt'), isTrue);
    });
  });

  group('Script.voiceIdFor', () {
    test('returns voice_id when present', () {
      final script = Script.fromJson(
        '{"characters":[{"name":"Bear","voice_prompt":"desc","voice_id":"v_bear"}],"chunks":[]}',
      );
      expect(script.voiceIdFor('Bear'), 'v_bear');
    });

    test('returns null when voice_id is null', () {
      final script = Script.fromJson(
        '{"characters":[{"name":"Bear","voice_prompt":"desc","voice_id":null}],"chunks":[]}',
      );
      expect(script.voiceIdFor('Bear'), isNull);
    });

    test('returns null when character not found', () {
      final script = Script.fromJson('{"characters":[],"chunks":[]}');
      expect(script.voiceIdFor('Unknown'), isNull);
    });
  });

  group('Script.voiceFor', () {
    test('returns voice for OpenAI schema character', () {
      final script = Script.fromJson(
        '{"characters":[{"name":"Narrator","voice":"alloy"}],"chunks":[]}',
      );
      expect(script.voiceFor('Narrator'), 'alloy');
    });

    test('returns alloy default when character not found', () {
      final script = Script.fromJson('{"characters":[],"chunks":[]}');
      expect(script.voiceFor('Unknown'), 'alloy');
    });
  });
}
