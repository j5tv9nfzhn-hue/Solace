import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/constants.dart';

/// 打开指定 App 页面的结果。
class AccessibilityOpenResult {
  const AccessibilityOpenResult({required this.ok, required this.message});

  final bool ok;

  /// 给用户看的一句话说明。
  final String message;
}

/// 无障碍可选模块（默认关闭；核心功能不依赖它）。
///
/// 安全演示流程：按用户明确指令打开指定 App 的指定页面，停在打开页即止，
/// 绝不自动点确认/支付/提交（原生侧根本没有 performAction/手势实现）。
/// 对标 Operit 的做法：工具权限分级、默认每次询问、操作前明确说明、
/// 可随时关；本模块连“每次询问”都不走自动执行——每一次打开都要用户
/// 在设置页亲手点按钮。
class AccessibilityAutomationService {
  static const _channel = MethodChannel(MethodChannels.accessibility);

  static const _kEnabled = 'accessibility_automation_enabled';

  /// 模块开关（默认关）。关掉即停用打开 App 功能，不影响任何核心体验。
  Future<bool> isModuleEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kEnabled) ?? false;
  }

  Future<void> setModuleEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabled, enabled);
  }

  /// 系统无障碍服务是否已开启（读 Settings.Secure，与模块开关无关）。
  Future<bool> isServiceEnabled() async {
    try {
      return await _channel.invokeMethod<bool>('isServiceEnabled') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 打开系统无障碍设置页（用户手动开启，程序内无法代开）。
  Future<void> openSystemSettings() async {
    try {
      await _channel.invokeMethod('openAccessibilitySettings');
    } catch (_) {}
  }

  /// 按用户明确指令打开指定 App 的指定页面，停在打开页即止。
  ///
  /// [packageName] 为目标 App 包名（如 `com.android.settings`）；
  /// [uri] 为可选深链（如某个 App 的内部页面链接），不填则只打开 App 首页。
  /// 模块关闭、包名为空、App 未安装时均拒绝并说明原因。
  Future<AccessibilityOpenResult> openAppPage({
    required String packageName,
    String? uri,
  }) async {
    if (!await isModuleEnabled()) {
      return const AccessibilityOpenResult(
        ok: false,
        message: '无障碍模块未开启：先在设置页打开开关（默认关闭）。',
      );
    }
    final pkg = packageName.trim();
    if (pkg.isEmpty) {
      return const AccessibilityOpenResult(
        ok: false,
        message: '没给 App 包名，不知道要打开哪个 App。',
      );
    }
    try {
      final ok = await _channel.invokeMethod<bool>('openAppPage', {
            'packageName': pkg,
            'uri': (uri ?? '').trim(),
          }) ??
          false;
      if (ok) {
        return AccessibilityOpenResult(
          ok: true,
          message: '已打开 $pkg，停在打开页，不会自动点任何按钮。',
        );
      }
      return AccessibilityOpenResult(
        ok: false,
        message: '打开失败：可能没装 $pkg，或系统拒绝了跳转。',
      );
    } on PlatformException catch (e) {
      if (e.code == 'MODULE_DISABLED') {
        return const AccessibilityOpenResult(
          ok: false,
          message: '无障碍模块未开启：先在设置页打开开关（默认关闭）。',
        );
      }
      if (e.code == 'APP_NOT_FOUND') {
        return AccessibilityOpenResult(
          ok: false,
          message: '没装 $pkg，打开失败。',
        );
      }
      return AccessibilityOpenResult(
        ok: false,
        message: '打开失败：${e.message ?? e.code}',
      );
    } catch (e) {
      return AccessibilityOpenResult(
        ok: false,
        message: '打开失败：$e',
      );
    }
  }
}
