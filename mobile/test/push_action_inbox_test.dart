import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/core/api.dart';
import 'package:rebi/core/event_outbox.dart';
import 'package:rebi/core/local_store.dart';
import 'package:rebi/core/notification_prefs.dart';
import 'package:rebi/core/push_action_inbox.dart';
import 'package:rebi/state/auth_controller.dart';
import 'package:rebi/state/notifications_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/app_harness.dart';
import 'helpers/notification_fakes.dart';

Future<void> flush() => Future<void>.delayed(const Duration(milliseconds: 30));

/// `ios/Runner/AppDelegate.swift` → `PushActionInbox.record` ile aynı biçim.
Future<void> swiftRecorded(List<Map<String, String>> taps) =>
    LocalStore.instance.setString(pendingPushActionsKey, jsonEncode(taps));

Map<String, String> waterTap({String userId = testUserId}) => {
      'reminder_id': 'water_intake',
      'action_id': 'water_intake:water500',
      'user_id': userId,
      'day': '2026-10-28',
    };

void main() {
  late FakeBackend backend;
  late AuthController auth;
  NotificationsController? controller;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalStore.init();
    loadTestI18n('tr');
    EventOutbox.instance.debugReset();
    backend = FakeBackend();
    apiHttpClient = backend.client;
    auth = AuthController()..debugSetUser(fakeUser());
  });

  tearDown(() {
    controller?.dispose();
    controller = null;
    auth.dispose();
  });

  NotificationsController make({bool handlesActions = true}) => controller = NotificationsController(
        auth,
        notifier: FakeReminderNotifier(),
        push: FakePushClient(handlesNotificationActions: handlesActions),
        appVersion: () async => '1.2.3',
        platform: () => 'ios',
        clock: () => DateTime(2026, 10, 28, 13, 5),
      );

  group('takePendingPushActions', () {
    test('Swift kaydını okur ve siler', () async {
      await swiftRecorded([waterTap()]);

      final taps = await takePendingPushActions();

      expect([for (final t in taps) (t.reminderId, t.actionId, t.userId)],
          [('water_intake', 'water_intake:water500', testUserId)]);
      expect(await takePendingPushActions(), isEmpty);
    });

    test('bozuk kayıt ve eksik satırlar atlanır', () async {
      await LocalStore.instance.setString(pendingPushActionsKey, '{bozuk');
      expect(await takePendingPushActions(), isEmpty);

      await swiftRecorded([
        {'reminder_id': 'water_intake', 'action_id': ''},
        waterTap(),
      ]);
      expect(await takePendingPushActions(), hasLength(1));
    });
  });

  group('denetleyici', () {
    test('oturum açılınca bekleyen dokunuş sunucuya kaydedilir', () async {
      await swiftRecorded([waterTap()]);

      make();
      await flush();

      final body = backend.bodyOf('/daily_tracking/ingest');
      expect(body['type'], 'water_intake');
      expect(body['payload'], {'ml': 500});
      expect(LocalStore.instance.getString(pendingPushActionsKey), isNull);
    });

    test('uygulama öne gelince yeni dokunuş kaydedilir', () async {
      await setNotificationsEnabled(testUserId, true);
      final c = make();
      await flush();
      await swiftRecorded([waterTap()]);

      await c.onAppResumed();
      await flush();

      expect(backend.calls('/daily_tracking/ingest'), hasLength(1));
    });

    test('başka hesabın bildiriminden gelen dokunuş kaydedilmez', () async {
      await swiftRecorded([waterTap(userId: 'baska-kullanici')]);

      make();
      await flush();

      expect(backend.calls('/daily_tracking/ingest'), isEmpty);
    });

    test('düğmeleri işlemeyen push istemcisinde kayıt okunmaz', () async {
      await swiftRecorded([waterTap()]);

      make(handlesActions: false);
      await flush();

      expect(backend.calls('/daily_tracking/ingest'), isEmpty);
      expect(LocalStore.instance.getString(pendingPushActionsKey), isNotNull);
    });
  });
}
