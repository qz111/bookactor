import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'providers/settings_provider.dart';
import 'screens/library_screen.dart';
import 'screens/book_detail_screen.dart';
import 'screens/upload_screen.dart';
import 'screens/loading_screen.dart';
import 'screens/player_screen.dart';
import 'screens/settings_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final initialLocation = ref.watch(initialLocationProvider);
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(path: '/', builder: (_, __) => const LibraryScreen()),
      GoRoute(
        path: '/book/:bookId',
        builder: (_, state) =>
            BookDetailScreen(bookId: state.pathParameters['bookId']!),
      ),
      GoRoute(path: '/upload', builder: (_, __) => const UploadScreen()),
      GoRoute(
        path: '/loading',
        builder: (context, state) {
          final extra = state.extra as LoadingParams?;
          return LoadingScreen(
            bookId: extra?.bookId ?? '',
            language: extra?.language ?? 'en',
            params: extra,
          );
        },
      ),
      GoRoute(
        path: '/loading/:bookId/:language',
        builder: (_, state) => LoadingScreen(
          bookId: state.pathParameters['bookId']!,
          language: state.pathParameters['language']!,
        ),
      ),
      GoRoute(
        path: '/player/:versionId',
        builder: (_, state) =>
            PlayerScreen(versionId: state.pathParameters['versionId']!),
      ),
      GoRoute(
        path: '/settings',
        builder: (_, __) => const SettingsScreen(),
      ),
    ],
  );
});

class BookActorApp extends ConsumerWidget {
  const BookActorApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'BookActor',
      routerConfig: router,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6C63FF)),
        useMaterial3: true,
      ),
    );
  }
}
