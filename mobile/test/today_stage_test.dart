import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/screens/today/empty_start.dart';
import 'package:rebi/screens/today/today_header.dart';
import 'package:rebi/state/theme_controller.dart';
import 'package:rebi/ui/tw.dart';
import 'package:rebi/ui/widgets/stage_overlap.dart';

import 'helpers/app_harness.dart';

/// Bugün'ün üst sahnesi, sahneye binen kart ve rutinsiz karşılama.
void main() {
  group('StageOverlap', () {
    testWidgets('gövde sahneye bindirilir: yükseklik, konum ve dokunma gövdeden başlar', (tester) async {
      var bodyTaps = 0;
      var stageTaps = 0;
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 300,
            child: StageOverlap(
              overlap: 30,
              stage: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => stageTaps++, child: const SizedBox(height: 100)),
              body: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => bodyTaps++, child: const SizedBox(height: 50)),
            ),
          ),
        ),
      ));
      expect(tester.getSize(find.byType(StageOverlap)), const Size(300, 120), reason: '100 + 50 - 30');
      expect(tester.getTopLeft(find.byType(GestureDetector).last).dy, 70, reason: 'gövde sahnenin alt 30 dp\'sine biner');

      // Bindirilen bölgeye (y=80) dokunma gövdeye gider, sahneye değil.
      await tester.tapAt(const Offset(150, 80));
      expect((bodyTaps, stageTaps), (1, 0));
      await tester.tapAt(const Offset(150, 40));
      expect((bodyTaps, stageTaps), (1, 1));
    });

    testWidgets('overlap sahneden büyükse gövde en üstten başlar', (tester) async {
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 200,
            child: StageOverlap(overlap: 500, stage: const SizedBox(height: 40), body: const SizedBox(height: 60)),
          ),
        ),
      ));
      expect(tester.getSize(find.byType(StageOverlap)).height, 60);
    });
  });

  group('tema derin tonu', () {
    test('her temanın sahne rengi vardır; koyu modda biraz koyulaşır ve üstünde krem yazı okunur', () {
      addTearDown(() => Tw.dark = false);
      Tw.dark = false;
      final light = {for (final e in rebiThemes.entries) e.key: e.value.stage};
      final deep = {for (final e in rebiThemes.entries) e.key: e.value.deep};
      Tw.dark = true;
      final dark = {for (final e in rebiThemes.entries) e.key: e.value.stage};
      Tw.dark = false;

      expect(light, isNotEmpty);
      const cream = Color(0xFFF7F3EC);
      for (final id in light.keys) {
        expect(light[id], deep[id], reason: '$id: açık modda sahne derin tonun kendisi');
        expect(dark[id]!.computeLuminance(), lessThan(light[id]!.computeLuminance()), reason: '$id: koyu modda sahne daha koyu');
        for (final c in [light[id]!, dark[id]!]) {
          final ratio = (cream.computeLuminance() + .05) / (c.computeLuminance() + .05);
          expect(ratio, greaterThanOrEqualTo(4.5), reason: '$id: krem yazı sahne zemininde okunmalı');
        }
      }
    });
  });

  group('rutinsiz karşılama (ilk giriş)', () {
    testWidgets('sahne kişisel selamla, kart "ilk adım" ve üç adımla gelir; ana düğme analize götürür', (tester) async {
      final h = await pumpApp(tester, location: '/dashboard');
      expect(find.byType(TodayHeader), findsOneWidget);
      expect(find.byType(TodayEmptyStart), findsOneWidget);
      expect(find.text(tr('dashboard.noAnalyzeTitle', {'name': 'Ayşe Test'})), findsOneWidget);
      expect(find.text(tr('mobileToday.empty.title')), findsOneWidget);
      for (final k in ['step1', 'step2', 'step3']) {
        expect(find.text(tr('mobileToday.empty.$k')), findsOneWidget);
      }
      expect(find.text(tr('dashboard.startAnalyze')), findsOneWidget);

      await tapText(tester, tr('dashboard.startAnalyze'));
      expect(h.router.routeInformationProvider.value.uri.path, '/dashboard/analyze');
    });

    testWidgets('sohbet eylemi sohbeti açar', (tester) async {
      final h = await pumpApp(tester, location: '/dashboard');
      await tapText(tester, tr('dashboard.chatWithAi'));
      expect(h.router.routeInformationProvider.value.uri.path, '/dashboard/chat');
    });

    testWidgets('Rutin sekmesinde de aynı karşılama görünür', (tester) async {
      await pumpApp(tester, location: '/dashboard/routine');
      expect(find.byType(TodayEmptyStart), findsOneWidget);
      expect(find.text(tr('dashboard.startAnalyze')), findsOneWidget);
    });
  });
}
