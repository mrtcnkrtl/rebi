import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/core/api.dart';
import 'package:rebi/core/demo_user.dart';
import 'package:rebi/core/event_outbox.dart';
import 'package:rebi/core/local_store.dart';
import 'package:rebi/core/privacy_storage.dart';
import 'package:rebi/core/notification_prefs.dart';
import 'package:rebi/core/today_plan.dart';
import 'package:rebi/state/auth_controller.dart';
import 'package:rebi/state/notifications_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/app_harness.dart';
import 'helpers/notification_fakes.dart';

TodayPlan planWith(List<Map<String, dynamic>> reminders) => TodayPlan.fromJson({
      'log_date': '2026-10-10',
      'weather': {'uv_index': 7, 'humidity': 40, 'temperature': 24},
      'weather_source': 'live',
      'reminders': reminders,
    });

Map<String, dynamic> rem(String id, String title, String start, String end, {int? every}) =>
    {'id': id, 'title': title, 'body': 'Gövde', 'start': start, 'end': end, 'every_minutes': every, 'log_event': null};

Future<void> flush() => Future<void>.delayed(const Duration(milliseconds: 30));

void main() {
  late FakeBackend backend;
  late AuthController auth;
  late FakeReminderNotifier notifier;
  late FakePushClient push;
  NotificationsController? controller;

  final now = DateTime(2026, 10, 10, 15, 30);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalStore.init();
    loadTestI18n('tr');
    backend = FakeBackend();
    apiHttpClient = backend.client;
    auth = AuthController()..debugSetUser(fakeUser());
    notifier = FakeReminderNotifier();
    push = FakePushClient(available: false);
  });

  tearDown(() {
    controller?.dispose();
    controller = null;
    auth.dispose();
  });

  NotificationsController make({FakePushClient? pushClient}) => controller = NotificationsController(
        auth,
        notifier: notifier,
        push: pushClient ?? push,
        appVersion: () async => '1.2.3',
        platform: () => 'android',
        clock: () => now,
      );

  group('öneri ve tercih', () {
    test('seçim yapılmamış kullanıcıya öneri görünür; reddedince bir daha çıkmaz', () async {
      final c = make();
      expect(c.promptVisible, isTrue);
      expect(c.enabled, isFalse);
      await c.dismissPrompt();
      expect(c.promptVisible, isFalse);
      expect(notificationsEnabledFor(testUserId), isNull, reason: '"şimdi değil" bir seçim sayılmaz');
    });

    test('desteklenmeyen platformda öneri yoktur, açma denenmez', () async {
      notifier.supported = false;
      final c = make();
      expect(c.promptVisible, isFalse);
      expect(await c.enable(), isFalse);
      expect(notifier.permissionRequests, 0);
    });

    test('oturum yoksa ve demo kullanıcıda öneri yoktur', () async {
      auth.debugSetUser(null);
      expect(make().promptVisible, isFalse);
      auth.debugSetUser(fakeUser(id: demoUserId));
      expect(controller!.promptVisible, isFalse);
      expect(await controller!.enable(), isFalse);
    });
  });

  group('açma', () {
    test('izin verilirse tercih kaydedilir ve bugünün kalan hatırlatmaları kurulur', () async {
      final c = make();
      c.syncReminders(planWith([rem('routine_evening', 'Akşam rutini', '21:00', '23:00')]));
      await flush();
      expect(notifier.replaced, isEmpty, reason: 'açılmadan hiçbir şey kurulmaz');

      expect(await c.enable(), isTrue);
      expect(c.enabled, isTrue);
      expect(c.permissionBlocked, isFalse);
      expect(c.promptVisible, isFalse);
      expect(notificationsEnabledFor(testUserId), isTrue);
      expect(notifier.permissionRequests, 1);

      final today = notifier.scheduled.where((n) => n.at.day == 10).toList();
      expect(today.map((n) => n.reminderId), ['routine_evening']);
      expect(today.single.title, 'Akşam rutini', reason: 'Türkçede sunucu metni');
      expect(today.single.at, DateTime(2026, 10, 10, 21));
      expect(notifier.scheduled.where((n) => n.at.day == 11), isNotEmpty, reason: 'yarının koşulsuz hatırlatıcıları');
    });

    test('izin reddedilirse hiçbir şey kurulmaz, kayıt yapılmaz ve öneri susar', () async {
      notifier.grantOnRequest = false;
      notifier.permission = false;
      final c = make(pushClient: FakePushClient());
      c.syncReminders(planWith([rem('routine_evening', 'Akşam rutini', '21:00', '23:00')]));

      expect(await c.enable(), isFalse);
      expect(c.enabled, isFalse);
      expect(c.permissionBlocked, isTrue);
      expect(c.promptVisible, isFalse);
      expect(notifier.replaced, isEmpty);
      expect(backend.calls('/devices/register'), isEmpty);
    });

    test('İngilizcede hatırlatıcılar çevrilir, yarınınki yerel çeviriden gelir', () async {
      loadTestI18n('en');
      final c = make();
      c.syncReminders(planWith([
        {...rem('spf_refresh', 'Güneş kremini yenile', '17:00', '17:00'), 'body': 'UV 7. Dışarıdaysan…'},
      ]));
      await c.enable();
      final today = notifier.scheduled.firstWhere((n) => n.at.day == 10);
      expect(today.title, 'Reapply sunscreen');
      expect(today.body, "UV 7. If you're outside, reapply every 2 hours.");
      final tomorrow = notifier.scheduled.firstWhere((n) => n.reminderId == 'routine_evening');
      expect(tomorrow.title, 'Evening routine');
    });

    test('Türkçede yarının bildirimleri Türkçe yerel metinle kurulur', () async {
      final c = make();
      await c.enable();
      c.syncReminders(planWith(const []));
      await flush();
      final water = notifier.scheduled.firstWhere((n) => n.reminderId == 'water_intake' && n.at.day == 11);
      expect(water.title, 'Su içme zamanı');
      expect(water.body, contains('2000'));
    });
  });

  group('zamanlama', () {
    test('aynı plan ikinci kez kurulmaz, değişen plan yeniden kurulur', () async {
      final c = make();
      await c.enable();
      final plan = planWith([rem('routine_evening', 'Akşam rutini', '21:00', '23:00')]);
      c.syncReminders(plan);
      await flush();
      final calls = notifier.replaced.length;

      c.syncReminders(plan);
      c.syncReminders(planWith([rem('routine_evening', 'Akşam rutini', '21:00', '23:00')]));
      await flush();
      expect(notifier.replaced.length, calls, reason: 'aynı içerik: yeniden kurma yok');

      c.syncReminders(planWith(const []));
      await flush();
      expect(notifier.replaced.length, calls + 1, reason: 'yapılan iş listeden düşünce bildirim de kalkar');
      expect(notifier.scheduled.where((n) => n.at.day == 10), isEmpty);
    });

    test('kullanıcı izni işletim sisteminden geri aldıysa kurulmaz ve uyarı çıkar', () async {
      final c = make();
      await c.enable();
      final before = notifier.replaced.length;
      notifier.permission = false;
      c.syncReminders(planWith([rem('routine_evening', 'Akşam rutini', '21:00', '23:00')]));
      await flush();
      expect(notifier.replaced.length, before);
      expect(c.permissionBlocked, isTrue);
    });

    test('kapatınca bekleyen bildirimler silinir ve sunucuya bildirilir', () async {
      final c = make(pushClient: FakePushClient());
      await c.enable();
      c.syncReminders(planWith([rem('routine_evening', 'Akşam rutini', '21:00', '23:00')]));
      await flush();
      expect(notifier.scheduled, isNotEmpty);

      await c.disable();
      expect(c.enabled, isFalse);
      expect(notificationsEnabledFor(testUserId), isFalse);
      expect(notifier.scheduled, isEmpty);
      expect(backend.bodyOf('/devices/register')['push_enabled'], isFalse);

      c.syncReminders(planWith([rem('routine_evening', 'Akşam rutini', '21:00', '23:00')]));
      await flush();
      expect(notifier.scheduled, isEmpty, reason: 'kapalıyken plan değişse de kurulmaz');
    });

    test('çıkış yapınca yerel bildirimler silinir (sonraki hesaba sızmaz)', () async {
      final c = make();
      await c.enable();
      c.syncReminders(planWith([rem('routine_evening', 'Akşam rutini', '21:00', '23:00')]));
      await flush();
      expect(notifier.scheduled, isNotEmpty);

      auth.debugSetUser(null);
      await flush();
      expect(notifier.scheduled, isEmpty);
    });
  });

  group('sunucu push\'u', () {
    test('cihaz sözleşmedeki alanlarla kaydedilir', () async {
      final c = make(pushClient: FakePushClient(pushToken: 'abc'));
      await c.enable();
      final body = backend.bodyOf('/devices/register');
      expect(body['user_id'], testUserId);
      expect(body['token'], 'abc');
      expect(body['platform'], 'android');
      expect(body['utc_offset_minutes'], now.timeZoneOffset.inMinutes);
      expect(body['locale'], 'tr');
      expect(body['app_version'], '1.2.3');
      expect(body['push_enabled'], isTrue);
      expect(body['actions_supported'], isFalse);
    });

    test('düğmeleri işleyebilen push istemcisi bunu kayıtta bildirir', () async {
      final c = make(pushClient: FakePushClient(handlesNotificationActions: true));
      await c.enable();
      expect(backend.bodyOf('/devices/register')['actions_supported'], isTrue);
    });

    test('sunucuda FCM açıksa yerel bildirim kurulmaz (çift bildirim olmaz)', () async {
      backend.pushConfigured = true;
      final c = make(pushClient: FakePushClient());
      c.syncReminders(planWith([rem('routine_evening', 'Akşam rutini', '21:00', '23:00')]));
      await c.enable();
      await flush();
      expect(c.pushActive, isTrue);
      expect(notifier.scheduled, isEmpty);
    });

    test('sunucuda FCM kapalıysa yerel bildirim devreye girer', () async {
      backend.pushConfigured = false;
      final c = make(pushClient: FakePushClient());
      c.syncReminders(planWith([rem('routine_evening', 'Akşam rutini', '21:00', '23:00')]));
      await c.enable();
      await flush();
      expect(c.pushActive, isFalse);
      expect(notifier.scheduled.where((n) => n.at.day == 10), isNotEmpty);
    });

    test('Firebase yoksa kayıt isteği atılmaz, yalnızca yerel bildirim çalışır', () async {
      final c = make();
      c.syncReminders(planWith(const []));
      await c.enable();
      expect(backend.calls('/devices/register'), isEmpty);
      expect(notifier.scheduled, isNotEmpty, reason: 'en azından yarının koşulsuz hatırlatıcıları kurulur');
    });

    test('uygulama her açılışta cihazı yeniden kaydeder (seçim yapılmışsa)', () async {
      await setNotificationsEnabled(testUserId, true);
      make(pushClient: FakePushClient());
      await flush();
      expect(backend.calls('/devices/register'), hasLength(1));
    });

    test('hiç seçim yapılmamışsa cihaz kaydedilmez', () async {
      make(pushClient: FakePushClient());
      await flush();
      expect(backend.calls('/devices/register'), isEmpty);
    });

    test('anahtar yenilenince yeni anahtarla yeniden kaydolur', () async {
      await setNotificationsEnabled(testUserId, true);
      final p = FakePushClient(pushToken: 'eski');
      make(pushClient: p);
      await flush();
      p.refreshToken('yeni');
      await flush();
      final tokens = [for (final r in backend.calls('/devices/register')) (jsonDecode(r.body) as Map)['token']];
      expect(tokens, ['eski', 'yeni']);
    });

    test('çıkıştan önce cihaz sunucudan kaldırılır', () async {
      final c = make(pushClient: FakePushClient(pushToken: 'abc'));
      await c.enable();
      await c.prepareSignOut();
      final del = backend.calls('/devices/register').last;
      expect(del.method, 'DELETE');
      expect(del.url.queryParameters, {'user_id': testUserId, 'token': 'abc'});
      expect(notifier.scheduled, isEmpty);
    });

    test('ağ yokken çıkış hazırlığı hata fırlatmaz', () async {
      final c = make(pushClient: FakePushClient());
      await c.enable();
      backend.devicesOffline = true;
      await expectLater(c.prepareSignOut(), completes);
    });
  });

  group('bildirime dokunma', () {
    test('uygulama açıkken dokunulan yerel bildirim ekranı açar', () async {
      final c = make();
      notifier.tap('/dashboard/checkin');
      await flush();
      expect(c.openRoute.value, '/dashboard/checkin');
    });

    test('uygulama bildirimle açıldıysa ilk ekran o bildirimin ekranıdır', () async {
      notifier.launch = '/dashboard/checkin';
      final c = make();
      await flush();
      expect(c.openRoute.value, '/dashboard/checkin');
    });

    test('sunucu bildirimine dokunma da aynı yolu kullanır', () async {
      final p = FakePushClient();
      final c = make(pushClient: p);
      p.open('/dashboard');
      await flush();
      expect(c.openRoute.value, '/dashboard');

      final p2 = FakePushClient()..initial = '/dashboard/checkin';
      controller!.dispose();
      final c2 = make(pushClient: p2);
      await flush();
      expect(c2.openRoute.value, '/dashboard/checkin');
    });

    test('normal açılışta yönlendirme yoktur', () async {
      final c = make();
      await flush();
      expect(c.openRoute.value, isNull);
    });
  });

  group('veri temizliği', () {
    test('hesap verisi silinince bildirim tercihleri ve bekleyen kayıtlar da silinir', () async {
      await setNotificationsEnabled(testUserId, true);
      await dismissNotificationPrompt(testUserId);
      await EventOutbox.instance.add(OutboxEvent(
        id: 'a',
        userId: testUserId,
        type: 'water_intake',
        payload: const {'ml': 250},
        timestamp: '2026-10-10T09:00:00+03:00',
        queuedAt: DateTime.now().millisecondsSinceEpoch,
      ));
      expect(EventOutbox.instance.pendingCount(testUserId), 1);

      await clearUserLocalData(testUserId);

      expect(notificationsEnabledFor(testUserId), isNull);
      expect(notificationPromptDismissed(testUserId), isFalse);
      expect(EventOutbox.instance.pendingCount(testUserId), 0);
      EventOutbox.instance.debugReset();
      expect(EventOutbox.instance.pendingCount(testUserId), 0, reason: 'diskten de silindi');
    });
  });
}
