import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/core/reminder_settings.dart';
import 'package:rebi/core/today_plan.dart';
import 'package:rebi/core/user_history.dart';
import 'package:rebi/core/user_profile.dart';
import 'package:rebi/core/user_snapshot.dart';

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

    test('kullanıcının hatırlatıcı ayarı', () {
      expect(plan.settings.wakeTime, '07:00');
      expect(plan.settings.sleepTime, '23:00');
      expect(plan.settings.waterEveryMinutes, 90);
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
        final local = reminderWindow(r.id, plan.settings);
        expect(local, isNotNull, reason: r.id);
        expect(local!.start, r.start, reason: '${r.id} başlangıç');
        expect(local.end, r.end, reason: '${r.id} bitiş');
      }
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

  test('GET /me/reminder-settings', () {
    final body = contract('reminder_settings');
    final settings = ReminderSettings.fromJson(body['settings']);

    expect(settings.wakeTime, '07:00');
    expect(settings.sleepTime, '23:00');
    expect(settings.waterEveryMinutes, 90);
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
