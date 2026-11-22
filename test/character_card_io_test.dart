import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:solace/models/ai_character.dart';
import 'package:solace/services/character_card_io_service.dart';

AICharacter character({String? avatarUrl}) => AICharacter(
      id: 'char_1',
      name: '阿澈',
      avatarUrl: avatarUrl,
      personality: '温柔又爱撒娇',
      coreDesire: '一直陪着用户',
      moralBoundary: '真诚，不说谎',
      backgroundStory: '雨夜车站相遇',
      createdAt: DateTime(2026, 1, 1),
    );

void main() {
  test('导出再导入往返：人设字段一致，id 是新的', () {
    final json = CharacterCardIOService.buildExportJson(character());
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    expect(decoded['format'], 'solace-character-card');
    expect(decoded['version'], 1);

    final result = CharacterCardIOService.parseImportJson(json);
    expect(result.isSuccess, isTrue);
    expect(result.error, isNull);
    final imported = result.character!;
    expect(imported.name, '阿澈');
    expect(imported.personality, '温柔又爱撒娇');
    expect(imported.coreDesire, '一直陪着用户');
    expect(imported.moralBoundary, '真诚，不说谎');
    expect(imported.backgroundStory, '雨夜车站相遇');
    expect(imported.id, isNot('char_1'));
    expect(imported.id, isNotEmpty);
  });

  test('不是 JSON / 格式不对 / 缺必填字段都返回明确错误', () {
    expect(
      CharacterCardIOService.parseImportJson('不是 json').isError,
      isTrue,
    );
    expect(
      CharacterCardIOService.parseImportJson('{"a":1}').error,
      contains('不是 Solace 角色卡'),
    );
    expect(
      CharacterCardIOService.parseImportJson(jsonEncode({
        'format': 'solace-character-card',
        'version': 1,
        'character': {'name': '', 'personality': 'x'},
      })).error,
      contains('角色名'),
    );
    expect(
      CharacterCardIOService.parseImportJson(jsonEncode({
        'format': 'solace-character-card',
        'version': 99,
        'character': {'name': '阿澈'},
      })).error,
      contains('版本'),
    );
    expect(
      CharacterCardIOService.parseImportJson(jsonEncode({
        'format': 'solace-character-card',
        'version': 1,
        'character': {
          'name': '阿澈',
          'personality': '温柔',
          'coreDesire': '',
          'moralBoundary': '真诚',
        },
      })).error,
      contains('不完整'),
    );
  });

  test('头像文件不存在时去掉头像并提醒，存在时保留', () async {
    final missing = CharacterCardIOService.parseImportJson(
      CharacterCardIOService.buildExportJson(
        character(avatarUrl: '/不存在的路径/avatar.png'),
      ),
    );
    expect(missing.isSuccess, isTrue);
    expect(missing.character!.avatarUrl, isNull);
    expect(missing.warnings, contains('头像文件不在本机，已去掉头像'));

    final tempDir = await Directory.systemTemp.createTemp('solace_card_test');
    try {
      final avatar = File('${tempDir.path}/avatar.png');
      await avatar.writeAsBytes([0, 1, 2, 3]);
      final kept = CharacterCardIOService.parseImportJson(
        CharacterCardIOService.buildExportJson(
          character(avatarUrl: avatar.path),
        ),
      );
      expect(kept.isSuccess, isTrue);
      expect(kept.character!.avatarUrl, avatar.path);
      expect(kept.warnings, isEmpty);
    } finally {
      await tempDir.delete(recursive: true);
    }
  });
}
