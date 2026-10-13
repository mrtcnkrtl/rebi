import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/core/today_plan.dart';
import 'package:rebi/core/user_snapshot.dart';

/// `docs/MOBIL-API.md` örnek yanıtı.
Map<String, dynamic> samplePlan() => {
      'user_id': 'u1',
      'log_date': '2026-10-04',
      'has_routine': true,
      'routine': [
        {'time': 'Sabah', 'action': 'Jel temizleyici', 'detail': 'Nazikçe', 'step_order': 10},
      ],
      'weather': {'uv_index': 7, 'humidity': 42, 'temperature': 24},
      'weather_source': 'live',
      'environment_advice': [
        {'time': 'Sabah', 'category': 'Koruma', 'icon': '☀️', 'action': 'SPF 50', 'detail': 'UV yüksek', 'priority': 1},
      ],
      'reminders': [
        {
          'id': 'water_intake',
          'title': 'Su içme zamanı',
          'body': 'Günlük hedef 2000 ml.',
          'start': '09:00',
          'end': '21:00',
          'every_minutes': 120,
          'log_event': 'water_intake',
        },
        {'id': 'lip_balm', 'title': 'Dudak balsamı', 'body': '…', 'start': '12:00', 'end': '13:00', 'every_minutes': null, 'log_event': null},
      ],
      'progress': {
        'water_ml_total': 750,
        'spf_refreshes': 1,
        'routine_morning_done': true,
        'makeup': {'logged': true, 'used': true, 'removed': false},
      },
      'checkin_done': true,
    };

Reminder reminder(String id, String start, String end) =>
    Reminder(id: id, title: id, body: '', start: start, end: end);

void main() {
  group('TodayPlan.fromJson', () {
    test('sözleşme örneğini ayrıştırır', () {
      final plan = TodayPlan.fromJson(samplePlan());
      expect(plan.hasRoutine, isTrue);
      expect(plan.routine.single['action'], 'Jel temizleyici');
      expect(plan.weather['uv_index'], 7);
      expect(plan.weatherSource, 'live');
      expect(plan.hasRealWeather, isTrue);
      expect(plan.environmentAdvice.single['action'], 'SPF 50');
      expect(plan.checkinDone, isTrue);

      final water = plan.reminders.first;
      expect(water.id, 'water_intake');
      expect(water.everyMinutes, 120);
      expect(water.logEvent, 'water_intake');
      expect(plan.reminders.last.logEvent, isNull);
      expect(plan.reminders.last.everyMinutes, isNull);

      expect(plan.progress.waterMl, 750);
      expect(plan.progress.waterFraction, closeTo(.375, 1e-9));
      expect(plan.progress.spfRefreshes, 1);
      expect(plan.progress.morningDone, isTrue);
      expect(plan.progress.eveningDone, isFalse);
      expect(plan.progress.makeupUsed, isTrue);
      expect(plan.progress.makeupRemoved, isFalse);
    });

    test('eksik ve bozuk alanlarda çökmez', () {
      final plan = TodayPlan.fromJson({'reminders': ['x', 3, null], 'progress': 'bozuk', 'weather': 5});
      expect(plan.hasRoutine, isFalse);
      expect(plan.reminders, isEmpty);
      expect(plan.progress.waterMl, 0);
      expect(plan.weather, isEmpty);
      expect(plan.weatherSource, 'default');
      expect(plan.hasRealWeather, isFalse);
    });

    test('su çubuğu hedefi aşınca taşmaz', () {
      expect(const DayProgress(waterMl: 3500).waterFraction, 1.0);
    });

    test('withProgress yalnızca ilerlemeyi değiştirir', () {
      final plan = TodayPlan.fromJson(samplePlan());
      final next = plan.withProgress(const DayProgress(waterMl: 1000));
      expect(next.progress.waterMl, 1000);
      expect(next.reminders, same(plan.reminders));
      expect(next.weatherSource, plan.weatherSource);
    });
  });

  group('DayProgress.withEvent', () {
    test('su, rutin, SPF ve beslenme sunucudaki toplama kurallarıyla eklenir', () {
      var p = const DayProgress(waterMl: 500);
      p = p.withEvent('water_intake', {'ml': 250});
      expect(p.waterMl, 750);
      p = p.withEvent('water_intake', {'ml': 'bozuk'});
      expect(p.waterMl, 750, reason: 'geçersiz miktar yok sayılır');
      p = p.withEvent('routine_completed_block', {'morning': true});
      expect(p.morningDone, isTrue);
      expect(p.eveningDone, isFalse);
      p = p.withEvent('routine_completed_block', {'evening': true});
      expect(p.eveningDone, isTrue);
      expect(p.morningDone, isTrue, reason: 'önceki durum silinmez');
      p = p.withEvent('spf_refresh', {}).withEvent('spf_refresh', {'n': 1});
      expect(p.spfRefreshes, 2);
      expect(p.withEvent('nutrition', {'junk_food': true}).nutritionLogged, isTrue);
    });

    test('makyaj: kullandım / temizledim / yöntem', () {
      const base = DayProgress();
      var p = base.withEvent('makeup', {'used': true});
      expect((p.makeupLogged, p.makeupUsed, p.makeupRemoved), (true, true, false));
      p = base.withEvent('makeup', {'used': false});
      expect((p.makeupLogged, p.makeupUsed, p.makeupRemoved), (true, false, false));
      p = base.withEvent('makeup', {'removed': true});
      expect((p.makeupUsed, p.makeupRemoved), (true, true), reason: 'temizlemek, yapılmış olmayı da gerektirir');
      p = base.withEvent('makeup', {'method': 'double'});
      expect((p.makeupUsed, p.makeupRemoved), (true, true));
      p = base.withEvent('makeup', {'method': 'none'});
      expect((p.makeupLogged, p.makeupUsed, p.makeupRemoved), (true, false, false), reason: '"none" temizlenmedi demektir');
    });

    test('bilinmeyen olay ilerlemeyi değiştirmez', () {
      const p = DayProgress(waterMl: 100);
      expect(p.withEvent('photo_meta', {'x': 1}).waterMl, 100);
      expect(p.withEvent('bilinmeyen', {}), same(p));
    });
  });

  group('reminderPhase', () {
    final r = reminder('routine_morning', '07:30', '09:30');

    test('pencere öncesi, içi (uçlar dahil) ve sonrası', () {
      expect(reminderPhase(r, DateTime(2026, 10, 4, 7, 29)), ReminderPhase.upcoming);
      expect(reminderPhase(r, DateTime(2026, 10, 4, 7, 30)), ReminderPhase.now);
      expect(reminderPhase(r, DateTime(2026, 10, 4, 8, 45)), ReminderPhase.now);
      expect(reminderPhase(r, DateTime(2026, 10, 4, 9, 30)), ReminderPhase.now);
      expect(reminderPhase(r, DateTime(2026, 10, 4, 9, 31)), ReminderPhase.past);
    });

    test('bozuk saat biçimi hatırlatıcıyı gizler', () {
      expect(reminderPhase(reminder('x', '7.30', '09:30'), DateTime(2026, 10, 4, 8)), ReminderPhase.past);
      expect(reminderPhase(reminder('x', '07:30', '25:00'), DateTime(2026, 10, 4, 8)), ReminderPhase.past);
    });
  });

  group('reminderActions', () {
    test('rutin blokları sabah / akşam ayrımını taşır', () {
      final morning = reminderActions(reminder('routine_morning', '07:30', '09:30')).single;
      expect(morning.type, 'routine_completed_block');
      expect(morning.payload, {'morning': true});
      final evening = reminderActions(reminder('routine_evening', '21:00', '23:00')).single;
      expect(evening.payload, {'evening': true});
    });

    test('makyaj, su ve beslenme olay yükleri sözleşmeye uyar', () {
      final makeup = reminderActions(reminder('makeup_log', '10:00', '11:00'));
      expect(makeup.map((a) => a.payload), [
        {'used': true},
        {'used': false},
      ]);
      expect(reminderActions(reminder('makeup_removal', '21:00', '23:00')).single.payload, {'removed': true, 'method': 'double'});
      expect(reminderActions(reminder('water_intake', '09:00', '21:00')).map((a) => a.payload), [
        {'ml': 250},
        {'ml': 500},
      ]);
      expect(reminderActions(reminder('nutrition_log', '20:00', '20:30')).map((a) => a.payload), [
        {'junk_food': true},
        {'junk_food': false},
      ]);
      expect(reminderActions(reminder('spf_refresh', '11:00', '16:00')).single.type, 'spf_refresh');
    });

    test('check-in ekrana gider, dudak balsamı eylemsizdir', () {
      expect(reminderActions(reminder('daily_checkin', '21:00', '22:30')).single.route, '/dashboard/checkin');
      expect(reminderActions(reminder('lip_balm', '12:00', '13:00')), isEmpty);
      expect(reminderActions(reminder('bilinmeyen', '12:00', '13:00')), isEmpty);
    });

    test('kayıt eylemlerinin hepsi geçerli bir olay tipi taşır', () {
      const known = {'routine_completed_block', 'makeup', 'water_intake', 'nutrition', 'spf_refresh'};
      for (final id in [
        'routine_morning',
        'routine_evening',
        'makeup_log',
        'makeup_removal',
        'water_intake',
        'spf_refresh',
        'nutrition_log',
      ]) {
        for (final a in reminderActions(reminder(id, '00:00', '23:59'))) {
          expect(known, contains(a.type), reason: id);
        }
      }
    });
  });

  group('UserSnapshot.fromJson', () {
    Map<String, dynamic> sample() => {
          'user_id': 'u1',
          'server_time': '2026-10-04T09:00:00Z',
          'log_date': '2026-10-04',
          'profile': {'skin_type': 'dry'},
          'has_routine': true,
          'routine': [
            {'action': 'SPF'},
          ],
          'progress': {'water_ml_total': 250},
          'checkin_done': false,
          'chat_cursor': 42,
          'consent': {
            'legal_accepted': true,
            'ai_processing_allowed': true,
            'location_processing_allowed': true,
            'photo_processing_allowed': false,
          },
          'plus': true,
          'synced': true,
        };

    test('açılış paketini ayrıştırır', () {
      final s = UserSnapshot.fromJson(sample());
      expect(s.profile['skin_type'], 'dry');
      expect(s.routine.single['action'], 'SPF');
      expect(s.progress.waterMl, 250);
      expect(s.chatCursor, 42);
      expect(s.plus, isTrue);
      expect(s.consent.complete, isTrue);
      expect(s.consent.locationAllowed, isTrue);
      expect(s.consent.photoAllowed, isFalse);
    });

    test('rıza eksikse tamamlanmış sayılmaz', () {
      expect(const ConsentState().complete, isFalse);
      expect(const ConsentState(legalAccepted: true).complete, isFalse);
      expect(const ConsentState(aiAllowed: true).complete, isFalse);
      expect(ConsentState.fromJson({'legal_accepted': true, 'ai_processing_allowed': 'true'}).complete, isFalse,
          reason: 'yalnızca açık true kabul edilir');
    });

    test('synced yalnızca açıkça false ise kapalıdır', () {
      expect(UserSnapshot.fromJson({...sample(), 'synced': false}).synced, isFalse);
      expect(UserSnapshot.fromJson({...sample()}..remove('synced')).synced, isTrue);
    });
  });
}
