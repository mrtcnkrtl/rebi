import 'dart:convert';

import 'package:flutter/material.dart' show BottomSheet, Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/core/routine_logic.dart';
import 'package:rebi/core/routine_tracking.dart';
import 'package:rebi/core/routine_usage.dart';
import 'package:rebi/screens/today/today_clock.dart';
import 'package:rebi/ui/shell/app_shell.dart';

import 'helpers/app_harness.dart';

/// Rafım: "ürün bitti" → rutinde soluk adım → "Aldım" ile geri dönüş; Rafım ekranı, giriş noktaları ve hatırlatma.
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

  setUp(() => todayPanelClock = () => DateTime(2026, 10, 10, 9, 15));
  tearDown(() => todayPanelClock = DateTime.now);

  List<RoutineItem> todaysMorning() => RoutineView(asRoutine(routine)).routineByDay[getTurkeyWeekdayIndex()]!.morning;

  /// Bugünün sabah adımlarından bakım ürünü olanlar (kahraman kartta görünürler).
  List<RoutineItem> skincareSteps() => [for (final it in todaysMorning()) if (isSkincareStep(it)) it];

  Map<String, dynamic> out(String name, {int days = 2, int? step}) => {
        'product': name,
        'step_order': step,
        'finished_at': '2026-10-08T10:00:00+00:00',
        'log_date': '2026-10-08',
        'days_out': days,
      };

  Finder inSheet(String text) => find.descendant(of: find.byType(BottomSheet), matching: find.text(text));

  Map<String, dynamic> lastIngest(Harness h) => h.backend.bodyOf('/daily_tracking/ingest');

  Map<String, dynamic> reminder(String id, String title, String start, String end) =>
      {'id': id, 'title': title, 'body': 'Gövde', 'start': start, 'end': end, 'every_minutes': null, 'log_event': null};

  group('Bugün: ürün bitti → rutinde soluk adım', () {
    testWidgets('sayfadan bitti işaretlenen ürünün adımı soluk görünür ve ilerlemeye sayılmaz', (tester) async {
      final steps = todaysMorning();
      final product = skincareSteps().first;
      final name = str(product['action']).trim();
      final h = await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs());
      expect(find.text(tr('mobileToday.hero.outBadge')), findsNothing);
      expect(find.text('0/${steps.length}'), findsWidgets);

      await tapText(tester, tr('mobileToday.productFinished'));
      await tapFinder(tester, inSheet(pickAction(product, localized: false)).first);
      await tapFinder(tester, inSheet(tr('mobileToday.sheets.products.saveCount', {'n': 1})).first);
      await settle(tester);

      expect(lastIngest(h)['type'], 'product_finished');
      expect(h.backend.productsOut.map((p) => p['product']), [name]);
      expect(find.text(tr('mobileToday.hero.outBadge')), findsOneWidget);
      expect(find.text(tr('mobileToday.hero.restock')), findsOneWidget);
      // Sabah halkası ve seçicisi biten ürünü toplamdan düşer (akşam seçicisi başka bir bloktur).
      expect(find.text('0/${steps.length - 1}'), findsNWidgets(2));
    });

    testWidgets('"Aldım" ürünü rafa geri koyar, adım yeniden işaretlenebilir olur', (tester) async {
      final product = skincareSteps().first;
      final name = str(product['action']).trim();
      final backend = FakeBackend()..productsOut = [out(name, step: stepOrder(product).round())];
      final h = await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs(), backend: backend);
      expect(find.text(tr('mobileToday.hero.outBadge')), findsOneWidget);

      await tapText(tester, tr('mobileToday.hero.restock'));

      final body = lastIngest(h);
      expect(body['type'], 'product_restocked');
      expect((body['payload'] as Map)['product'], name);
      expect((body['payload'] as Map)['step_order'], stepOrder(product).round());
      expect(h.backend.productsOut, isEmpty);
      expect(find.text(tr('mobileToday.hero.outBadge')), findsNothing);
      expect(find.text(tr('mobileToday.toast.restocked', {'product': name})), findsOneWidget);
    });

    testWidgets('"Aldım" geri alınabilir: ürün yeniden biter', (tester) async {
      final product = skincareSteps().first;
      final name = str(product['action']).trim();
      final backend = FakeBackend()..productsOut = [out(name)];
      final h = await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs(), backend: backend);

      await tapText(tester, tr('mobileToday.hero.restock'));
      await tapText(tester, tr('mobileToday.toast.undo'));

      expect(lastIngest(h)['type'], 'product_finished');
      expect(h.backend.productsOut.map((p) => p['product']), [name]);
    });

    testWidgets('biten ürünün adımı bloğun tamamlanmasını engellemez', (tester) async {
      final steps = todaysMorning();
      expect(steps.length, greaterThan(1));
      final product = skincareSteps().first;
      final backend = FakeBackend()..productsOut = [out(str(product['action']).trim(), step: stepOrder(product).round())];
      final h = await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs(), backend: backend);

      for (final step in steps) {
        if (identical(step, product) || str(step['action']) == str(product['action'])) continue;
        await tapText(tester, pickAction(step, localized: false));
      }

      expect(h.backend.progress['routine_morning_done'], isTrue, reason: 'kalan tüm adımlar işaretlenince blok tamamlanır');
    });

    testWidgets('ürün bitti sayfasında biten ürün "Aldım" ile geri açılır ve sayfa kapanır', (tester) async {
      final product = skincareSteps().first;
      final name = str(product['action']).trim();
      final backend = FakeBackend()..productsOut = [out(name)];
      final h = await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs(), backend: backend);

      await tapText(tester, tr('mobileToday.productFinished'));
      expect(inSheet(tr('mobileToday.sheets.products.already')), findsOneWidget);
      await tapFinder(tester, inSheet(tr('mobileToday.sheets.products.restock')).first);
      await settle(tester);

      expect(lastIngest(h)['type'], 'product_restocked');
      expect(h.backend.productsOut, isEmpty);
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('ürün bitti sayfasındaki bağlantı Rafım\'ı açar', (tester) async {
      await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs());

      await tapText(tester, tr('mobileToday.productFinished'));
      await tapFinder(tester, inSheet(tr('mobileToday.sheets.products.shelfLink')).first);
      await settle(tester);

      expect(find.text(tr('mobileShelf.subtitle')), findsOneWidget);
    });
  });

  group('Rafım ekranı', () {
    testWidgets('boş raf sakin bir açıklama gösterir', (tester) async {
      await pumpApp(tester, location: '/dashboard/shelf');

      expect(find.text(tr('mobileShelf.title')), findsOneWidget);
      expect(find.text(tr('mobileShelf.emptyTitle')), findsOneWidget);
      expect(find.text(tr('mobileShelf.restocked')), findsNothing);
    });

    testWidgets('biten ürünler yaşlarıyla listelenir', (tester) async {
      final backend = FakeBackend()
        ..productsOut = [
          out('Niasinamid serum', days: 0),
          out('SPF 50', days: 1),
          out('Temizleyici', days: 5),
        ];
      await pumpApp(tester, location: '/dashboard/shelf', backend: backend);

      expect(find.text('Niasinamid serum'), findsOneWidget);
      expect(find.text(tr('mobileShelf.age.today')), findsOneWidget);
      expect(find.text(tr('mobileShelf.age.yesterday')), findsOneWidget);
      expect(find.text(tr('mobileShelf.age.days', {'n': 5})), findsOneWidget);
      expect(find.text(tr('mobileShelf.restocked')), findsNWidgets(3));
      expect(find.text(tr('mobileShelf.hint')), findsOneWidget);
      expect(find.text(tr('mobileShelf.emptyTitle')), findsNothing);
    });

    testWidgets('"Aldım" ürünü listeden çıkarır, geri al yeniden ekler', (tester) async {
      final backend = FakeBackend()..productsOut = [out('Niasinamid serum', step: 20), out('SPF 50')];
      final h = await pumpApp(tester, location: '/dashboard/shelf', backend: backend);

      await tapFinder(tester, find.text(tr('mobileShelf.restocked')).first);
      await settle(tester);

      final body = lastIngest(h);
      expect(body['type'], 'product_restocked');
      expect((body['payload'] as Map)['product'], 'Niasinamid serum');
      expect((body['payload'] as Map)['step_order'], 20);
      expect(find.text('Niasinamid serum'), findsNothing);
      expect(find.text('SPF 50'), findsOneWidget);
      expect(find.text(tr('mobileToday.toast.restocked', {'product': 'Niasinamid serum'})), findsOneWidget);

      await tapText(tester, tr('mobileToday.toast.undo'));
      expect(lastIngest(h)['type'], 'product_finished');
      expect(find.text('Niasinamid serum'), findsOneWidget);
    });

    testWidgets('çevrimdışıyken "Aldım" kuyruğa alınır ve ürün hemen listeden çıkar', (tester) async {
      final backend = FakeBackend()
        ..productsOut = [out('Niasinamid serum')]
        ..ingestOffline = true;
      await pumpApp(tester, location: '/dashboard/shelf', backend: backend);

      await tapText(tester, tr('mobileShelf.restocked'));
      await settle(tester);

      expect(find.text('Niasinamid serum'), findsNothing);
      expect(find.text(tr('mobileShelf.emptyTitle')), findsOneWidget);
      expect(find.text(tr('mobileToday.queuedHint')), findsOneWidget);
      expect(find.text(tr('mobileShelf.pending', {'count': 1})), findsOneWidget);
    });

    testWidgets('sunucu reddederse ürün listede kalır ve hata söylenir', (tester) async {
      final backend = FakeBackend()
        ..productsOut = [out('Niasinamid serum')]
        ..ingestStatus = 422;
      await pumpApp(tester, location: '/dashboard/shelf', backend: backend);

      await tapText(tester, tr('mobileShelf.restocked'));
      await settle(tester);

      expect(find.text('Niasinamid serum'), findsOneWidget);
      expect(find.text(tr('mobileToday.toast.failed')), findsOneWidget);
    });

    testWidgets('"Yerine ne kullanabilirim?" ürün adıyla hazırlanmış mesajı sohbete gönderir', (tester) async {
      final backend = FakeBackend()..productsOut = [out('Niasinamid serum')];
      final h = await pumpApp(tester, location: '/dashboard/shelf', backend: backend);

      await tapText(tester, tr('mobileShelf.alternative'));
      await settle(tester);

      final sent = h.backend.bodyOf('/chat_general');
      expect(sent['message'], tr('mobileShelf.alternativePrompt', {'product': 'Niasinamid serum'}));
      expect(find.text(tr('mobileShelf.alternativePrompt', {'product': 'Niasinamid serum'})), findsWidgets);
    });

    testWidgets('yüklenemezse uyarı çıkar, tekrar denenince raf gelir', (tester) async {
      final backend = FakeBackend()
        ..productsOut = [out('SPF 50')]
        ..planFails = true;
      final h = await pumpApp(tester, location: '/dashboard/shelf', backend: backend);
      expect(find.text(tr('mobileShelf.loadFailed')), findsOneWidget);

      h.backend.planFails = false;
      await tapText(tester, tr('mobileShelf.retry'));

      expect(find.text(tr('mobileShelf.loadFailed')), findsNothing);
      expect(find.text('SPF 50'), findsOneWidget);
    });

    testWidgets('demo oturumunda sunucu verisi yoktur: boş raf', (tester) async {
      await pumpApp(tester, location: '/dashboard/shelf', loggedIn: false);

      // Giriş yapmamış kullanıcı panele giremez; giriş ekranına yönlenir ve raf çizilmez.
      expect(find.text(tr('mobileShelf.restocked')), findsNothing);
    });

    testWidgets('320 px ve %200 yazıda uzun ürün adlarıyla taşmaz', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final backend = FakeBackend()
        ..productsOut = [
          out('Yüzey aktif (SLES-free) köpük temizleyici, hassas ve kuruluğa eğilimli ciltler için nazik formül', days: 3),
          out('Niasinamid %4 + Hyaluronik asit (hafif jel) nemlendirici', days: 12),
        ];
      await pumpApp(tester, location: '/dashboard/shelf', backend: backend, size: const Size(320, 640));

      expect(tester.takeException(), isNull);
      expect(find.text(tr('mobileShelf.restocked')), findsNWidgets(2));
    });

    testWidgets('Rafım Bugün sekmesine bağlıdır ve geri çubuğu vardır', (tester) async {
      expect(tabForPath('/dashboard/shelf'), AppTab.today);
      expect(isSubPage('/dashboard/shelf'), isTrue);

      await pumpApp(tester, location: '/dashboard/shelf');
      expect(find.text(tr('mobileNav.back')), findsOneWidget);
    });
  });

  group('giriş noktaları', () {
    testWidgets('Bugün → Daha fazlası satırı biten ürün sayısını söyler ve Rafım\'a götürür', (tester) async {
      final backend = FakeBackend()..productsOut = [out('A'), out('B')];
      await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs(), backend: backend);

      expect(find.text(tr('mobileShelf.countHint', {'n': 2})), findsOneWidget);
      await tapText(tester, tr('mobileShelf.title'));
      await settle(tester);

      expect(find.text(tr('mobileShelf.subtitle')), findsOneWidget);
      expect(find.text('A'), findsOneWidget);
    });

    testWidgets('raf boşken satır "biten ürünlerini takip et" der', (tester) async {
      await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs());
      expect(find.text(tr('mobileShelf.emptyHint')), findsOneWidget);
    });

    testWidgets('Ben menüsünden açılır', (tester) async {
      await pumpApp(tester, location: '/dashboard/profile');

      await tapText(tester, tr('mobileShelf.title'));
      await settle(tester);

      expect(find.text(tr('mobileShelf.subtitle')), findsOneWidget);
    });
  });

  group('yenisini aldın mı hatırlatması', () {
    testWidgets('penceresi açıkken Gün akışı kartında eylemiyle çıkar; dokunmak Rafım\'ı açar', (tester) async {
      final backend = FakeBackend()
        ..productsOut = [out('Niasinamid serum', days: 3)];
      backend.todayPlan = {
        ...backend.todayPlan,
        'reminders': [reminder('restock_check', 'Yenisini aldın mı?', '09:00', '10:00')],
      };
      await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs(), backend: backend);

      expect(find.text('Yenisini aldın mı?'), findsOneWidget);
      await tapText(tester, tr('mobileToday.actions.openShelf'));
      await settle(tester);

      expect(find.text(tr('mobileShelf.subtitle')), findsOneWidget);
    });

    testWidgets('Hatırlatıcılar ekranında "Ürün yenileme" anahtarı ve penceresi görünür', (tester) async {
      await pumpApp(tester, location: '/dashboard/reminders');

      expect(find.text(tr('mobileReminders.categories.restock.title')), findsOneWidget);
      expect(find.text(tr('mobileReminders.categories.restock.desc')), findsOneWidget);
      expect(find.text(tr('mobileReminders.window', {'start': '18:00', 'end': '19:00'})), findsOneWidget);
    });

    testWidgets('İngilizce arayüzde başlık çevrilir', (tester) async {
      final backend = FakeBackend();
      backend.todayPlan = {
        ...backend.todayPlan,
        'reminders': [reminder('restock_check', 'Yenisini aldın mı?', '09:00', '10:00')],
      };
      await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs(), backend: backend, lang: 'en');

      expect(find.text('Did you restock?'), findsOneWidget);
      expect(find.text('Yenisini aldın mı?'), findsNothing);
    });
  });
}
