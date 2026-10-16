import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/core/today_plan.dart';
import 'package:rebi/screens/today/day_flow.dart';

import 'helpers/app_harness.dart';

/// Gün akışı şeridinin veri kuralları: hangi pencereler çizilir, yapıldı mı, çakışanlar nasıl dizilir.
TodayPlan planWith({
  Map<String, dynamic> progress = const {},
  Map<String, dynamic> weather = const {'uv_index': 3, 'humidity': 50, 'temperature': 20},
  Map<String, dynamic>? decisions,
  Map<String, dynamic> settings = const {},
  bool checkinDone = false,
  List<Map<String, dynamic>> reminders = const [],
}) =>
    TodayPlan.fromJson({
      'log_date': '2026-10-10',
      'has_routine': true,
      'routine': <dynamic>[],
      'weather': weather,
      'weather_source': 'live',
      'environment_advice': <dynamic>[],
      'reminders': reminders,
      'progress': progress,
      'checkin_done': checkinDone,
      'reminder_settings': settings,
      'weather_decisions': ?decisions,
    });

Map<String, dynamic> spfDecisions({Map<String, dynamic>? window, bool refresh = true}) => {
      'spf': {'spf': '50', 'level': 'high', 'uv': 7, 'refresh': refresh, 'refresh_every_minutes': 120, 'window': window},
      'moisture': {'kind': 'standard', 'humidity': 50, 'temperature': 20, 'night_mask': false},
      'lip_balm': {'needed': false, 'reason': null},
    };

FlowSegment seg(List<FlowSegment> all, String id) => all.firstWhere((e) => e.id == id);

void main() {
  group('buildFlowSegments', () {
    test('varsayılan gün: rutinler, makyaj sorusu, beslenme, check-in ve su; güneş kremi / balsam / temizlik yok', () {
      final all = buildFlowSegments(planWith());
      expect(all.map((e) => e.id).toSet(), {
        'routine_morning',
        'makeup_log',
        'nutrition_log',
        'routine_evening',
        'daily_checkin',
        'water_intake',
      });
      // 07:30 uyanma varsayılanı: sabah rutini 07:30–09:30
      expect((seg(all, 'routine_morning').start, seg(all, 'routine_morning').end), (450, 570));
    });

    test('biten işler dolu görünür, kayıtsız olanlar değil', () {
      final all = buildFlowSegments(planWith(
        progress: {
          'routine_morning_done': true,
          'nutrition_logged': true,
          'makeup': {'logged': true, 'used': true, 'removed': false},
        },
        checkinDone: true,
      ));
      expect(seg(all, 'routine_morning').done, isTrue);
      expect(seg(all, 'routine_evening').done, isFalse);
      expect(seg(all, 'nutrition_log').done, isTrue);
      expect(seg(all, 'makeup_log').done, isTrue);
      expect(seg(all, 'daily_checkin').done, isTrue);
      // Makyaj yapıldı ama temizlenmedi: akşam temizliği penceresi görünür, "yapılmadı".
      expect(seg(all, 'makeup_removal').done, isFalse);
    });

    test('makyaj temizlendiyse temizlik penceresi dolu', () {
      final all = buildFlowSegments(planWith(progress: {
        'makeup': {'logged': true, 'used': true, 'removed': true},
      }));
      expect(seg(all, 'makeup_removal').done, isTrue);
    });

    test('güneş kremi penceresi gerçek UV aralığından gelir', () {
      final all = buildFlowSegments(planWith(
        weather: {'uv_index': 7, 'humidity': 50, 'temperature': 20},
        decisions: spfDecisions(window: {'start': '12:00', 'end': '15:00', 'peak': '13:00'}),
        progress: {'spf_refreshes': 1},
      ));
      final spf = seg(all, 'spf_refresh');
      expect((spf.start, spf.end), (720, 900));
      expect(spf.done, isTrue);
    });

    test('UV aralığı bilinmiyorsa sabit pencere, yetersiz kısa pencere de sabite düşer', () {
      final fixed = seg(buildFlowSegments(planWith(decisions: spfDecisions())), 'spf_refresh');
      expect((fixed.start, fixed.end), (660, 960), reason: 'uyanma 07:30 → 11:00–16:00');

      final tooShort = seg(
        buildFlowSegments(planWith(decisions: spfDecisions(window: {'start': '12:00', 'end': '12:20'}))),
        'spf_refresh',
      );
      expect((tooShort.start, tooShort.end), (660, 960));
    });

    test('UV aralığı uyanma-uyku gününe kırpılır', () {
      final all = buildFlowSegments(planWith(
        settings: {'wake_time': '08:00', 'sleep_time': '18:00'},
        decisions: spfDecisions(window: {'start': '06:00', 'end': '20:00', 'peak': '13:00'}),
      ));
      final spf = seg(all, 'spf_refresh');
      expect((spf.start, spf.end), (480, 1080));
    });

    test('güneş kremi yalnızca UV yüksekse (karar yoksa hava değerinden) çizilir', () {
      expect(buildFlowSegments(planWith(weather: {'uv_index': 3})).any((e) => e.id == 'spf_refresh'), isFalse);
      expect(buildFlowSegments(planWith(weather: {'uv_index': 7})).any((e) => e.id == 'spf_refresh'), isTrue, reason: 'eski sunucu');
      expect(buildFlowSegments(planWith(decisions: spfDecisions(refresh: false))).any((e) => e.id == 'spf_refresh'), isFalse);
    });

    test('kapatılan kategori şeritte yer almaz', () {
      final all = buildFlowSegments(planWith(settings: {
        'enabled': {'water': false, 'nutrition': false},
      }));
      expect(all.any((e) => e.id == 'water_intake'), isFalse);
      expect(all.any((e) => e.id == 'nutrition_log'), isFalse);
      expect(all.any((e) => e.id == 'routine_morning'), isTrue);
    });

    test('su: pencere boyunca ayardaki aralıkla noktalar', () {
      final water = seg(buildFlowSegments(planWith(settings: {'water_every_minutes': 180})), 'water_intake');
      // 07:30 + 90 = 09:00 → 21:00, 3 saatte bir
      expect(water.slots, [540, 720, 900, 1080, 1260]);
      expect(water.isWater, isTrue);
    });

    test('dudak balsamı karar ya da (eski sunucuda) hatırlatıcı listesinden gelir', () {
      final withDecision = planWith(decisions: {
        ...spfDecisions(refresh: false),
        'lip_balm': {'needed': true, 'reason': 'cold'},
      });
      expect(buildFlowSegments(withDecision).any((e) => e.id == 'lip_balm'), isTrue);

      final legacy = planWith(reminders: [
        {'id': 'lip_balm', 'title': 'Dudak balsamı', 'body': '', 'start': '12:00', 'end': '13:00'},
      ]);
      expect(buildFlowSegments(legacy).any((e) => e.id == 'lip_balm'), isTrue);
    });
  });

  group('assignLanes', () {
    FlowSegment s(String id, int start, int end) => FlowSegment(id: id, start: start, end: end, done: false);

    test('çakışmayanlar aynı şeridi paylaşır, çakışanlar alt alta dizilir', () {
      final lanes = DayFlowStrip.assignLanes([
        s('a', 450, 570), // 07:30–09:30
        s('b', 600, 660), // 10:00–11:00: aynı şerit
        s('c', 540, 700), // a ve b ile çakışır: ikinci şerit
      ]);
      expect(lanes[0], lanes[1]);
      expect(lanes[2], isNot(lanes[0]));
    });

    test('akşam kümesi (üç pencere aynı saatte) üç ayrı şerit alır', () {
      final lanes = DayFlowStrip.assignLanes([s('a', 1260, 1380), s('b', 1260, 1380), s('c', 1260, 1350)]);
      expect({...lanes}.length, 3);
    });

    test('şerit sayısı sınırlıdır; fazlası son şeride biner ama çökmez', () {
      final lanes = DayFlowStrip.assignLanes([for (var i = 0; i < 7; i++) s('x$i', 600, 700)]);
      expect(lanes.reduce((a, b) => a > b ? a : b), lessThan(4));
    });

    test('boş liste', () => expect(DayFlowStrip.assignLanes(const []), isEmpty));
  });

  group('şerit ve açıklaması çizilir', () {
    testWidgets('320 px ve büyük yazıda taşmaz; okuyucuya özet verir; açıklama yalnızca bulunan kategorileri sayar', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final plan = planWith(
        weather: {'uv_index': 7, 'humidity': 50, 'temperature': 20},
        decisions: spfDecisions(window: {'start': '11:00', 'end': '16:00', 'peak': '13:00'}),
      );
      await pumpStandalone(
        tester,
        (theme) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            DayFlowStrip(plan: plan, theme: theme, now: 9 * 60 + 15),
            FlowLegend(plan: plan, theme: theme),
          ]),
        ),
        size: const Size(320, 640),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('09:15'), findsOneWidget, reason: 'şimdi balonu');
      expect(find.text('07:30'), findsOneWidget);
      expect(find.text('23:00'), findsOneWidget);
      expect(find.text(tr('mobileToday.flow.legend.spf')), findsOneWidget);
      expect(find.text(tr('mobileToday.flow.legend.lip')), findsNothing, reason: 'balsam gerekmiyor');
      expect(
        find.bySemanticsLabel(tr('mobileToday.flow.semantics', {'wake': '07:30', 'sleep': '23:00', 'now': '09:15'})),
        findsOneWidget,
      );
    });

    testWidgets('gün dışındaki saatte şimdi işareti çizilmez', (tester) async {
      final plan = planWith();
      await pumpStandalone(tester, (theme) => DayFlowStrip(plan: plan, theme: theme, now: 3 * 60));
      expect(find.text('03:00'), findsNothing);
    });
  });
}
