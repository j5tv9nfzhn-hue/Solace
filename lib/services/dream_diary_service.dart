import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:uuid/uuid.dart';

import '../config/constants.dart';
import '../models/dream_diary_entry.dart';
import '../repositories/local_storage_repository.dart';

/// 梦境日记服务 — 读写 + 注入单聊 prompt。
///
/// 存储复用角色日记的 SharedPreferences JSON 列表写法
///（`storage.getString/setString`，见 `ai_diary_screen.dart`），不建表；
/// 注入只取用户逐条打开分享的条目，最多 2 条、每条截断，失败时静默跳过，
/// 绝不阻塞聊天。
class DreamDiaryService {
  DreamDiaryService._();

  /// 注入上限：最多 2 条分享过的日记，每条最多 120 字（省 token）
  static const int maxInjectEntries = 2;
  static const int maxInjectChars = 120;

  /// 读全部日记（按时间倒序）。JSON 损坏的条目跳过，不抛错。
  static Future<List<DreamDiaryEntry>> loadAll(
    LocalStorageRepository storage,
  ) async {
    final raw = storage.getString(PrefKeys.dreamDiaryEntries);
    if (raw == null || raw.trim().isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      final entries = <DreamDiaryEntry>[];
      for (final item in list) {
        try {
          if (item is Map<String, dynamic>) {
            final entry = DreamDiaryEntry.fromJson(item);
            if (entry.id.isNotEmpty && entry.characterId.isNotEmpty) {
              entries.add(entry);
            }
          }
        } catch (e) {
          debugPrint('梦境日记：跳过一条损坏记录 — $e');
        }
      }
      entries.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return entries;
    } catch (e) {
      debugPrint('梦境日记：读取失败 — $e');
      return [];
    }
  }

  /// 新增一篇日记（id 由调用方或本方法生成），返回新建的条目。
  static Future<DreamDiaryEntry> createEntry({
    required LocalStorageRepository storage,
    required String characterId,
    required String title,
    required String content,
    String mood = '',
    bool sharedWithCharacter = false,
  }) async {
    final entry = DreamDiaryEntry(
      id: const Uuid().v4(),
      characterId: characterId,
      title: title.trim(),
      content: content.trim(),
      mood: mood.trim(),
      createdAt: DateTime.now(),
      sharedWithCharacter: sharedWithCharacter,
    );
    final all = await loadAll(storage);
    all.insert(0, entry);
    await _persist(storage, all);
    return entry;
  }

  /// 更新一条（按 id 替换，不存在则不写）。
  static Future<void> updateEntry(
    LocalStorageRepository storage,
    DreamDiaryEntry updated,
  ) async {
    final all = await loadAll(storage);
    final index = all.indexWhere((e) => e.id == updated.id);
    if (index < 0) return;
    all[index] = updated;
    await _persist(storage, all);
  }

  /// 删除一条。
  static Future<void> deleteEntry(
    LocalStorageRepository storage,
    String id,
  ) async {
    final all = await loadAll(storage);
    all.removeWhere((e) => e.id == id);
    await _persist(storage, all);
  }

  /// 给某个角色注入的 prompt 段：只取该角色分享过的日记。
  static Future<String> buildPromptBlockForCharacter(
    LocalStorageRepository storage,
    String characterId,
  ) async {
    final all = await loadAll(storage);
    final shared = all
        .where((e) => e.characterId == characterId && e.sharedWithCharacter)
        .toList();
    return buildPromptBlock(shared);
  }

  /// 纯函数：把日记条目拼成 prompt 段（方便单测）。
  /// 只取分享过的、内容非空的条目，最多 2 条；空列表或无可注入条目返回空串。
  static String buildPromptBlock(List<DreamDiaryEntry> entries) {
    final usable = entries
        .where((e) => e.sharedWithCharacter && e.content.trim().isNotEmpty)
        .take(maxInjectEntries)
        .toList();
    if (usable.isEmpty) return '';
    final buffer = StringBuffer();
    buffer.writeln('\n【用户写给你的梦境日记 — 已分享】');
    buffer.writeln('用户把下面这些脑洞剧情写下来并分享给了你，说明 TA 很想和你聊这些：');
    for (final entry in usable) {
      final content = entry.content.trim();
      final shown = content.length > maxInjectChars
          ? '${content.substring(0, maxInjectChars)}...'
          : content;
      final title = entry.title.trim().isEmpty ? '无标题' : entry.title.trim();
      final mood = entry.mood.trim().isEmpty ? '' : '（心情：${entry.mood.trim()}）';
      buffer.writeln('- 《$title》$mood：$shown');
    }
    buffer.writeln('如果用户聊起相关剧情，请自然地接上、回应 TA 的脑洞；没聊到时不用主动提起。');
    return buffer.toString();
  }

  static Future<void> _persist(
    LocalStorageRepository storage,
    List<DreamDiaryEntry> entries,
  ) async {
    await storage.setString(
      PrefKeys.dreamDiaryEntries,
      jsonEncode(entries.map((e) => e.toJson()).toList()),
    );
  }
}
