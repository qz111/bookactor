import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../db/database.dart';
import '../mock/mock_data.dart';
import '../models/audio_version.dart';
import '../models/book.dart';
import '../models/processing_mode.dart';
import '../providers/books_provider.dart';
import '../screens/loading_screen.dart';
import '../widgets/language_badge.dart';

class BookDetailScreen extends ConsumerWidget {
  final String bookId;
  const BookDetailScreen({super.key, required this.bookId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookAsync = ref.watch(singleBookProvider(bookId));
    final versionsAsync = ref.watch(audioVersionsProvider(bookId));

    return Scaffold(
      appBar: AppBar(title: const Text('Book')),
      body: bookAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (book) {
          if (book == null) {
            return const Center(child: Text('Book not found'));
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Cover image or placeholder
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  height: 200,
                  child: book.coverPath != null
                      ? Image.file(
                          File(book.coverPath!),
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              _coverPlaceholder(context),
                        )
                      : _coverPlaceholder(context),
                ),
              ),
              const SizedBox(height: 16),
              Text(book.title,
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 24),
              const Text('Audio Versions',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              versionsAsync.when(
                loading: () => const CircularProgressIndicator(),
                error: (e, _) => Text('Error: $e'),
                data: (versions) => Column(
                  children: [
                    ...versions.map((v) => ListTile(
                          leading: LanguageBadge(
                              language: v.language, status: v.status),
                          title: Text(_languageName(v.language)),
                          subtitle: Text(v.status),
                          trailing: v.status == 'ready'
                              ? IconButton(
                                  icon: const Icon(Icons.play_circle_filled),
                                  onPressed: () =>
                                      context.push('/player/${v.versionId}'),
                                )
                              : null,
                        )),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () =>
                          _showNewLanguageSheet(context, book),
                      icon: const Icon(Icons.add),
                      label: const Text('New Language'),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _coverPlaceholder(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: const Center(child: Icon(Icons.menu_book, size: 72)),
    );
  }

  String _languageName(String code) =>
      supportedLanguages.firstWhere(
        (l) => l['code'] == code,
        orElse: () => {'code': code, 'name': code},
      )['name']!;

  void _showNewLanguageSheet(BuildContext context, Book book) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _NewLanguageSheet(book: book),
    );
  }
}

class _NewLanguageSheet extends StatefulWidget {
  final Book book;
  const _NewLanguageSheet({required this.book});

  @override
  State<_NewLanguageSheet> createState() => _NewLanguageSheetState();
}

class _NewLanguageSheetState extends State<_NewLanguageSheet> {
  String _language = 'zh';
  String _llmProvider = 'gpt4o';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Add New Language',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _language,
            decoration: const InputDecoration(
                labelText: 'Language', border: OutlineInputBorder()),
            items: supportedLanguages
                .map((l) =>
                    DropdownMenuItem(value: l['code'], child: Text(l['name']!)))
                .toList(),
            onChanged: (v) => setState(() => _language = v!),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _llmProvider,
            decoration: const InputDecoration(
                labelText: 'LLM Provider', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'gpt4o', child: Text('GPT-4o')),
              DropdownMenuItem(value: 'gemini', child: Text('Gemini')),
            ],
            onChanged: (v) => setState(() => _llmProvider = v!),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () async {
                final versionId =
                    AudioVersion.makeVersionId(widget.book.bookId, _language);
                await AppDatabase.instance.insertAudioVersion(AudioVersion(
                  versionId: versionId,
                  bookId: widget.book.bookId,
                  language: _language,
                  llmProvider: _llmProvider,
                  scriptJson: '{}',
                  audioDir: '',
                  status: 'generating',
                  lastGeneratedLine: 0,
                  lastPlayedLine: 0,
                  createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
                ));
                if (!context.mounted) return;
                Navigator.pop(context);
                if (!context.mounted) return;
                context.push(
                  '/loading',
                  extra: LoadingParams(
                    bookId: widget.book.bookId,
                    versionId: versionId,
                    filePath: widget.book.pagesDir,
                    language: _language,
                    vlmProvider: widget.book.vlmProvider,
                    llmProvider: _llmProvider,
                    // processingMode is not used on resume (isNewBook: false skips analyzePages).
                    // Required field; textHeavy satisfies the constructor.
                    processingMode: ProcessingMode.textHeavy,
                    isNewBook: false,
                    lastGeneratedLine: -1,
                  ),
                );
              },
              child: const Text('Generate'),
            ),
          ),
        ],
      ),
    );
  }
}
