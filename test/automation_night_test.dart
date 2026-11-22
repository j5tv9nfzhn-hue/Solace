import 'package:flutter_test/flutter_test.dart';
import 'package:solace/services/automation_tools.dart';
import 'package:solace/services/proactive_time_triggers.dart';
import 'package:solace/services/proactive_trigger_rules.dart';
import 'package:solace/services/reality_context_service.dart';
import 'package:solace/services/weather_service.dart';

void main() {
  group('真实感上下文文本 buildRealityContextText', () {
    test('时间与星期：2026-11-23 是星期一，中午', () {
      final text = buildRealityContextText(
        RealitySnapshot(now: DateTime(2026, 11, 23, 12, 5)),
      );
      expect(text, contains('2026年11月23日星期一 12:05'));
      expect(text, contains('中午'));
    });

    test('深夜时段标注', () {
      final text = buildRealityContextText(
        RealitySnapshot(now: DateTime(2026, 11, 23, 1, 30)),
      );
      expect(text, contains('深夜'));
    });

    test('系统上下文身份：要求不输出、不复述', () {
      final text = buildRealityContextText(
        RealitySnapshot(now: DateTime(2026, 11, 23, 12, 5)),
      );
      expect(text, contains('<internal_context type="reality"'));
      expect(text, contains('绝对不要输出'));
      expect(text, contains('</internal_context>'));
    });

    test('电量行：充电状态如实写', () {
      final charging = buildRealityContextText(
        RealitySnapshot(
          now: DateTime(2026, 11, 23, 12, 5),
          batteryPercent: 62,
          isCharging: true,
        ),
      );
      expect(charging, contains('电量 62%，正在充电'));

      final low = buildRealityContextText(
        RealitySnapshot(
          now: DateTime(2026, 11, 23, 12, 5),
          batteryPercent: 15,
          isCharging: false,
        ),
      );
      expect(low, contains('电量 15%，未充电'));
    });

    test('使用时长：只写总分钟，未授权时整行省略', () {
      final withUsage = buildRealityContextText(
        RealitySnapshot(
          now: DateTime(2026, 11, 23, 12, 5),
          screenMinutesRecent3h: 85,
          usageAvailable: true,
        ),
      );
      expect(withUsage, contains('最近 3 小时亮屏约 85 分钟'));

      final withoutUsage = buildRealityContextText(
        RealitySnapshot(
          now: DateTime(2026, 11, 23, 12, 5),
          screenMinutesRecent3h: 85,
          usageAvailable: false,
        ),
      );
      expect(withoutUsage, isNot(contains('亮屏')));
    });

    test('天气：无缓存不写，绝不编晴天', () {
      final none = buildRealityContextText(
        RealitySnapshot(now: DateTime(2026, 11, 23, 12, 5)),
      );
      expect(none, isNot(contains('天气')));

      final sunny = buildRealityContextText(
        RealitySnapshot(
          now: DateTime(2026, 11, 23, 12, 5),
          weather: const WeatherData(
            type: WeatherType.sunny,
            label: '晴',
            temperature: 21.0,
          ),
          weatherAvailable: true,
        ),
      );
      expect(sunny, contains('天气：晴，21°C'));
    });

    test('定位：只写 1 位小数粗略坐标', () {
      final text = buildRealityContextText(
        RealitySnapshot(
          now: DateTime(2026, 11, 23, 12, 5),
          latitude: 39.9,
          longitude: 116.4,
          locationAvailable: true,
        ),
      );
      expect(text, contains('北纬 39.9、东经 116.4附近'));
      expect(text, contains('粗略定位'));
    });

    test('日程：只列时间与标题，无日程时明说暂无', () {
      final empty = buildRealityContextText(
        RealitySnapshot(
          now: DateTime(2026, 11, 23, 12, 5),
          calendarAvailable: true,
        ),
      );
      expect(empty, contains('今天暂无日程'));

      final withEvents = buildRealityContextText(
        RealitySnapshot(
          now: DateTime(2026, 11, 23, 12, 5),
          calendarAvailable: true,
          events: [
            CalendarEventItem(
              title: '开会',
              start: DateTime(2026, 11, 23, 9, 0),
            ),
          ],
        ),
      );
      expect(withEvents, contains('9:00 开会'));
    });

    test('步数明确未接入', () {
      expect(RealitySnapshot.stepsAvailable, isFalse);
    });

    test('开关默认值：总开、使用关、天气缓存开、定位关、日程关', () {
      const settings = RealityContextSettings();
      expect(settings.enabled, isTrue);
      expect(settings.usageEnabled, isFalse);
      expect(settings.weatherEnabled, isTrue);
      expect(settings.locationEnabled, isFalse);
      expect(settings.calendarEnabled, isFalse);
      expect(
        settings.copyWith(usageEnabled: true).usageEnabled,
        isTrue,
      );
    });
  });

  group('时间窗口 TimeWindow', () {
    test('普通窗口含起不含终', () {
      const window = TimeWindow(690, 780);
      expect(window.contains(690), isTrue);
      expect(window.contains(779), isTrue);
      expect(window.contains(780), isFalse);
      expect(window.contains(689), isFalse);
    });

    test('跨零点窗口', () {
      const window = TimeWindow(1380, 360);
      expect(window.contains(0), isTrue);
      expect(window.contains(359), isTrue);
      expect(window.contains(360), isFalse);
      expect(window.contains(1379), isFalse);
      expect(window.contains(1400), isTrue);
    });
  });

  group('时间规则 matchTimeBased', () {
    test('午饭 12:00 命中饭点，深夜规则不命中', () {
      final matched = ProactiveTriggerRules.matchTimeBased(
        now: DateTime(2026, 11, 23, 12, 0),
        recentScreenMinutes: 0,
      );
      expect(matched.map((r) => r.id), contains('time_meal'));
      expect(matched.map((r) => r.id), isNot(contains('time_late_night')));
    });

    test('15:00 不命中饭点', () {
      final matched = ProactiveTriggerRules.matchTimeBased(
        now: DateTime(2026, 11, 23, 15, 0),
        recentScreenMinutes: 0,
      );
      expect(matched.map((r) => r.id), isNot(contains('time_meal')));
    });

    test('深夜亮屏 15 分钟催睡，5 分钟不催', () {
      final enough = ProactiveTriggerRules.matchTimeBased(
        now: DateTime(2026, 11, 23, 23, 30),
        recentScreenMinutes: 15,
      );
      expect(enough.map((r) => r.id), contains('time_late_night'));

      final tooLittle = ProactiveTriggerRules.matchTimeBased(
        now: DateTime(2026, 11, 23, 23, 30),
        recentScreenMinutes: 5,
      );
      expect(
        tooLittle.map((r) => r.id),
        isNot(contains('time_late_night')),
      );
    });

    test('白天不催睡', () {
      final matched = ProactiveTriggerRules.matchTimeBased(
        now: DateTime(2026, 11, 23, 15, 0),
        recentScreenMinutes: 120,
      );
      expect(
        matched.map((r) => r.id),
        isNot(contains('time_late_night')),
      );
    });

    test('最近 3 小时亮屏 90 分钟提醒，89 分钟不提醒', () {
      final enough = ProactiveTriggerRules.matchTimeBased(
        now: DateTime(2026, 11, 23, 15, 0),
        recentScreenMinutes: 90,
      );
      expect(enough.map((r) => r.id), contains('time_long_screen'));

      final tooLittle = ProactiveTriggerRules.matchTimeBased(
        now: DateTime(2026, 11, 23, 15, 0),
        recentScreenMinutes: 89,
      );
      expect(
        tooLittle.map((r) => r.id),
        isNot(contains('time_long_screen')),
      );
    });
  });

  group('时间触发节流 TimeTriggerGate', () {
    test('每日上限到了不触发', () {
      expect(
        TimeTriggerGate.shouldFire(
          now: DateTime(2026, 11, 23, 12, 0),
          lastFiredAt: null,
          cooldownMinutes: 240,
          dailyCap: 1,
          firedToday: 1,
        ),
        isFalse,
      );
    });

    test('冷却期内不触发', () {
      expect(
        TimeTriggerGate.shouldFire(
          now: DateTime(2026, 11, 23, 12, 0),
          lastFiredAt: DateTime(2026, 11, 23, 11, 0),
          cooldownMinutes: 240,
          dailyCap: 1,
          firedToday: 0,
        ),
        isFalse,
      );
    });

    test('冷却过了可触发', () {
      expect(
        TimeTriggerGate.shouldFire(
          now: DateTime(2026, 11, 23, 12, 0),
          lastFiredAt: DateTime(2026, 11, 23, 7, 0),
          cooldownMinutes: 240,
          dailyCap: 1,
          firedToday: 0,
        ),
        isTrue,
      );
    });

    test('从未触发过可触发', () {
      expect(
        TimeTriggerGate.shouldFire(
          now: DateTime(2026, 11, 23, 12, 0),
          lastFiredAt: null,
          cooldownMinutes: 240,
          dailyCap: 1,
          firedToday: 0,
        ),
        isTrue,
      );
    });
  });

  group('外卖深链 buildTakeoutLinks', () {
    test('两个公开 Scheme，店名与菜名已编码', () {
      final links = AutomationTools.buildTakeoutLinks(
        shopName: '老乡鸡',
        dishes: ['宫保鸡丁'],
      );
      expect(links.primary.scheme, 'meituanwaimai');
      expect(links.primary.host, 'waimai.meituan.com');
      expect(links.fallback.scheme, 'imeituan');
      expect(links.primary.toString(), contains('%'));
      expect(links.primary.toString(), isNot(contains('老乡鸡')));
    });

    test('链接里没有任何订单/支付参数', () {
      final links = AutomationTools.buildTakeoutLinks(
        shopName: '测试店铺',
        dishes: ['测试菜品'],
      );
      for (final uri in [links.primary, links.fallback]) {
        final text = uri.toString().toLowerCase();
        expect(text, isNot(contains('pay')));
        expect(text, isNot(contains('order')));
        expect(text, isNot(contains('price')));
        expect(text, isNot(contains('submit')));
      }
    });

    test('空菜名单也只剩店名', () {
      final links =
          AutomationTools.buildTakeoutLinks(shopName: '测试店铺');
      expect(links.primary.queryParameters['query'], '测试店铺');
    });
  });
}
