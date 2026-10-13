import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/core/reminder_schedule.dart';
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
}
