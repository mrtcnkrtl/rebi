import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/core/chat_context.dart';
import 'package:rebi/core/chat_failure.dart';
import 'package:rebi/core/i18n.dart';
import 'package:rebi/core/local_store.dart';
import 'package:rebi/core/routine_tracking.dart';
import 'package:rebi/core/subscription.dart';
import 'package:rebi/core/today_plan.dart';
import 'package:rebi/screens/chat/chat_parts.dart';

import 'helpers/app_harness.dart';

/// Faz F1: sohbet. Hata kartı ve "Tekrar dene" (hata sohbet geçmişine girmez), "Rebi bugünü biliyor" şeridi,
/// yanıt biçimi, yerelleştirilmiş limit kartı.
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

  Future<void> ask(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await settle(tester);
  }

  tearDown(() => plusPurchasableOverride = null);

  group('hata kartı ve tekrar dene', () {
    testWidgets('sunucu yanıt vermezse sohbete metin yazılmaz; kart çıkar, "Tekrar dene" aynı mesajı yeniden gönderir', (tester) async {
      final backend = FakeBackend()..chatFailTimes = 1;
      final h = await pumpApp(tester, location: '/dashboard/chat', backend: backend);

      await ask(tester, 'Niasinamid ne işe yarar?');
      expect(find.text(tr('mobileChat.error.server')), findsOneWidget);
      expect(find.text('(503)'), findsOneWidget);
      expect(find.textContaining('Şu an yanıt alınamadı'), findsNothing, reason: 'eski davranış: hata asistan mesajı olarak yazılırdı');
      expect(find.text('Niasinamid ne işe yarar?'), findsOneWidget, reason: 'kullanıcının mesajı yerinde');
      final stored = LocalStore.instance.getJson('rebi-chat-history_$testUserId') as List;
      expect(stored.map((m) => (m as Map)['role']), ['user'], reason: 'hata geçmişe girmez');

      await tapText(tester, tr('mobileChat.retry'));
      expect(find.text(tr('mobileChat.error.server')), findsNothing);
      expect(find.textContaining('Niasinamid bariyeri destekler.'), findsOneWidget);

      final calls = h.backend.calls('/chat_general');
      expect(calls, hasLength(2));
      final second = jsonDecode(calls.last.body) as Map;
      expect(second['message'], 'Niasinamid ne işe yarar?');
      expect((second['history'] as List).map((m) => (m as Map)['role']), ['user'], reason: 'mesaj ikilenmez, hata geçmiş olarak gitmez');
      expect(find.text('Niasinamid ne işe yarar?'), findsOneWidget);
    });

    testWidgets('bağlantı yoksa "bağlantı kurulamadı" kartı çıkar; durum kodu gösterilmez', (tester) async {
      final backend = FakeBackend()
        ..chatFailTimes = 1
        ..chatFailOffline = true;
      await pumpApp(tester, location: '/dashboard/chat', backend: backend);

      await ask(tester, 'Merhaba');
      expect(find.text(tr('mobileChat.error.offline')), findsOneWidget);
      expect(find.textContaining('('), findsNothing);
    });

    testWidgets('oturum süresi dolduysa (401) ilgili mesaj çıkar', (tester) async {
      final backend = FakeBackend()
        ..chatFailTimes = 1
        ..chatFailStatus = 401;
      await pumpApp(tester, location: '/dashboard/chat', backend: backend);
      await ask(tester, 'Merhaba');
      expect(find.text(tr('mobileChat.error.auth')), findsOneWidget);
      expect(find.text('(401)'), findsOneWidget);
    });

    testWidgets('başka bir mesaj yazmak hata kartını kaldırır', (tester) async {
      final backend = FakeBackend()..chatFailTimes = 1;
      await pumpApp(tester, location: '/dashboard/chat', backend: backend);
      await ask(tester, 'Birinci');
      expect(find.text(tr('mobileChat.error.server')), findsOneWidget);

      await ask(tester, 'İkinci');
      expect(find.text(tr('mobileChat.error.server')), findsNothing);
    });

    testWidgets('sohbeti temizlemek hata kartını kaldırır', (tester) async {
      final backend = FakeBackend()..chatFailTimes = 1;
      await pumpApp(tester, location: '/dashboard/chat', backend: backend);
      await ask(tester, 'Birinci');
      expect(find.text(tr('mobileChat.error.server')), findsOneWidget);

      await tapText(tester, tr('chat.clear'));
      expect(find.text(tr('mobileChat.error.server')), findsNothing);
      expect(find.text(tr('chat.emptyTitle')), findsOneWidget);
    });

    testWidgets('İngilizce arayüzde hata metinleri çevrilir', (tester) async {
      final backend = FakeBackend()..chatFailTimes = 1;
      await pumpApp(tester, location: '/dashboard/chat', backend: backend, lang: 'en');
      await ask(tester, 'Hi');
      expect(find.text('The server isn\'t responding right now. Try again in a moment.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    test('ChatFailure.fromStatus', () {
      expect(ChatFailure.fromStatus(401), ChatFailure.auth);
      expect(ChatFailure.fromStatus(502), ChatFailure.server);
      expect(ChatFailure.fromStatus(503), ChatFailure.server);
      expect(ChatFailure.fromStatus(504), ChatFailure.server);
      expect(ChatFailure.fromStatus(500), ChatFailure.generic);
      expect(ChatFailure.fromStatus(422), ChatFailure.generic);
      expect(ChatFailure.server.messageKey, 'mobileChat.error.server');
    });
  });

  group('"Rebi bugünü biliyor" şeridi', () {
    testWidgets('bugünün verisinden bilgi çipleri çıkar; dokununca Bugün açılır', (tester) async {
      final backend = FakeBackend();
      backend.todayPlan = {
        ...backend.todayPlan,
        'weather_source': 'live',
        'weather': {'uv_index': 6, 'temperature': 18, 'humidity': 38},
        'has_routine': true,
        'progress': {
          'routine_morning_done': true,
          'makeup': {'logged': true, 'used': true, 'removed': false},
        },
      };
      backend.waterMl = 750;
      backend.productsOut = [
        {'product': 'SPF 50', 'step_order': 40, 'finished_at': '2026-10-08T10:00:00+00:00', 'log_date': '2026-10-08', 'days_out': 2},
      ];
      final h = await pumpApp(tester, location: '/dashboard/chat', prefs: acceptedPrefs(), backend: backend, size: const Size(800, 844));

      expect(find.text(tr('mobileChat.context.weather', {'uv': 6, 'temp': 18})), findsOneWidget);
      expect(find.text(tr('mobileChat.context.routine', {'done': 1, 'total': 2})), findsOneWidget);
      expect(find.text(tr('mobileChat.context.water', {'ml': 750, 'target': 2000})), findsOneWidget);
      final strip = find.descendant(of: find.byType(ChatContextStrip), matching: find.byType(ListView));
      await tester.drag(strip, const Offset(-700, 0));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(tr('mobileChat.context.makeupPending')), findsOneWidget);
      expect(find.text(tr('mobileChat.context.shelf', {'n': 1})), findsOneWidget, reason: 'şerit yana kayar');
      await tester.drag(strip, const Offset(1400, 0));
      await tester.pump(const Duration(milliseconds: 300));

      await tapText(tester, tr('mobileChat.context.weather', {'uv': 6, 'temp': 18}));
      expect(h.router.routeInformationProvider.value.uri.path, '/dashboard');
    });

    testWidgets('plan alınamadıysa şerit hiç çıkmaz (uydurma bilgi yok)', (tester) async {
      final backend = FakeBackend()..planFails = true;
      await pumpApp(tester, location: '/dashboard/chat', prefs: acceptedPrefs(), backend: backend);
      expect(find.textContaining('ml'), findsNothing);
    });

    test('chatContext: varsayılan hava söylenmez, rutin/su/makyaj/raf bilgisi plana göre', () {
      loadTestI18n('tr');
      TodayPlan plan(Map<String, dynamic> extra) => TodayPlan.fromJson({
            'log_date': '2026-10-10',
            'has_routine': true,
            'weather_source': 'default',
            'weather': {'uv_index': 8, 'temperature': 30},
            ...extra,
          });
      final i18n = I18n.instance;

      expect(chatContext(null, i18n), isEmpty);

      final basic = chatContext(plan(const {}), i18n);
      expect(basic.map((i) => i.id), ['routine', 'water'], reason: 'varsayılan hava ("UV 8") bilgi değildir');
      expect(basic.first.text, tr('mobileChat.context.routine', {'done': 0, 'total': 2}));

      final full = chatContext(
        plan({
          'weather_source': 'live',
          'progress': {
            'routine_morning_done': true,
            'routine_evening_done': true,
            'water_ml_total': 2000,
            'makeup': {'logged': true, 'used': true, 'removed': true},
          },
          'products_out': [
            {'product': 'A', 'finished_at': '2026-10-08T10:00:00+00:00', 'log_date': '2026-10-08', 'days_out': 1},
          ],
        }),
        i18n,
      );
      expect(full.map((i) => i.id), ['weather', 'routine', 'water', 'makeup', 'shelf']);
      expect(full[1].text, tr('mobileChat.context.routineDone'));
      expect(full[3].text, tr('mobileChat.context.makeupDone'));

      expect(chatContext(plan({'has_routine': false}), i18n).map((i) => i.id), ['water'], reason: 'rutini olmayana rutin satırı yok');
    });
  });

  group('yanıt biçimi', () {
    testWidgets('maddeler asılı girintiyle, ":" ile biten kısa satır alt başlık olarak gösterilir', (tester) async {
      final backend = FakeBackend()
        ..chatReply = 'Niasinamid bariyeri destekler.\n\nŞunlara dikkat et:\n• Yeni ürünü önce yama testiyle dene\n- Aynı akşam asitle karıştırma\n1. Güneş kremi şart\n\nEk okuma: kaynak 1';
      await pumpApp(tester, location: '/dashboard/chat', backend: backend);
      await ask(tester, 'Niasinamid?');

      expect(find.text('Niasinamid bariyeri destekler.'), findsOneWidget);
      expect(find.text('Şunlara dikkat et:'), findsOneWidget);
      expect(find.text('Yeni ürünü önce yama testiyle dene'), findsOneWidget, reason: 'madde işareti metinden ayrı çizilir');
      expect(find.text('Aynı akşam asitle karıştırma'), findsOneWidget);
      expect(find.text('Güneş kremi şart'), findsOneWidget);
      expect(find.text('Ek okuma: kaynak 1'), findsOneWidget);
      expect(find.text('•'), findsNWidgets(2), reason: '"•" ve "-" maddeleri aynı işaretle çizilir');
      expect(find.text('1.'), findsOneWidget);
    });

    testWidgets('bitişik satır sonları korunur, boş satırlar paragraf ayırır', (tester) async {
      await tester.pumpWidget(const _Host(ReplyText('Birinci satır\nİkinci satır\n\n\nÜçüncü', color: Color(0xFF000000))));
      expect(find.text('Birinci satır'), findsOneWidget);
      expect(find.text('İkinci satır'), findsOneWidget);
      expect(find.text('Üçüncü'), findsOneWidget);
    });
  });

  group('sohbet hakkı doldu kartı', () {
    testWidgets('İngilizcede kart çevrilidir; satın alma varsa Plus düğmeleri de', (tester) async {
      plusPurchasableOverride = true;
      final backend = FakeBackend()..quotaAfter = 0;
      await pumpApp(tester, location: '/dashboard/chat', backend: backend, lang: 'en');
      await ask(tester, 'Hi');

      expect(find.text(tr('chat.paywallTitleDay')), findsOneWidget);
      expect(find.text('Open Rebi Plus'), findsOneWidget);
      expect(find.text('Close for now'), findsOneWidget);
      expect(find.text(tr('mobileChat.limit.bulletData')), findsOneWidget);
      expect(find.text('Açık'), findsNothing);
    });

    testWidgets('limit kartı açıkken yazma alanı kilitli; kapatınca kart kalkar', (tester) async {
      final backend = FakeBackend()..quotaAfter = 0;
      await pumpApp(tester, location: '/dashboard/chat', backend: backend);
      await ask(tester, 'Merhaba');
      expect(find.text(tr('mobileChat.limit.titleDay')), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);

      await tapText(tester, tr('mobileChat.limit.close'));
      expect(find.text(tr('mobileChat.limit.titleDay')), findsNothing);
      expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isFalse);
    });
  });

  group('320 px ve %200 yazı', () {
    for (final lang in ['tr', 'en']) {
      testWidgets('sohbet: boş, konuşma, hata ve limit kartı taşmaz ($lang)', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2.0;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final backend = FakeBackend()
          ..chatFailTimes = 1
          ..chatReply = 'Uzun bir yanıt: ${'çok uzun bir cümle ' * 12}\n• madde bir ${'uzun ' * 20}\n• madde iki';
        await pumpApp(tester, location: '/dashboard/chat', backend: backend, size: const Size(320, 640), lang: lang);
        expect(tester.takeException()?.toString(), isNull, reason: 'boş durum');

        await ask(tester, 'Soru');
        expect(tester.takeException()?.toString(), isNull, reason: 'hata kartı');

        await tapText(tester, tr('mobileChat.retry'));
        expect(tester.takeException()?.toString(), isNull, reason: 'uzun yanıt');
      });
    }
  });
}

class _Host extends StatelessWidget {
  const _Host(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context) => MaterialApp(home: Scaffold(body: Center(child: child)));
}
