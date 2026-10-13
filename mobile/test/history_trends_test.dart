import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:rebi/core/history_trends.dart';
import 'package:rebi/core/routine_tracking.dart';
import 'package:rebi/core/user_history.dart';
import 'package:rebi/ui/tw.dart';
import 'package:rebi/ui/widgets/trend_charts.dart';

import 'helpers/app_harness.dart';

/// Geçmiş ekranındaki eğilim grafikleri ve haftalık özet.
void main() {
  final today = DateTime(2026, 10, 13);

  /// `ago` gün önceki günün `GET /me/history` satırı.
  Map<String, dynamic> row(int ago, {Map<String, dynamic> tracking = const {}, Map<String, dynamic>? checkin, DateTime? from}) {
    final base = from ?? today;
    return {
      'log_date': dayKey(DateTime(base.year, base.month, base.day - ago)),
      'tracking': {'events_count': 1, ...tracking},
      'checkin': ?checkin,
    };
  }

  List<HistoryDay> parse(List<Map<String, dynamic>> rows) =>
      UserHistory.fromJson({'days': rows, 'assessments': const <dynamic>[], 'synced': true}).days;

  group('eksen ve noktalar', () {
    test('7 gün: 7 günlük nokta, son nokta bugün', () {
      final t = buildTrends(const [], range: 7, today: today);
      expect(t.bucketDays, 1);
      expect(t.water.points, hasLength(7));
      expect(t.start, DateTime(2026, 10, 7));
      expect(t.end, today);
      expect(t.water.points.last.start, today);
      expect(t.isEmpty, isTrue);
    });

    test('30 gün günlük, 90 gün haftalık (13 nokta)', () {
      expect(buildTrends(const [], range: 30, today: today).water.points, hasLength(30));
      final t = buildTrends(const [], range: 90, today: today);
      expect(t.bucketDays, 7);
      expect(t.water.points, hasLength(13));
      expect(t.water.points.every((p) => p.days == 7), isTrue);
      expect(t.water.points.last.start, DateTime(2026, 10, 7), reason: 'son hafta bugünle biter');
    });

    test('ay ve yıl sınırı: tarihler doğru geriye gider', () {
      final t = buildTrends(const [], range: 30, today: DateTime(2026, 3, 2));
      expect(t.start, DateTime(2026, 2, 1));
      expect(t.water.points.first.start, DateTime(2026, 2, 1));
      expect(buildTrends(const [], range: 7, today: DateTime(2026, 1, 3)).start, DateTime(2025, 12, 28));
    });

    test('saat bilgisi olan bugün de aynı gün sayılır', () {
      final t = buildTrends(const [], range: 7, today: DateTime(2026, 10, 13, 23, 59));
      expect(t.end, today);
    });
  });

  group('değerler', () {
    test('günlük su yalnızca kayıtlı günlerde dolu, kayıtsız günler boş', () {
      final days = parse([
        row(0, tracking: {'water_ml_total': 1500}),
        row(2, tracking: {'water_ml_total': 500}),
        row(3, tracking: {'spf_refreshes': 1}),
      ]);
      final t = buildTrends(days, range: 7, today: today);
      expect([for (final p in t.water.points) p.value], [null, null, null, null, 500, null, 1500]);
      expect(t.water.average, 1000);
      expect(t.water.recorded, 2);
    });

    test('uyku ve stres: check-in önce, yoksa gün içi kayıt', () {
      final days = parse([
        row(0, tracking: {'sleep_hours': 5}, checkin: {'sleep_hours': 7.5, 'stress_level': 4}),
        row(1, tracking: {'sleep_hours': 6, 'avg_stress': 2.5}),
      ]);
      final t = buildTrends(days, range: 7, today: today);
      expect(t.sleep.points.last.value, 7.5, reason: 'check-in kazanır');
      expect(t.sleep.points[5].value, 6);
      expect(t.stress.points.last.value, 4);
      expect(t.stress.points[5].value, 2.5);
      expect(t.sleep.average, 6.75);
    });

    test('rutin: sabah+akşam 1, biri .5, ikisi de yok 0, kayıt yoksa boş', () {
      final days = parse([
        row(0, tracking: {'routine_morning_done': true, 'routine_evening_done': true}),
        row(1, tracking: {'routine_morning_done': true}),
        row(2, tracking: {'water_ml_total': 300}),
      ]);
      final t = buildTrends(days, range: 7, today: today);
      expect([for (final p in t.routine.points) p.value], [null, null, null, null, 0, .5, 1]);
      expect(t.routine.average, .5);
    });

    test('90 gün: haftalık nokta kayıtlı günlerin ortalaması; ortalama günlük değerlerden', () {
      final days = parse([
        row(0, tracking: {'water_ml_total': 2000}),
        row(1, tracking: {'water_ml_total': 1000}),
        row(10, tracking: {'water_ml_total': 600}),
      ]);
      final t = buildTrends(days, range: 90, today: today);
      expect(t.water.points.last.value, 1500, reason: 'son hafta: (2000+1000)/2');
      expect(t.water.points[11].value, 600, reason: 'bir önceki hafta tek kayıt');
      expect(t.water.average, closeTo(1200, .001), reason: '(2000+1000+600)/3, nokta ortalamalarının ortalaması değil');
    });

    test('aralık dışındaki günler yok sayılır', () {
      final days = parse([row(20, tracking: {'water_ml_total': 900})]);
      expect(buildTrends(days, range: 7, today: today).water.isEmpty, isTrue);
      expect(buildTrends(days, range: 30, today: today).water.isEmpty, isFalse);
    });
  });

  group('haftalık özet', () {
    test('bu hafta kayıt yoksa null', () {
      expect(summarizeWeeks(const [], today), isNull);
      expect(summarizeWeeks(parse([row(8, tracking: {'water_ml_total': 1})]), today), isNull, reason: 'yalnızca önceki hafta var');
    });

    test('son 7 gün ve önceki 7 gün ayrılır', () {
      final days = parse([
        row(0, tracking: {'water_ml_total': 2000, 'routine_morning_done': true, 'routine_evening_done': true, 'spf_refreshes': 2}),
        row(6, tracking: {'water_ml_total': 1000, 'nutrition': {'junk_food': true}}, checkin: {'sleep_hours': 7, 'stress_level': 2}),
        row(7, tracking: {'water_ml_total': 600, 'routine_morning_done': true, 'routine_evening_done': true}),
        row(13, tracking: {'water_ml_total': 400}, checkin: {'sleep_hours': 6, 'stress_level': 4}),
        row(14, tracking: {'water_ml_total': 9999}),
      ]);
      final w = summarizeWeeks(days, today)!;
      expect(w.current.recordedDays, 2);
      expect(w.current.avgWaterMl, 1500);
      expect(w.current.fullRoutineDays, 1);
      expect(w.current.spfRefreshes, 2);
      expect(w.current.junkDays, 1);
      expect(w.current.checkins, 1);
      expect(w.current.avgSleepHours, 7);
      expect(w.current.avgStress, 2);

      final p = w.previous!;
      expect(p.recordedDays, 2, reason: '7 ve 13 gün önce; 14 gün önce dahil değil');
      expect(p.avgWaterMl, 500);
      expect(p.fullRoutineDays, 1);
      expect(p.avgSleepHours, 6);
    });

    test('önceki hafta boşsa previous null', () {
      final w = summarizeWeeks(parse([row(0, tracking: {'water_ml_total': 100})]), today)!;
      expect(w.previous, isNull);
    });
  });

  group('geçmiş ekranı', () {
    final routine = routineFixture['routine'] as List;

    Map<String, Object> acceptedPrefs() => {
          trackAcceptedKey(testUserId): '1',
          trackSnapshotKey(testUserId): jsonEncode({
            'routine': routine,
            'userName': 'Ayşe Test',
            'weather': routineFixture['weather'],
            'flowDebug': routineFixture['flow_debug'],
            'acceptedAt': DateTime.now().millisecondsSinceEpoch - 3 * 86400000,
          }),
        };

    /// Sunucu satırları gerçek "bugün"e göre kurulur (ekran saati cihazdan okur).
    FakeBackend backendWith(List<Map<String, dynamic>> Function(DateTime now) build) {
      final b = FakeBackend();
      b.history = {...b.history, 'days': build(DateTime.now()), 'assessments': <dynamic>[], 'synced': true};
      return b;
    }

    List<Map<String, dynamic>> twoWeeks(DateTime now) => [
          row(0, from: now, tracking: {'water_ml_total': 2000, 'routine_morning_done': true, 'routine_evening_done': true, 'spf_refreshes': 1}, checkin: {
            'sleep_hours': 8,
            'stress_level': 2,
            'skin_feeling': 'iyi',
          }),
          row(2, from: now, tracking: {'water_ml_total': 1000, 'routine_morning_done': true}),
          row(8, from: now, tracking: {'water_ml_total': 800, 'routine_morning_done': true}, checkin: {'sleep_hours': 6, 'stress_level': 4}),
        ];

    testWidgets('dört eğilim kartı ve haftalık özet gösterilir', (tester) async {
      await pumpApp(tester, location: '/dashboard/history', prefs: acceptedPrefs(), backend: backendWith(twoWeeks));

      expect(find.text(tr('mobileHistory.trends.title')), findsOneWidget);
      expect(find.byType(TrendBars), findsOneWidget);
      expect(find.byType(TrendLine), findsNWidgets(2), reason: 'uyku ve stres');
      expect(find.byType(TrendStrip), findsOneWidget);

      // Bu hafta kartı: iki gün su (2000, 1000), önceki hafta 800 → +700 ml
      expect(find.text(tr('mobileHistory.week.title')), findsOneWidget);
      expect(find.text(tr('mobileHistory.week.subtitle')), findsOneWidget);
      expect(find.text(tr('mobileHistory.week.waterValue', {'ml': '1.500'})), findsOneWidget);
      expect(find.text('+700 ml'), findsOneWidget);
      expect(find.text(tr('mobileHistory.week.routineValue', {'n': 1})), findsOneWidget);
      expect(find.text(tr('mobileHistory.week.spfValue', {'n': 1})), findsOneWidget);
    });

    testWidgets('stres düştüyse iyi, su düştüyse uyarı renginde gösterilir', (tester) async {
      await pumpApp(tester, location: '/dashboard/history', prefs: acceptedPrefs(), backend: backendWith(twoWeeks));
      // Stres: 2 (bu hafta) - 4 (önceki) = -2,0 ve düşüş stres için iyidir.
      final stress = tester.widget<Text>(find.text('-2,0'));
      expect(stress.style!.color, Tw.green700);
      final sleep = tester.widget<Text>(find.text('+2,0 sa'));
      expect(sleep.style!.color, Tw.green700, reason: 'uyku arttı');
    });

    testWidgets('önceki hafta yoksa karşılaştırma ve ok gösterilmez', (tester) async {
      final backend = backendWith((now) => [row(0, from: now, tracking: {'water_ml_total': 900})]);
      await pumpApp(tester, location: '/dashboard/history', prefs: acceptedPrefs(), backend: backend);
      expect(find.text(tr('mobileHistory.week.subtitleNoPrev')), findsOneWidget);
      expect(find.byIcon(LucideIcons.trendingUp), findsNothing);
      expect(find.byIcon(LucideIcons.trendingDown), findsNothing);
    });

    testWidgets('90 günlük aralıkta haftalık not görünür, 7 günde görünmez', (tester) async {
      await pumpApp(tester, location: '/dashboard/history', prefs: acceptedPrefs(), backend: backendWith(twoWeeks));
      expect(find.textContaining(tr('mobileHistory.trends.weeklyNote')), findsNothing);
      await tapText(tester, tr('mobileHistory.range90'));
      await settle(tester);
      expect(find.textContaining(tr('mobileHistory.trends.weeklyNote')), findsNWidgets(4));
      await tapText(tester, tr('mobileHistory.range7'));
      await settle(tester);
      expect(find.textContaining(tr('mobileHistory.trends.weeklyNote')), findsNothing);
    });

    testWidgets('bir seri tamamen boşsa o kartta "kayıt yok" yazar, grafik çizilmez', (tester) async {
      // Yalnızca su var: uyku, stres ve rutin için hiç değer yok.
      final backend = backendWith((now) => [row(0, from: now, tracking: {'water_ml_total': 900})]);
      await pumpApp(tester, location: '/dashboard/history', prefs: acceptedPrefs(), backend: backend);
      expect(find.byType(TrendBars), findsOneWidget);
      expect(find.byType(TrendLine), findsNothing);
      expect(find.text(tr('mobileHistory.trends.noData')), findsNWidgets(2), reason: 'uyku ve stres');
      expect(find.byType(TrendStrip), findsOneWidget, reason: 'rutin: kayıtlı gün var, yapılmamış (0)');
    });

    testWidgets('kayıt yoksa eğilim bölümü çıkmaz', (tester) async {
      await pumpApp(tester, location: '/dashboard/history', prefs: acceptedPrefs(), backend: backendWith((_) => []));
      expect(find.text(tr('mobileHistory.trends.title')), findsNothing);
      expect(find.byType(TrendBars), findsNothing);
    });

    testWidgets('grafikler ekran okuyucuya özet okur', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, location: '/dashboard/history', prefs: acceptedPrefs(), backend: backendWith(twoWeeks));
      final label = tr('mobileHistory.trends.chartLabel', {'name': tr('mobileHistory.trends.water'), 'n': 3, 'avg': '1.267 ml'});
      expect(find.bySemanticsLabel(label), findsOneWidget);
      handle.dispose();
    });

    testWidgets('İngilizce arayüz', (tester) async {
      await pumpApp(tester, location: '/dashboard/history', prefs: acceptedPrefs(), backend: backendWith(twoWeeks), lang: 'en');
      expect(find.text('Trends'), findsOneWidget);
      expect(find.text('This week'), findsOneWidget);
      expect(find.text('+700 ml'), findsOneWidget);
    });

    for (final dark in [false, true]) {
      for (final (scale, size) in [(1.0, const Size(320, 568)), (2.0, const Size(320, 640))]) {
        testWidgets('${size.width.toInt()} px, yazı %${(scale * 100).round()}, ${dark ? 'koyu' : 'açık'}: taşmaz', (tester) async {
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          addTearDown(() => Tw.dark = false);
          Tw.dark = dark;
          await pumpApp(tester, location: '/dashboard/history', prefs: acceptedPrefs(), backend: backendWith(twoWeeks), size: size);
          await tester.drag(find.byType(Scrollable).first, const Offset(0, -600));
          await tester.pump();
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('grafik çizimi', () {
    Future<void> pumpChart(WidgetTester tester, Widget chart, {bool dark = false}) async {
      Tw.dark = dark;
      addTearDown(() => Tw.dark = false);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(backgroundColor: Tw.background, body: Padding(padding: const EdgeInsets.all(16), child: chart)),
      ));
    }

    testWidgets('boş ve tek noktalı veriyle çökmez', (tester) async {
      for (final values in <List<double?>>[
        const [],
        const [null],
        const [null, null, null],
        const [5],
        const [null, 3, null],
      ]) {
        await pumpChart(
          tester,
          Column(children: [
            TrendBars(values: values, maxY: 10, color: Colors.blue, semanticLabel: 'a'),
            TrendLine(values: values, minY: 0, maxY: 10, color: Colors.blue, semanticLabel: 'b', band: (2, 4)),
            TrendStrip(values: values, color: Colors.green, semanticLabel: 'c'),
          ]),
        );
        expect(tester.takeException(), isNull, reason: '$values');
      }
    });

    testWidgets('sınır dışı değerler kenara sıkıştırılır (taşma yok)', (tester) async {
      await pumpChart(
        tester,
        Column(children: [
          TrendBars(values: const [0, 99999, -5, 1], maxY: 100, color: Colors.blue, reference: 50, semanticLabel: 'a'),
          TrendLine(values: const [-50, 500, 3], minY: 1, maxY: 5, color: Colors.blue, semanticLabel: 'b'),
          TrendStrip(values: const [-1, 7, .5], color: Colors.green, semanticLabel: 'c'),
        ]),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('açık ve koyu modda farklı renkle çizilir (modda yeniden çizim)', (tester) async {
      await pumpChart(tester, const TrendBars(values: [1, 2], maxY: 3, color: Colors.blue, semanticLabel: 'a'));
      final light = tester.widget<CustomPaint>(find.descendant(of: find.byType(TrendBars), matching: find.byType(CustomPaint)).first).painter!;
      await pumpChart(tester, const TrendBars(values: [1, 2], maxY: 3, color: Colors.blue, semanticLabel: 'a'), dark: true);
      final dark = tester.widget<CustomPaint>(find.descendant(of: find.byType(TrendBars), matching: find.byType(CustomPaint)).first).painter!;
      expect(dark.shouldRepaint(light), isTrue, reason: 'iz / kılavuz rengi moda göre değişir');
    });
  });
}
