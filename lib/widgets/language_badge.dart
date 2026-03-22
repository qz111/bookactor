import 'package:flutter/material.dart';

class LanguageBadge extends StatelessWidget {
  final String language;
  final String status;

  const LanguageBadge(
      {super.key, required this.language, required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'ready' => Colors.green,
      'generating' => Colors.orange,
      'error' => Colors.red,
      _ => Colors.grey,
    };
    return Chip(
      label: Text(language.toUpperCase()),
      side: BorderSide(color: color),
      backgroundColor: color.withOpacity(0.1),
      labelStyle: TextStyle(color: color, fontSize: 11),
      padding: EdgeInsets.zero,
    );
  }
}
