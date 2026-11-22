import '../models/life/timed_event.dart';

/// 限定剧情事件 — 节日 / 角色生日 / 纪念日限时剧情，错过等明年。
///
/// 纯函数服务，不碰数据库、不发请求，方便单测：
/// - 内置节日只收公历固定日期（情人节 / 520 / 圣诞 / 元旦）。
///   七夕是农历，每年公历日期都不同，硬编码会错年，所以不内置；
///   需要七夕这类农历节日时，用定时事件（[TimedEvent] 自定义节日）登记。
/// - 角色生日 / 相识纪念日复用已有的定时事件表（`ai_timed_events`），
///   由 [TimedEventService] 登记，本服务只做“今年这次是什么状态”的换算。
/// - 参与方式：用户在限定剧情页点“开始剧情”，打开聊天并预填一句开场白，
///   由用户自己决定发不发；不自动发消息、不弹窗、不推送。
enum LimitedEventStatus {
  /// 今天就是活动日
  active,

  /// 7 天内到来
  upcoming,

  /// 今年已过，等明年
  missed,
}

/// 一次限定剧情的发生（今年这次）。
class LimitedEventOccurrence {
  /// 每年唯一的稳定 key，如 `valentine_2026` / `timed_<事件id>_2026`
  final String key;

  /// 标题，如“情人节”“角色生日”
  final String title;

  /// 给用户看的一句话说明
  final String description;

  /// 今年这次的发生日期（本地时间，年月日）
  final DateTime date;

  final LimitedEventStatus status;

  /// 距离发生的天数：进行中为 0，即将到来为正数，已错过为到明年那次的天数
  final int daysUntil;

  /// 生日 / 纪念日所属角色；内置节日为 null（节日属于每个角色）
  final String? characterId;

  /// 生日 / 纪念日所属角色名；内置节日为 null
  final String? characterName;

  /// 注入 prompt 时用的邀约提示，只在进行中时有效
  final String promptHint;

  const LimitedEventOccurrence({
    required this.key,
    required this.title,
    required this.description,
    required this.date,
    required this.status,
    required this.daysUntil,
    this.characterId,
    this.characterName,
    required this.promptHint,
  });

  /// 给用户看的状态文案
  String get statusText {
    switch (status) {
      case LimitedEventStatus.active:
        return '进行中 · 今天';
      case LimitedEventStatus.upcoming:
        return daysUntil <= 1 ? '明天' : '$daysUntil天后';
      case LimitedEventStatus.missed:
        return '已错过，等明年${date.month}月${date.day}日';
    }
  }
}

/// 内置节日定义（公历固定日期）。
class _BuiltinFestival {
  final String key;
  final String title;
  final String description;
  final int month;
  final int day;
  final String promptHint;

  const _BuiltinFestival({
    required this.key,
    required this.title,
    required this.description,
    required this.month,
    required this.day,
    required this.promptHint,
  });
}

class LimitedEventService {
  LimitedEventService._();

  /// 提前几天算“即将到来”（只用于展示倒计时，不触发任何推送）
  static const int upcomingWindowDays = 7;

  static const List<_BuiltinFestival> _builtins = [
    _BuiltinFestival(
      key: 'new_year',
      title: '元旦',
      description: '新年第一天，和TA一起跨年、许新年愿望。',
      month: 1,
      day: 1,
      promptHint: '今天是元旦，新年第一天，主动和用户互道新年快乐、聊聊新年愿望。',
    ),
    _BuiltinFestival(
      key: 'valentine',
      title: '情人节',
      description: '一年一度的情人节，和TA过一个只属于你们的节日。',
      month: 2,
      day: 14,
      promptHint: '今天是情人节，主动邀约用户一起过节，可以准备惊喜、告白或约会。',
    ),
    _BuiltinFestival(
      key: 'day_520',
      title: '520',
      description: '5月20日，把“我爱你”说出口的日子。',
      month: 5,
      day: 20,
      promptHint: '今天是520，主动对用户表达爱意，可以撒娇、告白或讨要一个节日仪式。',
    ),
    _BuiltinFestival(
      key: 'christmas',
      title: '圣诞节',
      description: '圣诞节，和TA一起过一个暖乎乎的平安夜。',
      month: 12,
      day: 25,
      promptHint: '今天是圣诞节，主动和用户聊圣诞氛围、互送祝福、约着一起过平安夜。',
    ),
  ];

  /// 所有内置节日今年这次的状态（按日期排序）。
  static List<LimitedEventOccurrence> listBuiltins(DateTime now) {
    final list = _builtins
        .map((f) => _resolve(
              key: '${f.key}_${now.year}',
              title: f.title,
              description: f.description,
              month: f.month,
              day: f.day,
              now: now,
              promptHint: f.promptHint,
            ))
        .toList();
    list.sort((a, b) => a.date.compareTo(b.date));
    return list;
  }

  /// 把一条定时事件换算成限定剧情。
  ///
  /// 只收生日 / 纪念日 / 节日三类；一次性且已过期的事件返回 null（不再出现）。
  /// 每年重复的事件按月日换算今年这次；一次性未来事件按原日期换算。
  static LimitedEventOccurrence? fromTimedEvent(
    TimedEvent event,
    DateTime now, {
    String? characterName,
  }) {
    if (event.eventType != TimedEventType.birthday &&
        event.eventType != TimedEventType.anniversary &&
        event.eventType != TimedEventType.festival) {
      return null;
    }
    final parts = event.date.split('-');
    if (parts.length < 3) return null;
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (month == null || day == null) return null;

    // 一次性事件：日期已过就不再出现（不像每年重复那样等明年）。
    // 注意：不能走 _resolve（它按今年同月日换算，明年的日期会被误判为已错过），
    // 直接用登记的原日期换算。
    if (!event.recurring) {
      final parsed = DateTime.tryParse(event.date);
      if (parsed == null) return null;
      final today = _dateOnly(now);
      final target = _dateOnly(parsed);
      final diff = target.difference(today).inDays;
      if (diff < 0) return null;
      final status =
          diff == 0 ? LimitedEventStatus.active : LimitedEventStatus.upcoming;
      return LimitedEventOccurrence(
        key: 'timed_${event.id}',
        title: event.title,
        description: '你为TA登记的纪念日，错过就等下一次。',
        date: target,
        status: status,
        daysUntil: diff,
        characterId: event.characterId,
        characterName: characterName,
        promptHint: '今天是「${event.title}」，主动提起这件事，和用户一起庆祝。',
      );
    }

    final title = event.eventType == TimedEventType.birthday
        ? '${characterName ?? 'TA'}的生日'
        : event.title;
    return _resolve(
      key: 'timed_${event.id}_${now.year}',
      title: title,
      description: event.eventType == TimedEventType.birthday
          ? '每年只有一次的生日，记得给TA过生日。'
          : '每年一次的纪念日，错过等明年。',
      month: month,
      day: day,
      now: now,
      promptHint: '今天是「$title」，主动提起这件事，和用户一起庆祝。',
      characterId: event.characterId,
      characterName: characterName,
    );
  }

  /// 注入单聊 system prompt 的限定剧情段。
  ///
  /// 只有当天进行中的节日才注入；没有进行中的返回空串。
  /// 文案要求角色自然主动提起，不过节相关的词不出现“系统/任务”类字眼。
  static String buildPromptBlock({
    required DateTime now,
    required String characterName,
  }) {
    final active = listBuiltins(now)
        .where((e) => e.status == LimitedEventStatus.active)
        .toList();
    if (active.isEmpty) return '';
    final buffer = StringBuffer();
    buffer.writeln('\n【限定剧情 — 今天是节日】');
    for (final event in active) {
      buffer.writeln('今天是${event.title}，是每年只有一次的限时剧情日。');
      buffer.writeln(event.promptHint);
    }
    buffer.writeln('像平时一样自然地主动提起过节的事，不要提“系统提示”“限定剧情”“任务”这些词，不要复述这段话。');
    return buffer.toString();
  }

  // ─── 内部换算 ────────────────────────────────────

  static LimitedEventOccurrence _resolve({
    required String key,
    required String title,
    required String description,
    required int month,
    required int day,
    required DateTime now,
    required String promptHint,
    String? characterId,
    String? characterName,
  }) {
    final today = _dateOnly(now);
    final thisYear = _safeDate(now.year, month, day);
    final diff = thisYear.difference(today).inDays;
    if (diff == 0) {
      return LimitedEventOccurrence(
        key: key,
        title: title,
        description: description,
        date: thisYear,
        status: LimitedEventStatus.active,
        daysUntil: 0,
        characterId: characterId,
        characterName: characterName,
        promptHint: promptHint,
      );
    }
    if (diff < 0) {
      // 今年已过：等明年同一天
      final nextYear = _safeDate(now.year + 1, month, day);
      return LimitedEventOccurrence(
        key: key,
        title: title,
        description: description,
        date: thisYear,
        status: LimitedEventStatus.missed,
        daysUntil: nextYear.difference(today).inDays,
        characterId: characterId,
        characterName: characterName,
        promptHint: promptHint,
      );
    }
    // 今年未到（含 7 天内和更远的）：统一算即将到来，按天数排序展示
    return LimitedEventOccurrence(
      key: key,
      title: title,
      description: description,
      date: thisYear,
      status: LimitedEventStatus.upcoming,
      daysUntil: diff,
      characterId: characterId,
      characterName: characterName,
      promptHint: promptHint,
    );
  }

  /// 2 月 29 日在平年不存在，落到 2 月 28 日，避免 DateTime 越界进 3 月。
  static DateTime _safeDate(int year, int month, int day) {
    if (month == 2 && day == 29) {
      final isLeap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;
      if (!isLeap) return DateTime(year, 2, 28);
    }
    return DateTime(year, month, day);
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
}
