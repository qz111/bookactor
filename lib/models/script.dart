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

class ScriptLine {
  final int index;
  final String character;
  final String text;
  final int page;
  final String status;

  const ScriptLine({
    required this.index,
    required this.character,
    required this.text,
    required this.page,
    required this.status,
  });

  factory ScriptLine.fromJson(Map<String, dynamic> json) => ScriptLine(
        index: json['index'] as int,
        character: json['character'] as String,
        text: json['text'] as String,
        page: json['page'] as int,
        status: json['status'] as String,
      );

  Map<String, dynamic> toJson() => {
        'index': index,
        'character': character,
        'text': text,
        'page': page,
        'status': status,
      };

  ScriptLine copyWith({String? status}) => ScriptLine(
        index: index,
        character: character,
        text: text,
        page: page,
        status: status ?? this.status,
      );
}

class Script {
  final List<ScriptCharacter> characters;
  final List<ScriptLine> lines;

  const Script({required this.characters, required this.lines});

  /// Looks up the OpenAI voice for a character by name.
  /// voice is NOT stored on lines — always resolved from this method.
  /// Defaults to 'alloy' if character not found.
  String voiceFor(String characterName) {
    final match =
        characters.where((c) => c.name == characterName).firstOrNull;
    return match?.voice ?? 'alloy';
  }

  factory Script.fromJson(String jsonStr) {
    final map = jsonDecode(jsonStr) as Map<String, dynamic>;
    return Script(
      characters: (map['characters'] as List)
          .map((c) => ScriptCharacter.fromJson(c as Map<String, dynamic>))
          .toList(),
      lines: (map['lines'] as List)
          .map((l) => ScriptLine.fromJson(l as Map<String, dynamic>))
          .toList(),
    );
  }

  String toJson() => jsonEncode({
        'characters': characters.map((c) => c.toJson()).toList(),
        'lines': lines.map((l) => l.toJson()).toList(),
      });
}
