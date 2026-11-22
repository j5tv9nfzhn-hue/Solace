import 'package:flutter_test/flutter_test.dart';
import 'package:solace/models/life/timed_event.dart';
import 'package:solace/services/limited_event_service.dart';

void main() {
  test('情人节当天进行中，前一天倒计时，过后等明年', () {
    final onDay = LimitedEventService.listBuiltins(DateTime(2026, 2, 14));
    final valentine = onDay.firstWhere((e) => e.title == '情人节');
    expect(valentine.status, LimitedEventStatus.active);
    expect(valentine.daysUntil, 0);
    expect(valentine.statusText, '进行中 · 今天');

    final before = LimitedEventService.listBuiltins(DateTime(2026, 2, 13));
    final beforeValentine = before.firstWhere((e) => e.title == '情人节');
    expect(beforeValentine.status, LimitedEventStatus.upcoming);
    expect(beforeValentine.daysUntil, 1);
    expect(beforeValentine.statusText, '明天');

    final after = LimitedEventService.listBuiltins(DateTime(2026, 2, 15));
    final afterValentine = after.firstWhere((e) => e.title == '情人节');
    expect(afterValentine.status, LimitedEventStatus.missed);
    expect(afterValentine.daysUntil, 364);
    expect(afterValentine.statusText, '已错过，等明年2月14日');
  });

  test('圣诞节 5 天前是即将到来', () {
    final list = LimitedEventService.listBuiltins(DateTime(2026, 12, 20));
    final christmas = list.firstWhere((e) => e.title == '圣诞节');
    expect(christmas.status, LimitedEventStatus.upcoming);
    expect(christmas.daysUntil, 5);
  });

  test('prompt 只在节日当天注入，平时返回空串', () {
    final onDay = LimitedEventService.buildPromptBlock(
      now: DateTime(2026, 2, 14),
      characterName: '阿澈',
    );
    expect(onDay, contains('情人节'));
    expect(onDay, contains('主动邀约'));

    final offDay = LimitedEventService.buildPromptBlock(
      now: DateTime(2026, 3, 1),
      characterName: '阿澈',
    );
    expect(offDay, isEmpty);
  });

  test('每年重复的生日按月日换算，过后等明年', () {
    final birthday = TimedEvent(
      id: 'evt_1',
      characterId: 'char_1',
      userId: 'local_user',
      eventType: TimedEventType.birthday,
      title: '角色生日',
      date: '2000-06-01',
      recurring: true,
      createdAt: DateTime(2026, 1, 1),
    );
    final before = LimitedEventService.fromTimedEvent(
      birthday,
      DateTime(2026, 5, 30),
      characterName: '阿澈',
    );
    expect(before, isNotNull);
    expect(before!.title, contains('阿澈'));
    expect(before.status, LimitedEventStatus.upcoming);
    expect(before.daysUntil, 2);

    final after = LimitedEventService.fromTimedEvent(
      birthday,
      DateTime(2026, 6, 2),
    );
    expect(after, isNotNull);
    expect(after!.status, LimitedEventStatus.missed);
  });

  test('2 月 29 日生日在平年落到 2 月 28 日', () {
    final birthday = TimedEvent(
      id: 'evt_2',
      characterId: 'char_1',
      userId: 'local_user',
      eventType: TimedEventType.birthday,
      title: '角色生日',
      date: '2000-02-29',
      recurring: true,
      createdAt: DateTime(2026, 1, 1),
    );
    final occ = LimitedEventService.fromTimedEvent(
      birthday,
      DateTime(2027, 2, 28),
    );
    expect(occ, isNotNull);
    expect(occ!.status, LimitedEventStatus.active);
  });

  test('一次性事件：明年的日期不误判为已错过，过期的不再出现', () {
    final future = TimedEvent(
      id: 'evt_3',
      characterId: 'char_1',
      userId: 'local_user',
      eventType: TimedEventType.anniversary,
      title: '相识一周年',
      date: '2027-03-08',
      recurring: false,
      createdAt: DateTime(2026, 1, 1),
    );
    final occ = LimitedEventService.fromTimedEvent(
      future,
      DateTime(2026, 3, 1),
    );
    expect(occ, isNotNull);
    expect(occ!.status, LimitedEventStatus.upcoming);
    expect(occ.date.year, 2027);

    final past = TimedEvent(
      id: 'evt_4',
      characterId: 'char_1',
      userId: 'local_user',
      eventType: TimedEventType.anniversary,
      title: '旧纪念日',
      date: '2026-01-01',
      recurring: false,
      createdAt: DateTime(2026, 1, 1),
    );
    expect(
      LimitedEventService.fromTimedEvent(past, DateTime(2026, 3, 1)),
      isNull,
    );
  });

  test('自定义类型不进限定剧情', () {
    final custom = TimedEvent(
      id: 'evt_5',
      characterId: 'char_1',
      userId: 'local_user',
      eventType: TimedEventType.custom,
      title: '随便记一下',
      date: '2026-06-01',
      recurring: true,
      createdAt: DateTime(2026, 1, 1),
    );
    expect(
      LimitedEventService.fromTimedEvent(custom, DateTime(2026, 5, 30)),
      isNull,
    );
  });
}
