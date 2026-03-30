import 'dart:convert';
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

/// Infers which pipeline stage failed, so resume re-enters at the right point.
/// Only call when [version.status] == 'error'.
ResumeStage inferResumeStage(Book book, AudioVersion version) {
  if (book.vlmOutput.isEmpty || book.vlmOutput == '[]') {
    return ResumeStage.vlm;
  }
  if (version.scriptJson.isEmpty || version.scriptJson == '{}') {
    return ResumeStage.llm;
  }
  try {
    final decoded = jsonDecode(version.scriptJson) as Map<String, dynamic>;
    final chunks = decoded['chunks'] as List?;
    if (chunks == null || chunks.isEmpty) return ResumeStage.llm;
    return ResumeStage.tts; // TTS stage — partial or total failure
  } catch (_) {
    return ResumeStage.llm;
  }
}

/// Returns true if ≥1 TTS chunk completed successfully.
/// Determines whether to show "Resume" vs "Retry" label for TTS-stage errors.
bool _hasTtsPartialProgress(AudioVersion version) {
  try {
    final decoded = jsonDecode(version.scriptJson) as Map<String, dynamic>;
    final chunks = decoded['chunks'] as List? ?? [];
    return chunks.any(
        (c) => (c as Map<String, dynamic>)['status'] == 'ready');
  } catch (_) {
    return false;
  }
}

class BookDetailScreen extends ConsumerStatefulWidget {
  final String bookId;
  const BookDetailScreen({super.key, required this.bookId});

  @override
  ConsumerState<BookDetailScreen> createState() => _BookDetailScreenState();

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

class _BookDetailScreenState extends ConsumerState<BookDetailScreen> {
  void _confirmDelete(BuildContext screenContext, AudioVersion version) {
    showDialog(
      context: screenContext,
      builder: (dialogContext) {
        bool deleting = false;
        return StatefulBuilder(
          builder: (_, setDialogState) => AlertDialog(
            title: const Text('Delete audio version?'),
            content: const Text(
              'This will permanently delete all audio files for this language. This cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: deleting ? null : () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: deleting
                    ? null
                    : () async {
                        setDialogState(() => deleting = true);
                        bool success = false;
                        try {
                          if (version.audioDir.isNotEmpty) {
                            try {
                              await Directory(version.audioDir)
                                  .delete(recursive: true);
                            } on FileSystemException {
                              // Directory already gone — proceed to DB cleanup.
                            }
                          }
                          await AppDatabase.instance
                              .deleteAudioVersion(version.versionId);
                          success = true;
                        } finally {
                          if (!success && mounted) {
                            setDialogState(() => deleting = false);
                          }
                        }
                        if (success && mounted) {
                          ref.invalidate(audioVersionsProvider(widget.bookId));
                          Navigator.pop(dialogContext);
                        } else if (!success && mounted) {
                          ScaffoldMessenger.of(screenContext).showSnackBar(
                            const SnackBar(content: Text('Could not delete audio version.')),
                          );
                        }
                      },
                child: deleting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Delete'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget? _buildVersionTrailing(BuildContext context, Book book, AudioVersion version) {
    if (version.status == 'ready') {
      return IconButton(
        icon: const Icon(Icons.play_circle_filled),
        onPressed: () => context.push('/player/${version.versionId}'),
      );
    }
    if (version.status == 'error') {
      final stage = inferResumeStage(book, version);
      final isPartialTts =
          stage == ResumeStage.tts && _hasTtsPartialProgress(version);
      final label = isPartialTts ? 'Resume' : 'Retry';
      return TextButton(
        onPressed: () => context.push(
          '/loading',
          extra: LoadingParams(
            bookId: book.bookId,
            versionId: version.versionId,
            filePath: book.pagesDir,
            language: version.language,
            vlmProvider: book.vlmProvider,
            llmProvider: version.llmProvider ?? 'gpt4o',
            ttsProvider: version.ttsProvider ?? 'openai',
            processingMode: ProcessingMode.textHeavy,
            isNewBook: false,
            startStage: stage,
          ),
        ),
        child: Text(label),
      );
    }
    return null; // generating — no action button
  }

  @override
  Widget build(BuildContext context) {
    final bookAsync = ref.watch(singleBookProvider(widget.bookId));
    final versionsAsync = ref.watch(audioVersionsProvider(widget.bookId));

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
                              widget._coverPlaceholder(context),
                        )
                      : widget._coverPlaceholder(context),
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
                    ...versions.map((v) => GestureDetector(
                          onLongPress: v.status == 'generating'
                              ? null
                              : () => _confirmDelete(context, v),
                          child: ListTile(
                            leading: LanguageBadge(
                                language: v.language, status: v.status),
                            title: Text(widget._languageName(v.language)),
                            subtitle: Text(v.status),
                            trailing: _buildVersionTrailing(context, book, v),
                          ),
                        )),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () =>
                          widget._showNewLanguageSheet(context, book),
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
  String _ttsProvider = 'qwen';   // locked because default language is zh

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
            onChanged: (v) => setState(() {
              _language = v!;
              if (const {'zh', 'zh-TW'}.contains(_language)) {
                _ttsProvider = 'qwen';
              } else if (_ttsProvider == 'qwen') {
                _ttsProvider = 'openai';
              }
            }),
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
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _ttsProvider,
            decoration: const InputDecoration(
                labelText: 'Text-to-Speech (TTS)',
                border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'openai', child: Text('OpenAI TTS')),
              DropdownMenuItem(value: 'gemini', child: Text('Gemini TTS')),
              DropdownMenuItem(value: 'qwen', child: Text('Qwen TTS (Chinese)')),
            ],
            onChanged: const {'zh', 'zh-TW'}.contains(_language)
                ? null
                : (v) => setState(() => _ttsProvider = v!),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () async {
                final versionId =
                    '${widget.book.bookId}_${_language}_$_ttsProvider';
                await AppDatabase.instance.insertAudioVersion(AudioVersion(
                  versionId: versionId,
                  bookId: widget.book.bookId,
                  language: _language,
                  llmProvider: _llmProvider,
                  ttsProvider: _ttsProvider,
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
                    ttsProvider: _ttsProvider,
                    // processingMode is not used on resume (isNewBook: false skips analyzePages).
                    // Required field; textHeavy satisfies the constructor.
                    processingMode: ProcessingMode.textHeavy,
                    isNewBook: false,
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
