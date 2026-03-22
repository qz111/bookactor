import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/books_provider.dart';
import '../widgets/book_card.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final booksAsync = ref.watch(booksProvider);
    final generatingAsync = ref.watch(generatingVersionsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My Books')),
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
                    onPressed: () {
                      for (final v in versions) {
                        context.push('/loading/${v.bookId}/${v.language}');
                      }
                    },
                    child: const Text('Resume'),
                  ),
                  TextButton(
                    onPressed: () {
                      // Phase 3: mark as error in DB
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
                        return BookCard(
                          book: book,
                          languageCount: versionsAsync.value?.length ?? 0,
                          onTap: () =>
                              context.push('/book/${book.bookId}'),
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
