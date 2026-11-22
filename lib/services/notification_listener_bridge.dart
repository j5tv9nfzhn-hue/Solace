import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/constants.dart';

/// 通知栏里的一条通知摘要（只含标题/正文前 100 字，不含任何 App 内文字）。
class ListenerNotification {
  const ListenerNotification({
    required this.key,
    required this.packageName,
    required this.title,
    required this.text,
    required this.hasReplyAction,
    required this.hasMediaAction,
  });

  /// 系统通知 key（代回时用）。
  final String key;
  final String packageName;
  final String title;
  final String text;

  /// 是否带 RemoteInput 回复动作。
  final bool hasReplyAction;

  /// 是否带播放/暂停动作。
  final bool hasMediaAction;

  factory ListenerNotification.fromMap(Map<String, dynamic> map) {
    return ListenerNotification(
      key: map['key'] as String? ?? '',
      packageName: map['packageName'] as String? ?? '',
      title: map['title'] as String? ?? '',
      text: map['text'] as String? ?? '',
      hasReplyAction: map['hasReplyAction'] as bool? ?? false,
      hasMediaAction: map['hasMediaAction'] as bool? ?? false,
    );
  }
}

/// 通知监听桥接（可选模块，默认关闭）。
///
/// 能力边界：只读通知栏摘要、在用户主动点的通知上用 RemoteInput 代回、
/// 只点音乐通知自带的播放/暂停动作。服务本身不联网、不上传。
/// 系统授权（通知访问）只能由用户在系统设置里手动开，程序内开不了；
/// 本模块开关只决定“是否使用”，关掉即停用全部三个动作。
class NotificationListenerBridge {
  static const _channel =
      MethodChannel(MethodChannels.notificationBridge);

  static const _kEnabled = 'notification_listener_enabled';

  /// 模块开关（默认关）。
  Future<bool> isModuleEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kEnabled) ?? false;
  }

  Future<void> setModuleEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabled, enabled);
  }

  /// 系统是否已授予通知访问（读 Settings.Secure，与模块开关无关）。
  Future<bool> isSystemEnabled() async {
    try {
      return await _channel.invokeMethod<bool>('isListenerEnabled') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 打开系统“通知访问”设置页（用户手动授予，程序内无法代开）。
  Future<void> openSystemSettings() async {
    try {
      await _channel.invokeMethod('openListenerSettings');
    } catch (_) {}
  }

  /// 最近通知摘要（模块关闭时返回空，不读）。
  Future<List<ListenerNotification>> getRecent() async {
    if (!await isModuleEnabled()) return const [];
    try {
      final raw =
          await _channel.invokeMethod<String>('getRecentNotifications');
      if (raw == null || raw.isEmpty) return const [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => ListenerNotification.fromMap(
              Map<String, dynamic>.from(e as Map)))
          .where((n) => n.key.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// 在指定通知上代回 [text]（需模块开启 + 系统已授权 + 该通知可回复）。
  Future<bool> reply(String key, String text) async {
    if (!await isModuleEnabled()) return false;
    if (key.isEmpty || text.trim().isEmpty) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'replyToNotification',
            {'key': key, 'text': text.trim()},
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// 切换音乐播放/暂停（需模块开启 + 系统已授权 + 有音乐通知）。
  Future<bool> toggleMediaPlayback() async {
    if (!await isModuleEnabled()) return false;
    try {
      return await _channel.invokeMethod<bool>('toggleMediaPlayback') ??
          false;
    } catch (_) {
      return false;
    }
  }
}
