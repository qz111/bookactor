import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookactor/models/script.dart';
import 'package:bookactor/providers/player_provider.dart';

const _scriptJson = '''
{
  "characters": [
    {"name": "Narrator", "voice": "Aoede"},
    {"name": "Bear", "voice": "Charon"}
  ],
  "chunks": [
    {"index": 0, "text": "Narrator: A.", "speakers": ["Narrator"], "duration_ms": 3000, "status": "ready"},
    {"index": 1, "text": "Bear: B.", "speakers": ["Bear"], "duration_ms": 0, "status": "error"},
    {"index": 2, "text": "Narrator: C.", "speakers": ["Narrator"], "duration_ms": 4000, "status": "ready"},
    {"index": 3, "text": "Bear: D.", "speakers": ["Bear"], "duration_ms": 2000, "status": "ready"}
  ]
}
''';

void main() {
  late ProviderContainer container;
  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  PlayerNotifier notifier() => container.read(playerProvider.notifier);
  PlayerState state() => container.read(playerProvider);

  group('PlayerNotifier', () {
    test('initial state has no script and chunk 0', () {
      expect(state().script, isNull);
      expect(state().currentChunkIndex, 0);
      expect(state().isPlaying, false);
    });

    test('loadScript sets script and startChunk', () {
      notifier().loadScript(Script.fromJson(_scriptJson), startChunk: 1);
      expect(state().script, isNotNull);
      expect(state().currentChunkIndex, 1);
    });

    test('readyChunks filters by status', () {
      notifier().loadScript(Script.fromJson(_scriptJson));
      // chunk index 1 has status error — only 3 ready
      expect(state().readyChunks.length, 3);
    });

    test('totalDurationMs sums ready chunk durations', () {
      notifier().loadScript(Script.fromJson(_scriptJson));
      // 3000 + 4000 + 2000 = 9000 (error chunk excluded)
      expect(state().totalDurationMs, 9000);
    });

    test('cumulativeOffsetMs sums durations before current chunk', () {
      notifier().loadScript(Script.fromJson(_scriptJson));
      notifier().goToChunk(1); // chunk at position 1 in readyChunks = 4000ms chunk
      // offset = first ready chunk = 3000ms
      expect(state().cumulativeOffsetMs, 3000);
    });

    test('nextChunk advances within ready chunks', () {
      notifier().loadScript(Script.fromJson(_scriptJson));
      expect(state().currentChunkIndex, 0);
      notifier().nextChunk();
      expect(state().currentChunkIndex, 1);
      notifier().nextChunk();
      expect(state().currentChunkIndex, 2);
      notifier().nextChunk();
      expect(state().currentChunkIndex, 2); // at last, no-op
    });

    test('prevChunk decrements and stops at 0', () {
      notifier().loadScript(Script.fromJson(_scriptJson), startChunk: 2);
      notifier().prevChunk();
      expect(state().currentChunkIndex, 1);
      notifier().prevChunk();
      expect(state().currentChunkIndex, 0);
      notifier().prevChunk();
      expect(state().currentChunkIndex, 0);
    });

    test('currentScriptChunk returns correct ready chunk', () {
      notifier().loadScript(Script.fromJson(_scriptJson));
      expect(state().currentScriptChunk?.text, 'Narrator: A.');
      notifier().nextChunk();
      // next ready chunk skips the error one
      expect(state().currentScriptChunk?.text, 'Narrator: C.');
    });

    test('isAtLastChunk returns true at last ready chunk', () {
      notifier().loadScript(Script.fromJson(_scriptJson));
      expect(notifier().isAtLastChunk, false);
      notifier().goToChunk(2);
      expect(notifier().isAtLastChunk, true);
    });
  });
}
