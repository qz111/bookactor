import 'package:flutter/material.dart';
class LoadingScreen extends StatelessWidget {
  final String bookId;
  final String language;
  const LoadingScreen({super.key, required this.bookId, required this.language});
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('Loading')));
}
