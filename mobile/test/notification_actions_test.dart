import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/core/api.dart';
import 'package:rebi/core/daily_tracking.dart';
import 'package:rebi/core/demo_user.dart';
import 'package:rebi/core/event_outbox.dart';
import 'package:rebi/core/local_store.dart';
import 'package:rebi/core/notification_actions.dart';
import 'package:rebi/core/today_plan.dart';
import 'package:rebi/state/auth_controller.dart';
import 'package:rebi/state/notifications_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/app_harness.dart';
import 'helpers/notification_fakes.dart';

Future<void> flush() => Future<void>.delayed(const Duration(milliseconds: 30));

void main() {
  late FakeBackend backend;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalStore.init();
    loadTestI18n('tr');
    EventOutbox.instance.debugReset();
    backend = FakeBackend();
    apiHttpClient = backend.client;
  });

  group('NotificationPayload', () {
    test('ekran, hatırlatıcı ve kullanıcıyı taşır; geri okunur', () {
      const payload = NotificationPayload(route: '/dashboard/checkin', reminderId: 'daily_checkin', userId: 'u1');
      final back = NotificationPayload.decode(payload.encode())!;
      expect((back.route, back.reminderId, back.userId), ('/dashboard/checkin', 'daily_checkin', 'u1'));
    });

    test('eski biçim (yalnızca ekran yolu) hâlâ okunur', () {
      final back = NotificationPayload.decode('/dashboard')!;
      expect(back.route, '/dashboard');
      expect(back.reminderId, isEmpty);
    });

    test('bozuk ya da eksik yük null verir', () {
      expect(NotificationPayload.decode(null), isNull);
      expect(NotificationPayload.decode(''), isNull);
      expect(NotificationPayload.decode('{bozuk'), isNull);
      expect(NotificationPayload.decode('{"reminder_id": "x"}'), isNull, reason: 'ekran yolu yok');
      expect(NotificationPayload.decode('[1]'), isNull);
    });
  });

  group('bildirim düğmeleri', () {
    List<String> labels(String id) => [for (final a in notificationQuickActions(id)) a.labelKey];

    test('yalnızca olay kaydeden eylemler düğme olur', () {
      expect(labels('routine_morning'), ['done']);
      expect(labels('routine_evening'), ['done']);
      expect(labels('makeup_log'), ['yes', 'no']);
      expect(labels('water_intake'), ['water250', 'water500']);
      expect(labels('spf_refresh'), ['done']);
      expect(labels('nutrition_log'), ['junkNo'], reason: '"yedim" ne yendiğini sorar, bildirimden yanıtlanmaz');
    });

    test('ekran ya da seçim sayfası açan ve bilinmeyen hatırlatıcıların düğmesi yoktur', () {
      expect(labels('makeup_removal'), isEmpty);
      expect(labels('daily_checkin'), isEmpty);
      expect(labels('lip_balm'), isEmpty);
      expect(labels('bilinmeyen'), isEmpty);
    });

    test('her düğme bir olay tipi taşır ve kimliğinden geri bulunur', () {
      for (final id in const ['routine_morning', 'makeup_log', 'water_intake', 'spf_refresh', 'nutrition_log']) {
        for (final a in notificationQuickActions(id)) {
          final found = resolveNotificationAction(id, notificationActionId(id, a));
          expect(found, isNotNull, reason: id);
          expect(found?.type, a.type);
          expect(found?.payload, a.payload);
        }
      }
      expect(notificationActionId('water_intake', notificationQuickActions('water_intake').first), 'water_intake:water250');
    });

    test('başka hatırlatıcıya ait ya da uydurma kimlik çözülmez', () {
      expect(resolveNotificationAction('water_intake', 'water_intake:junkNo'), isNull);
      expect(resolveNotificationAction('water_intake', 'routine_morning:done'), isNull);
      expect(resolveNotificationAction('daily_checkin', 'daily_checkin:open'), isNull);
      expect(resolveNotificationAction('water_intake', ''), isNull);
    });
  });

  group('kuyruğa alma (uygulama kapalıyken düğme)', () {
    test('olayı gönderilmeden kuyruğa yazar; gerçek anıyla ve tekil kimlikle', () async {
      final queued = await queueNotificationAction(
        const NotificationActionTap(reminderId: 'water_intake', actionId: 'water_intake:water250', userId: testUserId),
      );

      expect(queued, isTrue);
      expect(backend.calls('/daily_tracking/ingest'), isEmpty, reason: 'arka planda oturum yok: gönderilmez');
      final pending = EventOutbox.instance.pending(testUserId).single;
      expect(pending.type, 'water_intake');
      expect(pending.payload, {'ml': 250});
      expect(pending.id, isNotEmpty);
      expect(pending.at, isNotNull);
      final stored = LocalStore.instance.getJson('rebi_event_outbox_v1_$testUserId') as List;
      expect(stored, hasLength(1), reason: 'cihaza kalıcı yazıldı');
    });

    test('bilinmeyen eylem, kullanıcısız yük ve demo kullanıcı kuyruğa girmez', () async {
      expect(
        await queueNotificationAction(
          const NotificationActionTap(reminderId: 'water_intake', actionId: 'uydurma', userId: testUserId),
        ),
        isFalse,
      );
      expect(
        await queueNotificationAction(
          const NotificationActionTap(reminderId: 'water_intake', actionId: 'water_intake:water250', userId: ''),
        ),
        isFalse,
      );
      expect(
        await queueNotificationAction(
          const NotificationActionTap(reminderId: 'water_intake', actionId: 'water_intake:water250', userId: demoUserId),
        ),
        isFalse,
      );
      expect(EventOutbox.instance.pendingCount(testUserId), 0);
    });

    test('başka izolatın yazdığı olay yeniden okunca görünür', () async {
      expect(EventOutbox.instance.pendingCount(testUserId), 0);
      // Ana izolatın önbelleği boşken, arka plan işi aynı depoya olay yazdı.
      await LocalStore.instance.setJson('rebi_event_outbox_v1_$testUserId', [
        {
          'id': 'arka-plan-1',
          'user_id': testUserId,
          'type': 'water_intake',
          'payload': {'ml': 500},
          'timestamp': localIsoTimestamp(),
          'queued_at': DateTime.now().millisecondsSinceEpoch,
          'attempts': 0,
        },
      ]);
      expect(EventOutbox.instance.pendingCount(testUserId), 0, reason: 'önbellek eski');

      await EventOutbox.instance.reload(testUserId);

      expect(EventOutbox.instance.pending(testUserId).single.id, 'arka-plan-1');
      expect(await EventOutbox.instance.flush(testUserId), 1);
      expect(backend.bodyOf('/daily_tracking/ingest')['client_event_id'], 'arka-plan-1');
    });
  });

  group('NotificationsController', () {
    late AuthController auth;
    late FakeReminderNotifier notifier;
    NotificationsController? controller;
    final now = DateTime(2026, 10, 10, 15, 30);

    TodayPlan plan(List<Map<String, dynamic>> reminders, {Map<String, dynamic>? settings}) => TodayPlan.fromJson({
          'log_date': '2026-10-10',
          'weather': {'uv_index': 7, 'humidity': 40, 'temperature': 24},
          'weather_source': 'live',
          'reminders': reminders,
          'reminder_settings': ?settings,
        });

    Map<String, dynamic> rem(String id, String title, String start, String end, {int? every}) =>
        {'id': id, 'title': title, 'body': 'Gövde', 'start': start, 'end': end, 'every_minutes': every, 'log_event': null};

    NotificationsController make() => controller = NotificationsController(
          auth,
          notifier: notifier,
          appVersion: () async => '1.0.0',
          platform: () => 'android',
          clock: () => now,
        );

    setUp(() {
      auth = AuthController()..debugSetUser(fakeUser());
      notifier = FakeReminderNotifier();
    });

    tearDown(() {
      controller?.dispose();
      controller = null;
      auth.dispose();
    });

    test('kurulan bildirimlerin altında kullanıcı diliyle eylem düğmeleri ve kullanıcı vardır', () async {
      final c = make();
      await c.enable();
      c.syncReminders(plan([rem('water_intake', 'Su içme zamanı', '17:00', '17:00')]));
      await flush();

      final water = notifier.scheduled.firstWhere((n) => n.reminderId == 'water_intake' && n.at.day == 10);
      expect(water.userId, testUserId);
      expect([for (final a in water.actions) (a.id, a.label)], [
        ('water_intake:water250', '+250 ml'),
        ('water_intake:water500', '+500 ml'),
      ]);
      final checkin = notifier.scheduled.firstWhere((n) => n.reminderId == 'daily_checkin');
      expect(checkin.actions, isEmpty, reason: 'check-in bildirimden yanıtlanmaz, ekranı açar');
    });

    test('İngilizcede düğme etiketleri İngilizce', () async {
      loadTestI18n('en');
      final c = make();
      await c.enable();
      c.syncReminders(plan([rem('routine_evening', 'Akşam rutini', '21:00', '21:00')]));
      await flush();
      final evening = notifier.scheduled.firstWhere((n) => n.reminderId == 'routine_evening' && n.at.day == 10);
      expect(evening.actions.single.label, 'Done');
    });

    test('planın gün düzeni yarının bildirimlerini kaydırır', () async {
      final c = make();
      await c.enable();
      c.syncReminders(plan(const [], settings: {'wake_time': '06:00', 'sleep_time': '22:00'}));
      await flush();
      final morning = notifier.scheduled.firstWhere((n) => n.reminderId == 'routine_morning' && n.at.day == 11);
      expect(morning.at, DateTime(2026, 10, 11, 6));
      final evening = notifier.scheduled.firstWhere((n) => n.reminderId == 'routine_evening' && n.at.day == 11);
      expect(evening.at, DateTime(2026, 10, 11, 20));
    });

    test('uygulama açıkken düğmeye dokunulunca olay gönderilir', () async {
      make();
      notifier.tapAction(
        const NotificationActionTap(reminderId: 'water_intake', actionId: 'water_intake:water500', userId: testUserId),
      );
      await flush();

      final body = backend.bodyOf('/daily_tracking/ingest');
      expect(body['type'], 'water_intake');
      expect(body['payload'], {'ml': 500});
      expect(body['user_id'], testUserId);
      expect(body['source'], 'mobile');
      expect(body['client_event_id'], isNotEmpty);
    });

    test('sunucuya ulaşılamazsa olay kuyruğa alınır', () async {
      backend.ingestOffline = true;
      make();
      notifier.tapAction(
        const NotificationActionTap(reminderId: 'routine_morning', actionId: 'routine_morning:done', userId: testUserId),
      );
      await flush();

      final pending = EventOutbox.instance.pending(testUserId).single;
      expect(pending.type, 'routine_completed_block');
      expect(pending.payload, {'morning': true});
    });

    test('başka hesap için kurulmuş bildirimin, bilinmeyen ve ekran açan eylemlerin düğmesi yok sayılır', () async {
      make();
      for (final tap in [
        const NotificationActionTap(reminderId: 'water_intake', actionId: 'water_intake:water250', userId: 'baska-hesap'),
        const NotificationActionTap(reminderId: 'water_intake', actionId: 'uydurma', userId: testUserId),
        const NotificationActionTap(reminderId: 'daily_checkin', actionId: 'daily_checkin:open', userId: testUserId),
        const NotificationActionTap(reminderId: 'nutrition_log', actionId: 'nutrition_log:junkYes', userId: testUserId),
      ]) {
        notifier.tapAction(tap);
      }
      await flush();

      expect(backend.calls('/daily_tracking/ingest'), isEmpty);
      expect(EventOutbox.instance.pendingCount(testUserId), 0);
    });

    test('oturum yokken düğme olay göndermez', () async {
      auth.debugSetUser(null);
      make();
      notifier.tapAction(
        const NotificationActionTap(reminderId: 'water_intake', actionId: 'water_intake:water250', userId: testUserId),
      );
      await flush();
      expect(backend.calls('/daily_tracking/ingest'), isEmpty);
    });
  });
}

