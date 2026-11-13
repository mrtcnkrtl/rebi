import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/screens/landing_screen.dart';
import 'package:rebi/ui/brand/brand_button.dart';
import 'package:rebi/ui/brand/brand_caps.dart';
import 'package:rebi/ui/brand/brand_mark.dart';
import 'package:rebi/ui/brand/welcome_art.dart';

import 'helpers/app_harness.dart';

/// Açılış ve karşılama: yerel açılış ekranıyla dikişsiz geçiş, tek sekans, günün ışığı ve düğme detayları.
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

  group('açılış sekansı (karşılamanın içinde)', () {
    // Sekansta iki karo vardır: üst çubuktaki (gizli, yerini tutar) ve sürüklenen marka katmanındaki.
    Finder tileOf(double size) => find.byWidgetPredicate((w) => w is BrandMark && w.size == size);

    tearDown(() => landingIntroPending = false);

    testWidgets('ilk kare yerel açılışla örtüşür: karo ekranın tam ortasında ve ${BrandMark.launchSize.round()} dp', (tester) async {
      landingIntroPending = true;
      await pumpApp(tester, location: '/', loggedIn: false, settleAfter: false);

      final tile = tileOf(BrandMark.launchSize);
      expect(tile, findsOneWidget);
      // Ekran 390×844: yerel açılış (Android 12+ vektörü, Android 12 öncesi bitmap, iOS LaunchImage) karoyu tam ortaya koyar.
      expect(tester.getCenter(tile).dx, closeTo(195, .5));
      expect(tester.getCenter(tile).dy, closeTo(422, .5));
    });

    testWidgets('sekans bitince marka sol üstteki yerine oturur ve içerik hazırdır; ana düğme kayda götürür', (tester) async {
      landingIntroPending = true;
      final h = await pumpApp(tester, location: '/', loggedIn: false, settleAfter: false);
      await tester.pump(const Duration(milliseconds: 4800));

      // Üst çubuktaki yer: soldan 24 + karo 28 → merkez (38, 34).
      final tile = tileOf(28);
      expect(tester.getCenter(tile.first).dx, closeTo(38, .5));
      expect(tester.getCenter(tile.first).dy, closeTo(34, .5));
      expect(tileOf(BrandMark.launchSize), findsNothing, reason: 'büyük karo küçülüp yerine oturdu');
      expect(find.text(tr('mobileLanding.heroTitle')), findsOneWidget);

      await tapText(tester, tr('landing.ctaBuildRoutine'));
      expect(h.router.routeInformationProvider.value.uri.path, '/auth');
    });

    testWidgets('sekans sürerken dokunmak onu atlatır; henüz görünmeyen düğmeler tetiklenmez', (tester) async {
      landingIntroPending = true;
      final h = await pumpApp(tester, location: '/', loggedIn: false, settleAfter: false);
      await tester.pump(const Duration(milliseconds: 600));

      // Ana düğmenin yerine dokunmak (sekans sürerken) düğmeyi çalıştırmaz, sekansı atlatır.
      await tester.tapAt(tester.getCenter(find.text(tr('landing.ctaBuildRoutine'))));
      await tester.pump(const Duration(milliseconds: 1500));
      expect(h.router.routeInformationProvider.value.uri.path, '/');
      expect(tileOf(BrandMark.launchSize), findsNothing);

      // Sekans bitti: aynı düğme artık çalışır.
      await tapText(tester, tr('landing.ctaBuildRoutine'));
      expect(h.router.routeInformationProvider.value.uri.path, '/auth');
    });

    testWidgets('sekans yalnızca bir kez oynar: girişten geri dönüşte karşılama doğrudan son hâlinde açılır', (tester) async {
      landingIntroPending = true;
      final h = await pumpApp(tester, location: '/', loggedIn: false, settleAfter: false);
      await tester.pump(const Duration(milliseconds: 4800));
      expect(landingIntroPending, isFalse, reason: 'ilk karşılama bayrağı tükettikten sonra');

      h.router.go('/auth');
      await settle(tester, 10);
      h.router.go('/');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(tileOf(BrandMark.launchSize), findsNothing, reason: 'sekans yeniden oynamaz');
      expect(find.text(tr('landing.ctaBuildRoutine')), findsOneWidget);
    });

    testWidgets('sekans işaretsizken karşılama sekanssız, doğrudan son hâlinde açılır', (tester) async {
      await pumpApp(tester, location: '/', loggedIn: false);
      expect(tileOf(BrandMark.launchSize), findsNothing);
      expect(find.text(tr('landing.ctaBuildRoutine')), findsOneWidget);
    });
  });

  group('günün ışığı', () {
    tearDown(() => heroClock = DateTime.now);

    test('saat → gökyüzü: gündüz 05–17, akşam 17–21, gece 21–05', () {
      HeroSky at(int h, [int m = 0]) => HeroLight.at(DateTime(2026, 10, 22, h, m)).sky;
      expect(at(5), HeroSky.day);
      expect(at(10, 30), HeroSky.day);
      expect(at(16, 59), HeroSky.day);
      expect(at(17), HeroSky.dusk);
      expect(at(20, 59), HeroSky.dusk);
      expect(at(21), HeroSky.night);
      expect(at(23, 59), HeroSky.night);
      expect(at(0), HeroSky.night);
      expect(at(4, 59), HeroSky.night);
    });

    test('üç gökyüzünün ışık rengi ve disk konumu birbirinden farklıdır', () {
      final lights = [HeroLight.day, HeroLight.dusk, HeroLight.night];
      expect({for (final l in lights) l.glow}, hasLength(3));
      expect({for (final l in lights) l.discAt}, hasLength(3));
    });

    for (final light in [HeroLight.day, HeroLight.dusk, HeroLight.night]) {
      testWidgets('kahraman çizim ${light.sky.name} gökyüzüyle hatasız çizilir', (tester) async {
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: SizedBox(width: 320, height: 320, child: HeroArt(light: light)))));
        await tester.pump(const Duration(milliseconds: 3000));
        await tester.pump(const Duration(milliseconds: 2000)); // parıltı bandı penceresi
        expect(tester.takeException(), isNull);
        expect(find.byType(HeroArt), findsOneWidget);
      });
    }

    for (final (hour, sky) in [(10, HeroSky.day), (18, HeroSky.dusk), (23, HeroSky.night)]) {
      testWidgets('karşılama saati izler: saat $hour → ${sky.name} ışığı', (tester) async {
        heroClock = () => DateTime(2026, 10, 22, hour);
        await pumpApp(tester, location: '/', loggedIn: false);
        expect(tester.takeException(), isNull);
        expect(tester.widget<HeroArt>(find.byType(HeroArt)).light.sky, sky);
      });
    }
  });

  group('karşılamadan kayda geçiş', () {
    testWidgets('çıkarken yalnızca içerik süzülüp solar; zemin yerinde kalır, sonra kayıt sayfası açılır', (tester) async {
      final h = await pumpApp(tester, location: '/', loggedIn: false);
      final title = find.text(tr('mobileLanding.heroTitle'));
      double contentOpacity() => tester
          .widgetList<Opacity>(find.ancestor(of: title, matching: find.byType(Opacity)))
          .map((o) => o.opacity)
          .fold(1.0, (a, b) => a < b ? a : b);
      expect(contentOpacity(), 1.0, reason: 'duran karşılamada içerik tam görünür');

      await tester.tap(find.text(tr('auth.login')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(h.router.routeInformationProvider.value.uri.path, '/auth');
      expect(title, findsOneWidget, reason: 'geçiş sürerken karşılama hâlâ ağaçta');
      expect(contentOpacity(), lessThan(1.0), reason: 'içerik solmaya başladı');

      await settle(tester, 8);
      expect(title, findsNothing);
      expect(find.text(tr('auth.welcome')), findsOneWidget);
    });
  });

  group('düğme mikro detayları', () {
    testWidgets('ışık bandı (ShimmerOnce) dokunmayı engellemez ve bitince kaybolur', (tester) async {
      var taps = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: BrandButton(onDark: true, onPressed: () => taps++, label: 'Başla', shimmerDelay: const Duration(milliseconds: 100)),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 600)); // band geçerken
      await tester.tap(find.text('Başla'));
      expect(taps, 1);
      await tester.pump(const Duration(milliseconds: 2000)); // band bitti
      await tester.tap(find.text('Başla'));
      expect(taps, 2);
      expect(tester.takeException(), isNull);
    });
  });
}
