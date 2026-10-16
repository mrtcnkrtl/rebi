import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/core/api.dart';
import 'package:rebi/core/notification_actions.dart';
import 'package:rebi/core/reminder_schedule.dart';
import 'package:rebi/core/reminder_settings.dart';
import 'package:rebi/core/today_plan.dart';

import 'helpers/app_harness.dart';

({String title, String body}) _text(Reminder r) => (title: r.title.isEmpty ? 'varsayılan ${r.id}' : r.title, body: 'gövde');

Map<String, (String, String)> _windows(ReminderSettings s) => {
      for (final id in reminderCategoryOf.keys) id: (reminderWindow(id, s)!.start, reminderWindow(id, s)!.end),
    };

void main() {
  group('pencereler (sunucudaki reminder_windows ile aynı)', () {
    test('varsayılan düzen eski sabit pencereleri verir', () {
      expect(_windows(const ReminderSettings()), {
        'routine_morning': ('07:30', '09:30'),
        'makeup_log': ('10:00', '11:00'),
        'spf_refresh': ('11:00', '16:00'),
        'lip_balm': ('12:00', '13:00'),
        'water_intake': ('09:00', '21:00'),
        'nutrition_log': ('20:00', '20:30'),
        'routine_evening': ('21:00', '23:00'),
        'makeup_removal': ('21:00', '23:00'),
        'daily_checkin': ('21:00', '22:30'),
        'restock_check': ('18:00', '19:00'),
      });
    });

    test('uyanma ve uyku saatine göre kayar', () {
      final w = _windows(const ReminderSettings(wakeTime: '06:00', sleepTime: '22:00'));
      expect(w['routine_morning'], ('06:00', '08:00'));
      expect(w['water_intake'], ('07:30', '20:00'));
      expect(w['routine_evening'], ('20:00', '22:00'));
      expect(w['daily_checkin'], ('20:00', '21:30'));
      expect(w['nutrition_log'], ('19:00', '19:30'));
    });

    test('bilinmeyen kimliğin penceresi yoktur', () {
      expect(reminderWindow('bilinmeyen', const ReminderSettings()), isNull);
    });

    test('her pencere uyanık günün içinde ve sıralıdır', () {
      for (final (wake, sleep) in [('04:00', '13:00'), ('04:00', '23:59'), ('10:00', '23:59'), ('06:15', '21:40')]) {
        final s = ReminderSettings(wakeTime: wake, sleepTime: sleep);
        for (final e in _windows(s).entries) {
          final (start, end) = e.value;
          expect(start.compareTo(wake) >= 0 && start.compareTo(end) <= 0 && end.compareTo(sleep) <= 0, isTrue,
              reason: '${e.key} $wake–$sleep: $start–$end');
        }
      }
    });
  });

  group('ReminderSettings', () {
    test('bozuk veri varsayılana döner; tutarsız gün düzeni ikisini birden sıfırlar', () {
      expect(ReminderSettings.fromJson(null).sameAs(const ReminderSettings()), isTrue);
      expect(ReminderSettings.fromJson('bozuk').sameAs(const ReminderSettings()), isTrue);

      final s = ReminderSettings.fromJson({
        'wake_time': '25:00',
        'sleep_time': '23:00',
        'water_every_minutes': 45,
        'enabled': {'water': 'evet', 'spf': false, 'uydurma': false},
      });
      expect(s.wakeTime, '07:30');
      expect(s.sleepTime, '23:00');
      expect(s.waterEveryMinutes, 120);
      expect(s.isEnabled('water'), isTrue, reason: 'bool olmayan değer açık sayılır');
      expect(s.isEnabled('spf'), isFalse);
      expect(s.toJson()['enabled'], isNot(contains('uydurma')));
    });

    test('gün düzeni geçerlilik kuralları', () {
      expect(const ReminderSettings().dayIsValid, isTrue);
      expect(const ReminderSettings(wakeTime: '04:00', sleepTime: '13:00').dayIsValid, isTrue);
      expect(const ReminderSettings(wakeTime: '10:00', sleepTime: '17:00').dayIsValid, isFalse, reason: '9 saatten kısa');
      expect(const ReminderSettings(wakeTime: '03:59', sleepTime: '23:00').dayIsValid, isFalse, reason: '04:00den erken');
      expect(const ReminderSettings(wakeTime: 'x', sleepTime: '23:00').dayIsValid, isFalse);
    });

    test('değişiklik fark edilir, aynı ayar aynı sayılır', () {
      const base = ReminderSettings();
      expect(base.sameAs(base.copyWith()), isTrue);
      expect(base.sameAs(base.copyWith(wakeTime: '08:00')), isFalse);
      expect(base.sameAs(base.withCategory('spf', false)), isFalse);
      expect(base.sameAs(base.withCategory('spf', true)), isTrue, reason: 'açık sayılan kategori yazılsa da aynı');
    });

    test('toJson sunucuya her kategoriyi gönderir', () {
      final json = const ReminderSettings().withCategory('water', false).toJson();
      expect(json['wake_time'], '07:30');
      expect(json['water_every_minutes'], 120);
      expect((json['enabled'] as Map).keys, reminderCategories);
      expect((json['enabled'] as Map)['water'], isFalse);
    });

    test('saat biçimleri', () {
      expect(parseClock('07:30'), 450);
      expect(parseClock('7:05'), 425);
      expect(parseClock('24:00'), isNull);
      expect(parseClock('07:60'), isNull);
      expect(parseClock(null), isNull);
      expect(formatClock(450), '07:30');
      expect(formatClock(-5), '00:00');
      expect(formatClock(99999), '23:59');
    });
  });

  group('TodayPlan ve yarının bildirimleri', () {
    test('plan, sunucunun gönderdiği ayarı taşır; yoksa varsayılan', () {
      final plan = TodayPlan.fromJson({
        'reminder_settings': {'wake_time': '06:00', 'sleep_time': '22:00', 'water_every_minutes': 180},
      });
      expect(plan.settings.wakeTime, '06:00');
      expect(plan.settings.waterEveryMinutes, 180);
      expect(plan.withProgress(const DayProgress()).settings.sleepTime, '22:00');
      expect(TodayPlan.fromJson(const {}).settings.sameAs(const ReminderSettings()), isTrue);
    });

    test('dailyReminders ayarlara uyar, kapatılan kategoriyi çıkarır', () {
      final ids = dailyReminders(const ReminderSettings().withCategory('water', false).withCategory('makeup', false))
          .map((r) => r.id)
          .toList();
      expect(ids, ['routine_morning', 'nutrition_log', 'routine_evening', 'daily_checkin']);

      final water = dailyReminders(const ReminderSettings(waterEveryMinutes: 60)).firstWhere((r) => r.id == 'water_intake');
      expect(water.everyMinutes, 60);
    });

    test('yarın için kurulan bildirimler gün düzenine göre kayar', () {
      final now = DateTime(2026, 10, 10, 15, 30);
      final items = planNotifications(
        today: const [],
        now: now,
        textFor: _text,
        settings: const ReminderSettings(wakeTime: '06:00', sleepTime: '22:00', waterEveryMinutes: 180),
      );
      final morning = items.firstWhere((n) => n.reminderId == 'routine_morning');
      expect(morning.at, DateTime(2026, 10, 11, 6));
      final water = items.where((n) => n.reminderId == 'water_intake').map((n) => n.at.hour).toList();
      expect(water, [7, 10, 13, 16, 19], reason: '07:30–20:00 arası 3 saatte bir: 07:30, 10:30, … saat dilimi yok, dakika ayrı');
    });

    test('yarın için kapatılan kategori bildirim üretmez', () {
      final items = planNotifications(
        today: const [],
        now: DateTime(2026, 10, 10, 15, 30),
        textFor: _text,
        settings: const ReminderSettings().withCategory('checkin', false).withCategory('routine', false),
      );
      expect(items.map((n) => n.reminderId).toSet(), isNot(containsAll(['daily_checkin', 'routine_morning'])));
      expect(items.map((n) => n.reminderId), contains('water_intake'));
    });

    test('bildirimlere eylem düğmeleri ve kullanıcı eklenir; parmak izi bunlara duyarlıdır', () {
      final now = DateTime(2026, 10, 10, 15, 30);
      List<NotificationActionSpec> actions(Reminder r) =>
          [for (final a in notificationQuickActions(r.id)) NotificationActionSpec(notificationActionId(r.id, a), a.labelKey)];
      final items = planNotifications(
        today: [const Reminder(id: 'water_intake', title: 'Su', body: '', start: '17:00', end: '17:00')],
        now: now,
        textFor: _text,
        actionsFor: actions,
        userId: 'u1',
        includeTomorrow: false,
      );
      final water = items.single;
      expect(water.userId, 'u1');
      expect([for (final a in water.actions) a.id], ['water_intake:water250', 'water_intake:water500']);
      expect(water.payload.reminderId, 'water_intake');
      expect(water.payload.userId, 'u1');
      expect(water.payload.route, '/dashboard');

      final withoutActions = planNotifications(
        today: [const Reminder(id: 'water_intake', title: 'Su', body: '', start: '17:00', end: '17:00')],
        now: now,
        textFor: _text,
        userId: 'u1',
        includeTomorrow: false,
      );
      expect(scheduleSignature(items), isNot(scheduleSignature(withoutActions)));
    });
  });

  group('sunucu uçları', () {
    setUp(() {
      loadTestI18n('tr');
    });

    test('okuma sunucunun ayarını verir; hata ve ağ yokluğunda null', () async {
      final backend = FakeBackend();
      backend.reminderSettings = {...backend.reminderSettings, 'wake_time': '06:30'};
      apiHttpClient = backend.client;

      final s = await fetchReminderSettings(testUserId);
      expect(s!.wakeTime, '06:30');
      expect(backend.calls('/me/reminder-settings').single.url.queryParameters, {'user_id': testUserId});

      backend.reminderSettingsFails = true;
      expect(await fetchReminderSettings(testUserId), isNull);
    });

    test('kaydetme tüm ayarı gönderir ve sunucunun kabul ettiğini döndürür', () async {
      final backend = FakeBackend();
      apiHttpClient = backend.client;

      final result = await saveReminderSettings(
        testUserId,
        const ReminderSettings(wakeTime: '06:00', sleepTime: '22:30', waterEveryMinutes: 90).withCategory('spf', false),
      );

      expect(result.ok, isTrue);
      expect(result.settings!.wakeTime, '06:00');
      final body = backend.bodyOf('/me/reminder-settings');
      expect(body['user_id'], testUserId);
      expect(body['sleep_time'], '22:30');
      expect(body['water_every_minutes'], 90);
      expect((body['enabled'] as Map)['spf'], isFalse);
      expect((body['enabled'] as Map)['water'], isTrue);
    });

    test('sunucu 422 verirse nedeni döner, başka hatada boş mesaj', () async {
      final backend = FakeBackend()..reminderSettingsPutStatus = 422;
      apiHttpClient = backend.client;
      var result = await saveReminderSettings(testUserId, const ReminderSettings());
      expect(result.ok, isFalse);
      expect(result.error, 'Geçersiz değer.');

      backend.reminderSettingsPutStatus = 502;
      result = await saveReminderSettings(testUserId, const ReminderSettings());
      expect(result.ok, isFalse);
      expect(result.error, isEmpty, reason: 'ekran genel "kaydedilemedi" mesajını gösterir');
    });
  });

  group('günlük su hedefi', () {
    test('varsayılan 2000 ml; geçerli seçimler kabul edilir, bozuk değerler varsayılana döner', () {
      expect(const ReminderSettings().waterTargetMl, 2000);
      expect(ReminderSettings.fromJson(null).waterTargetMl, 2000);
      expect(ReminderSettings.fromJson({'water_target_ml': 2500}).waterTargetMl, 2500);
      for (final bad in [1234, '2500', null, true, -1, 99999]) {
        expect(ReminderSettings.fromJson({'water_target_ml': bad}).waterTargetMl, 2000, reason: '$bad');
      }
    });

    test('sunucuya gönderilir, kopyada korunur, değişiklik "kaydedilmemiş" sayılır', () {
      final s = const ReminderSettings().copyWith(waterTargetMl: 3000);
      expect(s.toJson()['water_target_ml'], 3000);
      expect(s.copyWith(wakeTime: '06:30').waterTargetMl, 3000);
      expect(s.sameAs(const ReminderSettings()), isFalse);
      expect(s.sameAs(ReminderSettings.fromJson(s.toJson())), isTrue);
    });

    test('seçenekler sunucuyla aynı (ml)', () {
      expect(waterTargetChoices, [1500, 1750, 2000, 2250, 2500, 3000]);
      expect(waterTargetChoices, contains(defaultWaterTargetMl));
    });
  });
}
