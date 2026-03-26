import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../db/database.dart';
import '../models/script.dart';
import '../providers/books_provider.dart';
import '../providers/player_provider.dart';
import '../services/audio_service.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  final String versionId;
  final bool isNewBook;
  final AudioService? audioService; // injected for testing

  const PlayerScreen({
    super.key,
    required this.versionId,
    this.isNewBook = false,
    this.audioService,
  });

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  late AudioService _audio;
  StreamSubscription<void>? _completionSub;
  StreamSubscription<Duration>? _positionSub;
  double _sliderPositionMs = 0;

  @override
  void initState() {
    super.initState();
    _audio = widget.audioService ?? AudioService();
    _completionSub = _audio.onComplete.listen((_) => _onChunkComplete());
    _positionSub = _audio.positionStream.listen((position) {
      if (!mounted) return;
      final playerState = ref.read(playerProvider);
      final offset = playerState.cumulativeOffsetMs.toDouble();
      setState(() {
        _sliderPositionMs = offset + position.inMilliseconds.toDouble();
      });
    });
    _loadScript();
  }

  Future<void> _loadScript() async {
    final String scriptJson;
    var startChunk = 0;

    if (widget.versionId == 'mock_book_001_en') {
      scriptJson = await rootBundle.loadString('assets/mock/script.json');
      if (!mounted) return;
    } else {
      final version = await AppDatabase.instance.getAudioVersion(widget.versionId);
      if (version == null || !mounted) return;
      scriptJson = version.scriptJson;
      startChunk = version.lastPlayedLine; // DB field repurposed as lastPlayedChunk
    }

    final script = Script.fromJson(scriptJson);
    if (!mounted) return;
    ref.read(playerProvider.notifier).loadScript(script, startChunk: startChunk);
    await _loadAndPlayCurrentChunk();
  }

  void _onChunkComplete() {
    if (!mounted) return;
    final notifier = ref.read(playerProvider.notifier);
    if (notifier.isAtLastChunk) {
      notifier.pause();
      return;
    }
    notifier.nextChunk();
    _loadAndPlayCurrentChunk();
  }

  Future<void> _loadAndPlayCurrentChunk({Duration seekTo = Duration.zero}) async {
    if (widget.versionId == 'mock_book_001_en') {
      await _audio.load('mock');
      await _audio.play();
      return;
    }
    try {
      final playerState = ref.read(playerProvider);
      final chunk = playerState.currentScriptChunk;
      if (chunk == null) return;
      final fileName = 'chunk_${chunk.index.toString().padLeft(3, '0')}.wav';
      final version = await AppDatabase.instance.getAudioVersion(widget.versionId);
      if (version == null) return;
      await _audio.load('${version.audioDir}/$fileName');
      if (seekTo != Duration.zero) await _audio.seek(seekTo);
      await _audio.play();
    } catch (e) {
      debugPrint('AudioService.load failed: $e');
    }
  }

  void _seekToMs(double targetMs) {
    final playerState = ref.read(playerProvider);
    final notifier = ref.read(playerProvider.notifier);
    final ready = playerState.readyChunks;
    int cumulative = 0;
    for (int i = 0; i < ready.length; i++) {
      final chunkEnd = cumulative + ready[i].durationMs;
      if (targetMs <= chunkEnd || i == ready.length - 1) {
        final offset = (targetMs - cumulative).round().clamp(0, ready[i].durationMs);
        notifier.goToChunk(i);
        _loadAndPlayCurrentChunk(seekTo: Duration(milliseconds: offset));
        break;
      }
      cumulative = chunkEnd;
    }
  }

  void _saveProgress(int chunkIndex) {
    AppDatabase.instance.updateLastPlayedLine(widget.versionId, chunkIndex);
  }

  @override
  void dispose() {
    _completionSub?.cancel();
    _positionSub?.cancel();
    _audio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final versionAsync = ref.watch(singleVersionProvider(widget.versionId));
    final playerState = ref.watch(playerProvider);
    final isMock = widget.versionId == 'mock_book_001_en';

    return versionAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
      data: (version) {
        if (version == null && !isMock) {
          return const Scaffold(body: Center(child: Text('Version not found')));
        }

        final chunk = playerState.currentScriptChunk;
        final totalDurationMs = playerState.totalDurationMs;
        final displayLanguage = version?.language.toUpperCase() ?? 'MOCK';

        return Scaffold(
          appBar: AppBar(
            title: Text(displayLanguage),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: widget.isNewBook ? 'Back to Generate' : 'Home',
              onPressed: () {
                _audio.stop();
                ref.invalidate(booksProvider);
                context.go(widget.isNewBook ? '/upload' : '/');
              },
            ),
            actions: widget.isNewBook
                ? [
                    IconButton(
                      icon: const Icon(Icons.home),
                      tooltip: 'Home',
                      onPressed: () {
                        _audio.stop();
                        ref.invalidate(booksProvider);
                        context.go('/');
                      },
                    ),
                  ]
                : null,
          ),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Scrollable dialogue transcript
                Expanded(
                  child: SingleChildScrollView(
                    child: Text(
                      chunk?.text ?? '',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Seekable timeline
                Slider(
                  value: _sliderPositionMs.clamp(0, totalDurationMs.toDouble()),
                  max: totalDurationMs > 0 ? totalDurationMs.toDouble() : 1,
                  onChanged: (v) => setState(() => _sliderPositionMs = v),
                  onChangeEnd: _seekToMs,
                ),
                // Playback controls
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.skip_previous),
                      onPressed: () {
                        ref.read(playerProvider.notifier).prevChunk();
                        _loadAndPlayCurrentChunk();
                      },
                    ),
                    IconButton(
                      icon: Icon(playerState.isPlaying ? Icons.pause : Icons.play_arrow),
                      iconSize: 48,
                      onPressed: () {
                        if (playerState.isPlaying) {
                          ref.read(playerProvider.notifier).pause();
                          _audio.pause();
                        } else {
                          ref.read(playerProvider.notifier).play();
                          _audio.play();
                        }
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_next),
                      onPressed: () {
                        ref.read(playerProvider.notifier).nextChunk();
                        _saveProgress(playerState.currentChunkIndex + 1);
                        _loadAndPlayCurrentChunk();
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.replay),
                      onPressed: () async {
                        await _audio.stop();
                        ref.read(playerProvider.notifier).goToChunk(0);
                        _loadAndPlayCurrentChunk();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
