import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/config/env.dart';
import 'package:rebi/core/beta_notice.dart';
import 'package:rebi/core/local_store.dart';
import 'package:rebi/screens/landing_screen.dart';
import 'package:rebi/ui/brand/beta_badge.dart';
import 'package:rebi/ui/components/beta_notice.dart';
import 'package:rebi/ui/components/modals.dart';

import 'helpers/app_harness.dart';

/// Beta sürüm bilgilendirmesi: giriş ekranlarındaki "BETA" etiketi ve ilk açılışta bir kez çıkan "hata çıkabilir" uyarısı.
void main() {
  setUp(() {
    betaNoticePending = false;
    startupSequencePlaying.value = false;
    landingIntroPending = false;
  });
  tearDown(() {
    betaNoticePending = false;
    startupSequencePlaying.value = false;
    landingIntroPending = false;
  });

  final panel = find.byType(BetaNoticePanel);

  /// Kapanış animasyonu (460 ms) pop'u izleyen ilk karede başlar: bir kare başlatır, bir sonraki bitirir.
  Future<void> closing(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  group('BETA etiketi', () {
    testWidgets('karşılamada markanın yanında durur ve ekran okuyucuya "Beta sürüm" der', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, location: '/', loggedIn: false);

      expect(find.byType(BetaBadge), findsOneWidget);
      expect(find.text('BETA'), findsOneWidget, reason: 'aralıklı büyük harfli etiket');
      expect(find.bySemanticsLabel(tr('mobileBeta.badgeLabel')), findsOneWidget);
      handle.dispose();
    });

    testWidgets('İngilizce arayüzde de BETA yazar', (tester) async {
      await pumpApp(tester, location: '/', loggedIn: false, lang: 'en');
      expect(find.text('BETA'), findsOneWidget);
    });

    testWidgets('giriş yapılmış uygulama içi ekranda etiket yok (yalnızca girişteki genel çubuk taşır)', (tester) async {
      await pumpApp(tester, location: '/dashboard');
      expect(find.byType(BetaBadge), findsNothing);
    });

    testWidgets('açılış sekansında etiket marka yerleştikten sonra, dil seçiciyle birlikte belirir', (tester) async {
      landingIntroPending = true;
      await pumpApp(tester, location: '/', loggedIn: false, settleAfter: false);
      double opacityOfBadge() {
        final o = tester.widget<Opacity>(find.ancestor(of: find.byType(BetaBadge), matching: find.byType(Opacity)).first);
        return o.opacity;
      }

      await tester.pump(const Duration(milliseconds: 600));
      expect(opacityOfBadge(), 0, reason: 'marka henüz ekranın ortasında kuruluyor');
      await tester.pump(const Duration(milliseconds: 2600));
      expect(opacityOfBadge(), 1);
    });
  });

  group('açılış uyarısı', () {
    test('beta derlemesinde ve bu cihazda görülmediyse gösterilir; görüldükten sonra gösterilmez', () async {
      expect(Env.betaBuild, isTrue, reason: 'varsayılan derleme betadır (REBI_BETA=false ile kapanır)');
      await LocalStore.init();
      expect(shouldShowBetaNotice(), isTrue);
      await markBetaNoticeSeen();
      expect(hasSeenBetaNotice(), isTrue);
      expect(shouldShowBetaNotice(), isFalse);
    });

    testWidgets('bekleyen uyarı açılıştan kısa süre sonra çıkar; "Anladım" kapatır; bir açılışta bir kez', (tester) async {
      betaNoticePending = true;
      await pumpApp(tester, location: '/dashboard', settleAfter: false);
      expect(betaNoticePending, isFalse, reason: 'kapı bayrağı kurulurken tüketir');
      expect(panel, findsNothing, reason: 'ekran önce oturur');

      await tester.pump(const Duration(milliseconds: 1000));
      await tester.pump(const Duration(milliseconds: 600));
      expect(panel, findsOneWidget);
      expect(find.text(tr('mobileBeta.title')), findsOneWidget);
      expect(find.text(tr('mobileBeta.body')), findsOneWidget);
      expect(find.text(tr('mobileBeta.report')), findsOneWidget);
      expect(find.byType(BetaBadge), findsOneWidget, reason: 'kartta da etiket');
      expect(hasSeenBetaNotice(), isTrue, reason: 'gösterilir gösterilmez görüldü yazılır');

      await tester.tap(find.text(tr('mobileBeta.ok')));
      await closing(tester);
      expect(panel, findsNothing);

      // Başka bir ekrana geçilince yeniden çıkmaz.
      await tester.pump(const Duration(milliseconds: 1500));
      expect(panel, findsNothing);
    });

    testWidgets('uyarı beklemiyorsa (zaten görüldü ya da test uygulaması) hiç çıkmaz', (tester) async {
      await pumpApp(tester, location: '/dashboard', prefs: {betaNoticeKey: '1'});
      await tester.pump(const Duration(seconds: 3));
      expect(panel, findsNothing);
    });

    testWidgets('Android geri tuşu uyarıyı kapatır, arkadaki ekran yerinde kalır', (tester) async {
      betaNoticePending = true;
      final h = await pumpApp(tester, location: '/dashboard', settleAfter: false);
      await tester.pump(const Duration(milliseconds: 1000));
      await tester.pump(const Duration(milliseconds: 600));
      expect(panel, findsOneWidget);

      await tester.binding.handlePopRoute();
      await closing(tester);
      expect(panel, findsNothing);
      expect(h.router.routerDelegate.currentConfiguration.uri.path, '/dashboard');
    });

    testWidgets('başka bir sekmedeyken de geri tuşu önce uyarıyı kapatır (sekme gezintisi bozulmaz)', (tester) async {
      betaNoticePending = true;
      final h = await pumpApp(tester, location: '/dashboard/history', settleAfter: false);
      await tester.pump(const Duration(milliseconds: 1000));
      await tester.pump(const Duration(milliseconds: 600));
      expect(panel, findsOneWidget);

      await tester.binding.handlePopRoute();
      await closing(tester);
      expect(panel, findsNothing);
      expect(h.router.routerDelegate.currentConfiguration.uri.path, '/dashboard/history');
    });

    testWidgets('karşılamanın giriş sekansı sürerken bekler; sekans bitince bir an sonra çıkar', (tester) async {
      betaNoticePending = true;
      landingIntroPending = true;
      await pumpApp(tester, location: '/', loggedIn: false, settleAfter: false);

      await tester.pump(const Duration(milliseconds: 1500));
      expect(startupSequencePlaying.value, isTrue);
      await tester.pump(const Duration(milliseconds: 1400));
      expect(panel, findsNothing, reason: 'marka kurulumunun üstüne binmez');

      await tester.pump(const Duration(milliseconds: 300)); // sekans (3 sn) bitti
      expect(startupSequencePlaying.value, isFalse);
      await tester.pump(const Duration(milliseconds: 500));
      expect(panel, findsNothing, reason: 'ekran oturana kadar kısa bir bekleme');

      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 600));
      expect(panel, findsOneWidget);
    });

    testWidgets('sekansı dokunarak atlayan kullanıcıya da uyarı sekans bitince çıkar', (tester) async {
      betaNoticePending = true;
      landingIntroPending = true;
      await pumpApp(tester, location: '/', loggedIn: false, settleAfter: false);
      await tester.pump(const Duration(milliseconds: 800));
      expect(panel, findsNothing);

      await tester.tapAt(const Offset(195, 400));
      await tester.pump(const Duration(milliseconds: 100));
      expect(startupSequencePlaying.value, isFalse);
      await tester.pump(const Duration(milliseconds: 1000));
      await tester.pump(const Duration(milliseconds: 600));
      expect(panel, findsOneWidget);
    });

    testWidgets('İngilizce metin, dar ekran ve %200 yazıda taşmadan kaydırılabilir', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      betaNoticePending = true;
      await pumpApp(tester, location: '/dashboard', lang: 'en', size: const Size(320, 568), settleAfter: false);
      await tester.pump(const Duration(milliseconds: 1000));
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('Rebi is in beta for now'), findsOneWidget);
      expect(find.text('Got it'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(find.byType(ModalFrame), findsOneWidget);
    });

    testWidgets('Rebi sohbetinin yapay zekâ izni kutusu ve beta uyarısı birbirini bozmaz', (tester) async {
      betaNoticePending = true;
      await pumpApp(tester, location: '/dashboard/chat', acknowledgeAi: false, settleAfter: false);
      await tester.pump(const Duration(milliseconds: 1000));
      await tester.pump(const Duration(milliseconds: 600));
      expect(panel, findsOneWidget, reason: 'beta uyarısı en üstte');

      await tester.tap(find.text(tr('mobileBeta.ok')));
      await closing(tester);
      expect(panel, findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
