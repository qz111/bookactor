import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/books_provider.dart';
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
              Container(
                height: 200,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(child: Icon(Icons.menu_book, size: 72)),
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
                                  onPressed: () => context
                                      .push('/player/${v.versionId}'),
                                )
                              : null,
                        )),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () =>
                          _showNewLanguageSheet(context, bookId),
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

  String _languageName(String code) => const {
        'en': 'English',
        'zh': 'Chinese (Simplified)',
        'zh-TW': 'Chinese (Traditional)',
        'fr': 'French',
        'es': 'Spanish',
        'de': 'German',
        'ja': 'Japanese',
        'ko': 'Korean',
      }[code] ??
      code;

  void _showNewLanguageSheet(BuildContext context, String bookId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _NewLanguageSheet(bookId: bookId),
    );
  }
}

class _NewLanguageSheet extends StatefulWidget {
  final String bookId;
  const _NewLanguageSheet({required this.bookId});

  @override
  State<_NewLanguageSheet> createState() => _NewLanguageSheetState();
}

class _NewLanguageSheetState extends State<_NewLanguageSheet> {
  String _language = 'zh';
  String _llmProvider = 'gpt4o';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
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
            items: const [
              DropdownMenuItem(value: 'zh', child: Text('Chinese (Simplified)')),
              DropdownMenuItem(value: 'zh-TW', child: Text('Chinese (Traditional)')),
              DropdownMenuItem(value: 'fr', child: Text('French')),
              DropdownMenuItem(value: 'es', child: Text('Spanish')),
              DropdownMenuItem(value: 'de', child: Text('German')),
              DropdownMenuItem(value: 'ja', child: Text('Japanese')),
              DropdownMenuItem(value: 'ko', child: Text('Korean')),
            ],
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
              onPressed: () {
                Navigator.pop(context);
                context.push('/loading/${widget.bookId}/$_language');
              },
              child: const Text('Generate'),
            ),
          ),
        ],
      ),
    );
  }
}
