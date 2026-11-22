import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:uuid/uuid.dart';

import '../models/ai_character.dart';
import '../utils/safe_file_picker.dart';

/// 角色卡本地导入导出 — 角色以本地文件进出，不经过服务器。
///
/// 格式：JSON 文本，`{"format":"solace-character-card","version":1,
/// "exportedAt":"...","character":{...AICharacter.toMap()...}}`。
/// 只导出角色本身的人设字段（[AICharacter.toMap] 的内容），不含聊天记录、
/// 记忆、钱包等数据；导入时生成新 id，不覆盖已有角色。
/// 头像只存本机路径：导入时头像文件不在本机就去掉头像（不报错，只提示）。
class CharacterCardIOService {
  CharacterCardIOService._();

  static const String formatName = 'solace-character-card';
  static const int formatVersion = 1;

  // ─── 导出 ────────────────────────────────────

  /// 把角色拼成导出 JSON（纯函数，方便单测）。
  static String buildExportJson(AICharacter character) {
    return jsonEncode({
      'format': formatName,
      'version': formatVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'character': character.toMap(),
    });
  }

  /// 导出：弹系统保存框，让用户选位置存 `.json` 文件。
  /// 返回 true=已保存，false=用户取消；失败抛错，由调用方提示。
  static Future<bool> exportCharacter(AICharacter character) async {
    final bytes = Uint8List.fromList(utf8.encode(buildExportJson(character)));
    final fileName = '${_sanitizeFileName(character.name)}_角色卡.json';
    final savedPath = await SafeFilePicker.saveFile(
      dialogTitle: '导出角色卡',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: ['json'],
      bytes: bytes,
    );
    return savedPath != null;
  }

  // ─── 导入 ────────────────────────────────────

  /// 导入：弹系统选文件框，读一个 `.json` 角色卡，校验后返回新角色。
  /// 用户取消返回 [CharacterCardImportResult.cancelled]；
  /// 文件不对返回带 [CharacterCardImportResult.error] 的结果，不抛错。
  static Future<CharacterCardImportResult> importCharacter() async {
    final picked = await SafeFilePicker.pickFiles(
      dialogTitle: '导入角色卡',
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) {
      return const CharacterCardImportResult.cancelled();
    }
    final bytes = picked.files.first.bytes;
    if (bytes == null) {
      return const CharacterCardImportResult.error('读取不到文件内容，请重试');
    }
    String text;
    try {
      text = utf8.decode(bytes);
    } catch (_) {
      return const CharacterCardImportResult.error('文件不是有效的文本，请选 Solace 导出的角色卡');
    }
    return parseImportJson(text);
  }

  /// 解析导入 JSON（纯函数，方便单测）：校验格式与必填字段，
  /// 通过则返回带全新 id 的角色；头像文件不在本机时去掉头像并记一条提醒。
  static CharacterCardImportResult parseImportJson(String jsonText) {
    Map<String, dynamic> root;
    try {
      final decoded = jsonDecode(jsonText);
      if (decoded is! Map<String, dynamic>) {
        return const CharacterCardImportResult.error('文件内容不是角色卡');
      }
      root = decoded;
    } catch (e) {
      debugPrint('角色卡导入：JSON 解析失败 — $e');
      return const CharacterCardImportResult.error('文件不是有效的 JSON，请选 Solace 导出的角色卡');
    }

    if (root['format'] != formatName) {
      return const CharacterCardImportResult.error('这不是 Solace 角色卡（格式不对）');
    }
    if (root['version'] != formatVersion) {
      return const CharacterCardImportResult.error('角色卡版本不受支持');
    }
    final rawCharacter = root['character'];
    if (rawCharacter is! Map<String, dynamic>) {
      return const CharacterCardImportResult.error('角色卡里没有角色数据');
    }

    final name = (rawCharacter['name'] as String?)?.trim() ?? '';
    final personality = (rawCharacter['personality'] as String?)?.trim() ?? '';
    final coreDesire = (rawCharacter['coreDesire'] as String?)?.trim() ?? '';
    final moralBoundary =
        (rawCharacter['moralBoundary'] as String?)?.trim() ?? '';
    if (name.isEmpty) {
      return const CharacterCardImportResult.error('角色卡缺少角色名');
    }
    if (personality.isEmpty || coreDesire.isEmpty || moralBoundary.isEmpty) {
      return const CharacterCardImportResult.error('角色卡缺少性格/心愿/原则，数据不完整');
    }

    AICharacter character;
    try {
      character = AICharacter.fromMap(rawCharacter);
    } catch (e) {
      debugPrint('角色卡导入：角色解析失败 — $e');
      return const CharacterCardImportResult.error('角色数据解析失败，文件可能已损坏');
    }

    final warnings = <String>[];
    var avatarUrl = character.avatarUrl;
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      var avatarExists = false;
      try {
        avatarExists = File(avatarUrl).existsSync();
      } catch (_) {
        avatarExists = false;
      }
      if (!avatarExists) {
        avatarUrl = null;
        warnings.add('头像文件不在本机，已去掉头像');
      }
    }

    // 导入永远是新角色：新 id、新建时间，不覆盖已有角色。
    // 注意：copyWith 传 null 清不掉头像（`avatarUrl ?? this.avatarUrl`），
    // 去掉头像必须走 clearAvatarUrl（见 ai_character.dart 的既有写法）。
    final imported = character.copyWith(
      id: const Uuid().v4(),
      avatarUrl: avatarUrl,
      clearAvatarUrl: avatarUrl == null && character.avatarUrl != null,
      createdAt: DateTime.now(),
    );
    return CharacterCardImportResult.success(imported, warnings: warnings);
  }

  static String _sanitizeFileName(String name) {
    final cleaned = name
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .trim();
    return cleaned.isEmpty ? '角色卡' : cleaned;
  }
}

/// 导入结果：成功 / 取消 / 失败三态，调用方按状态提示，不抛错。
class CharacterCardImportResult {
  final AICharacter? character;
  final List<String> warnings;
  final String? error;
  final bool isCancelled;

  const CharacterCardImportResult._({
    this.character,
    this.warnings = const [],
    this.error,
    this.isCancelled = false,
  });

  const CharacterCardImportResult.success(
    AICharacter character, {
    List<String> warnings = const [],
  }) : this._(character: character, warnings: warnings);

  const CharacterCardImportResult.cancelled() : this._(isCancelled: true);

  const CharacterCardImportResult.error(String message)
      : this._(error: message);

  bool get isSuccess => character != null;
  bool get isError => error != null;
}
