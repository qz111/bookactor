import 'dart:convert';

class ScriptCharacter {
  final String name;
  final String voice;
  final String? traits;

  const ScriptCharacter({required this.name, required this.voice, this.traits});

  factory ScriptCharacter.fromJson(Map<String, dynamic> json) =>
      ScriptCharacter(
        name: json['name'] as String,
        voice: json['voice'] as String,
        traits: json['traits'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'voice': voice,
        if (traits != null) 'traits': traits,
      };
}

class ScriptChunk {
  final int index;
  final String text;
  final List<String> speakers;
  final int durationMs;
  final String status;

  const ScriptChunk({
    required this.index,
    required this.text,
    required this.speakers,
    required this.durationMs,
    required this.status,
  });

  factory ScriptChunk.fromJson(Map<String, dynamic> json) => ScriptChunk(
        index: json['index'] as int,
        text: json['text'] as String,
        speakers: List<String>.from(json['speakers'] as List),
        durationMs: (json['duration_ms'] as num).toInt(),
        status: json['status'] as String,
      );

  Map<String, dynamic> toJson() => {
        'index': index,
        'text': text,
        'speakers': speakers,
        'duration_ms': durationMs,
        'status': status,
      };

  ScriptChunk copyWith({String? status, int? durationMs}) => ScriptChunk(
        index: index,
        text: text,
        speakers: speakers,
        durationMs: durationMs ?? this.durationMs,
        status: status ?? this.status,
      );
}

class Script {
  final List<ScriptCharacter> characters;
  final List<ScriptChunk> chunks;

  const Script({required this.characters, required this.chunks});

  /// Looks up the voice for a character by name.
  /// Defaults to 'alloy' if not found.
  String voiceFor(String characterName) {
    final match = characters.where((c) => c.name == characterName).firstOrNull;
    return match?.voice ?? 'alloy';
  }

  factory Script.fromJson(String jsonStr) {
    final map = jsonDecode(jsonStr) as Map<String, dynamic>;
    return Script(
      characters: (map['characters'] as List)
          .map((c) => ScriptCharacter.fromJson(c as Map<String, dynamic>))
          .toList(),
      chunks: (map['chunks'] as List)
          .map((c) => ScriptChunk.fromJson(c as Map<String, dynamic>))
          .toList(),
    );
  }

  String toJson() => jsonEncode({
        'characters': characters.map((c) => c.toJson()).toList(),
        'chunks': chunks.map((c) => c.toJson()).toList(),
      });
}
