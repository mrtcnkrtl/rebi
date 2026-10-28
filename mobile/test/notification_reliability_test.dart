import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/core/api.dart';
import 'package:rebi/core/event_outbox.dart';
import 'package:rebi/core/local_store.dart';
import 'package:rebi/core/notification_actions.dart';
import 'package:rebi/core/silence_budget.dart';
import 'package:rebi/core/today_plan.dart';
import 'package:rebi/state/auth_controller.dart';
import 'package:rebi/state/notifications_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/app_harness.dart';
import 'helpers/notification_fakes.dart';

/// Faz E: bildirim güvenilirliği. Sunucu push'unun canlılığı, saat dilimi / uzun ara sonrası yeniden kayıt,
/// izin geri alınması, kurulum hatasında yeniden deneme, akıllı susma ve test bildirimi.

Map<String, dynamic> rem(String id, String start, String end, {int? every}) =>
    {'id': id, 'title': 'Başlık $id', 'body': 'Gövde', 'start': start, 'end': end, 'every_minutes': every, 'log_event': null};

TodayPlan planFor(
  List<Map<String, dynamic>> reminders, {
  Map<String, dynamic> progress = const {},
  Map<String, dynamic> settings = const {},
  bool checkinDone = false,
}) =>
    TodayPlan.fromJson({
      'log_date': '2026-10-10',
      'weather': {'uv_index': 7, 'humidity': 40, 'temperature': 24},
      'weather_source': 'live',
      'reminders': reminders,
      'progress': progress,
      'reminder_settings': settings,
      'checkin_done': checkinDone,
    });

Future<void> flush() => Future<void>.delayed(const Duration(milliseconds: 30));

void main() {
  late FakeBackend backend;
  late AuthController auth;
  late FakeReminderNotifier notifier;
  NotificationsController? controller;
  late DateTime clockNow;
  late int offset;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalStore.init();
    loadTestI18n('tr');
    EventOutbox.instance.debugReset();
    backend = FakeBackend();
    apiHttpClient = backend.client;
    auth = AuthController()..debugSetUser(fakeUser());
    notifier = FakeReminderNotifier();
    clockNow = DateTime(2026, 10, 10, 15, 30);
    offset = 180;
  });

  tearDown(() {
    controller?.dispose();
    controller = null;
    auth.dispose();
  });

  NotificationsController make({FakePushClient? push}) => controller = NotificationsController(
        auth,
        notifier: notifier,
        push: push ?? FakePushClient(available: false),
        appVersion: () async => '1.2.3',
        platform: () => 'android',
        clock: () => clockNow,
        utcOffsetMinutes: () => offset,
      );

  int registrations() => backend.calls('/devices/register').where((r) => r.method == 'POST').length;

  final evening = rem('routine_evening', '21:00', '23:00');

  group('sunucu push\'u yalnızca dağıtıcı canlıysa geçerlidir', () {
    test('FCM açık ama dağıtıcı çalışmıyorsa hatırlatmalar yerelden kurulur (hiç hatırlatma kaybolmaz)', () async {
      backend
        ..pushConfigured = true
        ..dispatchAlive = false;
      final c = make(push: FakePushClient());
      c.syncReminders(planFor([evening]));
      await c.enable();
      await flush();

      expect(c.pushActive, isFalse);
      expect(notifier.scheduled.where((n) => n.at.day == 10).map((n) => n.reminderId), ['routine_evening']);
    });

    test('dağıtıcı dirilince, uygulama öne gelince push\'a geçilir ve yerel bildirimler silinir (çift bildirim olmaz)',
        () async {
      backend
        ..pushConfigured = true
        ..dispatchAlive = false;
      final c = make(push: FakePushClient());
      c.syncReminders(planFor([evening]));
      await c.enable();
      await flush();
      expect(notifier.scheduled, isNotEmpty);

      backend.dispatchAlive = true;
      await c.onAppResumed();
      await flush();

      expect(registrations(), 2, reason: 'sunucu durumu yeniden soruldu');
      expect(c.pushActive, isTrue);
      expect(notifier.scheduled, isEmpty);
    });

    test('dağıtıcı canlıyken, saat dilimi aynıysa ve kayıt tazeyse öne gelmek yeniden kayıt atmaz', () async {
      backend.pushConfigured = true;
      final c = make(push: FakePushClient());
      await c.enable();
      expect(registrations(), 1);

      await c.onAppResumed();
      await c.onAppResumed();

      expect(registrations(), 1);
      expect(c.pushActive, isTrue);
    });

    test('alanı bilmeyen eski sunucuda push açık sayılır (eski davranış)', () async {
      backend.pushConfigured = true;
      // Eski sunucu `dispatch_alive` göndermez.
      backend.omitDispatchAlive = true;
      final c = make(push: FakePushClient());
      await c.enable();
      expect(c.pushActive, isTrue);
    });
  });

  group('saat dilimi ve süre', () {
    test('saat farkı değişince (yolculuk, yaz saati) öne gelince cihaz yeni farkla yeniden kaydolur', () async {
      backend.pushConfigured = true;
      final c = make(push: FakePushClient());
      await c.enable();
      expect(backend.bodyOf('/devices/register')['utc_offset_minutes'], 180);

      offset = 120;
      await c.onAppResumed();

      expect(registrations(), 2);
      expect(jsonDecode(backend.calls('/devices/register').last.body)['utc_offset_minutes'], 120);
    });

    test('12 saatten uzun aradan sonra kayıt yenilenir, öncesinde yenilenmez', () async {
      backend.pushConfigured = true;
      final c = make(push: FakePushClient());
      await c.enable();

      clockNow = clockNow.add(const Duration(hours: 11));
      await c.onAppResumed();
      expect(registrations(), 1);

      clockNow = clockNow.add(const Duration(hours: 2));
      await c.onAppResumed();
      expect(registrations(), 2);
    });

    test('Firebase yoksa öne gelince kayıt denenmez ama bildirimler geçen zamana göre yeniden kurulur', () async {
      final c = make();
      c.syncReminders(planFor([rem('water_intake', '09:00', '21:00', every: 120)]));
      await c.enable();
      await flush();
      expect(notifier.scheduled.where((n) => n.at.day == 10).map((n) => n.at.hour), [17, 19, 21]);

      clockNow = DateTime(2026, 10, 10, 18, 10);
      await c.onAppResumed();
      await flush();

      expect(registrations(), 0);
      expect(notifier.scheduled.where((n) => n.at.day == 10).map((n) => n.at.hour), [19, 21], reason: '17:00 geçti');
    });

    test('birkaç gün sonrası için de bildirim kurulur (uygulama 2-3 gün açılmasa da hatırlatma sürer)', () async {
      final c = make();
      await c.enable();
      c.syncReminders(planFor(const []));
      await flush();

      final days = notifier.scheduled.map((n) => n.at.day).toSet();
      expect(days, {11, 12}, reason: 'bugün için liste gelmedi; yarın ve öbür gün kuruldu');
    });
  });

  group('izin', () {
    test('uygulama öne gelince geri alınan izin yakalanır; izin gelince bildirimler baştan kurulur', () async {
      final c = make();
      c.syncReminders(planFor([evening]));
      await c.enable();
      await flush();
      expect(c.permissionBlocked, isFalse);

      notifier.permission = false;
      await c.onAppResumed();
      expect(c.permissionBlocked, isTrue, reason: 'plan değişmese de izin geri alındığı anlaşılır');

      final before = notifier.replaced.length;
      notifier.permission = true;
      await c.onAppResumed();
      await flush();
      expect(c.permissionBlocked, isFalse);
      expect(notifier.replaced.length, before + 1, reason: 'aynı liste olsa da izin dönünce yeniden kurulur');
      expect(notifier.scheduled, isNotEmpty);
    });

    test('bildirimler kapalıyken öne gelmek izin uyarısı çıkarmaz', () async {
      notifier.permission = false;
      final c = make();
      await c.onAppResumed();
      expect(c.permissionBlocked, isFalse);
    });
  });

  group('kurulum hatası', () {
    test('bazı bildirimler kurulamazsa aynı liste bir sonraki senkronda yeniden denenir', () async {
      final c = make();
      final plan = planFor([evening]);
      c.syncReminders(plan);
      notifier.failOnReplace = 2;
      await c.enable();
      await flush();
      final attempts = notifier.replaced.length;

      c.syncReminders(plan);
      await flush();

      expect(notifier.replaced.length, attempts + 1, reason: 'imza "kuruldu" diye saklanmadı');
      expect(notifier.scheduled, isNotEmpty);

      c.syncReminders(plan);
      await flush();
      expect(notifier.replaced.length, attempts + 1, reason: 'başarılı kurulumdan sonra aynı liste tekrar kurulmaz');
    });
  });

  group('sessiz saatler', () {
    test('sessiz saate denk gelen yerel bildirimler kurulmaz', () async {
      final c = make();
      c.syncReminders(planFor(
        [rem('water_intake', '09:00', '21:00', every: 60)],
        settings: {
          'quiet': {'start': '17:30', 'end': '19:30'},
        },
      ));
      await c.enable();
      await flush();

      final todayHours = notifier.scheduled.where((n) => n.at.day == 10).map((n) => n.at.hour).toList();
      expect(todayHours, [16, 17, 20, 21], reason: '18:00 ve 19:00 sessiz saate (17:30–19:30) düşer');
    });
  });

  group('akıllı susma', () {
    final waterToday = rem('water_intake', '17:00', '21:00', every: 120);

    test('hedefi dolduran su düğmesi bugünün kalan su bildirimlerini kaldırır, yarınkiler kalır', () async {
      final c = make();
      c.syncReminders(planFor([waterToday], progress: {'water_ml_total': 1750}));
      await c.enable();
      await flush();
      expect(notifier.scheduled.where((n) => n.at.day == 10 && n.reminderId == 'water_intake'), hasLength(3));

      notifier.tapAction(
        NotificationActionTap(reminderId: 'water_intake', actionId: 'water_intake:water250', userId: testUserId),
      );
      await flush();

      expect(backend.bodyOf('/daily_tracking/ingest')['payload'], {'ml': 250});
      expect(notifier.scheduled.where((n) => n.at.day == 10 && n.reminderId == 'water_intake'), isEmpty);
      expect(notifier.scheduled.where((n) => n.at.day == 11 && n.reminderId == 'water_intake'), isNotEmpty);
    });

    test('hedef dolmadıysa kalan su bildirimleri durur ama susmaz', () async {
      final c = make();
      c.syncReminders(planFor([waterToday], progress: {'water_ml_total': 500}));
      await c.enable();
      await flush();

      notifier.tapAction(
        NotificationActionTap(reminderId: 'water_intake', actionId: 'water_intake:water250', userId: testUserId),
      );
      await flush();

      expect(notifier.scheduled.where((n) => n.at.day == 10 && n.reminderId == 'water_intake'), hasLength(3));
    });

    test('sunucuya ulaşılamasa da (kuyruğa alınsa da) iş hemen plana işlenir', () async {
      backend.ingestOffline = true;
      final c = make();
      c.syncReminders(planFor([waterToday], progress: {'water_ml_total': 1900}));
      await c.enable();
      await flush();

      notifier.tapAction(
        NotificationActionTap(reminderId: 'water_intake', actionId: 'water_intake:water250', userId: testUserId),
      );
      await flush();

      expect(EventOutbox.instance.pendingCount(testUserId), 1);
      expect(notifier.scheduled.where((n) => n.at.day == 10 && n.reminderId == 'water_intake'), isEmpty);
    });

    test('rutin düğmesi o günün rutin bildirimini kaldırır', () async {
      final c = make();
      c.syncReminders(planFor([evening]));
      await c.enable();
      await flush();
      expect(notifier.scheduled.where((n) => n.at.day == 10 && n.reminderId == 'routine_evening'), hasLength(1));

      notifier.tapAction(
        NotificationActionTap(reminderId: 'routine_evening', actionId: 'routine_evening:done', userId: testUserId),
      );
      await flush();

      expect(notifier.scheduled.where((n) => n.at.day == 10 && n.reminderId == 'routine_evening'), isEmpty);
      expect(notifier.scheduled.where((n) => n.at.day == 11 && n.reminderId == 'routine_evening'), isNotEmpty);
    });

    test('"makyaj yaptım" cevabı akşam makyaj temizliği hatırlatmasını ekler', () async {
      final c = make();
      c.syncReminders(planFor([rem('makeup_log', '16:00', '17:00'), evening]));
      await c.enable();
      await flush();
      expect(notifier.scheduled.where((n) => n.reminderId == 'makeup_removal'), isEmpty);

      notifier.tapAction(
        NotificationActionTap(reminderId: 'makeup_log', actionId: 'makeup_log:yes', userId: testUserId),
      );
      await flush();

      final removal = notifier.scheduled.where((n) => n.at.day == 10 && n.reminderId == 'makeup_removal').toList();
      expect(removal, hasLength(1));
      expect(removal.single.at, DateTime(2026, 10, 10, 21));
    });

    test('düğmeyle kaydedilen iş panele bildirilir (panel planını yeniden okur)', () async {
      final c = make();
      final seen = <String>[];
      final sub = c.recordedActions.listen(seen.add);
      addTearDown(sub.cancel);

      notifier.tapAction(
        NotificationActionTap(reminderId: 'water_intake', actionId: 'water_intake:water500', userId: testUserId),
      );
      await flush();
      expect(seen, ['water_intake']);

      notifier.tapAction(
        NotificationActionTap(reminderId: 'water_intake', actionId: 'water_intake:water500', userId: 'baska-hesap'),
      );
      await flush();
      expect(seen, ['water_intake'], reason: 'başka hesabın düğmesi yok sayılır');
    });

    test('kurulum sonrası günün kalan miktarları diske yazılır (uygulama kapalıyken susturma için)', () async {
      final c = make();
      c.syncReminders(planFor([waterToday], progress: {'water_ml_total': 1250, 'spf_refreshes': 1}));
      await c.enable();
      await flush();

      final budget = SilenceBudget.read(userId: testUserId, day: '2026-10-10')!;
      expect(budget.waterRemainingMl, 750);
      expect(budget.spfRemaining, 1);
    });
  });

  group('test bildirimi', () {
    test('izin varsa bir dakika sonrasına bir bildirim kurulur', () async {
      final c = make();
      await c.enable();

      expect(await c.sendTestNotification(), TestNotificationResult.scheduled);
      expect(notifier.tests.single.delay, const Duration(minutes: 1));
      expect(notifier.tests.single.title, isNotEmpty);
      expect(notifier.tests.single.body, isNotEmpty);
    });

    test('izin yoksa kurulmaz ve uyarı çıkar', () async {
      final c = make();
      await c.enable();
      notifier.permission = false;

      expect(await c.sendTestNotification(), TestNotificationResult.blocked);
      expect(notifier.tests, isEmpty);
      expect(c.permissionBlocked, isTrue);
    });

    test('kurulamazsa ya da platform desteklemiyorsa "kurulamadı" döner', () async {
      final c = make();
      await c.enable();
      notifier.testSucceeds = false;
      expect(await c.sendTestNotification(), TestNotificationResult.unavailable);

      notifier.supported = false;
      expect(await c.sendTestNotification(), TestNotificationResult.unavailable);
    });
  });
}
