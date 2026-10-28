import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/core/api.dart';
import 'package:rebi/core/user_history.dart';
import 'package:rebi/core/user_profile.dart';

import 'helpers/app_harness.dart';

Map<String, dynamic> day(
  String date, {
  int events = 1,
  Map<String, dynamic> tracking = const {},
  Map<String, dynamic>? checkin,
}) =>
    {
      'log_date': date,
      'tracking': {'events_count': events, ...tracking},
      'checkin': ?checkin,
    };

void main() {
  group('UserProfile', () {
    test('sunucu yanıtını ayrıştırır, boş metinleri null yapar', () {
      final p = UserProfile.fromJson({
        'full_name': ' Ayşe ',
        'skin_type': 'dry',
        'age': 29,
        'gender': 'female',
        'city': '   ',
        'updated_at': '2026-10-01T10:00:00Z',
        'synced': true,
      });
      expect(p.fullName, 'Ayşe');
      expect(p.skinType, 'dry');
      expect(p.age, 29);
      expect(p.gender, 'female');
      expect(p.city, isNull);
      expect(p.synced, isTrue);
    });

    test('eksik ve bozuk alanlarda çökmez', () {
      final p = UserProfile.fromJson({'age': 'abc', 'synced': false});
      expect(p.age, isNull);
      expect(p.skinType, isNull);
      expect(p.synced, isFalse);
      expect(UserProfile.fromJson({'age': '31'}).age, 31);
      expect(UserProfile.fromJson({'age': 31.0}).age, 31);
    });

    test('sunucunun kabul ettiği değer kümeleri', () {
      expect(UserProfile.skinTypes, ['normal', 'dry', 'oily', 'combination', 'sensitive']);
      expect(UserProfile.genders, ['female', 'male', 'other']);
    });
  });

  group('isInvalidAge', () {
    test('boş geçerlidir (değişiklik yok); sınırlar dahil 13–100 geçerlidir', () {
      expect(isInvalidAge(''), isFalse);
      expect(isInvalidAge('  '), isFalse);
      expect(isInvalidAge('13'), isFalse);
      expect(isInvalidAge('100'), isFalse);
      expect(isInvalidAge('29'), isFalse);
    });

    test('aralık dışı ve sayı olmayanlar geçersizdir', () {
      expect(isInvalidAge('12'), isTrue);
      expect(isInvalidAge('101'), isTrue);
      expect(isInvalidAge('0'), isTrue);
      expect(isInvalidAge('abc'), isTrue);
      expect(isInvalidAge('-5'), isTrue);
      expect(isInvalidAge('29.5'), isTrue);
    });
  });

  group('ProfileUpdate', () {
    test('yalnızca verilen alanlar gövdeye girer', () {
      expect(const ProfileUpdate(city: 'Ankara').toBody('u1'), {'user_id': 'u1', 'city': 'Ankara'});
      expect(const ProfileUpdate(skinType: 'oily', age: 30, gender: 'male', fullName: 'A').toBody('u1'), {
        'user_id': 'u1',
        'full_name': 'A',
        'skin_type': 'oily',
        'age': 30,
        'gender': 'male',
      });
    });

    test('boş şehir metni şehri temizlemek için gönderilir', () {
      final update = const ProfileUpdate(city: '');
      expect(update.isEmpty, isFalse);
      expect(update.toBody('u1')['city'], '');
    });

    test('hiç alan yoksa boştur', () => expect(const ProfileUpdate().isEmpty, isTrue));
  });

  group('profil uçları', () {
    late FakeBackend backend;
    setUp(() {
      backend = FakeBackend();
      apiHttpClient = backend.client;
    });

    test('fetchMyProfile kullanıcıyı sorgu parametresiyle ister', () async {
      final p = await fetchMyProfile(testUserId);
      expect(p!.skinType, 'dry');
      expect(backend.calls('/me/profile').single.url.queryParameters, {'user_id': testUserId});
    });

    test('fetchMyProfile hatada null döner', () async {
      backend.profileFails = true;
      expect(await fetchMyProfile(testUserId), isNull);
    });

    test('updateMyProfile PATCH gönderir ve güncel profili döndürür', () async {
      final r = await updateMyProfile(testUserId, const ProfileUpdate(skinType: 'oily', age: 31));
      expect(r.ok, isTrue);
      expect(r.profile!.skinType, 'oily');
      expect(r.profile!.age, 31);
      final call = backend.calls('/me/profile').single;
      expect(call.method, 'PATCH');
      expect(call.headers['Content-Type'], contains('application/json'));
      expect(backend.bodyOf('/me/profile'), {'user_id': testUserId, 'skin_type': 'oily', 'age': 31});
    });

    test('boş güncellemede istek atılmaz', () async {
      final r = await updateMyProfile(testUserId, const ProfileUpdate());
      expect(r.ok, isFalse);
      expect(backend.requests, isEmpty);
    });

    test('sunucu hata ayrıntısını döndürür', () async {
      backend
        ..profilePatchStatus = 422
        ..profilePatchDetail = 'Yaş geçersiz.';
      final r = await updateMyProfile(testUserId, const ProfileUpdate(age: 20));
      expect(r.ok, isFalse);
      expect(r.error, 'Yaş geçersiz.');
      expect(r.networkError, isFalse);
    });

    test('bağlantı hatası networkError olarak işaretlenir', () async {
      backend.profileOffline = true;
      final r = await updateMyProfile(testUserId, const ProfileUpdate(city: 'İzmir'));
      expect(r.ok, isFalse);
      expect(r.networkError, isTrue);
    });
  });

  group('UserHistory', () {
    test('günler en yeni başta sıralanır, verisiz günler elenir', () {
      final h = UserHistory.fromJson({
        'days': [
          day('2026-10-08', tracking: {'water_ml_total': 500}),
          day('2026-10-10', tracking: {'water_ml_total': 750}),
          day('2026-10-09', events: 0),
          day('2026-10-07', events: 0, checkin: {'skin_feeling': 'iyi'}),
        ],
        'synced': true,
      });
      expect(h.days.map((d) => d.logDate), ['2026-10-10', '2026-10-08', '2026-10-07']);
      expect(h.days.first.tracking.progress.waterMl, 750);
      expect(h.synced, isTrue);
    });

    test('check-in alanlarını ayrıştırır', () {
      final h = UserHistory.fromJson({
        'days': [
          day('2026-10-10', events: 0, checkin: {'skin_feeling': 'kuru', 'sleep_hours': 6.5, 'stress_level': 4, 'risk_score': 38}),
        ],
      });
      final c = h.days.single.checkin!;
      expect(c.skinFeeling, 'kuru');
      expect(c.sleepHours, 6.5);
      expect(c.stressLevel, 4);
      expect(c.riskScore, 38);
    });

    test('gün içi toplamdan makyaj, SPF, rutin, abur cubur ve ürünleri okur', () {
      final h = UserHistory.fromJson({
        'days': [
          day('2026-10-10', tracking: {
            'spf_refreshes': 2,
            'routine_morning_done': true,
            'routine_evening_done': false,
            'nutrition': {'junk_food': true},
            'products_finished': [
              {'product': 'SPF 50'},
              {'product': 'Nemlendirici'},
            ],
            'makeup': {'logged': true, 'used': true, 'removed': true},
          }),
        ],
      });
      final t = h.days.single.tracking;
      expect(t.progress.spfRefreshes, 2);
      expect(t.progress.morningDone, isTrue);
      expect(t.progress.eveningDone, isFalse);
      expect(t.progress.makeupUsed, isTrue);
      expect(t.progress.makeupRemoved, isTrue);
      expect(t.junkFood, isTrue);
      expect(t.productsFinished, 2);
    });

    test('analizleri ayrıştırır', () {
      final h = UserHistory.fromJson({
        'assessments': [
          {'id': 'a1', 'concern': 'acne', 'severity_score': 6, 'created_at': '2026-10-01T10:00:00Z'},
          {'concern': 'dryness'},
        ],
      });
      expect(h.assessments.map((a) => a.concern), ['acne', 'dryness']);
      expect(h.assessments.first.severityScore, 6);
      expect(h.assessments.first.createdAt, isNotNull);
      expect(h.assessments.last.createdAt, isNull);
    });

    test('bozuk yanıtta çökmez', () {
      final h = UserHistory.fromJson({
        'days': ['x', 5, null, {'tracking': 'bozuk'}],
        'assessments': 'bozuk',
        'synced': false,
      });
      expect(h.days, isEmpty);
      expect(h.assessments, isEmpty);
      expect(h.synced, isFalse);
    });
  });

  group('summarizeHistory', () {
    test('ortalamaları yalnızca verisi olan günlerden hesaplar', () {
      final days = UserHistory.fromJson({
        'days': [
          day('2026-10-10', tracking: {
            'water_ml_total': 1000,
            'routine_morning_done': true,
            'routine_evening_done': true,
          }, checkin: {'sleep_hours': 7, 'risk_score': 20}),
          day('2026-10-09', tracking: {'water_ml_total': 2000, 'routine_morning_done': true}, checkin: {'sleep_hours': 6, 'risk_score': 40}),
          day('2026-10-08', tracking: {'water_ml_total': 0, 'sleep_hours': 8}),
        ],
      }).days;
      final s = summarizeHistory(days);
      expect(s.recordedDays, 3);
      expect(s.checkins, 2);
      expect(s.fullRoutineDays, 1, reason: 'yalnızca sabah+akşam birlikte olan gün');
      expect(s.avgWaterMl, 1500, reason: 'su kaydı olmayan gün ortalamayı düşürmez');
      expect(s.avgSleepHours, 7.0, reason: 'check-in yoksa gün içi uyku kaydı kullanılır: (7+6+8)/3');
      expect(s.avgRiskScore, 30);
    });

    test('hiç veri yoksa ortalamalar null', () {
      final s = summarizeHistory(const []);
      expect(s.recordedDays, 0);
      expect(s.avgWaterMl, isNull);
      expect(s.avgSleepHours, isNull);
      expect(s.avgRiskScore, isNull);
    });
  });

  group('fetchHistory', () {
    late FakeBackend backend;
    setUp(() {
      backend = FakeBackend();
      apiHttpClient = backend.client;
    });

    test('gün sayısı sunucu sınırlarına (1–90) kırpılır', () async {
      await fetchHistory(testUserId, days: 500);
      expect(backend.calls('/me/history').last.url.queryParameters['days'], '90');
      await fetchHistory(testUserId, days: 0);
      expect(backend.calls('/me/history').last.url.queryParameters['days'], '1');
      await fetchHistory(testUserId);
      expect(backend.calls('/me/history').last.url.queryParameters['days'], '30');
      expect(backend.calls('/me/history').last.url.queryParameters['user_id'], testUserId);
    });

    test('hatada null döner', () async {
      backend.historyFails = true;
      expect(await fetchHistory(testUserId), isNull);
    });
  });
}
