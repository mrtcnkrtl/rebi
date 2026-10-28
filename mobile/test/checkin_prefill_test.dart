import 'dart:convert';

import 'package:flutter/material.dart' show TextField;
import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/core/checkin_prefill.dart';
import 'package:rebi/core/routine_tracking.dart';
import 'package:rebi/core/today_plan.dart';

import 'helpers/app_harness.dart';

DayProgress day(Map<String, dynamic> json) => DayProgress.fromJson(json);

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

  group('doldurma kuralları', () {
    test('boş gün hiçbir şey doldurmaz', () {
      final p = checkinPrefill(const DayProgress());
      expect(p.isEmpty, isTrue);
      expect(p.count, 0);
      expect(p.waterMl, isNull);
      expect(p.makeupUsed, isNull);
      expect(p.extras, isEmpty);
    });

    test('su toplamı 0dan büyükse gelir', () {
      expect(checkinPrefill(day({'water_ml_total': 1250})).waterMl, 1250);
      expect(checkinPrefill(day({'water_ml_total': 0})).waterMl, isNull);
    });

    test('makyaj: yaptı + yöntem, yapmadı, kayıt yok', () {
      final used = checkinPrefill(day({'makeup': {'logged': true, 'used': true, 'removed': true, 'removal_method': 'double'}}));
      expect((used.makeupUsed, used.removalMethod), (true, 'double'));

      final notUsed = checkinPrefill(day({'makeup': {'logged': true, 'used': false}}));
      expect((notUsed.makeupUsed, notUsed.removalMethod), (false, null), reason: 'yapmadıysa yöntem sorulmaz');

      final unlogged = checkinPrefill(day({'makeup': {'logged': false}}));
      expect((unlogged.makeupUsed, unlogged.removalMethod), (null, null));

      final noMethod = checkinPrefill(day({'makeup': {'logged': true, 'used': true, 'removed': false}}));
      expect((noMethod.makeupUsed, noMethod.removalMethod), (true, null));
    });

    test('beslenme: şekerli / abur cubur → yüksek glisemik, süt ürünü → süt; olmayan seçenek hayır', () {
      var p = checkinPrefill(day({'nutrition_logged': true, 'nutrition': {'sweets': true, 'dairy': false}}));
      expect(p.extras, {'high_glycemic_intake_today': true, 'heavy_dairy_today': false});

      p = checkinPrefill(day({'nutrition_logged': true, 'nutrition': {'snacks': true, 'dairy': true}}));
      expect(p.extras, {'high_glycemic_intake_today': true, 'heavy_dairy_today': true});

      p = checkinPrefill(day({'nutrition_logged': true, 'nutrition': {'balanced': true}}));
      expect(p.extras, {'high_glycemic_intake_today': false, 'heavy_dairy_today': false});

      p = checkinPrefill(day({'nutrition_logged': true, 'nutrition': {'fried_food': true}}));
      expect(p.extras['high_glycemic_intake_today'], isFalse, reason: 'kızartma tek başına yüksek glisemik sayılmaz');
    });

    test('eski beslenme kaydı (yalnızca junk_food) şekerli sayılır; hayır ise hayırdır', () {
      expect(checkinPrefill(day({'nutrition_logged': true, 'nutrition': {'junk_food': true}})).extras['high_glycemic_intake_today'], isTrue);
      expect(checkinPrefill(day({'nutrition_logged': true, 'nutrition': {'junk_food': false}})).extras['high_glycemic_intake_today'], isFalse);
    });

    test('beslenme kaydı yoksa ek sorular boş kalır', () {
      expect(checkinPrefill(day({'nutrition': {}})).extras, isEmpty);
    });

    test('güneş kremi yenilendiyse evet; yenilenmediyse bilinmez', () {
      expect(checkinPrefill(day({'spf_refreshes': 2})).extras, {'spf_applied_today': true});
      expect(checkinPrefill(day({'spf_refreshes': 0})).extras, isEmpty);
    });

    test('doldurulan cevap sayısı', () {
      final p = checkinPrefill(day({
        'water_ml_total': 900,
        'makeup': {'logged': true, 'used': true, 'removed': true, 'removal_method': 'wipe'},
        'nutrition_logged': true,
        'nutrition': {'dairy': true},
        'spf_refreshes': 1,
      }));
      // su + makyaj + yöntem + glisemik + süt + spf
      expect(p.count, 6);
    });
  });

  group('check-in ekranı', () {
    Future<Harness> open(WidgetTester tester, FakeBackend backend) =>
        pumpApp(tester, location: '/dashboard/checkin', prefs: acceptedPrefs(), backend: backend);

    FakeBackend busyDay() {
      final b = FakeBackend()..waterMl = 1250;
      b.todayPlan = {
        ...b.todayPlan,
        'progress': {
          'makeup': {'logged': true, 'used': true, 'removed': true, 'removal_method': 'wipe'},
          'nutrition_logged': true,
          'nutrition': {'sweets': true, 'dairy': false},
          'spf_refreshes': 1,
        },
      };
      return b;
    }

    testWidgets('bugünkü kayıtlar sorulara dolar ve bilgi satırı sayıyı söyler', (tester) async {
      final h = await open(tester, busyDay());

      expect(h.backend.calls('/daily_tracking/today').single.url.queryParameters['user_id'], testUserId);
      // su 1250 + makyaj + yöntem + glisemik + süt + spf = 6
      expect(find.text(tr('mobileCheckin.prefilled', {'n': 6})), findsOneWidget);
      final water = tester.widgetList<TextField>(find.byType(TextField)).where((f) => f.controller?.text == '1250');
      expect(water, hasLength(1), reason: 'su alanı doldu');
      expect(find.text('1.250 ml → yaklaşık 5 bardak'), findsOneWidget);
    });

    testWidgets('doldurulan cevaplar check-in gövdesine girer; elle değiştirilebilir', (tester) async {
      final h = await open(tester, busyDay());

      await tapText(tester, 'İrritasyon');
      await tapText(tester, tr('checkin.symptomBurning'));
      // Doldurulan "misel su / mendil" yerine "Çift aşama" seçilir.
      await tapText(tester, 'Çift aşama');
      await tapText(tester, tr('checkin.submit'));

      final body = h.backend.bodyOf('/daily_checkin');
      expect(body['water_ml_today'], 1250);
      expect(body['makeup_used_today'], true);
      expect(body['makeup_removal_today'], 'double', reason: 'kullanıcının değişikliği önceliklidir');
      expect(body['high_glycemic_intake_today'], true);
      expect(body['heavy_dairy_today'], false);
      expect(body['spf_applied_today'], true);
    });

    testWidgets('doldurulan temizleme yöntemi seçili gelir ve gövdede aynen gider', (tester) async {
      final h = await open(tester, busyDay());
      await tapText(tester, 'İrritasyon');
      await tapText(tester, tr('checkin.symptomBurning'));
      await tapText(tester, tr('checkin.submit'));
      expect(h.backend.bodyOf('/daily_checkin')['makeup_removal_today'], 'wipe');
    });

    testWidgets('kayıt yoksa bilgi satırı çıkmaz ve sorular boş kalır', (tester) async {
      final h = await open(tester, FakeBackend());
      expect(find.textContaining('cevap dolduruldu'), findsNothing);
      await tapText(tester, 'İrritasyon');
      await tapText(tester, tr('checkin.symptomBurning'));
      await tapText(tester, tr('checkin.submit'));
      final body = h.backend.bodyOf('/daily_checkin');
      expect(body.containsKey('water_ml_today'), isFalse);
      expect(body.containsKey('makeup_used_today'), isFalse);
      expect(body.containsKey('heavy_dairy_today'), isFalse);
    });

    testWidgets('takip verisi alınamazsa form yine açılır, bilgi satırı çıkmaz', (tester) async {
      final backend = busyDay()..trackingTodayFails = true;
      await open(tester, backend);
      expect(find.text(tr('checkin.title')), findsOneWidget);
      expect(find.textContaining('cevap dolduruldu'), findsNothing);
    });

    testWidgets('yalnızca makyaj yapılmadı kaydı: makyaj "hayır" gelir, yöntem sorulmaz', (tester) async {
      final backend = FakeBackend();
      backend.todayPlan = {
        ...backend.todayPlan,
        'progress': {
          'makeup': {'logged': true, 'used': false},
        },
      };
      final h = await open(tester, backend);
      expect(find.text(tr('mobileCheckin.prefilled', {'n': 1})), findsOneWidget);
      expect(find.text('Nasıl temizledin?'), findsNothing);
      await tapText(tester, 'İrritasyon');
      await tapText(tester, tr('checkin.symptomBurning'));
      await tapText(tester, tr('checkin.submit'));
      expect(h.backend.bodyOf('/daily_checkin')['makeup_used_today'], false);
    });

    testWidgets('İngilizce arayüzde bilgi satırı İngilizce', (tester) async {
      final h = await pumpApp(tester, location: '/dashboard/checkin', prefs: acceptedPrefs(), backend: busyDay(), lang: 'en');
      expect(h.backend.calls('/daily_tracking/today'), isNotEmpty);
      expect(find.text("6 answers were filled in from today's tracking. Change them if you like."), findsOneWidget);
    });
  });
}
