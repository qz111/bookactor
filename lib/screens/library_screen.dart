import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../db/database.dart';
import '../models/audio_version.dart';
import '../models/book.dart';
import '../models/processing_mode.dart';
import '../providers/books_provider.dart';
import '../screens/loading_screen.dart';
import '../widgets/book_card.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  void _confirmDeleteBook(BuildContext screenContext, Book book) {
    showDialog(
      context: screenContext,
      builder: (dialogContext) {
        bool deleting = false;
        return StatefulBuilder(
          builder: (_, setDialogState) => AlertDialog(
            title: Text('Delete "${book.title}"?'),
            content: const Text(
              'This will permanently delete the book and all its audio versions. This cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed:
                    deleting ? null : () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: deleting
                    ? null
                    : () async {
                        setDialogState(() => deleting = true);
                        bool success = false;
                        try {
                          final versions = await AppDatabase.instance
                              .getVersionsForBook(book.bookId);
                          for (final v in versions) {
                            if (v.audioDir.isNotEmpty) {
                              try {
                                await Directory(v.audioDir)
                                    .delete(recursive: true);
                              } on FileSystemException {
                                // already gone — continue
                              }
                            }
                          }
                          if (book.pagesDir.isNotEmpty) {
                            try {
                              await Directory(book.pagesDir)
                                  .delete(recursive: true);
                            } on FileSystemException {
                              // already gone
                            }
                          }
                          if (book.coverPath != null &&
                              book.coverPath!.isNotEmpty) {
                            try {
                              await File(book.coverPath!).delete();
                            } on FileSystemException {
                              // already gone
                            }
                          }
                          for (final v in versions) {
                            await AppDatabase.instance
                                .deleteAudioVersion(v.versionId);
                          }
                          await AppDatabase.instance.deleteBook(book.bookId);
                          success = true;
                        } finally {
                          if (!success && mounted) {
                            setDialogState(() => deleting = false);
                          }
                        }
                        if (success && mounted) {
                          ref.invalidate(booksProvider);
                          ref.invalidate(audioVersionsProvider(book.bookId));
                          Navigator.pop(dialogContext);
                        } else if (!success && mounted) {
                          ScaffoldMessenger.of(screenContext).showSnackBar(
                            const SnackBar(
                                content: Text('Could not delete book.')),
                          );
                        }
                      },
                child: deleting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child:
                            CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Delete'),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Capture scaffold context before any nested Consumer closures to avoid
    // the inner Consumer builder's `context` parameter shadowing this one.
    final screenContext = context;
    final booksAsync = ref.watch(booksProvider);
    final generatingAsync = ref.watch(generatingVersionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Books'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/settings'),
            tooltip: 'API Keys',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/upload'),
        icon: const Icon(Icons.add),
        label: const Text('Add Book'),
      ),
      body: Column(
        children: [
          // Cold-start resume banner
          generatingAsync.when(
            data: (versions) {
              if (versions.isEmpty) return const SizedBox.shrink();
              return MaterialBanner(
                content: Text(
                    '${versions.length} audiobook(s) were interrupted. Resume?'),
                actions: [
                  TextButton(
                    onPressed: () async {
                      for (final v in versions) {
                        final book =
                            await AppDatabase.instance.getBook(v.bookId);
                        if (book == null) continue;
                        if (!context.mounted) return;
                        context.push(
                          '/loading',
                          extra: LoadingParams(
                            bookId: v.bookId,
                            versionId: v.versionId,
                            filePath: book.pagesDir,
                            language: v.language,
                            vlmProvider: book.vlmProvider,
                            llmProvider: v.llmProvider ?? 'gpt4o',
                            ttsProvider: v.ttsProvider ?? 'openai',
                            processingMode: ProcessingMode.textHeavy,
                            isNewBook: false,
                          ),
                        );
                      }
                    },
                    child: const Text('Resume'),
                  ),
                  TextButton(
                    onPressed: () async {
                      for (final v in versions) {
                        await AppDatabase.instance.updateAudioVersionStatus(
                          v.versionId, 'error',
                        );
                      }
                      ref.invalidate(generatingVersionsProvider);
                    },
                    child: const Text('Dismiss'),
                  ),
                ],
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          // Book grid
          Expanded(
            child: booksAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (books) {
                if (books.isEmpty) {
                  return const Center(child: Text('No books yet'));
                }
                return GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 0.7,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: books.length,
                  itemBuilder: (context, index) {
                    final book = books[index];
                    return Consumer(
                      builder: (context, ref, _) {
                        final versionsAsync =
                            ref.watch(audioVersionsProvider(book.bookId));
                        final versions = versionsAsync.value ?? [];
                        final isGenerating =
                            versions.any((v) => v.status == 'generating');
                        return BookCard(
                          book: book,
                          languageCount: versions.length,
                          onTap: () =>
                              context.push('/book/${book.bookId}'),
                          onLongPress: isGenerating
                              ? () {}
                              : () => _confirmDeleteBook(screenContext, book),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
