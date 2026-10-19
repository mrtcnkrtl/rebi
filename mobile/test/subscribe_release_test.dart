import 'package:flutter_test/flutter_test.dart';

import 'helpers/app_harness.dart';

/// Mağaza incelemecisi ve kullanıcı abonelik ekranında geliştirici notu görmemeli.
void main() {
  group('abonelik ekranı (ödeme bağlantısı tanımsız)', () {
    testWidgets('kullanıcıya nötr bilgi gösterir, altyapı notu göstermez', (tester) async {
      await pumpApp(tester, location: '/dashboard/subscribe');
      expect(find.text(tr('mobileSubscribe.unavailable')), findsOneWidget);
      for (final dev in ['Stripe', 'iyzico', 'Ödeme URL', 'ortam değişkeni', 'Şimdilik ödeme altyapısı']) {
        expect(find.textContaining(dev), findsNothing, reason: '"$dev" geliştiriciye ait metin');
      }
    });

    testWidgets('İngilizce arayüzde de nötr bilgi', (tester) async {
      await pumpApp(tester, location: '/dashboard/subscribe', lang: 'en');
      expect(find.textContaining("can't be purchased in the app"), findsOneWidget);
      expect(find.textContaining('Stripe'), findsNothing);
    });

    testWidgets('Plus hesapta durum gösterilir', (tester) async {
      await pumpApp(tester, location: '/dashboard/subscribe', user: fakeUser(appMetadata: {'subscription_tier': 'plus'}));
      expect(find.text(tr('mobileSubscribe.active')), findsOneWidget);
    });
  });
}
