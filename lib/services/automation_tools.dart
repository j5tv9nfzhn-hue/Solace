import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'notification_service.dart';

/// 工具使用策略（对标 Operit 每工具三档，默认每次询问）。
enum AutomationToolPolicy {
  /// 每次执行前问用户（默认）。
  ask,

  /// 用户已明确允许，直接执行。
  allow,

  /// 拒绝使用该工具。
  deny,
}

/// 确定性工具执行结果。
///
/// 人设隔离铁律：这里只产出“执行结果摘要”供调用方当上下文喂给角色，
/// 工具定义（schema/参数表）绝不进角色 prompt。
class AutomationToolResult {
  const AutomationToolResult({
    required this.ok,
    required this.summary,
    this.detail,
    this.needsConfirmation = false,
    this.fallbackHint,
  });

  /// 是否执行成功。
  final bool ok;

  /// 一句话结果摘要（可直接当上下文）。
  final String summary;

  /// 补充说明（成功时为执行细节，失败时为失败原因）。
  final String? detail;

  /// true = 策略为“每次询问”且本次未确认，调用方应先问用户再重调。
  final bool needsConfirmation;

  /// 失败时的降级指引。
  final String? fallbackHint;

  factory AutomationToolResult.needsConfirmation(String toolName) {
    return AutomationToolResult(
      ok: false,
      summary: '“$toolName”需要你先点头才执行。',
      needsConfirmation: true,
    );
  }

  factory AutomationToolResult.denied(String toolName) {
    return AutomationToolResult(
      ok: false,
      summary: '“$toolName”已被你设为拒绝，不执行。',
      fallbackHint: '可在设置页把该工具改回“每次询问”或“允许”。',
    );
  }
}

/// 外卖深链（一句话下单的跳转目标）。
///
/// 只跳到美团外卖/美团 App 的搜索页（店名 + 菜名已带上），不预填支付、
/// 不自动下单、不传任何订单参数；支付铁律：用户自己在美团里指纹确认。
class TakeoutLinks {
  const TakeoutLinks({required this.primary, required this.fallback});

  /// 美团外卖 App（`meituanwaimai://`，社区公开的 URL Scheme）。
  final Uri primary;

  /// 美团主 App（`imeituan://`，社区公开的 URL Scheme）。
  final Uri fallback;
}

/// 确定性工具：外卖深链 / 闹钟 / 日历事件 / 本地通知 / 换壁纸。
///
/// 全部只用普通权限或系统 Intent（用户在系统界面里自己点确认），
/// 不用 Shizuku、不要求 root、不读屏、不模拟点击。
/// 每个工具的执行都受 [AutomationToolPolicy] 管：默认每次询问。
class AutomationTools {
  static const _channel = MethodChannel('com.solace.solace/automation');

  static const String toolTakeout = 'takeout';
  static const String toolAlarm = 'alarm';
  static const String toolCalendar = 'calendar';
  static const String toolNotification = 'notification';
  static const String toolWallpaper = 'wallpaper';

  static const List<String> allToolIds = [
    toolTakeout,
    toolAlarm,
    toolCalendar,
    toolNotification,
    toolWallpaper,
  ];

  static const Map<String, String> toolNames = {
    toolTakeout: '外卖深链',
    toolAlarm: '设闹钟',
    toolCalendar: '新建日历事件',
    toolNotification: '发本地通知',
    toolWallpaper: '换壁纸',
  };

  /// 各工具需要的权限/开启方式（设置页展示用）。
  static const Map<String, String> toolPermissionNotes = {
    toolTakeout:
        '无需系统权限；需安装美团外卖或美团 App，未安装时只留文字、不跳转。',
    toolAlarm: '无需系统权限；调用系统时钟设闹钟界面，由你自己点确认。',
    toolCalendar: '无需日历读写权限；调用系统日历新建界面，由你自己点保存。',
    toolNotification: '需通知权限（POST_NOTIFICATIONS）；未授予时通知发不出去。',
    toolWallpaper: '需 SET_WALLPAPER（普通权限，安装即授予）；图片须是本机文件。',
  };

  static String _policyKey(String toolId) => 'automation_policy_$toolId';

  Future<AutomationToolPolicy> getPolicy(String toolId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_policyKey(toolId));
    switch (raw) {
      case 'allow':
        return AutomationToolPolicy.allow;
      case 'deny':
        return AutomationToolPolicy.deny;
      case 'ask':
      default:
        return AutomationToolPolicy.ask;
    }
  }

  Future<void> setPolicy(
      String toolId, AutomationToolPolicy policy) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_policyKey(toolId), policy.name);
  }

  /// 执行工具（策略门：拒绝/未确认时不执行，只返回结果）。
  ///
  /// [args] 按工具取键：外卖 `shopName`/`dishes`（逗号分隔）；
  /// 闹钟 `hour`/`minute`/`label`；日历 `title`/`startMillis`/
  /// `endMillis`/`description`；通知 `title`/`body`/`delayMinutes`；
  /// 壁纸 `filePath`。
  Future<AutomationToolResult> execute(
    String toolId,
    Map<String, String> args, {
    bool confirmed = false,
  }) async {
    final policy = await getPolicy(toolId);
    final name = toolNames[toolId] ?? toolId;
    if (policy == AutomationToolPolicy.deny) {
      return AutomationToolResult.denied(name);
    }
    if (policy == AutomationToolPolicy.ask && !confirmed) {
      return AutomationToolResult.needsConfirmation(name);
    }
    try {
      switch (toolId) {
        case toolTakeout:
          return await _openTakeout(args);
        case toolAlarm:
          return await _setAlarm(args);
        case toolCalendar:
          return await _addCalendarEvent(args);
        case toolNotification:
          return await _sendNotification(args);
        case toolWallpaper:
          return await _setWallpaper(args);
        default:
          return AutomationToolResult(
            ok: false,
            summary: '未知工具：$toolId。',
          );
      }
    } catch (e) {
      return AutomationToolResult(
        ok: false,
        summary: '“$name”执行失败：$e',
        fallbackHint: toolPermissionNotes[toolId],
      );
    }
  }

  /// 外卖深链：按店名 + 菜名拼两个公开 URL Scheme（纯函数，可单测）。
  ///
  /// 只带搜索词，不带任何价格/订单/支付参数。
  static TakeoutLinks buildTakeoutLinks({
    required String shopName,
    List<String> dishes = const [],
  }) {
    final query = ([shopName, ...dishes]
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .join(' '))
        .trim();
    final encoded = Uri.encodeQueryComponent(query);
    return TakeoutLinks(
      primary: Uri.parse(
          'meituanwaimai://waimai.meituan.com/search?query=$encoded'),
      fallback: Uri.parse('imeituan://www.meituan.com/search?q=$encoded'),
    );
  }

  Future<AutomationToolResult> _openTakeout(
      Map<String, String> args) async {
    final shopName = (args['shopName'] ?? '').trim();
    final dishes = (args['dishes'] ?? '')
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (shopName.isEmpty) {
      return const AutomationToolResult(
        ok: false,
        summary: '没给店名，跳不过去。',
        fallbackHint: '先说想吃哪家店（或哪道菜），再帮你打开美团。',
      );
    }
    final links =
        buildTakeoutLinks(shopName: shopName, dishes: dishes);
    final dishText = dishes.isEmpty ? '' : '，菜已备好：${dishes.join('、')}';
    for (final uri in [links.primary, links.fallback]) {
      try {
        if (await canLaunchUrl(uri)) {
          final launched = await launchUrl(
            uri,
            mode: LaunchMode.externalApplication,
          );
          if (launched) {
            return AutomationToolResult(
              ok: true,
              summary: '已打开美团搜索「$shopName」$dishText，'
                  '等你自己挑好、自己指纹确认支付，我不替你下单。',
              detail: uri.toString(),
            );
          }
        }
      } catch (_) {
        // 换下一个 scheme 继续试。
      }
    }
    return AutomationToolResult(
      ok: false,
      summary: '没装美团外卖/美团 App，跳不过去。',
      detail: '店：$shopName$dishText',
      fallbackHint: '装好美团外卖后重试，或手动打开美团搜「$shopName」。',
    );
  }

  Future<AutomationToolResult> _setAlarm(
      Map<String, String> args) async {
    final hour = int.tryParse(args['hour'] ?? '');
    final minute = int.tryParse(args['minute'] ?? '');
    final label = (args['label'] ?? 'Solace 提醒').trim();
    if (hour == null || hour < 0 || hour > 23 || minute == null || minute < 0 || minute > 59) {
      return const AutomationToolResult(
        ok: false,
        summary: '闹钟时间不对（小时 0–23，分钟 0–59）。',
      );
    }
    final ok = await _channel.invokeMethod<bool>('setAlarm', {
      'hour': hour,
      'minute': minute,
      'message': label,
    });
    final hh = hour.toString().padLeft(2, '0');
    final mm = minute.toString().padLeft(2, '0');
    if (ok == true) {
      return AutomationToolResult(
        ok: true,
        summary: '已打开系统时钟，闹钟 $hh:$mm（$label）等你点确认。',
      );
    }
    return const AutomationToolResult(
      ok: false,
      summary: '系统没有可用的时钟应用，设不了闹钟。',
      fallbackHint: '可在系统时钟里手动设闹钟。',
    );
  }

  Future<AutomationToolResult> _addCalendarEvent(
      Map<String, String> args) async {
    final title = (args['title'] ?? '').trim();
    final startMillis = int.tryParse(args['startMillis'] ?? '');
    final endMillis = int.tryParse(args['endMillis'] ?? '');
    if (title.isEmpty || startMillis == null || endMillis == null) {
      return const AutomationToolResult(
        ok: false,
        summary: '日历事件缺标题或起止时间。',
      );
    }
    final ok = await _channel.invokeMethod<bool>('addCalendarEvent', {
      'title': title,
      'startMillis': startMillis,
      'endMillis': endMillis,
      'description': (args['description'] ?? '').trim(),
    });
    if (ok == true) {
      return AutomationToolResult(
        ok: true,
        summary: '已打开系统日历新建页「$title」，等你点保存。',
      );
    }
    return const AutomationToolResult(
      ok: false,
      summary: '系统没有可用的日历应用。',
      fallbackHint: '可在系统日历里手动新建事件。',
    );
  }

  Future<AutomationToolResult> _sendNotification(
      Map<String, String> args) async {
    final title = (args['title'] ?? 'Solace').trim();
    final body = (args['body'] ?? '').trim();
    if (body.isEmpty) {
      return const AutomationToolResult(
        ok: false,
        summary: '通知内容为空，发不了。',
      );
    }
    final service = NotificationService();
    await service.initialize();
    final delayMinutes = int.tryParse(args['delayMinutes'] ?? '0') ?? 0;
    final id = DateTime.now().millisecondsSinceEpoch % 100000;
    if (delayMinutes > 0) {
      await service.scheduleNotification(
        id: id,
        title: title,
        body: body,
        scheduledTime:
            DateTime.now().add(Duration(minutes: delayMinutes)),
      );
      return AutomationToolResult(
        ok: true,
        summary: '已安排 $delayMinutes 分钟后发通知「$title」。',
      );
    }
    await service.showInstantNotification(id: id, title: title, body: body);
    return AutomationToolResult(
      ok: true,
      summary: '已发本地通知「$title」。',
    );
  }

  Future<AutomationToolResult> _setWallpaper(
      Map<String, String> args) async {
    final filePath = (args['filePath'] ?? '').trim();
    if (filePath.isEmpty) {
      return const AutomationToolResult(
        ok: false,
        summary: '没给图片路径，换不了壁纸。',
      );
    }
    if (!await File(filePath).exists()) {
      return AutomationToolResult(
        ok: false,
        summary: '图片文件不存在：$filePath。',
        fallbackHint: '先在相册里选一张图（会存到本机），再换壁纸。',
      );
    }
    final ok = await _channel.invokeMethod<bool>(
        'setWallpaper', {'filePath': filePath});
    if (ok == true) {
      return const AutomationToolResult(
        ok: true,
        summary: '壁纸已换好。',
      );
    }
    return const AutomationToolResult(
      ok: false,
      summary: '换壁纸失败（图片可能损坏或格式不支持）。',
      fallbackHint: '换一张 JPG/PNG 图片重试。',
    );
  }
}
