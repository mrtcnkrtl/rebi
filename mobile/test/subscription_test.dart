import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:rebi/core/ads.dart';
import 'package:rebi/core/subscription.dart';
import 'package:rebi/state/auth_controller.dart';
import 'package:rebi/state/store_controller.dart';
import 'package:rebi/ui/components/ad_banner.dart';

import 'helpers/app_harness.dart';

Map<String, dynamic> storeMeta(String tier, {DateTime? expires}) => {
      'rebi_store': {
        'tier': tier,
        'expires_at_ms': (expires ?? DateTime.now().add(const Duration(days: 20))).millisecondsSinceEpoch,
      },
    };

StorePlan plan(String tier, {bool yearly = false, required String price}) {
  final id = 'rebi_${tier}_${yearly ? 'yearly' : 'monthly'}';
  return StorePlan(
    tier: tier,
    yearly: yearly,
    package: Package(
      '${tier}_${yearly ? 'yearly' : 'monthly'}',
      yearly ? PackageType.annual : PackageType.monthly,
      StoreProduct(id, '', tier, 0, price, 'TRY'),
      const PresentedOfferingContext('default', null, null),
    ),
  );
}

final allPlans = [
  plan('plus', price: '₺99,99'),
  plan('plus', yearly: true, price: '₺899,99'),
  plan('pro', price: '₺149,99'),
  plan('pro', yearly: true, price: '₺1.299,99'),
  plan('max', price: '₺199,99'),
  plan('max', yearly: true, price: '₺1.799,99'),
];

Future<void> ask(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.testTextInput.receiveAction(TextInputAction.send);
  await settle(tester);
}

void main() {
  tearDown(() {
    storePurchasesOverride = null;
    plusPurchasableOverride = null;
    Ads.enabledOverride = null;
  });

  group('mağaza kademesi', () {
    test('süresi geçmemiş kademe etkin; süre + 10 dk tolerans sonrası değil', () {
      final now = DateTime(2026, 11, 15, 12);
      expect(activeStoreTier(fakeUser(appMetadata: storeMeta('pro', expires: now.add(const Duration(hours: 1)))), now: now), 'pro');
      expect(activeStoreTier(fakeUser(appMetadata: storeMeta('pro', expires: now.subtract(const Duration(minutes: 5)))), now: now), 'pro');
      expect(activeStoreTier(fakeUser(appMetadata: storeMeta('pro', expires: now.subtract(const Duration(hours: 1)))), now: now), isNull);
      expect(activeStoreTier(fakeUser(appMetadata: {'rebi_store': {'tier': 'gold'}})), isNull);
      expect(activeStoreTier(fakeUser()), isNull);
    });

    test('mağaza kademesi Plus haklarını ve reklamsız kullanımı açar', () {
      expect(userHasRebiPlus(fakeUser(appMetadata: storeMeta('plus'))), isTrue);
      expect(userIsAdFree(fakeUser(appMetadata: storeMeta('plus'))), isTrue);
      expect(userIsAdFree(fakeUser(appMetadata: {'subscription_tier': 'plus'})), isTrue, reason: 'elle verilmiş Plus');
      expect(userIsAdFree(fakeUser()), isFalse);
      final expired = storeMeta('max', expires: DateTime.now().subtract(const Duration(days: 2)));
      expect(userHasRebiPlus(fakeUser(appMetadata: expired)), isFalse);
    });

    test('paket kimliğinden kademe ve dönem çıkarılır', () {
      expect(classifyPackage('pro_yearly', 'rebi_pro_yearly'), ('pro', true));
      expect(classifyPackage(r'$rc_monthly', 'rebi_max_monthly', type: PackageType.monthly), ('max', false));
      expect(classifyPackage(r'$rc_annual', 'com.rebiovil.plus.1y', type: PackageType.annual), ('plus', true));
      expect(classifyPackage('premium', 'rebi_premium'), isNull, reason: 'pro ≠ premium; bilinmeyen paket atlanır');
    });

    test('dönem sonunda oturum tazelenir: bitişten 90 sn sonra, sonra tolerans dolmadan bir kez daha', () {
      final exp = DateTime(2026, 12, 1, 9);
      final user = fakeUser(appMetadata: storeMeta('pro', expires: exp));
      expect(storeExpiry(user), exp);
      expect(nextEntitlementCheck(user, exp.subtract(const Duration(days: 3))), exp.add(const Duration(seconds: 90)));
      expect(nextEntitlementCheck(user, exp.add(const Duration(minutes: 2))), exp.add(const Duration(minutes: 8)),
          reason: 'webhook gecikti: tolerans (10 dk) bitmeden yeniden bak');
      expect(nextEntitlementCheck(user, exp.add(const Duration(minutes: 9))), isNull, reason: 'süre çoktan doldu');
      // Yenilenen süre token'a gelince bir sonraki dönemin sonuna kurulur.
      final renewed = fakeUser(appMetadata: storeMeta('pro', expires: exp.add(const Duration(days: 30))));
      expect(nextEntitlementCheck(renewed, exp.add(const Duration(minutes: 2))), exp.add(const Duration(days: 30, seconds: 90)));
    });

    test('süresiz ya da mağaza aboneliği olmayan hesapta bakılacak an yok', () {
      expect(nextEntitlementCheck(fakeUser(), DateTime.now()), isNull);
      expect(nextEntitlementCheck(fakeUser(appMetadata: {'rebi_store': {'tier': 'max', 'expires_at_ms': null}}), DateTime.now()), isNull);
      expect(nextEntitlementCheck(fakeUser(appMetadata: {'subscription_tier': 'plus'}), DateTime.now()), isNull);
      expect(nextEntitlementCheck(null, DateTime.now()), isNull);
    });

    test('mağaza anahtarı yoksa satın alma kapalı; anahtar varsa Plus girişi görünür', () {
      expect(storePurchasesEnabled, isFalse);
      expect(plusPurchasable, isFalse);
      storePurchasesOverride = true;
      expect(plusPurchasable, isTrue);
    });
  });

  group('abonelik sayfası', () {
    Future<void> open(WidgetTester tester, {Map<String, dynamic> meta = const {}, String lang = 'tr'}) async {
      storePurchasesOverride = true;
      final auth = AuthController()..debugSetUser(fakeUser(appMetadata: meta));
      await pumpApp(
        tester,
        location: '/dashboard/subscribe',
        authController: auth,
        user: fakeUser(appMetadata: meta),
        storeController: StoreController.preview(auth, allPlans),
        lang: lang,
      );
    }

    testWidgets('üç paket günlük hakları ve aylık fiyatlarıyla; varsayılan seçim orta paket', (tester) async {
      await open(tester);
      expect(find.text('Günde 50 soru'), findsOneWidget);
      expect(find.text('Günde 80 soru'), findsOneWidget);
      expect(find.text('Günde 120 soru'), findsOneWidget);
      expect(find.textContaining('₺149,99'), findsOneWidget);
      expect(find.textContaining('₺1.299,99'), findsNothing, reason: 'yıllık fiyatlar sekme değişince');
      expect(find.text('Pro ile devam et'), findsOneWidget);
      expect(find.text(tr('mobileSubscribe.store.restore')), findsOneWidget);
      expect(find.text(tr('mobileSubscribe.store.renewNoteAndroid')), findsOneWidget);
      expect(find.text(tr('mobileSubscribe.benefits.adFree.title')), findsOneWidget);

      await tapText(tester, tr('mobileSubscribe.store.yearly'));
      expect(find.textContaining('₺1.299,99'), findsOneWidget);
      await tapText(tester, 'Max');
      expect(find.text('Max ile devam et'), findsOneWidget);
    });

    testWidgets('abone: mevcut paket işaretli, üst pakete geçiş önerilir', (tester) async {
      await open(tester, meta: storeMeta('plus'));
      expect(find.text('Plus aktif'), findsOneWidget);
      expect(find.text(tr('mobileSubscribe.store.current')), findsWidgets);
      expect(find.text('Pro paketine geç'), findsOneWidget);
      expect(find.text(tr('mobileSubscribe.store.manage')), findsOneWidget);
    });

    testWidgets('320 px ve %200 yazıda taşmaz', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      storePurchasesOverride = true;
      final auth = AuthController()..debugSetUser(fakeUser());
      await pumpApp(
        tester,
        location: '/dashboard/subscribe',
        authController: auth,
        storeController: StoreController.preview(auth, allPlans),
        size: const Size(320, 640),
        lang: 'en',
      );
      expect(tester.takeException()?.toString(), isNull);
    });
  });

  group('sohbet: ücretli günlük hak', () {
    testWidgets('hak dolunca "yarın yenilenir" + üst pakete geçiş', (tester) async {
      storePurchasesOverride = true;
      final backend = FakeBackend()
        ..quotaAfter = 0
        ..usageKind = 'plan_daily';
      await pumpApp(tester, location: '/dashboard/chat', backend: backend, user: fakeUser(appMetadata: storeMeta('plus')));
      await ask(tester, 'Merhaba');
      expect(find.text(tr('mobileChat.limit.titlePlan')), findsOneWidget);
      expect(find.text(tr('mobileChat.limit.bodyPlan')), findsOneWidget);
      expect(find.text(tr('mobileChat.limit.upgrade')), findsWidgets);
    });

    testWidgets('en üst pakette satış yok, yalnızca bilgi', (tester) async {
      storePurchasesOverride = true;
      final backend = FakeBackend()
        ..quotaAfter = 0
        ..usageKind = 'plan_daily';
      await pumpApp(tester, location: '/dashboard/chat', backend: backend, user: fakeUser(appMetadata: storeMeta('max')));
      await ask(tester, 'Merhaba');
      expect(find.text(tr('mobileChat.limit.titlePlan')), findsOneWidget);
      expect(find.text(tr('mobileChat.limit.bodyPlanTop')), findsOneWidget);
      expect(find.text(tr('mobileChat.limit.upgrade')), findsNothing);
    });
  });

  group('reklam', () {
    testWidgets('reklam kapalı derlemede banner yer kaplamaz', (tester) async {
      await pumpApp(tester, location: '/dashboard/history');
      expect(find.byType(AdBanner), findsOneWidget);
      expect(find.text(tr('mobileAds.label')), findsNothing);
    });
  });
}
