import 'package:flutter/material.dart';

class KaraokeText extends StatelessWidget {
  final String text;
  final String character;

  const KaraokeText({super.key, required this.text, required this.character});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            character,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Text(text,
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
