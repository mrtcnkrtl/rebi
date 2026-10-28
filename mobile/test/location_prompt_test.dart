import 'dart:convert';

import 'package:flutter/material.dart' show Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/core/demo_user.dart';
import 'package:rebi/core/device_location.dart';
import 'package:rebi/core/local_store.dart';
import 'package:rebi/core/location_prefs.dart';
import 'package:rebi/core/notification_prefs.dart';
import 'package:rebi/core/privacy_storage.dart';
import 'package:rebi/core/routine_tracking.dart';
import 'package:rebi/state/location_prompt_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/app_harness.dart';
import 'helpers/notification_fakes.dart';

/// Faz F4: ilk açılışta izin sırası. Konum önerisi (gizlilik onayı varsa, telefon izni sorulmadıysa) bildirim önerisinden
/// önce gelir; ikisi aynı anda gösterilmez; izin penceresi yalnızca kullanıcı "Konumu aç" deyince açılır.
void main() {
  final routine = routineFixture['routine'] as List;

  Map<String, Object> acceptedPrefs() => {
        trackAcceptedKey(testUserId): '1',
        trackSnapshotKey(testUserId): jsonEncode({
          'routine': routine,
          'userName': 'Ayşe Test',
          'weather': routineFixture['weather'],
          'flowDebug': routineFixture['flow_debug'],
          'acceptedAt': DateTime.now().millisecondsSinceEpoch - 3 * 86400000,
        }),
      };

  FakeBackend consenting({bool location = true}) {
    final b = FakeBackend();
    b.snapshot = {
      ...b.snapshot,
      'consent': {...(b.snapshot['consent'] as Map).cast<String, dynamic>(), 'location_processing_allowed': location},
    };
    return b;
  }

  var requests = 0;
  LocationAccess nextRequestResult = LocationAccess.granted;

  setUp(() {
    requests = 0;
    nextRequestResult = LocationAccess.granted;
    setLocationAccess(
      read: () async => LocationAccess.askable,
      request: () async {
        requests++;
        return nextRequestResult;
      },
    );
  });

  tearDown(resetLocationAccess);

  group('LocationPromptController', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await LocalStore.init();
    });

    Future<LocationPromptController> make({bool consent = true, String user = 'u1', Future<void> Function()? onGranted}) async {
      final c = LocationPromptController(userId: user, consentAllowed: consent, onGranted: onGranted);
      await c.refresh();
      return c;
    }

    test('onay var, izin sorulmamış, öneri kapatılmamış: görünür', () async {
      final c = await make();
      expect(c.visible, isTrue);
      c.dispose();
    });

    test('gizlilik onayında konum yoksa öneri çıkmaz (izin penceresi de açılmaz)', () async {
      final c = await make(consent: false);
      expect(c.visible, isFalse);
      expect(requests, 0);
      c.dispose();
    });

    test('demo kullanıcıya önerilmez', () async {
      final c = await make(user: demoUserId);
      expect(c.visible, isFalse);
      c.dispose();
    });

    for (final access in [LocationAccess.granted, LocationAccess.blocked, LocationAccess.off]) {
      test('izin durumu $access ise öneri çıkmaz', () async {
        setLocationAccess(read: () async => access);
        final c = await make();
        expect(c.visible, isFalse);
        c.dispose();
      });
    }

    test('"Şimdi değil" öneriyi kalıcı kapatır; başka kullanıcıyı etkilemez', () async {
      final c = await make();
      await c.dismiss();
      expect(c.visible, isFalse);
      expect(locationPromptDismissed('u1'), isTrue);
      c.dispose();

      final again = await make();
      expect(again.visible, isFalse, reason: 'bir sonraki açılışta da çıkmaz');
      again.dispose();
      final other = await make(user: 'u2');
      expect(other.visible, isTrue);
      other.dispose();
    });

    test('"Konumu aç": izin penceresi açılır, öneri kapanır ve verilirse plan konumla yenilenir', () async {
      var reloaded = 0;
      final c = await make(onGranted: () async => reloaded++);
      expect(requests, 0, reason: 'uygulama açılırken izin sorulmadı');

      final result = await c.allow();

      expect(result, LocationAccess.granted);
      expect(requests, 1);
      expect(reloaded, 1);
      expect(c.visible, isFalse);
      expect(locationPromptDismissed('u1'), isTrue);
      c.dispose();
    });

    test('izin reddedilirse plan yenilenmez ama öneri bir daha çıkmaz', () async {
      nextRequestResult = LocationAccess.blocked;
      var reloaded = 0;
      final c = await make(onGranted: () async => reloaded++);
      await c.allow();
      expect(reloaded, 0);
      expect(c.visible, isFalse);
      expect(locationPromptDismissed('u1'), isTrue);
      c.dispose();
    });

    test('hesap verisi temizlenince konum tercihi de silinir', () async {
      await dismissLocationPrompt('u1');
      await clearUserLocalData('u1');
      expect(locationPromptDismissed('u1'), isFalse);
    });
  });

  group('Bugün ekranında ilk açılış', () {
    testWidgets('önce konum önerisi çıkar, bildirim önerisi onun arkasında bekler', (tester) async {
      final notifier = FakeReminderNotifier();
      await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs(), backend: consenting(), notifier: notifier);

      expect(find.text(tr('mobileLocation.promptTitle')), findsOneWidget);
      expect(find.text(tr('mobileNotifications.promptTitle')), findsNothing, reason: 'tek seferde tek öneri');
      expect(requests, 0);
    });

    testWidgets('"Konumu aç" izin penceresini açar, planı konumla yeniler ve ardından bildirim önerisi gelir', (tester) async {
      deviceLocationLookup = () async => (lat: 41.01, lon: 28.97);
      addTearDown(resetDeviceLocationLookup);
      final h = await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs(), backend: consenting(), notifier: FakeReminderNotifier());
      final plansBefore = h.backend.calls('/today/plan').length;

      await tapText(tester, tr('mobileLocation.promptEnable'));
      await settle(tester);

      expect(requests, 1);
      expect(find.text(tr('mobileLocation.promptTitle')), findsNothing);
      final plans = h.backend.calls('/today/plan');
      expect(plans.length, greaterThan(plansBefore), reason: 'plan yeniden okundu');
      expect(plans.last.url.queryParameters['lat'], '41.01');
      expect(plans.last.url.queryParameters['lon'], '28.97');
      expect(find.text(tr('mobileNotifications.promptTitle')), findsOneWidget, reason: 'konum kararı verildi, sıra bildirimde');
    });

    testWidgets('"Şimdi değil" konum önerisini kapatır ve bildirim önerisine geçer', (tester) async {
      await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs(), backend: consenting(), notifier: FakeReminderNotifier());
      await tapText(tester, tr('mobileLocation.promptLater'));

      expect(requests, 0);
      expect(find.text(tr('mobileLocation.promptTitle')), findsNothing);
      expect(find.text(tr('mobileNotifications.promptTitle')), findsOneWidget);
      expect(notificationsEnabledFor(testUserId), isNull);
    });

    testWidgets('gizlilik onayında konum yoksa doğrudan bildirim önerisi', (tester) async {
      await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs(), backend: consenting(location: false), notifier: FakeReminderNotifier());
      expect(find.text(tr('mobileLocation.promptTitle')), findsNothing);
      expect(find.text(tr('mobileNotifications.promptTitle')), findsOneWidget);
    });

    testWidgets('İngilizce arayüzde öneri çevrilir; 320 px ve %200 yazıda taşmaz', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpApp(
        tester,
        location: '/dashboard',
        prefs: acceptedPrefs(),
        backend: consenting(),
        notifier: FakeReminderNotifier(),
        lang: 'en',
        size: const Size(320, 640),
      );
      expect(find.text('Show the weather for where you are'), findsOneWidget);
      expect(tester.takeException()?.toString(), isNull);
    });
  });
}
