import 'package:flutter/material.dart';

class KaraokeText extends StatelessWidget {
  final String text;
  final String character;
  final bool isPlaying;

  const KaraokeText({
    super.key,
    required this.text,
    required this.character,
    this.isPlaying = false,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isPlaying
            ? Colors.amber.withValues(alpha: 0.15)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isPlaying
              ? Colors.amber.withValues(alpha: 0.5)
              : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          Text(
            character,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: isPlaying
                      ? Colors.amber
                      : Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            text,
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
