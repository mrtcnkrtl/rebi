import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/core/reminder_schedule.dart';
import 'package:rebi/core/reminder_settings.dart';
import 'package:rebi/core/today_plan.dart';
import 'package:rebi/core/user_history.dart';
import 'package:rebi/core/user_profile.dart';
import 'package:rebi/core/user_snapshot.dart';
import 'package:rebi/core/weather_decisions.dart';

/// Backend sözleşmesi (`../contract/*.json`): fixture'lar sunucunun gerçek yanıtlarından üretilir
/// (`backend/tests/test_contract.py`) ve backend testi yanıtların bu şekli koruduğunu doğrular.
/// Burada aynı dosyalar mobilin gerçek ayrıştırıcılarından geçer. Ayrıştırıcılar hoşgörülüdür
/// (alan yoksa varsayılana düşer), bu yüzden değerler tek tek doğrulanır: bir alanın adı ya da
/// türü değişirse ekran sessizce "0" göstermek yerine bu test kırılır.
///
/// Sahne (backend `_seed`): 750 ml su, makyaj yapıldı/temizlenmedi, abur cubur, 1 SPF tazeleme,
/// SPF ürünü bitti, sabah 10 ve 30. adımlar işaretli, gün düzeni 07:00–23:00, su 90 dk, beslenme kapalı.
Map<String, dynamic> contract(String name) =>
    jsonDecode(File('../contract/$name.json').readAsStringSync()) as Map<String, dynamic>;

void main() {
  test('contract klasörü bulunuyor ve boş değil', () {
    final files = Directory('../contract').listSync().where((f) => f.path.endsWith('.json')).toList();
    expect(files.length, greaterThanOrEqualTo(6));
  });

  group('GET /today/plan', () {
    final plan = TodayPlan.fromJson(contract('today_plan'));

    test('rutin, hava ve öneriler', () {
      expect(plan.hasRoutine, isTrue);
      expect(plan.routine, hasLength(4));
      expect(plan.weatherSource, 'tracking');
      expect(plan.weather['uv_index'], 6);
      expect(plan.weather['temperature'], 18);
      expect(plan.hasRealWeather, isTrue);
      expect(plan.environmentAdvice, isNotEmpty);
      expect(plan.checkinDone, isTrue);
    });

    test('bugünün ilerlemesi', () {
      final p = plan.progress;
      expect(p.waterMl, 750);
      expect(p.stepsDone['morning'], {10, 30});
      expect(p.stepsDone['evening'], isEmpty);
      expect(p.spfRefreshes, 1);
      expect(p.makeupLogged, isTrue);
      expect(p.makeupUsed, isTrue);
      expect(p.makeupRemoved, isFalse);
      expect(p.nutritionLogged, isTrue);
      expect(p.nutrition['junk_food'], isTrue);
      expect(p.finishedProducts, ['SPF 50 (geniş spektrumlu)']);
      expect(p.morningDone, isFalse);
    });

    test('kullanıcının kendi saat aralığı ve sessiz saatleri', () {
      expect(plan.settings.windows.keys, ['routine_evening']);
      expect(plan.settings.windows['routine_evening'], const ClockRange('21:30', '22:30'));
      expect(plan.settings.quiet, const ClockRange('13:00', '14:00'));
      final evening = plan.reminders.firstWhere((r) => r.id == 'routine_evening');
      expect((evening.start, evening.end), ('21:30', '22:30'), reason: 'sunucu kendi penceresiyle üretti');
      expect(reminderWindow('routine_evening', plan.settings), (start: '21:30', end: '22:30'));
    });

    test('kullanıcının hatırlatıcı ayarı', () {
      expect(plan.settings.wakeTime, '07:00');
      expect(plan.settings.sleepTime, '23:00');
      expect(plan.settings.waterEveryMinutes, 90);
      expect(plan.settings.waterTargetMl, 2500);
      expect(plan.waterTarget, 2500);
      expect(plan.settings.isEnabled('nutrition'), isFalse);
      expect(plan.settings.isEnabled('water'), isTrue);
    });

    test('hatırlatıcılar ayara uyar ve kapatılan kategori gelmez', () {
      final ids = plan.reminders.map((r) => r.id).toList();
      expect(ids, containsAll(['routine_morning', 'water_intake', 'spf_refresh', 'routine_evening']));
      expect(ids, isNot(contains('nutrition_log')));

      final water = plan.reminders.firstWhere((r) => r.id == 'water_intake');
      expect(water.everyMinutes, 90);
      expect(water.logEvent, 'water_intake');
    });

    test('mobilin yerel pencere hesabı sunucununkiyle aynı (bildirimler sunucudan sapmasın)', () {
      for (final r in plan.reminders) {
        // Güneş kremi penceresi gerçek saatlik UV'ye bağlıdır; ayardan türetilen sabit pencere değil (aşağıda ayrıca denetlenir).
        if (r.id == 'spf_refresh') continue;
        final local = reminderWindow(r.id, plan.settings);
        expect(local, isNotNull, reason: r.id);
        expect(local!.start, r.start, reason: '${r.id} başlangıç');
        expect(local.end, r.end, reason: '${r.id} bitiş');
      }
    });

    test('güneş kremi hatırlatması gerçek UV penceresine oturur', () {
      final window = plan.decisions!.spf.window!;
      final spf = plan.reminders.firstWhere((r) => r.id == 'spf_refresh');
      expect(spf.start, window.start);
      expect(spf.end, window.end);
      expect(spf.everyMinutes, 120);
    });

    test('Rafım: biten ürünler sözleşmedeki alanlarla okunur', () {
      final shelf = plan.productsOut.single;
      expect(shelf.product, 'SPF 50 (geniş spektrumlu)');
      expect(shelf.stepOrder, 40);
      expect(shelf.daysOut, 0);
      expect(shelf.finishedAt, isNotNull);
      expect(plan.isOut('spf 50 (geniş   spektrumlu)'), isTrue);
      expect(plan.settings.isEnabled('restock'), isTrue, reason: 'yeni hatırlatıcı kategorisi sunucuyla aynı');
    });

    test('havaya göre üç karar', () {
      final d = plan.decisions!;
      expect(d.spf.spf, '50');
      expect(d.spf.level, 'high');
      expect(d.spf.uv, 6);
      expect(d.spf.refresh, isTrue);
      expect(d.spf.refreshEveryMinutes, 120);
      expect((d.spf.window!.start, d.spf.window!.end, d.spf.window!.peak), ('11:00', '16:00', '13:00'));
      expect(d.moisture.kind, 'boost');
      expect(d.moisture.humidity, 38);
      expect(d.moisture.nightMask, isFalse);
      expect(d.lipBalm.needed, isFalse);
      expect(d.lipBalm.reason, isNull);
    });

    test('eski sunucu (weather_decisions yok) kararları null bırakır, ekran öneri listesine düşer', () {
      final old = Map<String, dynamic>.of(contract('today_plan'))..remove('weather_decisions');
      expect(TodayPlan.fromJson(old).decisions, isNull);
      expect(WeatherDecisions.fromJson({'spf': {}}), isNull, reason: 'yarım veri de geçersiz sayılır');
    });
  });

  group('GET /me/snapshot', () {
    final s = UserSnapshot.fromJson(contract('me_snapshot'));

    test('profil, rutin, rıza ve sohbet imleci', () {
      expect(s.userId, isNotEmpty);
      expect(s.logDate, isNotEmpty);
      expect(s.profile['skin_type'], 'oily');
      expect(s.hasRoutine, isTrue);
      expect(s.routine, hasLength(4));
      expect(s.checkinDone, isTrue);
      expect(s.chatCursor, 1);
      expect(s.plus, isFalse);
      expect(s.synced, isTrue);
    });

    test('rıza durumu tamam sayılır', () {
      expect(s.consent.legalAccepted, isTrue);
      expect(s.consent.aiAllowed, isTrue);
      expect(s.consent.locationAllowed, isTrue);
      expect(s.consent.photoAllowed, isTrue);
      expect(s.consent.complete, isTrue);
    });

    test('bugünün ilerlemesi plan ile aynı biçimde okunur', () {
      expect(s.progress.waterMl, 750);
      expect(s.progress.stepsDone['morning'], {10, 30});
      expect(s.progress.finishedProducts, hasLength(1));
    });
  });

  test('yuva kuralı: sunucudaki _slots ile mobildeki reminderSlots aynı girdiden aynı dakikaları üretir', () {
    final cases = contract('reminder_slots')['cases'] as List;
    expect(cases.length, greaterThanOrEqualTo(10));
    for (final raw in cases) {
      final c = raw as Map<String, dynamic>;
      final reminder = (c['reminder'] as Map).cast<String, dynamic>();
      final quiet = ClockRange.tryParse(c['quiet']);
      final slots = reminderSlots(
        Reminder(
          id: 'x',
          title: '',
          body: '',
          start: '${reminder['start']}',
          end: '${reminder['end']}',
          everyMinutes: reminder['every_minutes'] as int?,
        ),
        quiet: quiet,
      );
      expect(slots, (c['slots'] as List).cast<int>(), reason: '${c['name']}');
    }
  });

  test('GET /me/reminder-settings', () {
    final body = contract('reminder_settings');
    final settings = ReminderSettings.fromJson(body['settings']);
    expect(settings.windows['routine_evening'], const ClockRange('21:30', '22:30'));
    expect(settings.quiet, const ClockRange('13:00', '14:00'));

    expect(settings.wakeTime, '07:00');
    expect(settings.sleepTime, '23:00');
    expect(settings.waterEveryMinutes, 90);
    expect(settings.waterTargetMl, 2500);
    expect(settings.isEnabled('nutrition'), isFalse);
    expect(body['synced'], isTrue);
    for (final category in reminderCategories) {
      expect((body['settings']['enabled'] as Map).containsKey(category), isTrue, reason: category);
    }
  });

  test('GET /me/profile', () {
    final p = UserProfile.fromJson(contract('me_profile'));

    expect(p.fullName, 'Ayşe Yılmaz');
    expect(p.skinType, 'oily');
    expect(p.age, 29);
    expect(p.gender, 'female');
    expect(p.city, 'İstanbul');
    expect(p.synced, isTrue);
  });

  test('GET /me/history', () {
    final h = UserHistory.fromJson(contract('me_history'));

    expect(h.synced, isTrue);
    expect(h.waterTargetMl, 2500, reason: 'kullanıcının su hedefi (sahnede 2500 ml); grafik ve hedef günleri bununla hesaplanır');
    expect(h.assessments.single.concern, 'acne');
    expect(h.assessments.single.severityScore, 4);
    expect(h.days, hasLength(2));
    // En yeni gün başta.
    final today = h.days.first;
    expect(today.tracking.progress.waterMl, 750);
    expect(today.tracking.junkFood, isTrue);
    expect(today.tracking.productsFinished, 1);
    expect(today.checkin, isNotNull);
    expect(h.days.last.tracking.progress.waterMl, 500);
    expect(h.days.last.checkin, isNull);
  });

  test('POST /daily_tracking/ingest yanıtındaki aggregated aynı ilerleme biçimidir', () {
    final body = contract('daily_tracking_ingest');
    final progress = DayProgress.fromJson(body['aggregated']);

    expect(body['ok'], isTrue);
    expect(body['log_date'], isNotEmpty);
    expect(progress.waterMl, 1000); // günün toplamı: 750 + 250
  });
}
