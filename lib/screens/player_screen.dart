import 'package:flutter/material.dart';
class PlayerScreen extends StatelessWidget {
  final String versionId;
  const PlayerScreen({super.key, required this.versionId});
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('Player')));
}
