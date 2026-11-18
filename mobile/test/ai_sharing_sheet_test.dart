import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/core/ai_sharing.dart';
import 'package:rebi/ui/components/modals.dart';
import 'package:rebi/ui/tw.dart';

import 'helpers/app_harness.dart';
import 'helpers/visual.dart';

/// Yapay zekâ veri paylaşımı izin sayfası: editoryal düzen, altta sabit eylemler, küçük ekran ve büyük yazıda taşmama.
void main() {
  testWidgets('gönderilen her veri satırı, alıcı, gönderilmeyenler ve kontrol bölümleri görünür', (tester) async {
    await pumpApp(tester, location: '/dashboard', acknowledgeAi: false);
    expect(find.byType(AiSharingPanel), findsOneWidget);
    expect(find.text('GİZLİLİK İZNİ'), findsOneWidget, reason: 'etiket Türkçe büyük harfle (i → İ) yazılır');
    final items = tr('mobileAiSharing.items').split('\n').where((e) => e.trim().isNotEmpty);
    for (final item in items) {
      expect(find.text(item.trim()), findsOneWidget);
    }
    for (final key in ['whoTitle', 'who', 'notSentTitle', 'notSent', 'controlTitle', 'control', 'privacyLink']) {
      expect(find.text(tr('mobileAiSharing.$key')), findsOneWidget, reason: key);
    }
  });

  testWidgets('eylemler içerik kaydırılmadan görünür (altta sabit)', (tester) async {
    await pumpApp(tester, location: '/dashboard', acknowledgeAi: false, size: const Size(360, 640));
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    for (final key in ['allow', 'decline']) {
      final rect = tester.getRect(find.text(tr('mobileAiSharing.$key')));
      expect(rect.bottom, lessThanOrEqualTo(screen.height), reason: '$key ekranda');
      expect(rect.top, greaterThan(0));
    }
    await tester.tap(find.text(tr('mobileAiSharing.allow')));
    await tester.pumpAndSettle();
    expect(hasAiSharingConsent(testUserId), isTrue);
  });

  testWidgets('küçük ekranda ve 1.6x yazıda taşma yok', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpApp(tester, location: '/dashboard', acknowledgeAi: false, size: const Size(320, 568));
    expect(find.byType(AiSharingPanel), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('izin, ilgili özellikten önce sorulduğunda da aynı sayfa açılır', (tester) async {
    await pumpApp(tester, location: '/dashboard/account');
    final ctx = tester.element(find.byType(Scaffold).first);
    final result = showAiSharingDialog(ctx);
    await tester.pumpAndSettle();
    expect(find.byType(AiSharingPanel), findsOneWidget);
    await tester.tap(find.text(tr('mobileAiSharing.decline')));
    await tester.pumpAndSettle();
    expect(await result, isFalse);
  });

  group('görsel', () {
    setUpAll(() async {
      if (screenshotsEnabled) await loadBrandFonts();
    });
    for (final dark in [false, true]) {
      for (final lang in ['tr', 'en']) {
        final name = 'ai-sharing-${dark ? 'koyu' : 'acik'}-$lang';
        testWidgets(name, (tester) async {
          if (!screenshotsEnabled) return;
          Tw.dark = dark;
          addTearDown(() => Tw.dark = false);
          debugDisableShadows = false;
          try {
            await pumpApp(tester, location: '/dashboard', acknowledgeAi: false, realFonts: true, lang: lang);
            await shoot(tester, name);
            await tester.drag(find.text(tr('mobileAiSharing.intro')), const Offset(0, -900));
            await tester.pumpAndSettle();
            await shoot(tester, '$name-alt');
          } finally {
            debugDisableShadows = true;
          }
        });
      }
    }
  });
}
