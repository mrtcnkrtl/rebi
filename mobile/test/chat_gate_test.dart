import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:rebi/screens/chat/chat_gate.dart';
import 'package:rebi/screens/chat/chat_parts.dart';
import 'package:rebi/state/auth_controller.dart';
import 'package:rebi/ui/tw.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'helpers/app_harness.dart';

/// Başarılı girişi Supabase'siz taklit eder: gerçek SDK gibi `signedIn` olayını yayar.
class _FakeAuth extends AuthController {
  @override
  Future<SignInResult> signIn(String email, String password) async {
    final u = fakeUser();
    debugEmitAuthState(AuthState(AuthChangeEvent.signedIn, Session(accessToken: 'tok', tokenType: 'bearer', user: u)));
    return SignInResult(user: u);
  }
}

/// Şu an üstte açık olan konum. `push` ile açılan sayfa (giriş) yönlendirici bilgisine yansımaz; üst eşleşmeden okunur.
Uri _at(Harness h) {
  final config = h.router.routerDelegate.currentConfiguration;
  final top = config.last;
  return top is ImperativeRouteMatch ? top.matches.uri : config.uri;
}

final _signUp = find.byKey(const Key('chat-gate-signup'));
final _signIn = find.byKey(const Key('chat-gate-signin'));

/// Oturumsuz "Rebi ile konuş" (`/rebi`): sohbet hesap ister; yazı alanı yerine davet gösterilir, hiçbir istek atılmaz.
void main() {
  group('oturumsuz davet (/rebi)', () {
    testWidgets('yazı alanı yerine davet: Rebi kendini tanıtır, iki net eylem sunar; öneri ve sohbet isteği yok', (tester) async {
      final h = await pumpApp(tester, location: '/rebi', loggedIn: false);

      expect(find.byType(ChatGate), findsOneWidget);
      expect(find.text(tr('mobileChat.gate.title')), findsOneWidget, reason: 'sahnenin başlığı');
      expect(find.text(tr('mobileChat.gate.hello')), findsOneWidget);
      expect(find.text(tr('mobileChat.gate.why')), findsOneWidget, reason: 'neden hesap gerektiği');
      expect(find.text(tr('auth.signup')), findsOneWidget);
      expect(find.text(tr('auth.login')), findsOneWidget);
      expect(find.text(tr('mobileAuth.trust')), findsOneWidget);

      expect(find.byType(TextField), findsNothing, reason: 'yazılamayan bir alan gösterilmez');
      expect(find.text(tr('mobileChat.suggestions.generic1')), findsNothing, reason: 'dokununca gönderilmeyecek öneri yok');
      expect(find.text(tr('chat.emptyTitle')), findsNothing);

      expect(h.backend.calls('/chat_general'), isEmpty);
      expect(h.backend.calls('/chat_usage'), isEmpty, reason: 'demo kimliğiyle kota sorgusu atılmaz');
      expect(h.backend.calls('/chat/history'), isEmpty);
      expect(h.backend.calls('/today/plan'), isEmpty);
    });

    testWidgets('Kayıt ol: kayıt kipinde girişi açar; girişten sonra gidilecek yer sekmeli sohbettir', (tester) async {
      final h = await pumpApp(tester, location: '/rebi', loggedIn: false);
      await tapFinder(tester, _signUp);

      expect(_at(h).path, '/auth');
      expect(_at(h).queryParameters['mode'], 'signup');
      expect(_at(h).queryParameters['next'], '/dashboard/chat');
      expect(find.text(tr('auth.createAccount')), findsOneWidget);
      expect(find.text(tr('auth.fullName')), findsOneWidget);
    });

    testWidgets('Giriş yap: giriş kipini açar', (tester) async {
      final h = await pumpApp(tester, location: '/rebi', loggedIn: false);
      await tapFinder(tester, _signIn);

      expect(_at(h).path, '/auth');
      expect(_at(h).queryParameters['mode'], isNull);
      expect(_at(h).queryParameters['next'], '/dashboard/chat');
      expect(find.text(tr('auth.welcome')), findsOneWidget);
      expect(find.text(tr('auth.fullName')), findsNothing);
    });

    testWidgets('girişten geri dönünce kullanıcı davette kalır (karşılamaya atılmaz)', (tester) async {
      final h = await pumpApp(tester, location: '/rebi', loggedIn: false);
      await tapFinder(tester, _signIn);
      expect(_at(h).path, '/auth');

      await tester.tap(find.byIcon(LucideIcons.chevronLeft));
      await settle(tester, 8);
      expect(_at(h).path, '/rebi');
      expect(find.byType(ChatGate), findsOneWidget);
      expect(find.text(tr('mobileChat.gate.title')), findsOneWidget);
    });

    testWidgets('Android geri tuşu girişi kapatıp davete döner', (tester) async {
      final h = await pumpApp(tester, location: '/rebi', loggedIn: false);
      await tapFinder(tester, _signUp);
      expect(_at(h).path, '/auth');

      await tester.binding.handlePopRoute();
      await settle(tester, 8);
      expect(_at(h).path, '/rebi');
      expect(find.byType(ChatGate), findsOneWidget);
    });

    testWidgets('geri düğmesi karşılamaya döner; karşılamadan girişe gidilirse geri yine karşılamadır', (tester) async {
      final h = await pumpApp(tester, location: '/rebi', loggedIn: false);
      await tester.tap(find.byIcon(LucideIcons.chevronLeft));
      await settle(tester, 8);
      expect(_at(h).path, '/');

      await tapText(tester, tr('auth.login'));
      expect(_at(h).path, '/auth');
      await tester.tap(find.byIcon(LucideIcons.chevronLeft));
      await settle(tester, 8);
      expect(_at(h).path, '/', reason: 'altında sohbet yok: önceki davranış korunur');
    });

    testWidgets('davetten girişe, girişten sekmeli sohbete: giriş başarılı olunca yazı alanı gelir', (tester) async {
      final fake = _FakeAuth();
      final h = await pumpApp(tester, location: '/rebi', loggedIn: false, authController: fake);
      await tapFinder(tester, _signIn);

      await tester.enterText(find.byType(TextFormField).at(0), 'ayse@ornek.com');
      await tester.enterText(find.byType(TextFormField).at(1), 'parola123');
      await settle(tester, 4);
      await tapFinder(tester, find.byKey(const Key('auth-submit')).first);
      await settle(tester, 8);

      expect(_at(h).path, '/dashboard/chat');
      expect(find.byType(ChatGate), findsNothing);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text(tr('chat.emptyTitle')), findsOneWidget);
    });

    testWidgets('oturum başka yoldan açılırsa (ör. e-posta bağlantısı) davet yerini sohbete bırakır', (tester) async {
      final h = await pumpApp(tester, location: '/rebi', loggedIn: false);
      expect(find.byType(TextField), findsNothing);

      h.auth.debugSetUser(fakeUser());
      await settle(tester, 6);
      expect(find.byType(ChatGate), findsNothing);
      expect(find.byType(TextField), findsOneWidget);
      expect(h.backend.calls('/chat_usage'), isNotEmpty, reason: 'oturum gelince sohbetin kotası yüklenir');
    });
  });

  group('yapay zekâ beyanı', () {
    testWidgets('davetin üstüne binmez; oturum açılınca sohbette ilk kez gösterilir', (tester) async {
      final h = await pumpApp(tester, location: '/rebi', loggedIn: false, acknowledgeAi: false);
      expect(find.text(tr('common.aiDisclaimerTitle')), findsNothing, reason: 'davette yapay zekâ kullanılmıyor');
      expect(_signUp, findsOneWidget);

      h.auth.debugSetUser(fakeUser());
      await settle(tester, 6);
      expect(find.text(tr('common.aiDisclaimerTitle')), findsOneWidget, reason: 'sohbet açıldı: beyan şimdi gösterilir');
    });
  });

  group('oturumluyken sohbet değişmez', () {
    testWidgets('/rebi oturumluda de eski sohbettir: yazı alanı var, davet yok, mesaj kullanıcının kimliğiyle gider', (tester) async {
      final h = await pumpApp(tester, location: '/rebi');
      expect(find.byType(ChatGate), findsNothing);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text(tr('chat.emptyTitle')), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Selam');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await settle(tester);
      expect(h.backend.bodyOf('/chat_general')['user_id'], testUserId);
    });

    testWidgets('/dashboard/chat: davet yok, geri düğmesi yok', (tester) async {
      await pumpApp(tester, location: '/dashboard/chat');
      expect(find.byType(ChatGate), findsNothing);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byIcon(LucideIcons.chevronLeft), findsNothing);
    });

    testWidgets('/dashboard/chat oturumsuzken girişe, girişten sonra sohbete yönlendirilir (korumalı rota)', (tester) async {
      final h = await pumpApp(tester, location: '/dashboard/chat', loggedIn: false);
      expect(_at(h).path, '/auth');
      expect(_at(h).queryParameters['next'], '/dashboard/chat');
    });
  });

  group('sahne ve yerleşim', () {
    testWidgets('uzun ekranda sahne yükselir ve başlığı taşır', (tester) async {
      await pumpApp(tester, location: '/rebi', loggedIn: false);
      final tall = tester.widget<ChatStage>(find.byType(ChatStage));
      expect(tall.expanded, isTrue);
      expect(tall.introducing, isTrue);
      expect(tall.heroLift, greaterThan(0));
      expect(find.text(tr('mobileChat.gate.title')), findsOneWidget);
    });

    testWidgets('320×568: sahne ince, başlık gövdenin başında tam bir kez; iki eylem de görünür ve en az 48 dp', (tester) async {
      await pumpApp(tester, location: '/rebi', loggedIn: false, size: const Size(320, 568));
      final stage = tester.widget<ChatStage>(find.byType(ChatStage));
      expect(stage.expanded, isFalse);
      expect(stage.heroLift, 0);
      expect(find.text(tr('mobileChat.gate.title')), findsOneWidget);
      for (final f in [_signUp, _signIn]) {
        expect(f, findsOneWidget);
        final box = tester.getRect(f);
        expect(box.height, greaterThanOrEqualTo(48));
        expect(box.left, greaterThanOrEqualTo(0));
        expect(box.right, lessThanOrEqualTo(320));
        expect(box.bottom, lessThanOrEqualTo(568));
      }
      expect(tester.takeException(), isNull);
    });

    for (final lang in ['tr', 'en']) {
      for (final dark in [false, true]) {
        testWidgets('%200 yazıda 320×640 taşmaz; eylemler ekran içinde kalır ($lang, ${dark ? 'koyu' : 'açık'})', (tester) async {
          Tw.dark = dark;
          addTearDown(() => Tw.dark = false);
          await pumpApp(tester, location: '/rebi', loggedIn: false, size: const Size(320, 640), lang: lang);
          // Ölçek, açılıştaki karşılama karesi çizildikten sonra büyütülür (denetlenen şey davettir).
          tester.platformDispatcher.textScaleFactorTestValue = 2.0;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await settle(tester, 6);
          expect(tester.takeException(), isNull);
          expect(find.text(tr('mobileChat.gate.hello')), findsOneWidget);
          expect(_signUp, findsOneWidget);
          expect(_signIn, findsOneWidget);
          expect(tester.getRect(_signIn).bottom, lessThanOrEqualTo(640), reason: 'eylemler ekran dışına itilmez');
          expect(tester.getRect(_signUp).top, greaterThanOrEqualTo(0));
        });
      }
    }

    testWidgets('"animasyonları azalt" açıkken tüm içerik ilk karede görünür (belirme animasyonu oynamaz)', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await pumpApp(tester, location: '/rebi', loggedIn: false, settleAfter: false);
      await tester.pump();
      await tester.pump();
      expect(find.text(tr('mobileChat.gate.why')), findsOneWidget);
      for (final o in tester.widgetList<Opacity>(find.ancestor(of: _signUp, matching: find.byType(Opacity)))) {
        expect(o.opacity, 1, reason: 'belirme animasyonu oynamaz');
      }
    });

    testWidgets('animasyon açıkken mesajlar sırayla, eylemler en son belirir', (tester) async {
      await pumpApp(tester, location: '/rebi', loggedIn: false, settleAfter: false);
      await tester.pump();
      await tester.pump();
      double opacityOf(Finder f) => tester.widgetList<Opacity>(find.ancestor(of: f, matching: find.byType(Opacity))).map((o) => o.opacity).reduce((a, b) => a < b ? a : b);
      expect(opacityOf(find.text(tr('mobileChat.gate.hello'))), lessThan(1));
      await settle(tester, 6);
      expect(opacityOf(find.text(tr('mobileChat.gate.hello'))), 1, reason: 'ilk mesaj yerleşti');
      expect(opacityOf(_signUp), lessThan(1), reason: 'eylemler mesajlardan sonra gelir');
      await settle(tester, 8);
      expect(opacityOf(_signUp), 1);
    });
  });
}
