import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart' show BoxDecoration, Color, Column, Container, Size, SizedBox;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/core/haptics.dart';
import 'package:rebi/core/routine_logic.dart';
import 'package:rebi/core/routine_tracking.dart';
import 'package:rebi/screens/today/today_clock.dart';
import 'package:rebi/ui/widgets/skeleton.dart';

import 'helpers/app_harness.dart';

/// Son cila: iskelet yükleme ve dokunsal geri bildirim.
void main() {
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

  setUp(() => todayPanelClock = () => DateTime(2026, 10, 10, 9, 15));
  tearDown(() => todayPanelClock = DateTime.now);

  group('iskelet', () {
    testWidgets('kart iskeleti 320 genişlikte taşmaz ve nabız atar', (tester) async {
      await pumpStandalone(
        tester,
        (theme) => const Column(children: [SkeletonCard(lines: 3, withActions: true), SizedBox(height: 8), SkeletonCard()]),
        size: const Size(320, 640),
      );
      expect(find.byType(SkeletonBox), findsWidgets);
      expect(tester.takeException(), isNull);

      Color? colorOf() {
        final box = find.descendant(of: find.byType(SkeletonBox).first, matching: find.byType(Container));
        return (tester.widget<Container>(box).decoration as BoxDecoration?)?.color;
      }

      final start = colorOf();
      await tester.pump(const Duration(milliseconds: 450));
      expect(colorOf(), isNot(start), reason: 'renk zamanla değişir');
    });

    testWidgets('yükleniyor etiketi okuyucuya söylenir', (tester) async {
      await pumpStandalone(tester, (theme) => const SkeletonCard());
      expect(find.bySemanticsLabel(tr('mobileCommon.loading')), findsOneWidget);
    });

    testWidgets('plan yüklenirken Şimdi kartı ve takip kartları iskelet gösterir; gelince kalkar', (tester) async {
      final backend = FakeBackend()..planGate = Completer<void>();
      await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs(), backend: backend);
      expect(find.byType(SkeletonCard), findsNWidgets(4), reason: 'Gün akışı kartı + su kartı + makyaj ile beslenme kartları');
      expect(find.text(tr('mobileToday.makeup.ask')), findsNothing);

      backend.planGate!.complete();
      await settle(tester);
      expect(find.byType(SkeletonCard), findsNothing);
      expect(find.text(tr('mobileToday.makeup.ask')), findsOneWidget);
    });

    testWidgets('plan yüklenemezse iskelet kalmaz, uyarı çıkar', (tester) async {
      final backend = FakeBackend()..planFails = true;
      await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs(), backend: backend);
      expect(find.byType(SkeletonCard), findsNothing);
      expect(find.text(tr('mobileToday.loadFailed')), findsOneWidget);
    });
  });

  group('dokunsal geri bildirim', () {
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

    test('Haptics doğru titreşim türlerini ister', () async {
      Haptics.selection();
      Haptics.success();
      Haptics.failure();
      await Future<void>.delayed(Duration.zero);
      expect(calls, ['HapticFeedbackType.selectionClick', 'HapticFeedbackType.lightImpact', 'HapticFeedbackType.mediumImpact']);
    });

    testWidgets('kayıt başarılı olunca hafif, başarısız olunca orta titreşim', (tester) async {
      final backend = FakeBackend();
      await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs(), backend: backend);
      calls.clear();

      await tapText(tester, tr('mobileToday.actions.water250'));
      expect(calls, contains('HapticFeedbackType.lightImpact'));

      calls.clear();
      backend.ingestStatus = 422;
      await tapText(tester, tr('mobileToday.actions.water500'));
      expect(calls, contains('HapticFeedbackType.mediumImpact'));
      expect(calls, isNot(contains('HapticFeedbackType.lightImpact')));
    });

    testWidgets('rutin adımı işaretlenince seçim titreşimi', (tester) async {
      await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs());
      calls.clear();
      final first = RoutineView(asRoutine(routine)).routineByDay[getTurkeyWeekdayIndex()]!.morning.first;
      await tapText(tester, pickAction(first, localized: false));
      expect(calls, contains('HapticFeedbackType.selectionClick'));
    });
  });
}
