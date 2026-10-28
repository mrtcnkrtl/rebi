import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/core/routine_logic.dart';

/// Web `pages/Dashboard.jsx` ve `lib/structuredRoutineBadges.jsx` davranışının birebir karşılığı.
void main() {
  // Gerçek backend yanıtı (`/generate_routine`, akne + yağlı cilt, kriz modu).
  final fixture = jsonDecode(File('test/fixtures/generate_routine_response.json').readAsStringSync()) as Map;
  final routine = asRoutine(fixture['routine']);

  group('RoutineView (gerçek backend rutini)', () {
    final v = RoutineView(routine);

    test('sabah ürünleri step_order ile sıralı, yaşam adımları ayrı', () {
      expect(v.morningProducts.map((r) => r['step_order']), [10, 30, 40]);
      expect(v.eveningProducts.map((r) => r['step_order']), [10, 18, 20, 30]);
      expect(v.lifestyleItems.map((r) => r['category']), ['Zihin', 'Yaşam', 'Yaşam']);
    });

    test('"Sabah ve Akşam" ve "Bitkisel" satırları ürün sayılır ama sabah/akşam listesine girmez (web ile aynı)', () {
      expect(v.productItems.any((r) => r['time'] == 'Sabah ve Akşam'), isTrue);
      expect(v.morningProducts.any((r) => r['time'] == 'Sabah ve Akşam'), isFalse);
      expect(v.productItems.any((r) => r['category'] == 'Bitkisel'), isTrue);
    });

    test('günlük denge kartı ayrılır, yaşam listesinden düşer', () {
      expect(str(v.dailyBalanceItem?['action']), startsWith('Günlük denge:'));
      expect(v.wellnessItems.any((r) => str(r['action']).startsWith('Günlük denge:')), isFalse);
      expect(v.dailyLifestyleItems, isEmpty);
    });

    test('akşam zihin/yaşam adımları "akşam — yaşam" bloğuna gider', () {
      expect(v.wellnessEveningItems.map((r) => r['category']), ['Zihin', 'Yaşam']);
      expect(v.wellnessMorningItems, isEmpty);
    });

    test('haftalık madde yalnız atanmış günlerde görünür', () {
      expect(v.weeklyItems, hasLength(1));
      expect(v.weeklyItems.single.displayDays, [0, 6]);
      expect(v.routineByDay[0]!.evening.length, 4);
      expect(v.routineByDay[3]!.evening.length, 3);
    });

    test('BHA içerdiği için sabah kullanım uyarısı üretilir', () {
      expect(v.eveningMorningHints, contains('BHA (salisilik asit) rutininde: sabah kullanmayın.'));
    });

    test('ürün listesi tekilleştirilir ve sırayı korur', () {
      expect(v.routineIngredientsList.first, startsWith('Temizleme:'));
      expect(v.routineIngredientsList.toSet().length, v.routineIngredientsList.length);
    });
  });

  group('computeEveningActivesMorningHints', () {
    test('kural başına tek satır, web sırasıyla', () {
      final hints = computeEveningActivesMorningHints([
        {'action': 'Retinol %0.3 serum', 'detail': 'Glikolik asit haftada 2 gece'},
        {'action': 'Azelaik asit %10'},
        {'action': 'retinol tekrar'},
      ]);
      expect(hints, [
        'Retinoid (retinol, retinal, adapalen vb.) rutininde: sabah kullanmayın.',
        'AHA (glikolik, laktik vb.) rutininde: sabah kullanmayın.',
        'Azelaik asit (tedavi konsantrasyonu) rutininde: sabah kullanmayın.',
      ]);
    });

    test('"retinolsuz" kelime sınırı nedeniyle eşleşmez', () {
      expect(computeEveningActivesMorningHints([{'action': 'retinolsuz krem'}]), isEmpty);
    });
  });

  group('haftalık gün hesabı', () {
    test('getDefaultWeeklyDays', () {
      expect(getDefaultWeeklyDays('Haftada 3 gece uygula'), [0, 3, 6]);
      expect(getDefaultWeeklyDays('haftada 2-3 kez'), [0, 6]);
      expect(getDefaultWeeklyDays('haftada 1 kez'), [0]);
      expect(getDefaultWeeklyDays('haftada 7 gün'), [0, 1, 2, 3, 4, 5, 6]);
      expect(getDefaultWeeklyDays('haftada 4 defa'), [0, 2, 4, 6]);
      expect(getDefaultWeeklyDays('her gün'), isEmpty);
    });

    test('isWeeklyUsageItem büyük/küçük harf duyarsız', () {
      expect(isWeeklyUsageItem({'detail': 'HAFTADA 2 GECE'}), isTrue);
      expect(isWeeklyUsageItem({'detail': 'günde iki kez'}), isFalse);
    });

    test('getTurkeyWeekdayIndex: Pzt=0 … Paz=6', () {
      expect(getTurkeyWeekdayIndex(DateTime(2026, 10, 12)), 0);
      expect(getTurkeyWeekdayIndex(DateTime(2026, 10, 11)), 6);
    });
  });

  group('friendlyRoutineTitle', () {
    test('tireden sonraki insan okunur kısım, INCI gizlenir', () {
      expect(friendlyRoutineTitle('Retinol %0.3 — Gece serumu (INCI: Retinol)'), 'Gece serumu');
    });
    test('ara ver işaretleri temizlenir', () {
      expect(friendlyRoutineTitle('⏸️ Salisilik asit tonik — ARA VER'), 'Salisilik asit tonik');
      expect(friendlyRoutineTitle('AHA tonik — şimdilik kullanma'), 'AHA tonik');
    });
    test('boşsa yedek başlık', () {
      expect(friendlyRoutineTitle('', 'Bu adım'), 'Bu adım');
    });
  });

  test('dailyBalanceLevel: flow_debug önce, yoksa başlıktan', () {
    expect(dailyBalanceLevel({'action': 'Günlük denge: Orta'}, {'risk_info': {'level': 'high'}}), 'high');
    expect(dailyBalanceLevel({'action': 'Günlük denge: Kriz'}, null), 'crisis');
    expect(dailyBalanceLevel({'action': 'Günlük denge: Yüksek'}, null), 'high');
    expect(dailyBalanceLevel({'action': 'Günlük denge: Orta'}, null), 'moderate');
    expect(dailyBalanceLevel({'action': 'Günlük denge: İyi'}, null), 'normal');
  });

  group('structuredRoutineBadges', () {
    test('tüm rozetler', () {
      expect(
        structuredRoutineBadges({
          'action': 'BHA tonik',
          'ramp_stage': 'starter',
          'strength_pct': '2',
          'frequency_per_week': 3,
          'active_families': ['bha', 'aha', 'retinol', 'pigment', 'niacinamide'],
        }),
        ['Alıştırma', '%2', '3×/hafta', 'BHA · AHA · Retinol · Leke'],
      );
    });
    test('7+ sıklık "Her gün", 0 sıklık rozet üretmez', () {
      expect(structuredRoutineBadges({'action': 'x', 'frequency_per_week': 7}), ['Her gün']);
      expect(structuredRoutineBadges({'action': 'x', 'frequency_per_week': 0}), isEmpty);
    });
    test('risk özeti satırına rozet konmaz', () {
      expect(structuredRoutineBadges({'action': 'Günlük denge: Kriz', 'strength_pct': 5}), isEmpty);
    });
    test('ondalık yüzde JS gibi yazılır', () {
      expect(structuredRoutineBadges({'action': 'x', 'strength_pct': 0.3}), ['%0.3']);
      expect(structuredRoutineBadges({'action': 'x', 'strength_pct': 5.0}), ['%5']);
    });
  });

  test('sortByStepOrder kararlıdır (eşit sıralar yer değiştirmez)', () {
    final sorted = sortByStepOrder([
      {'id': 'a', 'step_order': 20},
      {'id': 'b'},
      {'id': 'c', 'step_order': 20},
      {'id': 'd', 'step_order': 10},
    ]);
    expect(sorted.map((r) => r['id']), ['d', 'a', 'c', 'b']);
  });

  test('pickAction / pickDetail yerelleştirilmiş alanı tercih eder', () {
    final item = {'action': 'Temizleyici', 'action_localized': 'Cleanser', 'detail': 'Ayrıntı'};
    expect(pickAction(item, localized: true), 'Cleanser');
    expect(pickAction(item, localized: false), 'Temizleyici');
    expect(pickDetail(item, localized: true), 'Ayrıntı');
  });
}
