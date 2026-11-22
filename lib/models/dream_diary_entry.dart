import 'package:equatable/equatable.dart';

/// 梦境日记 — 用户写给某个角色的脑洞剧情（不是角色写的 AI 日记）。
///
/// 存储：SharedPreferences JSON 列表（[PrefKeys.dreamDiaryEntries]），
/// 不建表、不上传；只有用户逐条打开 [sharedWithCharacter] 后，
/// 内容才会被注入该角色的单聊 prompt，角色才能读到并回应。
class DreamDiaryEntry extends Equatable {
  final String id;
  final String characterId;
  final String title;
  final String content;

  /// 心情词（自由填写，如“甜”“刀”“悬疑”），可为空
  final String mood;
  final DateTime createdAt;

  /// 是否分享给角色：默认 false（隐私默认不分享），用户逐条打开才注入。
  final bool sharedWithCharacter;

  const DreamDiaryEntry({
    required this.id,
    required this.characterId,
    required this.title,
    required this.content,
    this.mood = '',
    required this.createdAt,
    this.sharedWithCharacter = false,
  });

  DreamDiaryEntry copyWith({
    String? id,
    String? characterId,
    String? title,
    String? content,
    String? mood,
    DateTime? createdAt,
    bool? sharedWithCharacter,
  }) {
    return DreamDiaryEntry(
      id: id ?? this.id,
      characterId: characterId ?? this.characterId,
      title: title ?? this.title,
      content: content ?? this.content,
      mood: mood ?? this.mood,
      createdAt: createdAt ?? this.createdAt,
      sharedWithCharacter: sharedWithCharacter ?? this.sharedWithCharacter,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'characterId': characterId,
        'title': title,
        'content': content,
        'mood': mood,
        'createdAt': createdAt.toIso8601String(),
        'sharedWithCharacter': sharedWithCharacter,
      };

  factory DreamDiaryEntry.fromJson(Map<String, dynamic> json) {
    return DreamDiaryEntry(
      id: json['id'] as String? ?? '',
      characterId: json['characterId'] as String? ?? '',
      title: json['title'] as String? ?? '',
      content: json['content'] as String? ?? '',
      mood: json['mood'] as String? ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      sharedWithCharacter: json['sharedWithCharacter'] == true,
    );
  }

  @override
  List<Object?> get props => [
        id,
        characterId,
        title,
        content,
        mood,
        createdAt,
        sharedWithCharacter,
      ];
}
