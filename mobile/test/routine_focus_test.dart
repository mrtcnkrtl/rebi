import 'dart:convert';

import 'package:flutter/rendering.dart' show debugDisableShadows;
import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/core/routine_logic.dart';
import 'package:rebi/core/routine_tracking.dart';
import 'package:rebi/screens/today/routine_focus.dart';
import 'package:rebi/screens/today/today_clock.dart';
import 'package:rebi/ui/brand/brand_caps.dart';

import 'helpers/app_harness.dart';
import 'helpers/visual.dart';

/// Odak modu: rutini tek tek uygulatır ve her "Yaptım" bugünün kaydına işler.
void main() {
  final routine = routineFixture['routine'] as List;

  Map<String, Object> prefs() => {
        trackAcceptedKey(testUserId): '1',
        trackSnapshotKey(testUserId): jsonEncode({
          'routine': routine,
          'userName': 'Ayşe Test',
          'weather': routineFixture['weather'],
          'flowDebug': routineFixture['flow_debug'],
          'acceptedAt': DateTime.now().millisecondsSinceEpoch - 3 * 86400000,
        }),
      };

  final morning = RoutineView(asRoutine(routine)).routineByDay[getTurkeyWeekdayIndex(DateTime(2026, 10, 10))]!.morning;
  String name(RoutineItem item) => shortStepName(pickAction(item, localized: false));
  // Üst etiket marka büyük harfiyle yazılır ("ADIM 1 / 3").
  String stepLabel(Map<String, Object?> vars) => brandCaps(tr('mobileFocus.stepOf', vars), 'tr');

  setUp(() => todayPanelClock = () => DateTime(2026, 10, 10, 9, 15));
  tearDown(() => todayPanelClock = DateTime.now);

  Future<Harness> open(WidgetTester tester, {FakeBackend? backend}) async {
    final h = await pumpApp(tester, location: '/dashboard', prefs: prefs(), backend: backend);
    await tapText(tester, tr('mobileFocus.start'));
    return h;
  }

  testWidgets('her "Yaptım" adımı işaretler; son adım bloğu tamamlar ve bitiş ekranı açılır', (tester) async {
    expect(morning.length, greaterThan(1));
    final h = await open(tester);
    expect(find.text(name(morning.first)), findsWidgets);
    expect(find.text(stepLabel({'n': 1, 'total': morning.length})), findsOneWidget);

    for (var i = 0; i < morning.length; i++) {
      final last = i == morning.length - 1;
      await tapText(tester, tr(last ? 'mobileFocus.doneLast' : 'mobileFocus.done'));
    }
    expect(h.backend.progress['routine_morning_done'], isTrue);
    expect(find.text(tr('mobileFocus.finishTitle.morning')), findsOneWidget);

    await tapText(tester, tr('mobileFocus.close'));
    expect(find.text(tr('mobileFocus.finishBody')), findsNothing, reason: 'Bugün ekranına dönüldü');
  });

  testWidgets('"atla" adımı işaretlemez', (tester) async {
    final h = await open(tester);
    final before = h.backend.calls('/daily_tracking/ingest').length;
    await tapText(tester, tr('mobileFocus.skip'));
    expect(h.backend.calls('/daily_tracking/ingest'), hasLength(before));
    expect(find.text(stepLabel({'n': 2, 'total': morning.length})), findsOneWidget);
  });

  testWidgets('daha önce işaretlenen adımdan sonra başlar; işaretli adımın işareti kalkmaz', (tester) async {
    final backend = FakeBackend();
    final first = stepOrder(morning.first).round();
    backend.todayPlan = {
      ...backend.todayPlan,
      'progress': {
        'routine_steps': {
          'morning': [first],
        },
      },
    };
    final h = await open(tester, backend: backend);
    expect(find.text(stepLabel({'n': 2, 'total': morning.length})), findsOneWidget);
    await tapFinder(tester, find.byTooltip(tr('mobileFocus.close')));
    expect(h.backend.calls('/daily_tracking/ingest'), isEmpty);
  });

  test('bekleme yalnızca serum/aktif adımından sonra önerilir', () {
    expect(suggestsWait({'step_order': 20}, last: false), isTrue);
    expect(suggestsWait({'step_order': 25}, last: false), isTrue);
    expect(suggestsWait({'step_order': 20}, last: true), isFalse, reason: 'son adımdan sonra beklenecek bir şey yok');
    expect(suggestsWait({'step_order': 10}, last: false), isFalse);
    expect(suggestsWait({'step_order': 30}, last: false), isFalse);
    expect(suggestsWait({'step_order': 40}, last: false), isFalse);
  });

  testWidgets('serum adımında bekleme sayacı geri sayar ve durdurulabilir', (tester) async {
    // Akşam (cumartesi): temizlik → Niasinamid %10 serum (sıra 20) → gece nemlendiricisi. Serumdan sonra bekleme önerilir.
    todayPanelClock = () => DateTime(2026, 10, 10, 21, 0);
    await open(tester);
    expect(find.text(tr('mobileFocus.wait')), findsNothing, reason: 'temizlikten sonra bekleme yok');
    await tapText(tester, tr('mobileFocus.skip'));
    expect(find.text(tr('mobileFocus.wait')), findsOneWidget);

    await tapText(tester, tr('mobileFocus.wait'));
    expect(find.text(tr('mobileFocus.waiting', {'s': focusWaitSeconds})), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text(tr('mobileFocus.waiting', {'s': focusWaitSeconds - 3})), findsOneWidget);
    await tapText(tester, tr('mobileFocus.waiting', {'s': focusWaitSeconds - 3}));
    expect(find.text(tr('mobileFocus.wait')), findsOneWidget, reason: 'durduruldu');
  });

  group('görsel', () {
    setUpAll(() async {
      if (screenshotsEnabled) await loadBrandFonts();
    });

    testWidgets('odak-modu', (tester) async {
      if (!screenshotsEnabled) return;
      debugDisableShadows = false;
      try {
        await pumpApp(tester, location: '/dashboard', prefs: prefs(), realFonts: true);
        await tapText(tester, tr('mobileFocus.start'));
        await shoot(tester, 'odak-1');
        for (var i = 0; i < morning.length; i++) {
          await tapText(tester, tr(i == morning.length - 1 ? 'mobileFocus.doneLast' : 'mobileFocus.done'));
        }
        await shoot(tester, 'odak-bitti');
      } finally {
        debugDisableShadows = true;
      }
    });
  });
}
