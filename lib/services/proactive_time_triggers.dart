import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/constants.dart';
import 'proactive_rate_limiter.dart';
import 'proactive_trigger_rules.dart';

/// 时间触发节流（纯函数，可单测）：冷却 + 每日上限双闸。
///
/// 冷却按“上次触发”算，每日上限按“今天已触发次数”算；
/// 两道闸都过才放行，绝不连发打扰用户。
class TimeTriggerGate {
  TimeTriggerGate._();

  static bool shouldFire({
    required DateTime now,
    required DateTime? lastFiredAt,
    required int cooldownMinutes,
    required int dailyCap,
    required int firedToday,
  }) {
    if (firedToday >= dailyCap) return false;
    if (lastFiredAt != null &&
        now.difference(lastFiredAt).inMinutes < cooldownMinutes) {
      return false;
    }
    return true;
  }
}

/// 时间触发的开关与触发记录（SharedPreferences 持久化，跨重启有效）。
///
/// 每条规则独立开关（默认全开，设置页可关）；
/// 触发记录按规则 id 存“上次触发时间 + 当天日期 + 当天次数”。
class ProactiveTimeTriggerState {
  static String _enabledKey(String ruleId) {
    switch (ruleId) {
      case 'time_meal':
        return PrefKeys.timeTriggerMeal;
      case 'time_long_screen':
        return PrefKeys.timeTriggerLongScreen;
      case 'time_late_night':
        return PrefKeys.timeTriggerLateNight;
      default:
        return 'time_trigger_enabled_$ruleId';
    }
  }

  static String _lastKey(String ruleId) => 'time_trigger_last_$ruleId';
  static String _dayKey(String ruleId) => 'time_trigger_day_$ruleId';
  static String _countKey(String ruleId) => 'time_trigger_count_$ruleId';

  static String _dayString(DateTime now) =>
      '${now.year}-${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';

  /// 规则是否开启（默认开）。
  Future<bool> isEnabled(String ruleId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey(ruleId)) ?? true;
  }

  Future<void> setEnabled(String ruleId, bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey(ruleId), enabled);
  }

  /// 在 [now] 时刻，[recentScreenMinutes]（最近 3 小时亮屏分钟）下，
  /// 返回所有“命中时间窗口且过了节流闸”的规则（按内置顺序）。
  Future<List<ProactiveTriggerRule>> checkTimeRules({
    required DateTime now,
    required int recentScreenMinutes,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final matched = ProactiveTriggerRules.matchTimeBased(
      now: now,
      recentScreenMinutes: recentScreenMinutes,
    );
    final due = <ProactiveTriggerRule>[];
    for (final rule in matched) {
      if (prefs.getBool(_enabledKey(rule.id)) == false) continue;
      final lastRaw = prefs.getString(_lastKey(rule.id));
      final lastFiredAt =
          lastRaw == null ? null : DateTime.tryParse(lastRaw);
      var firedToday = 0;
      if (prefs.getString(_dayKey(rule.id)) == _dayString(now)) {
        firedToday = prefs.getInt(_countKey(rule.id)) ?? 0;
      }
      if (TimeTriggerGate.shouldFire(
        now: now,
        lastFiredAt: lastFiredAt,
        cooldownMinutes: rule.cooldownMinutes ??
            ProactiveRateLimiter.defaultCooldownMinutes,
        dailyCap: rule.dailyCap,
        firedToday: firedToday,
      )) {
        due.add(rule);
      }
    }
    return due;
  }

  /// 记录一次触发（供决策引擎放行后调用）。
  Future<void> markFired(String ruleId, DateTime now) async {
    final prefs = await SharedPreferences.getInstance();
    final today = _dayString(now);
    final firedToday = prefs.getString(_dayKey(ruleId)) == today
        ? (prefs.getInt(_countKey(ruleId)) ?? 0)
        : 0;
    await prefs.setString(_lastKey(ruleId), now.toIso8601String());
    await prefs.setString(_dayKey(ruleId), today);
    await prefs.setInt(_countKey(ruleId), firedToday + 1);
    debugPrint('[TimeTrigger] 规则 $ruleId 已触发（今天第 ${firedToday + 1} 次）');
  }
}
