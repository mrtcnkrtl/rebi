import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/core/routine_tracking.dart';
import 'package:rebi/ui/components/profile_details_card.dart';

import 'helpers/app_harness.dart';

/// Profil bilgileri (`GET/PATCH /me/profile`) ve geçmiş ekranı (`GET /me/history`).
void main() {
  final routine = routineFixture['routine'] as List;

  Map<String, Object> acceptedPrefs() => {
        trackAcceptedKey(testUserId): '1',
        trackSnapshotKey(testUserId): jsonEncode({
          'routine': routine,
          'userName': 'Ayşe Test',
          'weather': routineFixture['weather'],
          'flowDebug': routineFixture['flow_debug'],
          'acceptedAt': DateTime.now().millisecondsSinceEpoch - 3 * 86400000,
        }),
      };

  Map<String, dynamic> day(String date, {Map<String, dynamic> tracking = const {}, Map<String, dynamic>? checkin}) => {
        'log_date': date,
        'tracking': {'events_count': 1, ...tracking},
        'checkin': ?checkin,
      };

  group('profil kartı', () {
    Future<FakeBackend> pumpCard(WidgetTester tester, {FakeBackend? backend, String lang = 'tr', Size? size}) =>
        pumpStandalone(tester, (theme) => ProfileDetailsCard(theme: theme), backend: backend, lang: lang, size: size ?? const Size(390, 844));

    List<TextField> fields(WidgetTester tester) => tester.widgetList<TextField>(find.byType(TextField)).toList();

    testWidgets('mevcut profili sunucudan yükleyip gösterir', (tester) async {
      final backend = await pumpCard(tester);
      expect(backend.calls('/me/profile').single.method, 'GET');
      expect(backend.calls('/me/profile').single.url.queryParameters['user_id'], testUserId);
      expect(find.text(tr('mobileProfile.title')), findsOneWidget);
      final f = fields(tester);
      expect(f[0].controller!.text, '29', reason: 'yaş');
      expect(f[1].controller!.text, 'İstanbul', reason: 'şehir');
    });

    testWidgets('değişiklik yoksa istek atılmaz', (tester) async {
      final backend = await pumpCard(tester);
      await tapText(tester, tr('mobileProfile.save'));
      expect(find.text(tr('mobileProfile.nothingChanged')), findsOneWidget);
      expect(backend.calls('/me/profile').where((r) => r.method == 'PATCH'), isEmpty);
    });

    testWidgets('yalnızca değişen alan gönderilir', (tester) async {
      final backend = await pumpCard(tester);
      await tester.enterText(find.byType(TextField).last, 'Ankara');
      await tapText(tester, tr('mobileProfile.save'));
      await settle(tester);

      final patch = backend.calls('/me/profile').where((r) => r.method == 'PATCH').single;
      expect(jsonDecode(patch.body), {'user_id': testUserId, 'city': 'Ankara'});
      expect(find.text(tr('mobileProfile.saved')), findsOneWidget);
      expect(backend.profile['city'], 'Ankara');
    });

    testWidgets('yaş, cinsiyet ve cilt tipi değişince hepsi birlikte gider', (tester) async {
      final backend = await pumpCard(tester);
      await tester.enterText(find.byType(TextField).first, '34');
      await tapText(tester, packS('gender.male'));
      await tapText(tester, packS('skinPicker.oily.label'));
      await tapText(tester, tr('mobileProfile.save'));
      await settle(tester);

      final patch = jsonDecode(backend.calls('/me/profile').where((r) => r.method == 'PATCH').single.body) as Map;
      expect(patch, {'user_id': testUserId, 'skin_type': 'oily', 'age': 34, 'gender': 'male'});
      expect(find.text(tr('mobileProfile.saved')), findsOneWidget);
    });

    testWidgets('şehir silinince boş metinle temizlenir', (tester) async {
      final backend = await pumpCard(tester);
      await tester.enterText(find.byType(TextField).last, '');
      await tapText(tester, tr('mobileProfile.save'));
      await settle(tester);
      final patch = jsonDecode(backend.calls('/me/profile').where((r) => r.method == 'PATCH').single.body) as Map;
      expect(patch, {'user_id': testUserId, 'city': ''});
    });

    testWidgets('geçersiz yaş gönderilmez ve uyarı çıkar', (tester) async {
      final backend = await pumpCard(tester);
      await tester.enterText(find.byType(TextField).first, '9');
      await settle(tester, 3);
      expect(find.text(tr('mobileProfile.ageInvalid')), findsOneWidget, reason: 'yazarken satır içi uyarı');

      await tapText(tester, tr('mobileProfile.save'));
      expect(backend.calls('/me/profile').where((r) => r.method == 'PATCH'), isEmpty);
      expect(find.text(tr('mobileProfile.ageInvalid')), findsWidgets);
    });

    testWidgets('yaş alanı yalnızca rakam kabul eder', (tester) async {
      await pumpCard(tester);
      await tester.enterText(find.byType(TextField).first, '3a4');
      expect(fields(tester).first.controller!.text, '34');
    });

    testWidgets('sunucu reddederse hata metni gösterilir ve alanlar korunur', (tester) async {
      final backend = FakeBackend()
        ..profilePatchStatus = 422
        ..profilePatchDetail = 'Şehir geçersiz.';
      await pumpCard(tester, backend: backend);
      await tester.enterText(find.byType(TextField).last, 'Ankara');
      await tapText(tester, tr('mobileProfile.save'));
      await settle(tester);
      expect(find.text('Şehir geçersiz.'), findsOneWidget);
      expect(fields(tester).last.controller!.text, 'Ankara', reason: 'yazdığın kaybolmaz');
    });

    testWidgets('bağlantı yokken kaydetme anlaşılır uyarı verir', (tester) async {
      final backend = await pumpCard(tester);
      backend.profileOffline = true;
      await tester.enterText(find.byType(TextField).last, 'Ankara');
      await tapText(tester, tr('mobileProfile.save'));
      await settle(tester);
      expect(find.text(tr('mobileProfile.saveFailed')), findsOneWidget);
      expect(find.text(tr('mobileProfile.saved')), findsNothing);
    });

    testWidgets('yükleme başarısızsa uyarı ve tekrar dene çıkar, tekrar denenince form gelir', (tester) async {
      final backend = FakeBackend()..profileFails = true;
      await pumpCard(tester, backend: backend);
      expect(find.text(tr('mobileProfile.loadFailed')), findsOneWidget);
      expect(find.text(tr('mobileProfile.save')), findsNothing);

      backend.profileFails = false;
      await tapText(tester, tr('mobileProfile.retry'));
      await settle(tester);
      expect(find.text(tr('mobileProfile.loadFailed')), findsNothing);
      expect(find.text(tr('mobileProfile.save')), findsOneWidget);
    });

    testWidgets('sunucu profili saklamıyorsa (synced=false) uyarı verir ve kaydedildi demez', (tester) async {
      final backend = FakeBackend()..profileSynced = false;
      await pumpCard(tester, backend: backend);
      expect(find.text(tr('mobileProfile.notSynced')), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, 'Ankara');
      await tapText(tester, tr('mobileProfile.save'));
      await settle(tester);
      expect(find.text(tr('mobileProfile.saved')), findsNothing);
    });

    testWidgets('İngilizce arayüzde çevrilir', (tester) async {
      await pumpCard(tester, lang: 'en');
      expect(find.text('My skin profile'), findsOneWidget);
      expect(find.text('Save profile'), findsOneWidget);
    });

    testWidgets('320 genişlikte taşmaz', (tester) async {
      await pumpCard(tester, size: const Size(320, 568));
      await tester.enterText(find.byType(TextField).first, '9');
      await settle(tester, 3);
      expect(tester.takeException(), isNull);
    });
  });

  group('geçmiş ekranı', () {
    FakeBackend withHistory(List<Map<String, dynamic>> days, {List<Map<String, dynamic>> assessments = const [], bool synced = true}) {
      final b = FakeBackend();
      b.history = {...b.history, 'days': days, 'assessments': assessments, 'synced': synced};
      return b;
    }

    testWidgets('günler en yeni başta, özet ve etiketlerle listelenir', (tester) async {
      final backend = withHistory([
        day('2026-10-08', tracking: {'water_ml_total': 500}),
        day('2026-10-10', tracking: {
          'water_ml_total': 1500,
          'spf_refreshes': 2,
          'routine_morning_done': true,
          'routine_evening_done': true,
          'nutrition': {'junk_food': true},
          'products_finished': [
            {'product': 'SPF'},
          ],
          'makeup': {'logged': true, 'used': true, 'removed': true},
        }, checkin: {'skin_feeling': 'kuru', 'sleep_hours': 6.5, 'stress_level': 4, 'risk_score': 38}),
      ]);
      final h = await pumpApp(tester, location: '/dashboard/history', prefs: acceptedPrefs(), backend: backend);

      expect(h.backend.calls('/me/history').single.url.queryParameters, {
        'user_id': testUserId,
        'days': '30',
        'utc_offset_minutes': '${DateTime.now().timeZoneOffset.inMinutes}',
      });
      expect(find.text(tr('mobileHistory.title')), findsOneWidget);

      // Özet
      expect(find.text(tr('mobileHistory.summary.recordedDays', {'n': 2})), findsOneWidget);
      expect(find.text(tr('mobileHistory.summary.checkins', {'n': 1})), findsOneWidget);
      expect(find.text(tr('mobileHistory.summary.fullRoutine', {'n': 1})), findsOneWidget);
      expect(find.text(tr('mobileHistory.summary.avgWater', {'ml': 1000})), findsOneWidget);

      // Sıra: 10 Ekim, 8 Ekim'den önce
      final dayTitles = find.textContaining('Ekim');
      expect(dayTitles, findsWidgets);
      final y10 = tester.getTopLeft(find.textContaining('10 Ekim')).dy;
      final y8 = tester.getTopLeft(find.textContaining('8 Ekim')).dy;
      expect(y10, lessThan(y8), reason: 'en yeni gün üstte');

      // Etiketler
      expect(find.text(tr('mobileHistory.chips.water', {'ml': 1500})), findsOneWidget);
      expect(find.text(tr('mobileHistory.chips.spf', {'n': 2})), findsOneWidget);
      expect(find.text(tr('mobileHistory.chips.morning')), findsOneWidget);
      expect(find.text(tr('mobileHistory.chips.evening')), findsOneWidget);
      expect(find.text(tr('mobileHistory.chips.makeupRemoved')), findsOneWidget);
      expect(find.text(tr('mobileHistory.chips.junk')), findsOneWidget);
      expect(find.text(tr('mobileHistory.chips.products', {'n': 1})), findsOneWidget);

      // Check-in satırı
      expect(
        find.text('${tr('mobileHistory.checkin.title')} · Kuru · ${tr('mobileHistory.checkin.sleep', {'h': 6.5})} · '
            '${tr('mobileHistory.checkin.stress', {'n': 4})} · ${tr('mobileHistory.checkin.risk', {'n': 38})}'),
        findsOneWidget,
      );
    });

    testWidgets('son analizler çevrilmiş şikâyet adıyla listelenir', (tester) async {
      final backend = withHistory([
        day('2026-10-10', tracking: {'water_ml_total': 250}),
      ], assessments: [
        {'id': 'a1', 'concern': 'acne', 'severity_score': 6, 'created_at': '2026-10-01T10:00:00Z'},
      ]);
      await pumpApp(tester, location: '/dashboard/history', prefs: acceptedPrefs(), backend: backend);
      expect(find.text(tr('mobileHistory.assessmentsTitle')), findsOneWidget);
      expect(find.text('${packS('concern.acne')} · ${tr('mobileHistory.severity', {'n': 6})}'), findsOneWidget);
    });

    testWidgets('aralık değişince yeni gün sayısıyla yeniden istenir', (tester) async {
      final h = await pumpApp(tester, location: '/dashboard/history', prefs: acceptedPrefs());
      await tapText(tester, tr('mobileHistory.range7'));
      await settle(tester);
      await tapText(tester, tr('mobileHistory.range90'));
      await settle(tester);
      final days = h.backend.calls('/me/history').map((r) => r.url.queryParameters['days']).toList();
      expect(days, ['30', '7', '90']);
    });

    testWidgets('aynı aralığa tekrar dokunmak yeni istek atmaz', (tester) async {
      final h = await pumpApp(tester, location: '/dashboard/history', prefs: acceptedPrefs());
      await tapText(tester, tr('mobileHistory.range30'));
      expect(h.backend.calls('/me/history'), hasLength(1));
    });

    testWidgets('kayıt yoksa boş durum gösterilir', (tester) async {
      await pumpApp(tester, location: '/dashboard/history', prefs: acceptedPrefs());
      expect(find.text(tr('mobileHistory.empty')), findsOneWidget);
    });

    testWidgets('yükleme başarısızsa uyarı çıkar, tekrar denenince liste gelir', (tester) async {
      final backend = withHistory([
        day('2026-10-10', tracking: {'water_ml_total': 250}),
      ])
        ..historyFails = true;
      final h = await pumpApp(tester, location: '/dashboard/history', prefs: acceptedPrefs(), backend: backend);
      expect(find.text(tr('mobileHistory.loadFailed')), findsOneWidget);

      h.backend.historyFails = false;
      await tapText(tester, tr('mobileHistory.retry'));
      await settle(tester);
      expect(find.text(tr('mobileHistory.loadFailed')), findsNothing);
      expect(find.text(tr('mobileHistory.chips.water', {'ml': 250})), findsOneWidget);
    });

    testWidgets('sunucu kayıt tutmuyorsa (synced=false) bilgi notu gösterilir', (tester) async {
      await pumpApp(tester, location: '/dashboard/history', prefs: acceptedPrefs(), backend: withHistory(const [], synced: false));
      expect(find.text(tr('mobileHistory.notSynced')), findsOneWidget);
    });

    testWidgets('giriş yapmamış kullanıcı girişe yönlendirilir', (tester) async {
      final h = await pumpApp(tester, location: '/dashboard/history', loggedIn: false);
      expect(h.router.state.uri.path, '/auth');
      expect(h.router.state.uri.queryParameters['next'], '/dashboard/history');
    });

    testWidgets('panelden açılır', (tester) async {
      final h = await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs());
      await tapText(tester, tr('mobileHistory.open'));
      await settle(tester);
      expect(h.router.state.uri.path, '/dashboard/history');
      expect(find.text(tr('mobileHistory.title')), findsOneWidget);
    });

    testWidgets('İngilizce arayüzde çevrilir', (tester) async {
      final backend = withHistory([
        day('2026-10-10', tracking: {'water_ml_total': 250}, checkin: {'skin_feeling': 'irritasyon'}),
      ]);
      await pumpApp(tester, location: '/dashboard/history', prefs: acceptedPrefs(), backend: backend, lang: 'en');
      expect(find.text('My history'), findsOneWidget);
      expect(find.text('250 ml water'), findsOneWidget);
      expect(find.textContaining('Irritated'), findsOneWidget);
    });

    testWidgets('320 genişlikte uzun içerik taşmaz', (tester) async {
      final backend = withHistory([
        day('2026-10-10', tracking: {
          'water_ml_total': 2750,
          'spf_refreshes': 3,
          'routine_morning_done': true,
          'routine_evening_done': true,
          'nutrition': {'junk_food': true},
          'products_finished': [
            {'product': 'a'},
            {'product': 'b'},
            {'product': 'c'},
          ],
          'makeup': {'logged': true, 'used': true, 'removed': true},
        }, checkin: {'skin_feeling': 'irritasyon', 'sleep_hours': 5.5, 'stress_level': 5, 'risk_score': 88}),
      ], assessments: [
        {'concern': 'sensitivity', 'severity_score': 9, 'created_at': '2026-10-01T10:00:00Z'},
      ]);
      await pumpApp(tester, location: '/dashboard/history', prefs: acceptedPrefs(), backend: backend, size: const Size(320, 568));
      expect(tester.takeException(), isNull);
    });
  });
}
