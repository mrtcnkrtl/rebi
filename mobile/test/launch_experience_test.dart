import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/ui/brand/brand_caps.dart';
import 'package:rebi/ui/brand/brand_mark.dart';

import 'helpers/app_harness.dart';

/// Açılış ve karşılama: yerel açılış ekranıyla dikişsiz geçiş ve etiket yazımı.
void main() {
  group('brandCaps / brandTracking', () {
    test('Türkçede i→İ ve ı→I (Dart\'ın toUpperCase\'i yerel ayar bilmez)', () {
      expect(brandCaps('dermokozmetik yapay zekası', 'tr'), 'DERMOKOZMETİK YAPAY ZEKASI');
      expect(brandCaps('ılık', 'tr'), 'ILIK');
      expect(brandCaps('Analiz', 'az'), 'ANALİZ');
    });

    test('diğer Latin dillerinde olağan büyük harf; Arapçada metin değişmez ve harf aralığı sıfırdır', () {
      expect(brandCaps('Dermocosmetic AI', 'en'), 'DERMOCOSMETIC AI');
      expect(brandCaps('الذكاء الاصطناعي', 'ar'), 'الذكاء الاصطناعي');
      expect(brandTracking('ar', 2.4), 0);
      expect(brandTracking('tr', 2.4), 2.4);
    });
  });

  group('açılış ekranı', () {
    testWidgets('ilk kare yerel açılışla örtüşür: karo ekranın tam ortasında ve ${BrandMark.launchSize.round()} dp', (tester) async {
      final h = await pumpApp(tester, location: '/', loggedIn: false);
      h.router.go('/splash');
      await tester.pump(); // açılış sayfası kuruldu; animasyon henüz ilerlemedi

      final tile = find.byType(BrandMark);
      expect(tile, findsOneWidget);
      expect(tester.getSize(tile), const Size.square(BrandMark.launchSize));
      // Ekran 390×844: yerel açılış (Android 12+ vektörü, Android 12 öncesi bitmap, iOS LaunchImage) karoyu tam ortaya koyar.
      expect(tester.getCenter(tile).dx, closeTo(195, .5));
      expect(tester.getCenter(tile).dy, closeTo(422, .5));
    });

    testWidgets('animasyon bitince marka yazısı ve slogan görünür, dokunmak karşılamaya geçirir', (tester) async {
      final h = await pumpApp(tester, location: '/', loggedIn: false);
      h.router.go('/splash');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1900));
      expect(find.text('R'), findsOneWidget);
      expect(find.text('i'), findsOneWidget);

      await tester.tap(find.byType(BrandMark));
      await settle(tester, 8);
      expect(h.router.routeInformationProvider.value.uri.path, '/');
    });
  });
}
