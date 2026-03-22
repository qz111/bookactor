import 'package:flutter_test/flutter_test.dart';
import 'package:bookactor/models/audio_version.dart';

void main() {
  group('AudioVersion', () {
    const version = AudioVersion(
      versionId: 'abc123_en',
      bookId: 'abc123',
      language: 'en',
      llmProvider: 'gpt4o',
      scriptJson: '{}',
      audioDir: '/path/audio',
      status: 'ready',
      lastGeneratedLine: 4,
      lastPlayedLine: 2,
      createdAt: 1711065600,
    );

    test('versionId matches book_id + language', () {
      expect(version.versionId, '${version.bookId}_${version.language}');
    });

    test('toMap/fromMap round-trip', () {
      final restored = AudioVersion.fromMap(version.toMap());
      expect(restored.versionId, version.versionId);
      expect(restored.status, version.status);
      expect(restored.lastGeneratedLine, version.lastGeneratedLine);
      expect(restored.lastPlayedLine, version.lastPlayedLine);
    });

    test('copyWith updates only specified fields', () {
      final updated = version.copyWith(status: 'generating', lastGeneratedLine: 2);
      expect(updated.status, 'generating');
      expect(updated.lastGeneratedLine, 2);
      expect(updated.bookId, version.bookId);
    });
  });
}
