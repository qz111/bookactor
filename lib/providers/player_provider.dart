import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/script.dart';

class PlayerState {
  final Script? script;
  final int currentChunkIndex;
  final bool isPlaying;

  const PlayerState({
    this.script,
    this.currentChunkIndex = 0,
    this.isPlaying = false,
  });

  PlayerState copyWith({Script? script, int? currentChunkIndex, bool? isPlaying}) =>
      PlayerState(
        script: script ?? this.script,
        currentChunkIndex: currentChunkIndex ?? this.currentChunkIndex,
        isPlaying: isPlaying ?? this.isPlaying,
      );

  List<ScriptChunk> get readyChunks =>
      script?.chunks.where((c) => c.status == 'ready').toList() ?? [];

  ScriptChunk? get currentScriptChunk {
    final ready = readyChunks;
    if (currentChunkIndex >= ready.length) return null;
    return ready[currentChunkIndex];
  }

  int get totalDurationMs =>
      readyChunks.fold(0, (sum, c) => sum + c.durationMs);

  int get cumulativeOffsetMs {
    final ready = readyChunks;
    int offset = 0;
    for (int i = 0; i < currentChunkIndex && i < ready.length; i++) {
      offset += ready[i].durationMs;
    }
    return offset;
  }
}

class PlayerNotifier extends Notifier<PlayerState> {
  @override
  PlayerState build() => const PlayerState();

  void loadScript(Script script, {int startChunk = 0}) {
    state = PlayerState(script: script, currentChunkIndex: startChunk);
  }

  void play() => state = state.copyWith(isPlaying: true);
  void pause() => state = state.copyWith(isPlaying: false);

  void nextChunk() {
    final ready = state.readyChunks;
    if (state.currentChunkIndex < ready.length - 1) {
      state = state.copyWith(currentChunkIndex: state.currentChunkIndex + 1);
    }
  }

  void prevChunk() {
    if (state.currentChunkIndex > 0) {
      state = state.copyWith(currentChunkIndex: state.currentChunkIndex - 1);
    }
  }

  void goToChunk(int index) {
    final ready = state.readyChunks;
    if (index >= 0 && index < ready.length) {
      state = state.copyWith(currentChunkIndex: index);
    }
  }

  bool get isAtLastChunk {
    return state.currentChunkIndex >= state.readyChunks.length - 1;
  }

  Script? get script => state.script;
}

final playerProvider =
    NotifierProvider<PlayerNotifier, PlayerState>(PlayerNotifier.new);
