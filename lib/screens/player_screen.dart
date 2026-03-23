import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../db/database.dart';
import '../models/script.dart';
import '../providers/books_provider.dart';
import '../providers/player_provider.dart';
import '../services/audio_service.dart';
import '../widgets/karaoke_text.dart';
import '../widgets/audio_controls.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  final String versionId;
  final AudioService? audioService; // injected for testing

  const PlayerScreen({
    super.key,
    required this.versionId,
    this.audioService,
  });

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  late AudioService _audio;
  StreamSubscription<void>? _completionSub;

  @override
  void initState() {
    super.initState();
    _audio = widget.audioService ?? AudioService();
    _completionSub = _audio.onComplete.listen((_) => _onLineComplete());
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

    // Begin playback of the first (or resumed) line automatically
    await _loadAndPlayCurrentLine();
  }

  void _onLineComplete() {
    if (!mounted) return;
    // Auto-advance to next line
    final notifier = ref.read(playerProvider.notifier);
    notifier.nextLine();
    _loadAndPlayCurrentLine();
  }

  Future<void> _loadAndPlayCurrentLine() async {
    // For mock data, skip actual file loading
    if (widget.versionId == 'mock_book_001_en') {
      await _audio.load('mock'); // will succeed silently in test or prod
      await _audio.play();
      return;
    }

    final state = ref.read(playerProvider);
    final line = state.currentScriptLine;
    if (line == null) return;

    final fileName = 'line_${line.index.toString().padLeft(3, '0')}.mp3';

    // Fetch version for audioDir
    final version =
        await AppDatabase.instance.getAudioVersion(widget.versionId);
    if (version == null) return;

    final filePath = '${version.audioDir}/$fileName';
    await _audio.load(filePath);
    await _audio.play();
  }

  void _saveProgress(int line) {
    AppDatabase.instance.updateLastPlayedLine(widget.versionId, line);
  }

  @override
  void dispose() {
    _completionSub?.cancel();
    _audio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final versionAsync = ref.watch(singleVersionProvider(widget.versionId));
    final playerState = ref.watch(playerProvider);

    // For the mock version, the DB returns null — show the player UI anyway
    // using script data already loaded into playerProvider.
    final isMock = widget.versionId == 'mock_book_001_en';

    return versionAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) =>
          Scaffold(body: Center(child: Text('Error: $e'))),
      data: (version) {
        // For mock, version will be null but we still want to show the player
        if (version == null && !isMock) {
          return const Scaffold(
              body: Center(child: Text('Version not found')));
        }

        final line = playerState.currentScriptLine;
        final readyLines = playerState.script?.lines
                .where((l) => l.status == 'ready')
                .toList() ??
            [];

        // Determine display language: use DB value or fall back to mock label
        final displayLanguage =
            version?.language.toUpperCase() ?? 'MOCK';

        return Scaffold(
          appBar: AppBar(title: Text(displayLanguage)),
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
                    _audio.play();
                  },
                  onPause: () {
                    ref.read(playerProvider.notifier).pause();
                    _audio.pause();
                  },
                  onNext: () {
                    ref.read(playerProvider.notifier).nextLine();
                    _saveProgress(playerState.currentLine + 1);
                    _loadAndPlayCurrentLine();
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
