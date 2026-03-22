import '../models/book.dart';
import '../models/audio_version.dart';

Book createMockBook() => const Book(
      bookId: 'mock_book_001',
      title: 'Little Bear',
      pagesDir: '',
      vlmOutput: '[]',
      vlmProvider: 'gemini',
      createdAt: 1711065600,
    );

AudioVersion createMockAudioVersion() => const AudioVersion(
      versionId: 'mock_book_001_en',
      bookId: 'mock_book_001',
      language: 'en',
      llmProvider: 'gpt4o',
      scriptJson: '',  // loaded from assets/mock/script.json at runtime
      audioDir: '',
      status: 'ready',
      lastGeneratedLine: 6,
      lastPlayedLine: 0,
      createdAt: 1711065600,
    );

/// BCP 47 language codes with display names shown in dropdowns.
const supportedLanguages = [
  {'code': 'en', 'name': 'English'},
  {'code': 'zh', 'name': 'Chinese (Simplified)'},
  {'code': 'zh-TW', 'name': 'Chinese (Traditional)'},
  {'code': 'fr', 'name': 'French'},
  {'code': 'es', 'name': 'Spanish'},
  {'code': 'de', 'name': 'German'},
  {'code': 'ja', 'name': 'Japanese'},
  {'code': 'ko', 'name': 'Korean'},
];
