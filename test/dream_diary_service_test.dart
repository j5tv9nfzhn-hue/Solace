import 'package:flutter_test/flutter_test.dart';
import 'package:solace/models/dream_diary_entry.dart';
import 'package:solace/services/dream_diary_service.dart';

DreamDiaryEntry entry({
  String id = 'd1',
  String characterId = 'char_1',
  String title = '初遇',
  String content = '我们在雨夜的车站相遇，TA 撑着一把透明的伞。',
  String mood = '甜',
  bool shared = true,
}) =>
    DreamDiaryEntry(
      id: id,
      characterId: characterId,
      title: title,
      content: content,
      mood: mood,
      createdAt: DateTime(2026, 11, 23, 1, 0),
      sharedWithCharacter: shared,
    );

void main() {
  test('模型 JSON 往返 + copyWith 改分享状态', () {
    final original = entry();
    final restored = DreamDiaryEntry.fromJson(original.toJson());
    expect(restored, original);
    expect(restored.sharedWithCharacter, isTrue);

    final unshared = original.copyWith(sharedWithCharacter: false);
    expect(unshared.sharedWithCharacter, isFalse);
    expect(unshared.title, original.title);
  });

  test('损坏的 JSON 字段有兜底，不抛错', () {
    final restored = DreamDiaryEntry.fromJson({});
    expect(restored.id, isEmpty);
    expect(restored.sharedWithCharacter, isFalse);
  });

  test('prompt 只注入分享过的条目，最多 2 条', () {
    final block = DreamDiaryService.buildPromptBlock([
      entry(id: 'd1'),
      entry(id: 'd2', title: '第二场', shared: false),
      entry(id: 'd3', title: '第三场'),
      entry(id: 'd4', title: '第四场'),
    ]);
    expect(block, contains('初遇'));
    expect(block, contains('第三场'));
    expect(block, isNot(contains('第二场')));
    expect(block, isNot(contains('第四场')));
  });

  test('没有可注入的条目返回空串', () {
    expect(DreamDiaryService.buildPromptBlock([]), isEmpty);
    expect(
      DreamDiaryService.buildPromptBlock([entry(shared: false)]),
      isEmpty,
    );
    expect(
      DreamDiaryService.buildPromptBlock([entry(content: '   ')]),
      isEmpty,
    );
  });

  test('超长内容截断到 120 字', () {
    final long = '剧情' * 100;
    final block = DreamDiaryService.buildPromptBlock([entry(content: long)]);
    expect(block, contains('...'));
    expect(block, contains(long.substring(0, 120)));
    expect(block, isNot(contains(long)));
  });
}
