import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookactor/models/script.dart';
import 'package:bookactor/providers/player_provider.dart';

const _scriptJson = '''
{
  "characters": [
    {"name": "Narrator", "voice": "alloy"},
    {"name": "Little Bear", "voice": "nova"}
  ],
  "lines": [
    {"index": 0, "character": "Narrator", "text": "Line 0", "page": 1, "status": "ready"},
    {"index": 1, "character": "Little Bear", "text": "Line 1", "page": 1, "status": "error"},
    {"index": 2, "character": "Narrator", "text": "Line 2", "page": 2, "status": "ready"},
    {"index": 3, "character": "Little Bear", "text": "Line 3", "page": 2, "status": "ready"}
  ]
}
''';

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
  });

  tearDown(() {
    container.dispose();
  });

  PlayerNotifier notifier() => container.read(playerProvider.notifier);
  PlayerState state() => container.read(playerProvider);

  group('PlayerNotifier', () {
    test('initial state has no script and line 0', () {
      expect(state().script, isNull);
      expect(state().currentLine, 0);
      expect(state().isPlaying, false);
    });

    test('loadScript sets script and startLine', () {
      final script = Script.fromJson(_scriptJson);
      notifier().loadScript(script, startLine: 2);
      expect(state().script, isNotNull);
      expect(state().currentLine, 2);
      expect(state().isPlaying, false);
    });

    test('play and pause toggle isPlaying', () {
      notifier().loadScript(Script.fromJson(_scriptJson));
      notifier().play();
      expect(state().isPlaying, true);
      notifier().pause();
      expect(state().isPlaying, false);
    });

    test('nextLine advances within ready lines only', () {
      // Ready lines at index 0, 2, 3 — error line at index 1 is skipped
      notifier().loadScript(Script.fromJson(_scriptJson));
      expect(state().currentLine, 0); // ready line 0
      notifier().nextLine();
      expect(state().currentLine, 1); // ready line 1 (which is script index 2)
      notifier().nextLine();
      expect(state().currentLine, 2); // ready line 2 (which is script index 3)
      notifier().nextLine();
      expect(state().currentLine, 2); // already at last ready line, no-op
    });

    test('prevLine decrements and stops at 0', () {
      notifier().loadScript(Script.fromJson(_scriptJson), startLine: 2);
      notifier().prevLine();
      expect(state().currentLine, 1);
      notifier().prevLine();
      expect(state().currentLine, 0);
      notifier().prevLine();
      expect(state().currentLine, 0); // already at 0, no-op
    });

    test('currentScriptLine returns correct ready line', () {
      final script = Script.fromJson(_scriptJson);
      notifier().loadScript(script);
      // currentLine=0 → first ready line = script line index 0 ("Line 0")
      expect(state().currentScriptLine?.text, 'Line 0');
      notifier().nextLine();
      // currentLine=1 → second ready line = script line index 2 ("Line 2", skipping error)
      expect(state().currentScriptLine?.text, 'Line 2');
    });

    test('currentScriptLine returns null when script not loaded', () {
      expect(state().currentScriptLine, isNull);
    });

    test('nextLine is no-op when script is null', () {
      notifier().nextLine(); // should not throw
      expect(state().currentLine, 0);
    });
  });
}
