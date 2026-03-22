import 'package:flutter/material.dart';

class AudioControls extends StatelessWidget {
  final bool isPlaying;
  final int currentLine;
  final int totalLines;
  final VoidCallback onPlay;
  final VoidCallback onPause;
  final VoidCallback onNext;
  final VoidCallback onPrev;

  const AudioControls({
    super.key,
    required this.isPlaying,
    required this.currentLine,
    required this.totalLines,
    required this.onPlay,
    required this.onPause,
    required this.onNext,
    required this.onPrev,
  });

  @override
  Widget build(BuildContext context) {
    final progress = totalLines > 0 ? (currentLine + 1) / totalLines : 0.0;
    return Column(
      children: [
        LinearProgressIndicator(value: progress),
        const SizedBox(height: 8),
        Text('${currentLine + 1} / $totalLines',
            style: Theme.of(context).textTheme.bodySmall),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
                iconSize: 36,
                onPressed: onPrev,
                icon: const Icon(Icons.skip_previous)),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: isPlaying ? onPause : onPlay,
              child: Icon(isPlaying ? Icons.pause : Icons.play_arrow,
                  size: 32),
            ),
            const SizedBox(width: 8),
            IconButton(
                iconSize: 36,
                onPressed: onNext,
                icon: const Icon(Icons.skip_next)),
          ],
        ),
      ],
    );
  }
}
