import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/core/notification_actions.dart';
import 'package:rebi/core/reminder_schedule.dart';
import 'package:rebi/core/reminder_settings.dart';
import 'package:rebi/core/today_plan.dart';

Reminder r(String id, String start, String end, {int? every}) =>
    Reminder(id: id, title: id, body: '', start: start, end: end, everyMinutes: every);

({String title, String body}) text(Reminder r) => (title: r.title.isEmpty ? 'varsayılan ${r.id}' : r.title, body: 'gövde');

void main() {
  group('reminderSlots', () {
    test('tek seferlik hatırlatıcı pencerenin başında gönderilir', () {
      expect(reminderSlots(r('routine_morning', '07:30', '09:30')), [450]);
    });

    test('aralıklı hatırlatıcı pencere boyunca tekrarlar (uçlar dahil)', () {
      expect(reminderSlots(r('water_intake', '09:00', '21:00', every: 120)), [540, 660, 780, 900, 1020, 1140, 1260]);
      expect(reminderSlots(r('spf_refresh', '11:00', '16:00', every: 120)), [660, 780, 900]);
    });

    test('bozuk ya da ters pencere bildirim üretmez', () {
      expect(reminderSlots(r('x', '9.00', '10:00')), isEmpty);
      expect(reminderSlots(r('x', '10:00', '09:00')), isEmpty);
      expect(reminderSlots(r('x', '10:00', '25:00')), isEmpty);
    });

    test('sıfır / negatif aralık sonsuz döngüye girmez', () {
      expect(reminderSlots(r('x', '09:00', '21:00', every: 0)), [540]);
      expect(reminderSlots(r('x', '09:00', '21:00', every: -5)), [540]);
    });

    test('sessiz saat yuvaları düşürür; başlangıç dahil, bitiş hariç', () {
      final water = r('water_intake', '09:00', '13:00', every: 60);
      expect(reminderSlots(water, quiet: const ClockRange('10:00', '11:00')), [540, 660, 720, 780]);
    });

    test('gece yarısını aşan sessiz saat akşam yuvalarını düşürür, gündüzü etkilemez', () {
      final water = r('water_intake', '09:00', '23:00', every: 120);
      expect(reminderSlots(water, quiet: const ClockRange('22:00', '07:00')), [540, 660, 780, 900, 1020, 1140, 1260]);
    });

    test('tek seferlik hatırlatıcı sessiz saate düşerse, pencere izin veriyorsa bitişine ertelenir; sığmıyorsa susar', () {
      expect(reminderSlots(r('lip_balm', '12:00', '13:00'), quiet: const ClockRange('11:30', '12:30')), [750]);
      expect(reminderSlots(r('lip_balm', '12:00', '12:30'), quiet: const ClockRange('11:00', '12:30')), [750]);
      expect(reminderSlots(r('nutrition_log', '20:00', '20:30'), quiet: const ClockRange('19:00', '22:00')), isEmpty);
      expect(reminderSlots(r('routine_morning', '06:00', '09:00'), quiet: const ClockRange('22:00', '07:00')), [420]);
    });

    test('sessiz saat pencereye değmiyorsa hiçbir şey değişmez', () {
      expect(reminderSlots(r('routine_morning', '07:30', '09:30'), quiet: const ClockRange('13:00', '14:00')), [450]);
    });
  });

  group('planNotifications', () {
    final now = DateTime(2026, 10, 10, 15, 30);

    test('bugünün geçmiş saatleri atlanır, kalanlar zamana göre sıralanır', () {
      final items = planNotifications(
        today: [
          r('spf_refresh', '11:00', '16:00', every: 120),
          r('routine_evening', '21:00', '23:00'),
          r('lip_balm', '12:00', '13:00'),
          r('water_intake', '09:00', '21:00', every: 120),
        ],
        now: now,
        textFor: text,
        includeTomorrow: false,
      );
      expect([for (final n in items) '${n.at.hour}:${n.at.minute.toString().padLeft(2, '0')} ${n.reminderId}'], [
        '17:00 water_intake',
        '19:00 water_intake',
        '21:00 routine_evening',
        '21:00 water_intake',
      ]);
      expect(items.every((n) => n.at.isAfter(now)), isTrue);
    });

    test('kimlikler 1den başlayıp sıralıdır', () {
      final items = planNotifications(today: [r('routine_evening', '21:00', '23:00')], now: now, textFor: text);
      expect([for (final n in items) n.id], [for (var i = 1; i <= items.length; i++) i]);
    });

    test('yarın için koşulsuz hatırlatıcılar eklenir, bugünün planına bağlı olmaz', () {
      final items = planNotifications(today: const [], now: now, textFor: text);
      final tomorrow = items.where((n) => n.at.day == 11).toList();
      expect(tomorrow.map((n) => n.reminderId).toSet(), {
        'routine_morning',
        'water_intake',
        'makeup_log',
        'nutrition_log',
        'routine_evening',
        'daily_checkin',
      });
      expect(tomorrow.first.reminderId, 'routine_morning');
      expect(tomorrow.first.at, DateTime(2026, 10, 11, 7, 30));
      expect(items.where((n) => n.at.day == 10), isEmpty, reason: 'bugünden liste gelmedi');
    });

    test('yarının metni sunucu metni olmadığı için yerel metin sağlayıcıdan alınır', () {
      final items = planNotifications(today: const [], now: now, textFor: text);
      expect(items.first.title, 'varsayılan routine_morning');
    });

    test('ay sonunda yarın doğru güne düşer', () {
      final items = planNotifications(today: const [], now: DateTime(2026, 10, 31, 22, 0), textFor: text);
      expect(items.first.at, DateTime(2026, 11, 1, 7, 30));
    });

    test('toplam sınır aşılmaz ve en erken olanlar kalır', () {
      final items = planNotifications(today: const [], now: now, textFor: text, limit: 3);
      expect(items, hasLength(3));
      expect(items.map((n) => n.at).toList()..sort(), items.map((n) => n.at).toList());
    });

    test('varsayılan sınır iOS sınırının (64) altındadır', () {
      final many = [for (var i = 0; i < 30; i++) r('k$i', '16:00', '23:00', every: 15)];
      final items = planNotifications(today: many, now: now, textFor: text);
      expect(items.length, maxScheduledNotifications);
      expect(maxScheduledNotifications, lessThan(64));
    });

    test('check-in bildirimi check-in ekranını açar, diğerleri paneli', () {
      expect(routeForReminder('daily_checkin'), '/dashboard/checkin');
      expect(routeForReminder('water_intake'), '/dashboard');
      expect(routeForReminder(null), '/dashboard');
      final items = planNotifications(today: [r('daily_checkin', '21:00', '22:30')], now: now, textFor: text, includeTomorrow: false);
      expect(items.single.route, '/dashboard/checkin');
    });

    test('aynı saatteki bildirimlerin sırası kararlıdır', () {
      List<String> order() => [
            for (final n in planNotifications(
              today: [r('routine_evening', '21:00', '23:00'), r('daily_checkin', '21:00', '22:30')],
              now: now,
              textFor: text,
              includeTomorrow: false,
            ))
              n.reminderId,
          ];
      expect(order(), ['daily_checkin', 'routine_evening']);
      expect(order(), order());
    });
  });

  group('scheduleSignature', () {
    test('aynı liste aynı, farklı metin ya da saat farklı parmak izi verir', () {
      final now = DateTime(2026, 10, 10, 15, 30);
      List<PlannedNotification> plan(String title) => planNotifications(
            today: [r('routine_evening', '21:00', '23:00')],
            now: now,
            textFor: (r) => (title: title, body: ''),
            includeTomorrow: false,
          );
      expect(scheduleSignature(plan('a')), scheduleSignature(plan('a')));
      expect(scheduleSignature(plan('a')), isNot(scheduleSignature(plan('b'))));
      expect(scheduleSignature(const []), '');
    });
  });

  group('birkaç günlük ufuk', () {
    final now = DateTime(2026, 10, 10, 15, 30);

    List<PlannedNotification> plan({
      List<Reminder> today = const [],
      ReminderSettings settings = const ReminderSettings(),
      DateTime? at,
      int futureDays = scheduleFutureDays,
      int limit = maxScheduledNotifications,
    }) =>
        planNotifications(today: today, now: at ?? now, textFor: text, settings: settings, futureDays: futureDays, limit: limit);

    test('bugünden sonra iki gün için koşulsuz hatırlatıcılar kurulur', () {
      final days = plan().map((n) => n.at.day).toSet();
      expect(days, {11, 12});
      expect(scheduleFutureDays, 2);
    });

    test('futureDays ufku ayarlar; includeTomorrow false hepsini kapatır', () {
      expect(plan(futureDays: 1).map((n) => n.at.day).toSet(), {11});
      expect(plan(futureDays: 3).map((n) => n.at.day).toSet(), {11, 12, 13});
      expect(planNotifications(today: const [], now: now, textFor: text, includeTomorrow: false), isEmpty);
    });

    test('her gün ayarlardaki kendi pencereleriyle kurulur', () {
      final s = const ReminderSettings().withWindow('routine_morning', const ClockRange('09:00', '10:00'));
      final mornings = plan(settings: s).where((n) => n.reminderId == 'routine_morning').map((n) => n.at).toList();
      expect(mornings, [DateTime(2026, 10, 11, 9), DateTime(2026, 10, 12, 9)]);
    });

    test('sessiz saatler bugünün ve sonraki günlerin bildirimlerini süzer', () {
      final s = const ReminderSettings().withQuiet(const ClockRange('09:00', '10:00'));
      final items = plan(today: [r('water_intake', '16:00', '22:00', every: 60)], settings: s);
      expect(items.where((n) => n.at.day == 11 && n.reminderId == 'water_intake').map((n) => n.at.hour), isNot(contains(9)));
      expect(items.where((n) => n.at.day == 10 && n.reminderId == 'water_intake'), hasLength(7));
      expect(items.where((n) => n.at.hour == 9 && n.at.minute == 0), isEmpty);
    });

    test('sınır dolunca en yakın bildirimler kalır, uzak günler kırpılır', () {
      final items = plan(today: [for (var i = 0; i < 6; i++) r('k$i', '16:00', '23:00', every: 15)]);
      expect(items, hasLength(maxScheduledNotifications));
      final times = items.map((n) => n.at).toList();
      expect([...times]..sort(), times);
      expect(items.every((n) => n.at.day == 10), isTrue, reason: 'yoğun bir günde bugün sınırı doldurur');
    });

    test('gece yarısı, ay ve yıl geçişlerinde gün doğru ilerler', () {
      final nye = plan(at: DateTime(2026, 12, 31, 23, 50));
      expect(nye.map((n) => (n.at.year, n.at.month, n.at.day)).toSet(), {(2027, 1, 1), (2027, 1, 2)});

      final feb = plan(at: DateTime(2028, 2, 28, 22, 0));
      expect(feb.map((n) => (n.at.month, n.at.day)).toSet(), {(2, 29), (3, 1)}, reason: 'artık yıl');

      final justAfterMidnight = plan(today: [r('routine_morning', '07:30', '09:30')], at: DateTime(2026, 10, 11, 0, 5));
      expect(justAfterMidnight.first.at, DateTime(2026, 10, 11, 7, 30), reason: 'yeni günün planı bugündür');
      expect(justAfterMidnight.where((n) => n.at.day == 11 && n.reminderId == 'routine_morning'), hasLength(1));
    });

    test('bildirimin günü kaydedilir ve yükte taşınır (kapalı uygulamada günün kalanını susturmak için)', () {
      final item = plan(today: [r('water_intake', '17:00', '17:00')], futureDays: 0).single;
      expect(item.day, '2026-10-10');
      expect(item.payload.day, '2026-10-10');
      expect(NotificationPayload.decode(item.payload.encode())!.day, '2026-10-10');
      expect(localDayKey(DateTime(2026, 3, 5)), '2026-03-05');
    });
  });

  group('remindersFor (yapılan iş hemen yansır)', () {
    TodayPlan planWith(List<Reminder> reminders, {Map<String, dynamic> progress = const {}, bool checkinDone = false, Map<String, dynamic>? settings}) =>
        TodayPlan.fromJson({
          'log_date': '2026-10-10',
          'reminders': [
            for (final x in reminders)
              {'id': x.id, 'title': x.title, 'body': '', 'start': x.start, 'end': x.end, 'every_minutes': x.everyMinutes},
          ],
          'progress': progress,
          'checkin_done': checkinDone,
          'reminder_settings': settings ?? const {},
        });

    List<String> ids(TodayPlan p) => [for (final x in remindersFor(p)) x.id];

    final all = [
      r('routine_morning', '07:30', '09:30'),
      r('makeup_log', '10:00', '11:00'),
      r('water_intake', '09:00', '21:00', every: 120),
      r('spf_refresh', '11:00', '16:00', every: 120),
      r('nutrition_log', '20:00', '20:30'),
      r('routine_evening', '21:00', '23:00'),
      r('daily_checkin', '21:00', '22:30'),
      r('lip_balm', '12:00', '13:00'),
    ];

    test('hiçbir şey yapılmadıysa liste aynı kalır', () {
      expect(ids(planWith(all)), all.map((x) => x.id));
    });

    test('yapılan her iş kendi hatırlatıcısını düşürür', () {
      expect(ids(planWith(all, progress: {'routine_morning_done': true})), isNot(contains('routine_morning')));
      expect(ids(planWith(all, progress: {'routine_evening_done': true})), isNot(contains('routine_evening')));
      expect(ids(planWith(all, progress: {'makeup': {'logged': true}})), isNot(contains('makeup_log')));
      expect(ids(planWith(all, progress: {'nutrition_logged': true})), isNot(contains('nutrition_log')));
      expect(ids(planWith(all, checkinDone: true)), isNot(contains('daily_checkin')));
    });

    test('su hedefi dolunca su hatırlatıcısı düşer; hedef kişiseldir', () {
      expect(ids(planWith(all, progress: {'water_ml_total': 1999})), contains('water_intake'));
      expect(ids(planWith(all, progress: {'water_ml_total': 2000})), isNot(contains('water_intake')));
      final custom = {'water_target_ml': 3000};
      expect(ids(planWith(all, progress: {'water_ml_total': 2500}, settings: custom)), contains('water_intake'));
      expect(ids(planWith(all, progress: {'water_ml_total': 3000}, settings: custom)), isNot(contains('water_intake')));
    });

    test('güneş kremi günde iki tazelemeden sonra düşer', () {
      expect(ids(planWith(all, progress: {'spf_refreshes': 1})), contains('spf_refresh'));
      expect(ids(planWith(all, progress: {'spf_refreshes': spfRefreshMaxPerDay})), isNot(contains('spf_refresh')));
    });

    test('bilgi veren hatırlatıcılar (dudak balsamı) yapılan işe bağlı değildir', () {
      final done = {
        'routine_morning_done': true,
        'routine_evening_done': true,
        'water_ml_total': 9999,
        'nutrition_logged': true,
        'makeup': {'logged': true},
        'spf_refreshes': 5,
      };
      expect(ids(planWith(all, progress: done, checkinDone: true)), ['lip_balm']);
    });

    test('makyaj yapıldı ve temizlenmediyse temizleme hatırlatıcısı eklenir; temizlenince düşer', () {
      final used = ids(planWith(all, progress: {'makeup': {'logged': true, 'used': true}}));
      expect(used, contains('makeup_removal'));
      final removal = remindersFor(planWith(all, progress: {'makeup': {'logged': true, 'used': true}}))
          .firstWhere((x) => x.id == 'makeup_removal');
      expect((removal.start, removal.end), ('21:00', '23:00'));
      expect(removal.logEvent, 'makeup');

      expect(ids(planWith(all, progress: {'makeup': {'logged': true, 'used': true, 'removed': true}})), isNot(contains('makeup_removal')));
      expect(ids(planWith(all, progress: {'makeup': {'logged': true, 'used': false}})), isNot(contains('makeup_removal')));
    });

    test('makyaj kategorisi kapalıysa temizleme hatırlatıcısı eklenmez; sunucunun getirdiği tekrar eklenmez', () {
      final off = {'enabled': {'makeup': false}};
      expect(ids(planWith(all, progress: {'makeup': {'logged': true, 'used': true}}, settings: off)), isNot(contains('makeup_removal')));
      final already = [...all, r('makeup_removal', '21:00', '23:00')];
      expect(ids(planWith(already, progress: {'makeup': {'logged': true, 'used': true}})).where((i) => i == 'makeup_removal'), hasLength(1));
    });
  });
}
