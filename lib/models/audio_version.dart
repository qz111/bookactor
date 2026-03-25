class AudioVersion {
  final String versionId;
  final String bookId;
  final String language;
  final String? llmProvider;
  final String? ttsProvider;
  final String scriptJson;
  final String audioDir;
  final String status;
  final int lastGeneratedLine;
  final int lastPlayedLine;
  final int createdAt;

  const AudioVersion({
    required this.versionId,
    required this.bookId,
    required this.language,
    this.llmProvider,
    this.ttsProvider,
    required this.scriptJson,
    required this.audioDir,
    required this.status,
    required this.lastGeneratedLine,
    required this.lastPlayedLine,
    required this.createdAt,
  });

  static String makeVersionId(String bookId, String language) =>
      '${bookId}_$language';

  Map<String, dynamic> toMap() => {
        'version_id': versionId,
        'book_id': bookId,
        'language': language,
        'llm_provider': llmProvider,
        'tts_provider': ttsProvider,
        'script_json': scriptJson,
        'audio_dir': audioDir,
        'status': status,
        'last_generated_line': lastGeneratedLine,
        'last_played_line': lastPlayedLine,
        'created_at': createdAt,
      };

  factory AudioVersion.fromMap(Map<String, dynamic> map) => AudioVersion(
        versionId: map['version_id'] as String,
        bookId: map['book_id'] as String,
        language: map['language'] as String,
        llmProvider: map['llm_provider'] as String?,
        ttsProvider: map['tts_provider'] as String?,
        scriptJson: map['script_json'] as String,
        audioDir: map['audio_dir'] as String,
        status: map['status'] as String,
        lastGeneratedLine: map['last_generated_line'] as int,
        lastPlayedLine: map['last_played_line'] as int,
        createdAt: map['created_at'] as int,
      );

  AudioVersion copyWith({
    String? status,
    int? lastGeneratedLine,
    int? lastPlayedLine,
    String? scriptJson,
  }) =>
      AudioVersion(
        versionId: versionId,
        bookId: bookId,
        language: language,
        llmProvider: llmProvider,
        ttsProvider: ttsProvider,
        scriptJson: scriptJson ?? this.scriptJson,
        audioDir: audioDir,
        status: status ?? this.status,
        lastGeneratedLine: lastGeneratedLine ?? this.lastGeneratedLine,
        lastPlayedLine: lastPlayedLine ?? this.lastPlayedLine,
        createdAt: createdAt,
      );
}
