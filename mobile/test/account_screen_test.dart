import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/screens/profile_screen.dart';

import 'helpers/app_harness.dart';
import 'helpers/notification_fakes.dart';

/// Hesap ve gizlilik ekranı (`/dashboard/account`): her bölüm kendi durumunu taşıyan ayrı kart. Supabase olmadan açılabilmesi için
/// `debugAccountAvailable` açılır; ad/şifre/fotoğraf Supabase isteyen eylemleri burada denenmez, doğrulama ve hesap silme akışı denenir.
void main() {
  setUp(() => debugAccountAvailable = true);
  tearDown(() => debugAccountAvailable = null);

  Future<void> reveal(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await settle(tester, 3);
  }

  group('düzen', () {
    testWidgets('bölümler sırayla çizilir; hesabı sil en sondadır', (tester) async {
      await pumpApp(tester, location: '/dashboard/account', size: const Size(390, 4200));

      final titles = [
        tr('profile.accountSummary'),
        tr('mobileAccount.name.title'),
        tr('mobileAccount.password.title'),
        tr('mobileAccount.privacy.title'),
        tr('profile.photosTitle'),
        tr('mobileAccount.delete.title'),
      ];
      var lastY = -1.0;
      for (final t in titles) {
        final f = find.text(t);
        expect(f, findsOneWidget, reason: t);
        final y = tester.getTopLeft(f).dy;
        expect(y, greaterThan(lastY), reason: '"$t" önceki bölümün altında olmalı');
        lastY = y;
      }
      expect(find.text(tr('mobileNav.back')), findsOneWidget, reason: 'sahnede tek Geri');
    });

    testWidgets('e-posta ve üyelik tarihi özet kartındadır', (tester) async {
      await pumpApp(tester, location: '/dashboard/account', size: const Size(390, 4200));
      expect(find.text('test@rebi.app'), findsOneWidget);
      expect(find.textContaining(tr('profile.membership', {'date': ''}).trim()), findsOneWidget);
    });

    testWidgets('Supabase yoksa ekran okunur bir bilgi gösterir (sahnesiz yedek)', (tester) async {
      debugAccountAvailable = false;
      await pumpApp(tester, location: '/dashboard/account');
      expect(find.text(tr('mobileAccount.unavailable')), findsOneWidget);
    });

    testWidgets('İngilizce arayüzde Türkçe sabit metin kalmaz', (tester) async {
      await pumpApp(tester, location: '/dashboard/account', size: const Size(390, 4200), lang: 'en');
      for (final en in ['Change password', 'Privacy permissions', 'Permanently delete account', 'Display name']) {
        expect(find.text(en), findsOneWidget, reason: en);
      }
      for (final tr in ['Şifre değiştir', 'Gizlilik izinleri', 'Hesabı kalıcı olarak sil', 'Görünen ad']) {
        expect(find.text(tr), findsNothing, reason: tr);
      }
    });
  });

  group('şifre', () {
    testWidgets('kısa şifre ve uyuşmayan tekrar nedenini söyler', (tester) async {
      await pumpApp(tester, location: '/dashboard/account', size: const Size(390, 4200));
      final pwd = find.widgetWithText(TextField, tr('mobileAccount.password.hint'));
      final again = find.widgetWithText(TextField, tr('mobileAccount.password.confirm'));
      await reveal(tester, pwd);

      await tester.enterText(pwd, 'abc');
      await settle(tester, 2);
      await tapText(tester, tr('mobileAccount.password.update'));
      expect(find.text(tr('mobileAccount.password.tooShort')), findsOneWidget);

      await tester.enterText(pwd, 'abcdef');
      await tester.enterText(again, 'abcdeX');
      await tapText(tester, tr('mobileAccount.password.update'));
      expect(find.text(tr('mobileAccount.password.mismatch')), findsOneWidget);
    });

    testWidgets('şifre alanı boşken güncelle düğmesi kapalıdır', (tester) async {
      await pumpApp(tester, location: '/dashboard/account', size: const Size(390, 4200));
      await reveal(tester, find.text(tr('mobileAccount.password.update')));
      await tapText(tester, tr('mobileAccount.password.update'));
      expect(find.text(tr('mobileAccount.password.tooShort')), findsNothing);
    });
  });

  group('hesabı sil', () {
    testWidgets('onay ifadesi yazılmadan istek gitmez', (tester) async {
      final h = await pumpApp(tester, location: '/dashboard/account', size: const Size(390, 4200));
      await reveal(tester, find.text(tr('mobileAccount.delete.button')));

      await tester.tap(find.text(tr('mobileAccount.delete.button')));
      await settle(tester, 3);
      expect(h.backend.calls('/account/delete'), isEmpty);

      await tester.enterText(find.widgetWithText(TextField, accountDeletePhrase), 'YANLIS');
      await settle(tester, 2);
      await tester.tap(find.text(tr('mobileAccount.delete.button')));
      await settle(tester, 3);
      expect(h.backend.calls('/account/delete'), isEmpty, reason: 'ifade aynen yazılmadı');
    });

    testWidgets('doğru ifadeyle sunucuya gider; planlı bildirimler silinir ve karşılamaya dönülür', (tester) async {
      final notifier = FakeReminderNotifier(supported: false);
      final h = await pumpApp(tester, location: '/dashboard/account', size: const Size(390, 4200), notifier: notifier);
      await reveal(tester, find.text(tr('mobileAccount.delete.button')));

      await tester.enterText(find.widgetWithText(TextField, accountDeletePhrase), accountDeletePhrase);
      await settle(tester, 2);
      final cancelsBefore = notifier.cancelCalls;
      await tester.tap(find.text(tr('mobileAccount.delete.button')));
      await settle(tester, 12);

      final body = h.backend.bodyOf('/account/delete');
      expect(body['user_id'], testUserId);
      expect(body['confirm_text'], accountDeletePhrase);
      expect(notifier.cancelCalls, greaterThan(cancelsBefore), reason: 'silinen hesabın hatırlatıcıları çalmaya devam etmez');
      expect(h.router.routeInformationProvider.value.uri.path, '/');
    });

    testWidgets('sunucu reddederse ekranda kalır ve nedeni gösterir', (tester) async {
      final backend = FakeBackend()..accountDeleteStatus = 500;
      final h = await pumpApp(tester, location: '/dashboard/account', size: const Size(390, 4200), backend: backend);
      await reveal(tester, find.text(tr('mobileAccount.delete.button')));

      await tester.enterText(find.widgetWithText(TextField, accountDeletePhrase), accountDeletePhrase);
      await settle(tester, 2);
      await tester.tap(find.text(tr('mobileAccount.delete.button')));
      await settle(tester, 12);

      expect(find.text('Hesap silinemedi (sunucu)'), findsOneWidget);
      expect(h.router.routeInformationProvider.value.uri.path, '/dashboard/account');
      expect(h.auth.user, isNotNull, reason: 'oturum açık kalır');
    });
  });
}
