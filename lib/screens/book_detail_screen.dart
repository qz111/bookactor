import 'package:flutter/material.dart';
class BookDetailScreen extends StatelessWidget {
  final String bookId;
  const BookDetailScreen({super.key, required this.bookId});
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('Book Detail')));
}
