import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../db/database.dart';
import '../models/script.dart';
import '../providers/books_provider.dart';
import '../providers/player_provider.dart';
import '../widgets/karaoke_text.dart';
import '../widgets/audio_controls.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  final String versionId;
  const PlayerScreen({super.key, required this.versionId});

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  Timer? _mockTimer;

  @override
  void initState() {
    super.initState();
    _loadScript();
  }

  Future<void> _loadScript() async {
    // Phase 2: mock version loads from asset; real versions load from DB
    final String scriptJson;
    var startLine = 0;

    if (widget.versionId == 'mock_book_001_en') {
      scriptJson = await rootBundle.loadString('assets/mock/script.json');
      // Mock version is not in DB; always start from line 0
      if (!mounted) return;
    } else {
      final version =
          await AppDatabase.instance.getAudioVersion(widget.versionId);
      if (version == null || !mounted) return;
      scriptJson = version.scriptJson;
      startLine = version.lastPlayedLine;
    }

    final script = Script.fromJson(scriptJson);
    if (!mounted) return;
    ref
        .read(playerProvider.notifier)
        .loadScript(script, startLine: startLine);
  }

  void _startMockPlayback() {
    _mockTimer?.cancel();
    _mockTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      final state = ref.read(playerProvider);
      if (!state.isPlaying) return;
      final readyCount =
          state.script?.lines.where((l) => l.status == 'ready').length ?? 0;
      if (state.currentLine < readyCount - 1) {
        ref.read(playerProvider.notifier).nextLine();
        _saveProgress(state.currentLine + 1);
      } else {
        ref.read(playerProvider.notifier).pause();
        _mockTimer?.cancel();
      }
    });
  }

  void _saveProgress(int line) {
    AppDatabase.instance.updateLastPlayedLine(widget.versionId, line);
  }

  @override
  void dispose() {
    _mockTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final versionAsync = ref.watch(singleVersionProvider(widget.versionId));
    final playerState = ref.watch(playerProvider);

    return versionAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) =>
          Scaffold(body: Center(child: Text('Error: $e'))),
      data: (version) {
        if (version == null) {
          return const Scaffold(
              body: Center(child: Text('Version not found')));
        }

        final line = playerState.currentScriptLine;
        final readyLines = playerState.script?.lines
                .where((l) => l.status == 'ready')
                .toList() ??
            [];

        return Scaffold(
          appBar: AppBar(title: Text(version.language.toUpperCase())),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Page image placeholder (Phase 3 will show real page images)
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(
                      child: Text(
                        'Page ${line?.page ?? 1}',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (line != null)
                  KaraokeText(
                      text: line.text, character: line.character),
                const SizedBox(height: 24),
                AudioControls(
                  isPlaying: playerState.isPlaying,
                  currentLine: playerState.currentLine,
                  totalLines: readyLines.length,
                  onPlay: () {
                    ref.read(playerProvider.notifier).play();
                    _startMockPlayback();
                  },
                  onPause: () {
                    ref.read(playerProvider.notifier).pause();
                    _mockTimer?.cancel();
                  },
                  onNext: () {
                    ref.read(playerProvider.notifier).nextLine();
                    _saveProgress(playerState.currentLine + 1);
                  },
                  onPrev: () =>
                      ref.read(playerProvider.notifier).prevLine(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
