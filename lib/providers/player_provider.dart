import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/script.dart';

class PlayerState {
  final Script? script;
  final int currentLine;
  final bool isPlaying;

  const PlayerState({
    this.script,
    this.currentLine = 0,
    this.isPlaying = false,
  });

  PlayerState copyWith({Script? script, int? currentLine, bool? isPlaying}) =>
      PlayerState(
        script: script ?? this.script,
        currentLine: currentLine ?? this.currentLine,
        isPlaying: isPlaying ?? this.isPlaying,
      );

  /// Returns the current ready line, or null if script not loaded or done.
  ScriptLine? get currentScriptLine {
    if (script == null) return null;
    final readyLines =
        script!.lines.where((l) => l.status == 'ready').toList();
    if (currentLine >= readyLines.length) return null;
    return readyLines[currentLine];
  }
}

class PlayerNotifier extends Notifier<PlayerState> {
  @override
  PlayerState build() => const PlayerState();

  void loadScript(Script script, {int startLine = 0}) {
    state = PlayerState(script: script, currentLine: startLine);
  }

  void play() => state = state.copyWith(isPlaying: true);
  void pause() => state = state.copyWith(isPlaying: false);

  void nextLine() {
    if (script == null) return;
    final readyCount =
        state.script!.lines.where((l) => l.status == 'ready').length;
    if (state.currentLine < readyCount - 1) {
      state = state.copyWith(currentLine: state.currentLine + 1);
    }
  }

  void prevLine() {
    if (state.currentLine > 0) {
      state = state.copyWith(currentLine: state.currentLine - 1);
    }
  }

  Script? get script => state.script;
}

final playerProvider =
    NotifierProvider<PlayerNotifier, PlayerState>(PlayerNotifier.new);
