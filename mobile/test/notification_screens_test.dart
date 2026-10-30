import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rebi/core/api.dart';
import 'package:rebi/core/i18n.dart';
import 'package:rebi/core/local_store.dart';
import 'package:rebi/core/notification_ports.dart';
import 'package:rebi/core/notification_prefs.dart';
import 'package:rebi/core/routine_tracking.dart';
import 'package:rebi/state/auth_controller.dart';
import 'package:rebi/state/notifications_controller.dart';
import 'package:rebi/state/theme_controller.dart';
import 'package:rebi/ui/components/notification_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/app_harness.dart';
import 'helpers/notification_fakes.dart';

/// Bildirim önerisi (panel), profil anahtarı ve oturum kapatma. Sözleşme: `docs/MOBIL-API.md` → "Bildirimler".
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

  group('panel önerisi', () {
    testWidgets('seçim yapılmamışsa öneri çıkar; "bildirimleri aç" izin ister, kurar ve kartı kaldırır', (tester) async {
      final notifier = FakeReminderNotifier();
      final h = await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs(), notifier: notifier);
      expect(find.text(tr('mobileNotifications.promptTitle')), findsOneWidget);

      await tapText(tester, tr('mobileNotifications.promptEnable'));
      await settle(tester);

      expect(notifier.permissionRequests, 1);
      expect(h.notifications.enabled, isTrue);
      expect(notificationsEnabledFor(testUserId), isTrue);
      expect(find.text(tr('mobileNotifications.promptTitle')), findsNothing);
      expect(notifier.scheduled, isNotEmpty, reason: 'bugünün planı yüklenmişti: hatırlatmalar hemen kurulur');
      expect(notifier.scheduled.any((n) => n.reminderId == 'routine_morning' && n.title == 'Sabah rutini'), isTrue);
    });

    testWidgets('"şimdi değil" kartı kaldırır, izin istemez ve kararı hatırlar', (tester) async {
      final notifier = FakeReminderNotifier();
      await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs(), notifier: notifier);
      await tapText(tester, tr('mobileNotifications.promptLater'));
      expect(find.text(tr('mobileNotifications.promptTitle')), findsNothing);
      expect(notifier.permissionRequests, 0);
      expect(notifier.replaced, isEmpty);
      expect(notificationPromptDismissed(testUserId), isTrue);
    });

    testWidgets('daha önce "şimdi değil" denmişse öneri yeniden çıkmaz', (tester) async {
      final h = await pumpApp(
        tester,
        location: '/dashboard',
        prefs: {...acceptedPrefs(), 'rebi_notifications_prompt_dismissed_v1_$testUserId': '1'},
        notifier: FakeReminderNotifier(),
      );
      expect(find.text(tr('mobileNotifications.promptTitle')), findsNothing);
      expect(h.notifications.enabled, isFalse);
    });

    testWidgets('izin reddedilirse kart kalkar ve hiçbir bildirim kurulmaz', (tester) async {
      final notifier = FakeReminderNotifier()
        ..grantOnRequest = false
        ..permission = false;
      final h = await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs(), notifier: notifier);
      await tapText(tester, tr('mobileNotifications.promptEnable'));
      await settle(tester);
      expect(find.text(tr('mobileNotifications.promptTitle')), findsNothing);
      expect(h.notifications.permissionBlocked, isTrue);
      expect(notifier.replaced, isEmpty);
      expect(notificationsEnabledFor(testUserId), isNull);
    });

    testWidgets('bildirim desteklenmeyen platformda öneri hiç çıkmaz', (tester) async {
      await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs());
      expect(find.text(tr('mobileNotifications.promptTitle')), findsNothing);
    });

    testWidgets('önceden açılmışsa öneri çıkmaz ve açılışta hatırlatmalar kurulur', (tester) async {
      final notifier = FakeReminderNotifier();
      await pumpApp(
        tester,
        location: '/dashboard',
        prefs: {...acceptedPrefs(), 'rebi_notifications_enabled_v1_$testUserId': '1'},
        notifier: notifier,
      );
      await settle(tester);
      expect(find.text(tr('mobileNotifications.promptTitle')), findsNothing);
      expect(notifier.scheduled, isNotEmpty);
    });

    testWidgets('İngilizce arayüzde öneri çevrilir', (tester) async {
      await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs(), notifier: FakeReminderNotifier(), lang: 'en');
      expect(find.text('Get reminders as notifications'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('öneri 320 genişlikte taşmaz', (tester) async {
      await pumpApp(
        tester,
        location: '/dashboard',
        prefs: acceptedPrefs(),
        notifier: FakeReminderNotifier(),
        size: const Size(320, 568),
      );
      expect(find.text(tr('mobileNotifications.promptTitle')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // Profil ekranı Supabase olmadan açılmadığı için kart tek başına çizilir.
  group('profil anahtarı', () {
    Future<NotificationsController> pumpCard(
      WidgetTester tester, {
      required FakeReminderNotifier notifier,
      Map<String, Object> prefs = const {},
      PushClient push = const NoPushClient(),
      FakeBackend? backend,
      Size size = const Size(390, 844),
    }) async {
      tester.view.physicalSize = size * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues(prefs);
      await tester.runAsync(LocalStore.init);
      loadTestI18n('tr');
      apiHttpClient = (backend ?? FakeBackend()).client;
      final auth = AuthController()..debugSetUser(fakeUser());
      addTearDown(auth.dispose);
      final theme = ThemeController(auth);
      final controller = NotificationsController(auth, notifier: notifier, push: push, platform: () => 'android');
      addTearDown(controller.dispose);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<I18n>.value(value: I18n.instance),
          ChangeNotifierProvider<NotificationsController>.value(value: controller),
        ],
        child: MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: NotificationSettingsCard(theme: theme.theme))),
        ),
      ));
      await settle(tester);
      return controller;
    }

    Switch theSwitch(WidgetTester tester) => tester.widget<Switch>(find.byType(Switch));

    testWidgets('anahtar kapalı başlar; açınca izin ister, tercih kalıcı olur', (tester) async {
      final notifier = FakeReminderNotifier();
      final c = await pumpCard(tester, notifier: notifier);
      expect(find.text(tr('mobileNotifications.title')), findsOneWidget);
      expect(theSwitch(tester).value, isFalse);

      await tester.tap(find.byType(Switch));
      await settle(tester);

      expect(notifier.permissionRequests, 1);
      expect(c.enabled, isTrue);
      expect(notificationsEnabledFor(testUserId), isTrue);
      expect(theSwitch(tester).value, isTrue);
      expect(find.text(tr('mobileNotifications.modeLocal')), findsOneWidget);
    });

    testWidgets('kapatınca bekleyen bildirimler silinir', (tester) async {
      final notifier = FakeReminderNotifier();
      final c = await pumpCard(
        tester,
        notifier: notifier,
        prefs: {'rebi_notifications_enabled_v1_$testUserId': '1'},
      );
      expect(theSwitch(tester).value, isTrue);
      final cancels = notifier.cancelCalls;

      await tester.tap(find.byType(Switch));
      await settle(tester);

      expect(c.enabled, isFalse);
      expect(notificationsEnabledFor(testUserId), isFalse);
      expect(notifier.cancelCalls, greaterThan(cancels));
      expect(theSwitch(tester).value, isFalse);
      expect(find.text(tr('mobileNotifications.modeLocal')), findsNothing);
    });

    testWidgets('izin işletim sisteminde kapalıysa yönlendirme metni görünür ve anahtar açılmaz', (tester) async {
      final notifier = FakeReminderNotifier()
        ..grantOnRequest = false
        ..permission = false;
      await pumpCard(tester, notifier: notifier);
      await tester.tap(find.byType(Switch));
      await settle(tester);
      expect(find.text(tr('mobileNotifications.blocked')), findsOneWidget);
      expect(theSwitch(tester).value, isFalse);
      expect(notificationsEnabledFor(testUserId), isNull);
    });

    testWidgets('sunucu push gönderiyorsa "sunucudan gönderilir" yazar', (tester) async {
      final backend = FakeBackend()..pushConfigured = true;
      await pumpCard(
        tester,
        notifier: FakeReminderNotifier(),
        prefs: {'rebi_notifications_enabled_v1_$testUserId': '1'},
        push: FakePushClient(),
        backend: backend,
      );
      await settle(tester);
      expect(find.text(tr('mobileNotifications.modePush')), findsOneWidget);
    });

    testWidgets('bildirim desteklenmiyorsa kart hiç gösterilmez', (tester) async {
      await pumpCard(tester, notifier: FakeReminderNotifier(supported: false));
      expect(find.byType(Switch), findsNothing);
      expect(find.text(tr('mobileNotifications.title')), findsNothing);
    });

    testWidgets('kart 320 genişlikte taşmaz', (tester) async {
      await pumpCard(
        tester,
        notifier: FakeReminderNotifier()
          ..grantOnRequest = false
          ..permission = false,
        size: const Size(320, 568),
      );
      await tester.tap(find.byType(Switch));
      await settle(tester);
      expect(find.text(tr('mobileNotifications.blocked')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('oturum kapatma', () {
    testWidgets('çıkışta cihaz sunucudan kaldırılır ve yerel bildirimler silinir', (tester) async {
      final notifier = FakeReminderNotifier();
      final h = await pumpApp(
        tester,
        location: '/dashboard',
        prefs: {...acceptedPrefs(), 'rebi_notifications_enabled_v1_$testUserId': '1'},
        notifier: notifier,
        push: FakePushClient(pushToken: 'abc'),
      );
      await settle(tester);
      expect(notifier.scheduled, isNotEmpty);

      await tapText(tester, tr('mobileNav.me'));
      await tapText(tester, tr('mobileMe.logout'));
      await tapText(tester, tr('mobileMe.logoutConfirm.confirm'));
      await settle(tester);

      final delete = h.backend.calls('/devices/register').where((r) => r.method == 'DELETE');
      expect(delete, hasLength(1));
      expect(delete.single.url.queryParameters, {'user_id': testUserId, 'token': 'abc'});
      expect(notifier.scheduled, isEmpty);
    });
  });
}
