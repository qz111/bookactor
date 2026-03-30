import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/settings_service.dart';
import '../services/api_service.dart';

/// Singleton SettingsService instance.
final settingsServiceProvider = Provider<SettingsService>((ref) {
  return SettingsService();
});

/// Loads all API keys from secure storage.
/// Invalidate this after saveKeys() to rebuild apiServiceProvider.
final apiKeysProvider =
    FutureProvider<({String openAi, String google, String qwen, String qwenWorkspaceId})>((ref) async {
  return ref.watch(settingsServiceProvider).getKeys();
});

/// Builds ApiService pre-loaded with the saved API keys.
final apiServiceProvider = FutureProvider<ApiService>((ref) async {
  final keys = await ref.watch(apiKeysProvider.future);
  return ApiService(
    baseUrl: 'http://localhost:8088',
    openAiKey: keys.openAi,
    googleKey: keys.google,
    qwenKey: keys.qwen,
    qwenWorkspaceId: keys.qwenWorkspaceId,
  );
});

/// Initial GoRouter location — overridden in main.dart based on hasKeys().
final initialLocationProvider = Provider<String>((_) => '/');
