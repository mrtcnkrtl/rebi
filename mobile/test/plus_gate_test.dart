import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/core/subscription.dart';

import 'helpers/app_harness.dart';

/// v1 mağaza sürümü: Plus satın alınamıyor (ödeme bağlantısı / IAP yok). Hiçbir ekranda "Plus'a geç"
/// çağrısı çıkmamalı; elle Plus verilmiş hesaplar çalışmaya devam etmeli.
void main() {
  final plusUser = {'subscription_tier': 'plus'};

  group('anahtar', () {
    test('varsayılan: ödeme bağlantısı tanımsız → satın alma yok', () {
      expect(plusPurchasable, isFalse);
    });

    test('geçersiz kılma testte açıp kapatır', () {
      plusPurchasableOverride = true;
      expect(plusPurchasable, isTrue);
      plusPurchasableOverride = false;
      expect(plusPurchasable, isFalse);
      plusPurchasableOverride = null;
    });

    testWidgets('Plus girişi: satın alma varsa ya da hesap Plus ise görünür', (tester) async {
      addTearDown(() => plusPurchasableOverride = null);
      expect(plusEntryVisible(fakeUser()), isFalse);
      expect(plusEntryVisible(fakeUser(appMetadata: plusUser)), isTrue);
      expect(plusEntryVisible(null), isFalse);
      plusPurchasableOverride = true;
      expect(plusEntryVisible(fakeUser()), isTrue);
      expect(plusEntryVisible(null), isTrue);
    });
  });

  group('Plus satın alınamıyor', () {
    testWidgets('Ben sekmesi: ücretsiz hesapta Plus satırı yok', (tester) async {
      await pumpApp(tester, location: '/dashboard/profile');
      expect(find.text(tr('mobileMe.plus.title')), findsNothing);
      expect(find.text(tr('mobileMe.plus.hint')), findsNothing);
      expect(find.text(tr('mobileMe.logout')), findsOneWidget, reason: 'diğer satırlar yerinde');
    });

    testWidgets('Ben sekmesi: Plus hesapta satır ve etkin mesajı kalır', (tester) async {
      await pumpApp(tester, location: '/dashboard/profile', user: fakeUser(appMetadata: plusUser));
      expect(find.text(tr('mobileMe.plus.title')), findsOneWidget);
      expect(find.text(tr('mobileMe.plus.active')), findsOneWidget);
    });

    testWidgets('temalar: premium temalar ücretsiz hesapta listelenmez, abonelik bağlantısı yok', (tester) async {
      await pumpApp(tester, location: '/dashboard/themes');
      expect(find.text('Pudra'), findsOneWidget, reason: 'ücretsiz tema');
      expect(find.text('Gün Batımı'), findsNothing, reason: 'premium tema');
      expect(find.text('abonelik sayfası'), findsNothing);
    });

    testWidgets('temalar: Plus hesapta premium temalar seçilir', (tester) async {
      final h = await pumpApp(tester, location: '/dashboard/themes', user: fakeUser(appMetadata: plusUser));
      await tapText(tester, 'Gün Batımı');
      expect(h.theme.themeId, 'sunset');
    });

    testWidgets('sohbet: kota dolunca yalnızca limit bilgisi çıkar, Plus tanıtımı ve düğmeleri yok', (tester) async {
      final backend = FakeBackend()..quotaAfter = 0;
      await pumpApp(tester, location: '/dashboard/chat', backend: backend);
      await tester.enterText(find.byType(TextField), 'Merhaba');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await settle(tester);

      expect(find.text(tr('mobileChat.limit.titleDay')), findsOneWidget);
      expect(find.text(tr('mobileChat.limit.bodyDay')), findsOneWidget);
      expect(find.text(tr('chat.paywallTitleDay')), findsNothing);
      expect(find.text('REBI PLUS'), findsNothing);
      expect(find.text('Plus ile'), findsNothing);
      expect(find.text('Rebi Plus’ı aç'), findsNothing);
      expect(find.text('Plus’a geç'), findsNothing);

      await tapText(tester, tr('mobileChat.limit.close'));
      expect(find.text(tr('mobileChat.limit.titleDay')), findsNothing);
    });

    testWidgets('sohbet: sayaç altında "Rebi Plus" bağlantısı yok', (tester) async {
      await pumpApp(tester, location: '/dashboard/chat');
      expect(find.text(tr('chat.plusUpgradeLink')), findsNothing);
      expect(find.text(tr('chat.footerHintShort')), findsOneWidget);
    });

    testWidgets('açılış sayfasında Plus tanıtımı yok', (tester) async {
      await pumpApp(tester, location: '/', loggedIn: false);
      expect(find.text(tr('landing.plus.unlimitedAiTitle')), findsNothing);
      expect(find.text(tr('landing.plus.premiumThemesTitle')), findsNothing);
    });

    testWidgets('320 px ve büyük yazıda limit paneli taşmaz', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final backend = FakeBackend()..quotaAfter = 0;
      await pumpApp(tester, location: '/dashboard/chat', backend: backend, size: const Size(320, 640));
      await tester.enterText(find.byType(TextField), 'Merhaba');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await settle(tester);
      expect(find.text(tr('mobileChat.limit.titleDay')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Plus satın alınabiliyor (ileride IAP / ödeme bağlantısı)', () {
    testWidgets('Ben sekmesi ve tema bağlantısı geri gelir', (tester) async {
      withPlusPurchasable();
      await pumpApp(tester, location: '/dashboard/profile');
      expect(find.text(tr('mobileMe.plus.title')), findsOneWidget);
    });

    testWidgets('premium temalar kilitli olarak listelenir', (tester) async {
      withPlusPurchasable();
      await pumpApp(tester, location: '/dashboard/themes');
      expect(find.text('Gün Batımı'), findsOneWidget);
      expect(find.text('abonelik sayfası'), findsOneWidget);
    });

    testWidgets('sohbet kotası dolunca Plus paneli çıkar', (tester) async {
      withPlusPurchasable();
      final backend = FakeBackend()..quotaAfter = 0;
      await pumpApp(tester, location: '/dashboard/chat', backend: backend);
      await tester.enterText(find.byType(TextField), 'Merhaba');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await settle(tester);
      expect(find.text(tr('chat.paywallTitleDay')), findsOneWidget);
      expect(find.text('Rebi Plus’ı aç'), findsOneWidget);
    });
  });
}
