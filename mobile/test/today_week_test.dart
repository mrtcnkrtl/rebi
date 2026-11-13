import 'dart:convert';

import 'package:flutter/rendering.dart' show debugDisableShadows;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/core/routine_tracking.dart';
import 'package:rebi/screens/today/today_clock.dart';

import 'helpers/app_harness.dart';
import 'helpers/visual.dart';

/// Bugün: "bu hafta" şeridi ve rutin bloğu tamamlanınca gelen an (titreşim + bir sonraki adım cümlesi).
void main() {
  final routine = routineFixture['routine'] as List;
  final today = DateTime(2026, 10, 10, 9, 15);
  final planDay = DateTime.parse('${FakeBackend().todayPlan['log_date']}');

  Map<String, Object> prefs({required int acceptedDaysAgo}) => {
        trackAcceptedKey(testUserId): '1',
        trackSnapshotKey(testUserId): jsonEncode({
          'routine': routine,
          'userName': 'Ayşe Test',
          'weather': routineFixture['weather'],
          'flowDebug': routineFixture['flow_debug'],
          // Sahte sunucunun "bugün"üne göre (şeridin son günü planın günüdür).
          'acceptedAt': planDay.subtract(Duration(days: acceptedDaysAgo)).add(const Duration(hours: 9)).millisecondsSinceEpoch,
        }),
      };

  /// Bugünden geriye 7 gün; `full`/`half` verilen günler (0 = bugün) işaretli.
  /// Sunucuda olduğu gibi son gün, planın günüdür (`log_date`).
  List<Map<String, Object>> week({Set<int> full = const {}, Set<int> half = const {}}) {
    final now = planDay;
    return [
      for (var back = 6; back >= 0; back--)
        {
          'log_date': DateTime(now.year, now.month, now.day).subtract(Duration(days: back)).toIso8601String().substring(0, 10),
          'morning': full.contains(back) || half.contains(back),
          'evening': full.contains(back),
        },
    ];
  }

  setUp(() => todayPanelClock = () => today);
  tearDown(() => todayPanelClock = DateTime.now);

  testWidgets('şerit sunucunun haftasını gösterir: tam günler sayılır', (tester) async {
    final backend = FakeBackend();
    backend.todayPlan = {...backend.todayPlan, 'week': week(full: {1, 2, 4}, half: {3})};
    await pumpApp(tester, location: '/dashboard', prefs: prefs(acceptedDaysAgo: 30), backend: backend);
    expect(find.text(tr('mobileToday.week.title')), findsOneWidget);
    expect(find.text(tr('mobileToday.week.full', {'n': 3, 'total': 7})), findsOneWidget);
  });

  testWidgets('yeni kullanıcı: takipten önceki günler kaçırılmış sayılmaz', (tester) async {
    final backend = FakeBackend();
    backend.todayPlan = {...backend.todayPlan, 'week': week()};
    await pumpApp(tester, location: '/dashboard', prefs: prefs(acceptedDaysAgo: 1), backend: backend);
    // Dün kabul edildi: yalnızca dün ve bugün sayılır.
    expect(find.text(tr('mobileToday.week.full', {'n': 0, 'total': 2})), findsOneWidget);
  });

  testWidgets('eski sunucu (week yok): şerit hiç çizilmez', (tester) async {
    final backend = FakeBackend();
    backend.todayPlan = {...backend.todayPlan}..remove('week');
    await pumpApp(tester, location: '/dashboard', prefs: prefs(acceptedDaysAgo: 30), backend: backend);
    expect(find.text(tr('mobileToday.week.title')), findsNothing);
  });

  group('tamamlanma anı', () {
    final calls = <String>[];

    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'HapticFeedback.vibrate') calls.add('${call.arguments}');
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });

    testWidgets('"yaptım" ile sabah bitince belirgin titreşim ve akşamın saati; şerit bugünü tam saymaz', (tester) async {
      final backend = FakeBackend();
      backend.todayPlan = {...backend.todayPlan, 'week': week()};
      await pumpApp(tester, location: '/dashboard', prefs: prefs(acceptedDaysAgo: 30), backend: backend);
      calls.clear();

      await tapText(tester, tr('mobileToday.bar.mark.morning'));
      expect(calls, contains('HapticFeedbackType.heavyImpact'));
      expect(find.text(tr('mobileToday.hero.nextEvening', {'time': '21:00'})), findsOneWidget);
    });

    testWidgets('açılışta zaten tamamlanmış blok titreşim çaldırmaz', (tester) async {
      final backend = FakeBackend();
      backend.todayPlan = {
        ...backend.todayPlan,
        'progress': {'routine_morning_done': true},
      };
      await pumpApp(tester, location: '/dashboard', prefs: prefs(acceptedDaysAgo: 30), backend: backend);
      expect(calls, isNot(contains('HapticFeedbackType.heavyImpact')));
    });
  });

  group('görsel', () {
    setUpAll(() async {
      if (screenshotsEnabled) await loadBrandFonts();
    });

    testWidgets('bugun-hafta', (tester) async {
      if (!screenshotsEnabled) return;
      debugDisableShadows = false;
      try {
        final backend = FakeBackend();
        backend.todayPlan = {...backend.todayPlan, 'week': week(full: {1, 2, 4, 5}, half: {3})};
        await pumpApp(tester, location: '/dashboard', prefs: prefs(acceptedDaysAgo: 30), backend: backend, realFonts: true);
        await tapText(tester, tr('mobileToday.bar.mark.morning'));
        await tester.pumpAndSettle();
        await shoot(tester, 'bugun-hafta-tamam');
      } finally {
        debugDisableShadows = true;
      }
    });
  });
}
