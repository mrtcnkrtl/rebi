import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/core/api.dart';
import 'package:rebi/core/daily_tracking.dart';
import 'package:rebi/core/day_log.dart';
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

    test('metni ve düğmeleri taşır: uygulama kapalıyken erteleme bildirimi bunlarla yeniden kurulur', () {
      const payload = NotificationPayload(
        route: '/dashboard',
        reminderId: 'routine_evening',
        userId: 'u1',
        day: '2026-10-10',
        title: 'Akşam rutini',
        body: 'Gövde',
        actions: [NotificationActionSpec('routine_evening:done', 'Yaptım'), NotificationActionSpec('routine_evening:later', '30 dk sonra')],
      );
      final back = NotificationPayload.decode(payload.encode())!;
      expect((back.title, back.body, back.day), ('Akşam rutini', 'Gövde', '2026-10-10'));
      expect([for (final a in back.actions) (a.id, a.label)], [('routine_evening:done', 'Yaptım'), ('routine_evening:later', '30 dk sonra')]);
      final old = NotificationPayload.decode('{"route": "/dashboard", "reminder_id": "x"}')!;
      expect(old.title, isEmpty);
      expect(old.actions, isEmpty);
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

    test('her soruda olası her cevap vardır; kullanıcı tek cevaba zorlanmaz', () {
      expect(labels('routine_morning'), ['done', 'later', 'skip'], reason: 'Yaptım · 30 dk sonra · Bugün atla');
      expect(labels('routine_evening'), ['done', 'later', 'skip']);
      expect(labels('makeup_log'), ['yes', 'no']);
      expect(labels('makeup_removal'), ['removed', 'notRemoved'], reason: 'Temizledim · Temizlemedim');
      expect(labels('water_intake'), ['waterYes', 'waterNo'], reason: 'su bildirimi: "İçtim" ve "İçmedim"');
      expect(labels('spf_refresh'), ['done', 'notNeeded'], reason: 'Yaptım · Bugün gerek yok');
      expect(labels('nutrition_log'), ['junkYes', 'junkNo'], reason: 'Evet, yedim · Hayır');
      for (final id in const ['routine_morning', 'routine_evening', 'makeup_log', 'makeup_removal', 'water_intake', 'spf_refresh', 'nutrition_log']) {
        expect(notificationQuickActions(id).length, inInclusiveRange(2, maxNotificationActions), reason: id);
      }
    });

    test('bildirimdeki cevaplar doğru kaydı yazar', () {
      ReminderAction a(String id, String key) => resolveNotificationAction(id, '$id:$key')!;
      expect(a('routine_evening', 'skip').type, 'routine_skipped');
      expect(a('routine_evening', 'skip').payload, {'block': 'evening'});
      expect(a('routine_morning', 'skip').type, 'routine_skipped');
      expect(a('routine_morning', 'skip').payload, {'block': 'morning'});
      expect(a('routine_evening', 'later').type, isNull, reason: 'erteleme kayıt yazmaz');
      expect(a('routine_evening', 'later').snoozeMinutes, 30);
      expect(a('nutrition_log', 'junkYes').type, 'nutrition');
      expect(a('nutrition_log', 'junkYes').payload, {'junk_food': true});
      expect(a('makeup_removal', 'removed').type, 'makeup');
      expect(a('makeup_removal', 'removed').payload, {'removed': true});
      expect(a('makeup_removal', 'notRemoved').type, 'makeup');
      expect(a('makeup_removal', 'notRemoved').payload, {'method': 'none'});
      expect(a('spf_refresh', 'notNeeded').type, 'spf_skipped');
    });

    test('uygulamada ayrıntı sayfası açan cevaplar bildirimde kısa cevabı yazar', () {
      Reminder r(String id) => Reminder(id: id, title: '', body: '', start: '', end: '');
      final yes = reminderActions(r('nutrition_log')).first;
      expect((yes.sheet, yes.type), (DaySheet.nutrition, 'nutrition'));
      final removed = reminderActions(r('makeup_removal')).first;
      expect((removed.sheet, removed.type), (DaySheet.cleansing, 'makeup'));
    });

    test('cevap soruyu kapatır; doldurulan sorular (su, güneş kremi) ve erteleme kapatmaz', () {
      ReminderAction a(String id, String key) => resolveNotificationAction(id, '$id:$key')!;
      for (final (id, key) in const [
        ('routine_morning', 'done'),
        ('routine_evening', 'skip'),
        ('makeup_log', 'no'),
        ('makeup_removal', 'notRemoved'),
        ('nutrition_log', 'junkYes'),
        ('spf_refresh', 'notNeeded'),
      ]) {
        expect(actionClosesReminder(a(id, key)), isTrue, reason: '$id:$key');
      }
      for (final (id, key) in const [('water_intake', 'waterYes'), ('water_intake', 'waterNo'), ('spf_refresh', 'done'), ('routine_evening', 'later')]) {
        expect(actionClosesReminder(a(id, key)), isFalse, reason: '$id:$key');
      }
    });

    test('ekran açan ve bilinmeyen hatırlatıcıların düğmesi yoktur', () {
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
      expect(notificationActionId('water_intake', notificationQuickActions('water_intake').first), 'water_intake:waterYes');
    });

    test('"İçtim" bir bardak (250 ml) su yazar; "İçmedim" su toplamını değiştirmeyen ayrı bir olaydır', () {
      final yes = resolveNotificationAction('water_intake', 'water_intake:waterYes')!;
      expect(yes.type, 'water_intake');
      expect(yes.payload, {'ml': 250});
      final no = resolveNotificationAction('water_intake', 'water_intake:waterNo')!;
      expect(no.type, 'water_skipped');
      expect(no.payload, isEmpty);
    });

    test('önceki sürümde kurulmuş "+250 / +500 ml" düğmeleri güncellemeden sonra da çözülür', () {
      expect(resolveNotificationAction('water_intake', 'water_intake:water250')?.payload, {'ml': 250});
      expect(resolveNotificationAction('water_intake', 'water_intake:water500')?.payload, {'ml': 500});
    });

    test('uygulama içindeki su kutusunun hızlı ekleme eylemleri değişmedi (+250 / +500 ml)', () {
      final inApp = [for (final a in reminderActions(const Reminder(id: 'water_intake', title: '', body: '', start: '', end: ''))) a.labelKey];
      expect(inApp, ['water250', 'water500']);
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

    test('"İçtim" su olarak, "İçmedim" ayrı bir olay olarak kuyruğa girer', () async {
      expect(
        await queueNotificationAction(
          const NotificationActionTap(reminderId: 'water_intake', actionId: 'water_intake:waterYes', userId: testUserId),
        ),
        isTrue,
      );
      expect(
        await queueNotificationAction(
          const NotificationActionTap(reminderId: 'water_intake', actionId: 'water_intake:waterNo', userId: testUserId),
        ),
        isTrue,
      );

      final pending = EventOutbox.instance.pending(testUserId).toList();
      expect([for (final e in pending) e.type], ['water_intake', 'water_skipped']);
      expect(pending.first.payload, {'ml': 250});
      expect(pending.last.payload, isEmpty);
      expect(pending.first.id, isNot(pending.last.id), reason: 'her dokunuş ayrı bir kayıt');
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
        ('water_intake:waterYes', 'İçtim'),
        ('water_intake:waterNo', 'İçmedim'),
      ]);
      final checkin = notifier.scheduled.firstWhere((n) => n.reminderId == 'daily_checkin');
      expect(checkin.actions, isEmpty, reason: 'check-in bildirimden yanıtlanmaz, ekranı açar');
    });

    test('İngilizcede su bildirimi "I drank" / "I didn\'t"', () async {
      loadTestI18n('en');
      final c = make();
      await c.enable();
      c.syncReminders(plan([rem('water_intake', 'Time for water', '17:00', '17:00')]));
      await flush();
      final water = notifier.scheduled.firstWhere((n) => n.reminderId == 'water_intake' && n.at.day == 10);
      expect([for (final a in water.actions) a.label], ['I drank', "I didn't"]);
    });

    test('uygulama açıkken "İçmedim"e dokunulunca water_skipped olayı gönderilir', () async {
      make();
      notifier.tapAction(
        const NotificationActionTap(reminderId: 'water_intake', actionId: 'water_intake:waterNo', userId: testUserId),
      );
      await flush();

      final body = backend.bodyOf('/daily_tracking/ingest');
      expect(body['type'], 'water_skipped');
      expect(body['user_id'], testUserId);
      expect(body['client_event_id'], isNotEmpty);
    });

    test('İngilizcede düğme etiketleri İngilizce', () async {
      loadTestI18n('en');
      final c = make();
      await c.enable();
      c.syncReminders(plan([rem('routine_evening', 'Akşam rutini', '21:00', '21:00')]));
      await flush();
      final evening = notifier.scheduled.firstWhere((n) => n.reminderId == 'routine_evening' && n.at.day == 10);
      expect([for (final a in evening.actions) a.label], ['Done', 'In 30 min', 'Skip today']);
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

    test('"Evet, yedim" bildirimden yanıtlanır: abur cubur yendi kaydı', () async {
      make();
      notifier.tapAction(
        const NotificationActionTap(reminderId: 'nutrition_log', actionId: 'nutrition_log:junkYes', userId: testUserId),
      );
      await flush();
      final body = backend.bodyOf('/daily_tracking/ingest');
      expect(body['type'], 'nutrition');
      expect(body['payload'], {'junk_food': true});
    });

    test('akşam rutini "Bugün atla": kayıt yazılır, o günün akşam hatırlatması kalmaz', () async {
      final c = make();
      await c.enable();
      c.syncReminders(plan([rem('routine_evening', 'Akşam rutini', '21:00', '21:00')]));
      await flush();
      expect(notifier.scheduled.where((n) => n.reminderId == 'routine_evening' && n.at.day == 10), hasLength(1));

      notifier.tapAction(
        const NotificationActionTap(reminderId: 'routine_evening', actionId: 'routine_evening:skip', userId: testUserId),
      );
      await flush();

      final body = backend.bodyOf('/daily_tracking/ingest');
      expect(body['type'], 'routine_skipped');
      expect(body['payload'], {'block': 'evening'});
      expect(notifier.scheduled.where((n) => n.reminderId == 'routine_evening' && n.at.day == 10), isEmpty);
      expect(notifier.scheduled.where((n) => n.reminderId == 'routine_evening' && n.at.day == 11), isNotEmpty,
          reason: 'yarın yine hatırlatılır');
    });

    test('"30 dk sonra": kayıt yazmaz, bildirim 30 dk sonraya yeniden kurulur ve plan yenilense de kalır', () async {
      final c = make();
      await c.enable();
      final today = plan([rem('routine_evening', 'Akşam rutini', '15:00', '15:00')]);
      c.syncReminders(today);
      await flush();

      notifier.tapAction(
        const NotificationActionTap(reminderId: 'routine_evening', actionId: 'routine_evening:later', userId: testUserId),
      );
      await flush();

      expect(backend.calls('/daily_tracking/ingest'), isEmpty);
      final snoozed = notifier.scheduled.where((n) => n.reminderId == 'routine_evening' && n.at.day == 10).single;
      expect(snoozed.at, now.add(const Duration(minutes: 30)));
      expect([for (final a in snoozed.actions) a.id], contains('routine_evening:done'), reason: 'ertelenen bildirimde de tüm cevaplar');

      // Plan yeniden gelir (bildirimler baştan kurulur): erteleme kaybolmaz.
      c.syncReminders(plan([rem('routine_evening', 'Akşam rutini', '15:00', '15:00'), rem('water_intake', 'Su', '17:00', '17:00')]));
      await flush();
      expect(notifier.scheduled.where((n) => n.reminderId == 'routine_evening' && n.at == now.add(const Duration(minutes: 30))), hasLength(1));
    });

    test('ertelenen soru o arada cevaplanırsa ertelenen bildirim düşer', () async {
      final c = make();
      await c.enable();
      c.syncReminders(plan([rem('routine_evening', 'Akşam rutini', '15:00', '15:00')]));
      await flush();
      notifier.tapAction(
        const NotificationActionTap(reminderId: 'routine_evening', actionId: 'routine_evening:later', userId: testUserId),
      );
      await flush();
      notifier.tapAction(
        const NotificationActionTap(reminderId: 'routine_evening', actionId: 'routine_evening:done', userId: testUserId),
      );
      await flush();

      expect(notifier.scheduled.where((n) => n.reminderId == 'routine_evening' && n.at.day == 10), isEmpty);
    });

    test('başka hesap için kurulmuş bildirimin, bilinmeyen ve ekran açan eylemlerin düğmesi yok sayılır', () async {
      make();
      for (final tap in [
        const NotificationActionTap(reminderId: 'water_intake', actionId: 'water_intake:water250', userId: 'baska-hesap'),
        const NotificationActionTap(reminderId: 'water_intake', actionId: 'uydurma', userId: testUserId),
        const NotificationActionTap(reminderId: 'daily_checkin', actionId: 'daily_checkin:open', userId: testUserId),
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

