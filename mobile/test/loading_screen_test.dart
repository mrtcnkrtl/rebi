import 'package:flutter/material.dart' show Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/ui/components/loading_screen.dart';

import 'helpers/app_harness.dart';

/// Rutin üretilirken gösterilen bekleme ekranı: sahne dilinde, çevrilmiş, küçük ekranda ve büyük yazıda taşmaz.
void main() {
  for (final lang in ['tr', 'en']) {
    testWidgets('dört adım ve başlık ($lang); sıradaki adım ilerler', (tester) async {
      await pumpStandalone(tester, (theme) => const LoadingScreen(), lang: lang);
      expect(find.text(tr('mobileAnalyze.loading.title')), findsOneWidget);
      for (final k in ['weather', 'science', 'ai', 'build']) {
        expect(find.text(tr('mobileAnalyze.loading.$k')), findsOneWidget, reason: k);
      }
      expect(find.text(tr('mobileAnalyze.loading.note')), findsOneWidget);
      // Adımlar zamanla ilerler; sürekli animasyon yüzünden pumpAndSettle yerine kare ilerletilir.
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('320×568 ve %200 yazıda taşmaz', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpStandalone(tester, (theme) => const LoadingScreen(), size: const Size(320, 568));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(tester.takeException(), isNull);
  });
}
