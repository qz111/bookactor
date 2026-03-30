import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SettingsService {
  static const _openAiKey = 'openai_api_key';
  static const _googleKey = 'google_api_key';
  static const _qwenKey = 'qwen_api_key';
  static const _qwenWorkspaceId = 'qwen_workspace_id';

  final FlutterSecureStorage _storage;

  SettingsService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  // Qwen key is optional — only required when using Chinese TTS.
  // OpenAI + Google keys are the minimum required to launch the app.
  Future<bool> hasKeys() async {
    final openAi = await _storage.read(key: _openAiKey);
    final google = await _storage.read(key: _googleKey);
    return openAi != null &&
        openAi.isNotEmpty &&
        google != null &&
        google.isNotEmpty;
  }

  Future<({String openAi, String google, String qwen, String qwenWorkspaceId})> getKeys() async {
    final openAi = await _storage.read(key: _openAiKey) ?? '';
    final google = await _storage.read(key: _googleKey) ?? '';
    final qwen = await _storage.read(key: _qwenKey) ?? '';
    final qwenWorkspaceId = await _storage.read(key: _qwenWorkspaceId) ?? '';
    return (openAi: openAi, google: google, qwen: qwen, qwenWorkspaceId: qwenWorkspaceId);
  }

  Future<void> saveKeys({
    required String openAiKey,
    required String googleKey,
    String qwenKey = '',
    String qwenWorkspaceId = '',
  }) async {
    await _storage.write(key: _openAiKey, value: openAiKey);
    await _storage.write(key: _googleKey, value: googleKey);
    await _storage.write(key: _qwenKey, value: qwenKey);
    await _storage.write(key: _qwenWorkspaceId, value: qwenWorkspaceId);
  }

  Future<void> clearKeys() async {
    await _storage.delete(key: _openAiKey);
    await _storage.delete(key: _googleKey);
    await _storage.delete(key: _qwenKey);
    await _storage.delete(key: _qwenWorkspaceId);
  }
}
