import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/core/reminder_schedule.dart';
import 'package:rebi/core/shelf.dart';
import 'package:rebi/core/today_plan.dart';

/// Rafım'ın saf mantığı: ad eşleşmesi, sunucu yanıtının okunması ve henüz gönderilmemiş olayın hemen yansıması.
ShelfItem item(String name, {int? step, int days = 0}) => ShelfItem(product: name, stepOrder: step, daysOut: days);

void main() {
  group('shelfKey', () {
    test('büyük/küçük harf ve fazla boşluk fark yaratmaz', () {
      expect(shelfKey('  Jel   Temizleyici '), shelfKey('jel temizleyici'));
      expect(shelfKey('SPF 50'), 'spf 50');
      expect(shelfKey(''), isEmpty);
    });

    test('sunucu gibi ilk 120 karakterle eşleşir', () {
      final long = 'u' * 300;
      expect(shelfKey(long).length, shelfMaxNameLength);
      expect(shelfName(long).length, shelfMaxNameLength);
      expect(shelfName('  kısa  '), 'kısa');
    });
  });

  group('parseShelf', () {
    test('sunucu kaydını okur', () {
      final items = parseShelf([
        {'product': 'Niasinamid serum', 'step_order': 20, 'finished_at': '2026-10-14T10:00:00+00:00', 'log_date': '2026-10-14', 'days_out': 2},
      ]);

      expect(items.single.product, 'Niasinamid serum');
      expect(items.single.stepOrder, 20);
      expect(items.single.daysOut, 2);
      expect(items.single.finishedAt, isNotNull);
      expect(items.single.key, 'niasinamid serum');
    });

    test('bozuk ya da eksik kayıtlar atlanır; alan yoksa boş liste', () {
      expect(parseShelf(null), isEmpty);
      expect(parseShelf('liste değil'), isEmpty);
      expect(parseShelf([
        {'product': '  '},
        {'step_order': 3},
        'metin',
        {'product': 'Geçerli', 'step_order': 'x', 'days_out': -4, 'finished_at': 'tarih değil'},
      ]).map((i) => (i.product, i.stepOrder, i.daysOut, i.finishedAt)), [('Geçerli', null, 0, null)]);
    });

    test('plan yanıtından gelir; alan olmayan eski sunucuda boştur', () {
      TodayPlan plan(Map<String, dynamic> extra) => TodayPlan.fromJson({'log_date': '2026-10-10', 'progress': <String, dynamic>{}, ...extra});

      expect(plan({}).productsOut, isEmpty);
      final withOut = plan({
        'products_out': [
          {'product': 'SPF 50', 'step_order': 40, 'days_out': 0},
        ],
      });
      expect(withOut.productsOut.single.product, 'SPF 50');
      expect(withOut.isOut('spf  50'), isTrue);
      expect(withOut.isOut('Başka ürün'), isFalse);
    });
  });

  group('shelfWith (bekleyen olayın etkisi)', () {
    test('bitti işareti ürünü başa ekler, tekrar işaretlemek ilk kaydı korur', () {
      final now = DateTime(2026, 10, 10, 9);
      final first = shelfWith([item('A', days: 3)], shelfFinishedEvent, {'product': 'B', 'step_order': 20}, now: now);

      expect(first.map((i) => i.product), ['B', 'A']);
      expect(first.first.stepOrder, 20);
      expect(first.first.finishedAt, now);

      final again = shelfWith(first, shelfFinishedEvent, {'product': ' b '});
      expect(again, same(first), reason: 'aynı ürün (ad eşleşmesi) ikinci kez eklenmez');
    });

    test('aldım ürünü listeden çıkarır; hiç bitmemiş ürün için bir şey yapmaz', () {
      final list = [item('A'), item('B')];

      expect(shelfWith(list, shelfRestockedEvent, {'product': 'a'}).map((i) => i.product), ['B']);
      expect(shelfWith(list, shelfRestockedEvent, {'product': 'C'}).map((i) => i.product), ['A', 'B']);
    });

    test('adsız ve ilgisiz olaylar listeyi değiştirmez', () {
      final list = [item('A')];

      expect(shelfWith(list, shelfFinishedEvent, {}), same(list));
      expect(shelfWith(list, shelfFinishedEvent, {'product': '   '}), same(list));
      expect(shelfWith(list, 'water_intake', {'product': 'A'}), same(list));
    });

    test('bitti sonra aldım sonra yine bitti: son olay geçerli', () {
      var list = <ShelfItem>[];
      for (final type in [shelfFinishedEvent, shelfRestockedEvent, shelfFinishedEvent]) {
        list = shelfWith(list, type, {'product': 'Krem'});
      }
      expect(list.map((i) => i.product), ['Krem']);
      list = shelfWith(list, shelfRestockedEvent, {'product': 'Krem'});
      expect(list, isEmpty);
    });
  });

  test('shelfAge: bugün, dün, n gün', () {
    expect(shelfAge(item('A', days: 0)), (kind: 'today', days: 0));
    expect(shelfAge(item('A', days: 1)), (kind: 'yesterday', days: 1));
    expect(shelfAge(item('A', days: 5)), (kind: 'days', days: 5));
  });

  group('yenisini aldın mı hatırlatması', () {
    test('bildirime dokunmak Rafım\'ı açar; diğerleri eskisi gibi', () {
      expect(routeForReminder('restock_check'), '/dashboard/shelf');
      expect(routeForReminder('daily_checkin'), '/dashboard/checkin');
      expect(routeForReminder('water_intake'), '/dashboard');
      expect(routeForReminder(null), '/dashboard');
    });

    test('kartta "Rafım\'a git" eylemi sunulur', () {
      const r = Reminder(id: 'restock_check', title: 't', body: 'b', start: '18:00', end: '19:00');

      final actions = reminderActions(r);

      expect(actions.single.labelKey, 'openShelf');
      expect(actions.single.route, '/dashboard/shelf');
    });
  });
}
