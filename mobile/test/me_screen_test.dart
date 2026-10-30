import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/core/i18n.dart';
import 'package:rebi/ui/components/language_sheet.dart';

import 'helpers/app_harness.dart';

/// "Ben" sekmesi: çıkış yanlışlıkla dokunmaya karşı onay ister; dil seçimi satır + alt sayfadır.
void main() {
  group('çıkış', () {
    testWidgets('onay sayfası açılır; vazgeçince oturum ve ekran korunur', (tester) async {
      final h = await pumpApp(tester, location: '/dashboard/profile');
      await tapText(tester, tr('mobileMe.logout'));

      expect(find.text(tr('mobileMe.logoutConfirm.title')), findsOneWidget);
      expect(find.text(tr('mobileMe.logoutConfirm.body')), findsOneWidget);
      expect(h.auth.user, isNotNull, reason: 'onay verilmeden çıkış yapılmaz');

      await tapText(tester, tr('mobileMe.logoutConfirm.cancel'));
      expect(find.text(tr('mobileMe.logoutConfirm.title')), findsNothing);
      expect(h.auth.user, isNotNull);
      expect(h.router.routeInformationProvider.value.uri.path, '/dashboard/profile');
    });

    testWidgets('onaylanınca karşılamaya döner', (tester) async {
      final h = await pumpApp(tester, location: '/dashboard/profile');
      await tapText(tester, tr('mobileMe.logout'));
      await tapText(tester, tr('mobileMe.logoutConfirm.confirm'));
      await settle(tester);
      expect(h.router.routeInformationProvider.value.uri.path, '/');
    });

    testWidgets('İngilizce arayüzde onay sayfası İngilizce', (tester) async {
      await pumpApp(tester, location: '/dashboard/profile', lang: 'en');
      await tapText(tester, 'Sign out');
      expect(find.text('Sign out?'), findsOneWidget);
      expect(find.text('Yes, sign out'), findsOneWidget);
    });
  });

  group('dil', () {
    testWidgets('satır mevcut dili söyler; dokununca alt sayfa açılır ve dil değişir', (tester) async {
      await pumpApp(tester, location: '/dashboard/profile');
      expect(find.text(languageLabels['tr']!), findsOneWidget, reason: 'satırın açıklaması geçerli dil');

      await tapText(tester, tr('lang.label'));
      // Alt sayfada iki seçenek var; Türkçe yazı hem satırda hem sayfada görünür.
      expect(find.text(languageLabels['en']!), findsOneWidget);

      await tapText(tester, languageLabels['en']!);
      await settle(tester, 4);
      expect(I18n.instance.lang, 'en');
      expect(find.text('Sign out'), findsOneWidget, reason: 'ekran yeni dilde yeniden çizilir');
    });
  });
}
