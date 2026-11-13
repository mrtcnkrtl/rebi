import 'package:flutter_test/flutter_test.dart';

import 'helpers/app_harness.dart';

/// Giriş / kayıt düzeni: sabit alt şerit ve katlanan isteğe bağlı izinler.
void main() {
  group('giriş ve kayıt düzeni', () {
    testWidgets('alt şerit (giriş↔kayıt bağlantısı ve güven notu) sabit durur, klavye açılınca yer açmak için gizlenir', (tester) async {
      await pumpApp(tester, location: '/auth', loggedIn: false);
      expect(find.text(tr('auth.haveNoAccount')), findsOneWidget);
      expect(find.text(tr('mobileAuth.trust')), findsOneWidget);

      // Cihaz oranı 3: 300 mantıksal piksellik klavye.
      tester.view.viewInsets = const FakeViewPadding(bottom: 900);
      addTearDown(tester.view.resetViewInsets);
      await settle(tester, 6);
      expect(find.text(tr('auth.haveNoAccount')), findsNothing);
      expect(find.text(tr('mobileAuth.trust')), findsNothing);

      tester.view.resetViewInsets();
      await settle(tester, 6);
      expect(find.text(tr('auth.haveNoAccount')), findsOneWidget);
    });

    testWidgets('kayıt kipinde de alt şerit "Zaten hesabın var mı?" bağlantısını gösterir ve girişe döner', (tester) async {
      await pumpApp(tester, location: '/auth?mode=signup', loggedIn: false);
      expect(find.text(tr('auth.createAccount')), findsOneWidget);
      await tapText(tester, tr('auth.login'));
      expect(find.text(tr('auth.welcome')), findsOneWidget);
    });
  });
}
