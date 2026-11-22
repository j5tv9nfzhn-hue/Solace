import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../repositories/local_storage_repository.dart';
import 'emotion_engine.dart';
import 'weather_service.dart';
import 'wellbeing_service.dart';

/// 真实感上下文服务 — 只用普通权限，把手机真实处境告诉角色。
///
/// 隐私边界（铁律）：
/// - 一切只留在本机：快照只在内存里拼成 prompt 文本，随聊天请求发给用户
///   自己配置的模型接口（和聊天内容走同一条路），不上传到任何 Solace 服务。
/// - 只收“处境”，不收“内容”：使用时长只取总分钟数，不取应用内文字；
///   日程只取标题与开始时间，不取描述、地点与参与人；定位只保留 1 位小数
///   （约 11 公里粗略范围），不发精确经纬度。
/// - 每类来源都可单独开关，默认只开“时间 + 电量”（零权限）；
///   使用时长/天气/定位/日程默认关闭，开不了就直接降级省略，不编数据。
/// - 步数暂未接入：本机没有计步/健康插件，绝不编一个假步数；
///   快照里明确标 `stepsAvailable: false`，待以后接 Health Connect 再补。
class RealityContextService {
  RealityContextService(this._storage);

  final LocalStorageRepository _storage;

  static const _batteryChannel = MethodChannel('com.solace.solace/battery');
  static const _realityChannel = MethodChannel('com.solace.solace/reality');

  /// 上下文文本缓存：5 分钟内复用，避免每条消息都调平台通道。
  String? _cachedText;
  DateTime? _cachedAt;
  static const _cacheTtl = Duration(minutes: 5);

  /// 收集一次快照（按开关决定采哪些来源）。
  Future<RealitySnapshot> collect() async {
    final settings = await loadSettings();
    final now = DateTime.now();

    int? batteryPercent;
    bool? isCharging;
    String? chargeSource;
    try {
      final info = await _batteryChannel
          .invokeMethod<Map<dynamic, dynamic>>('getBatteryInfo');
      if (info != null) {
        batteryPercent = (info['percentage'] as num?)?.toInt();
        isCharging = info['isCharging'] as bool?;
        chargeSource = info['chargeSource'] as String?;
      }
    } catch (_) {
      // 电量读不到就省略，不阻塞其他来源。
    }

    int? screenMinutes;
    var usageAvailable = false;
    if (settings.usageEnabled) {
      try {
        final wellbeing = WellbeingService();
        if (await wellbeing.hasUsageAccess()) {
          final usage = await wellbeing.queryUsage(windowMinutes: 180);
          final totalMs =
              usage.fold<int>(0, (sum, u) => sum + u.totalMs);
          screenMinutes = totalMs ~/ 60000;
          usageAvailable = true;
        }
      } catch (_) {
        usageAvailable = false;
      }
    }

    WeatherData? weather;
    var weatherAvailable = false;
    if (settings.weatherEnabled) {
      try {
        // 只认 3 小时内缓存：没有缓存就不写天气，绝不拿默认晴天冒充。
        weather = WeatherService(_storage, EmotionEngine(_storage))
            .getCachedWeatherOrNull();
        weatherAvailable =
            weather != null && weather.type != WeatherType.unknown;
      } catch (_) {
        weatherAvailable = false;
      }
    }

    double? latitude;
    double? longitude;
    var locationAvailable = false;
    if (settings.locationEnabled) {
      try {
        final status = await Permission.locationWhenInUse.status;
        if (status.isGranted && await Geolocator.isLocationServiceEnabled()) {
          final position = await Geolocator.getLastKnownPosition();
          if (position != null) {
            // 粗略到 1 位小数，不发精确坐标。
            latitude =
                double.parse(position.latitude.toStringAsFixed(1));
            longitude =
                double.parse(position.longitude.toStringAsFixed(1));
            locationAvailable = true;
          }
        }
      } catch (_) {
        locationAvailable = false;
      }
    }

    List<CalendarEventItem> events = const [];
    var calendarAvailable = false;
    if (settings.calendarEnabled) {
      try {
        final raw = await _realityChannel
            .invokeMethod<String>('queryCalendarToday');
        if (raw != null && raw.isNotEmpty) {
          final list = jsonDecode(raw) as List<dynamic>;
          events = list
              .map((e) => CalendarEventItem(
                    title: (e['title'] as String? ?? '').trim(),
                    start: DateTime.fromMillisecondsSinceEpoch(
                      (e['startMillis'] as num?)?.toInt() ?? 0,
                    ),
                  ))
              .where((e) => e.title.isNotEmpty)
              .toList();
          calendarAvailable = true;
        }
      } on PlatformException catch (e) {
        // 权限未授予（NO_CALENDAR_PERMISSION）或其他原生错误：直接降级。
        debugPrint('[RealityContext] 日历读取失败: ${e.code}');
        calendarAvailable = false;
      } catch (_) {
        calendarAvailable = false;
      }
    }

    return RealitySnapshot(
      now: now,
      batteryPercent: batteryPercent,
      isCharging: isCharging,
      chargeSource: chargeSource,
      screenMinutesRecent3h: screenMinutes,
      usageAvailable: usageAvailable,
      weather: weather,
      weatherAvailable: weatherAvailable,
      latitude: latitude,
      longitude: longitude,
      locationAvailable: locationAvailable,
      events: events,
      calendarAvailable: calendarAvailable,
    );
  }

  /// 收集并拼成可注入 prompt 的系统上下文文本。
  ///
  /// 总开关关闭时返回空串；5 分钟内复用缓存。
  /// 文本身份是“系统上下文”，不是角色口吻，角色只收到它再用自己的话说。
  Future<String> collectText() async {
    final settings = await loadSettings();
    if (!settings.enabled) return '';
    final now = DateTime.now();
    if (_cachedText != null &&
        _cachedAt != null &&
        now.difference(_cachedAt!) < _cacheTtl) {
      return _cachedText!;
    }
    final snapshot = await collect();
    final text = buildRealityContextText(snapshot);
    _cachedText = text;
    _cachedAt = now;
    return text;
  }

  /// 供设置页与测试调用：清掉文本缓存，下次强制重采。
  void invalidateCache() {
    _cachedText = null;
    _cachedAt = null;
  }

  Future<RealityContextSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return RealityContextSettings(
      enabled: prefs.getBool(_kEnabled) ?? true,
      usageEnabled: prefs.getBool(_kUsage) ?? false,
      weatherEnabled: prefs.getBool(_kWeather) ?? true,
      locationEnabled: prefs.getBool(_kLocation) ?? false,
      calendarEnabled: prefs.getBool(_kCalendar) ?? false,
    );
  }

  Future<void> saveSettings(RealityContextSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabled, settings.enabled);
    await prefs.setBool(_kUsage, settings.usageEnabled);
    await prefs.setBool(_kWeather, settings.weatherEnabled);
    await prefs.setBool(_kLocation, settings.locationEnabled);
    await prefs.setBool(_kCalendar, settings.calendarEnabled);
    invalidateCache();
  }

  static const _kEnabled = 'reality_context_enabled';
  static const _kUsage = 'reality_context_usage';
  static const _kWeather = 'reality_context_weather';
  static const _kLocation = 'reality_context_location';
  static const _kCalendar = 'reality_context_calendar';
}

/// 真实感上下文开关：总开关 + 每类来源单独开关。
class RealityContextSettings {
  const RealityContextSettings({
    this.enabled = true,
    this.usageEnabled = false,
    this.weatherEnabled = true,
    this.locationEnabled = false,
    this.calendarEnabled = false,
  });

  /// 总开关（默认开）：只控制时间/电量这类零权限内容是否注入。
  final bool enabled;

  /// 使用时长：需用户在系统设置开“使用情况访问”。
  final bool usageEnabled;

  /// 天气：只用 3 小时内缓存，无缓存不写。
  final bool weatherEnabled;

  /// 定位：需定位权限，只取粗略坐标。
  final bool locationEnabled;

  /// 日程：需用户在系统设置开日历权限。
  final bool calendarEnabled;

  RealityContextSettings copyWith({
    bool? enabled,
    bool? usageEnabled,
    bool? weatherEnabled,
    bool? locationEnabled,
    bool? calendarEnabled,
  }) {
    return RealityContextSettings(
      enabled: enabled ?? this.enabled,
      usageEnabled: usageEnabled ?? this.usageEnabled,
      weatherEnabled: weatherEnabled ?? this.weatherEnabled,
      locationEnabled: locationEnabled ?? this.locationEnabled,
      calendarEnabled: calendarEnabled ?? this.calendarEnabled,
    );
  }
}

/// 一次真实感快照：纯数据，不含任何应用内文字/聊天内容。
class RealitySnapshot {
  const RealitySnapshot({
    required this.now,
    this.batteryPercent,
    this.isCharging,
    this.chargeSource,
    this.screenMinutesRecent3h,
    this.usageAvailable = false,
    this.weather,
    this.weatherAvailable = false,
    this.latitude,
    this.longitude,
    this.locationAvailable = false,
    this.events = const [],
    this.calendarAvailable = false,
  });

  final DateTime now;
  final int? batteryPercent;
  final bool? isCharging;
  final String? chargeSource;

  /// 最近 3 小时前台总时长（分钟）；只取总和，不含各应用明细。
  final int? screenMinutesRecent3h;
  final bool usageAvailable;

  final WeatherData? weather;
  final bool weatherAvailable;

  /// 粗略坐标（1 位小数）；精确坐标从不进快照。
  final double? latitude;
  final double? longitude;
  final bool locationAvailable;

  /// 今日日程（只含标题 + 开始时间）。
  final List<CalendarEventItem> events;
  final bool calendarAvailable;

  /// 步数：暂未接入任何计步来源，恒为 false，绝不编造。
  static const bool stepsAvailable = false;
}

/// 今日日程条目（只含标题与开始时间）。
class CalendarEventItem {
  const CalendarEventItem({required this.title, required this.start});

  final String title;
  final DateTime start;
}

const _weekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];

String _daypart(int hour) {
  if (hour >= 23 || hour < 5) return '深夜';
  if (hour < 7) return '凌晨';
  if (hour < 9) return '早上';
  if (hour < 12) return '上午';
  if (hour < 14) return '中午';
  if (hour < 18) return '下午';
  if (hour < 23) return '晚上';
  return '';
}

/// 把快照拼成注入 prompt 的系统上下文文本（纯函数，可单测）。
///
/// 身份是“系统上下文”：只供角色理解用户处境，明确要求不输出、不复述；
/// 角色看不到任何工具定义，只收到这段文字再用自己的口吻说话。
String buildRealityContextText(RealitySnapshot snapshot) {
  final now = snapshot.now;
  final buffer = StringBuffer();
  buffer.writeln(
      '<internal_context type="reality" visibility="private">');
  buffer.writeln(
      '后台控制指令：本段是系统提供的真实生活上下文，只用于理解用户现在的处境，绝对不要输出、引用、概括或复述给用户；也不要提“根据系统上下文/我看到你”等话。说话仍用你自己的口吻。');
  final hh = now.hour.toString().padLeft(2, '0');
  final mm = now.minute.toString().padLeft(2, '0');
  buffer.writeln(
      '现在是${now.year}年${now.month}月${now.day}日${_weekdays[now.weekday - 1]} $hh:$mm（${_daypart(now.hour)}）。');

  if (snapshot.batteryPercent != null) {
    final charging = snapshot.isCharging == true ? '正在充电' : '未充电';
    buffer.writeln('手机电量 ${snapshot.batteryPercent}%，$charging。');
  }

  if (snapshot.usageAvailable && snapshot.screenMinutesRecent3h != null) {
    buffer.writeln('用户最近 3 小时亮屏约 ${snapshot.screenMinutesRecent3h} 分钟。');
  }

  if (snapshot.weatherAvailable && snapshot.weather != null) {
    final weather = snapshot.weather!;
    final temp = weather.temperature != 20.0
        ? '，${weather.temperature.toStringAsFixed(0)}°C'
        : '';
    buffer.writeln('天气：${weather.label}$temp。');
  }

  if (snapshot.locationAvailable &&
      snapshot.latitude != null &&
      snapshot.longitude != null) {
    buffer.writeln(
        '用户位置约在北纬 ${snapshot.latitude}、东经 ${snapshot.longitude}附近（粗略定位，仅用于天气与生活话题）。');
  }

  if (snapshot.calendarAvailable) {
    if (snapshot.events.isEmpty) {
      buffer.writeln('用户今天暂无日程。');
    } else {
      final items = snapshot.events.map((e) {
        final h = e.start.hour.toString().padLeft(2, '0');
        final m = e.start.minute.toString().padLeft(2, '0');
        return '$h:$m ${e.title}';
      }).join('；');
      buffer.writeln('用户今天的日程：$items。');
    }
  }

  buffer.writeln('</internal_context>');
  return buffer.toString();
}
