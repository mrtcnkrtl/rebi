import 'package:flutter/material.dart' show TextField;
import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/core/chat_suggestions.dart';
import 'package:rebi/core/i18n.dart';
import 'package:rebi/core/today_plan.dart';

import 'helpers/app_harness.dart';

TodayPlan plan({
  Map<String, dynamic> weather = const {'uv_index': 2, 'humidity': 50, 'temperature': 20},
  String source = 'live',
  Map<String, dynamic> progress = const {},
}) =>
    TodayPlan.fromJson({'weather': weather, 'weather_source': source, 'progress': progress, 'reminders': const []});

void main() {
  final morning = DateTime(2026, 10, 10, 9);
  final evening = DateTime(2026, 10, 10, 18);

  setUp(() => loadTestI18n('tr'));

  List<String> ids(TodayPlan? p, DateTime at) => [for (final s in chatSuggestions(p, at, I18n.instance)) s.id];

  group('öneri kuralları', () {
    test('plan yokken yalnızca genel sorular çıkar', () {
      expect(ids(null, morning), ['generic1', 'generic2', 'generic3']);
    });

    test('yüksek UV güneş kremi sorusunu, orta UV SPF yeter mi sorusunu getirir; metne UV işlenir', () {
      expect(ids(plan(weather: {'uv_index': 8, 'humidity': 50, 'temperature': 22}), morning).first, 'uvHigh');
      expect(ids(plan(weather: {'uv_index': 4, 'humidity': 50, 'temperature': 22}), morning).first, 'uvMid');
      expect(ids(plan(weather: {'uv_index': 2, 'humidity': 50, 'temperature': 22}), morning), isNot(contains('uvMid')));

      final s = chatSuggestions(plan(weather: {'uv_index': 7.6, 'humidity': 50, 'temperature': 22}), morning, I18n.instance).first;
      expect(s.text, 'Bugün UV 8. Güneş kremimi ne sıklıkla yenilemeliyim?');
    });

    test('tahmini (varsayılan) hava için hava sorusu önerilmez', () {
      final p = plan(weather: {'uv_index': 9, 'humidity': 20, 'temperature': 35}, source: 'default');
      expect(ids(p, morning), ['generic1', 'generic2', 'generic3']);
    });

    test('soğuk, sıcak ve kuru hava', () {
      expect(ids(plan(weather: {'uv_index': 1, 'humidity': 60, 'temperature': 4}), morning), contains('cold'));
      expect(ids(plan(weather: {'uv_index': 1, 'humidity': 60, 'temperature': 33}), morning), contains('hot'));
      expect(ids(plan(weather: {'uv_index': 1, 'humidity': 25, 'temperature': 20}), morning), contains('dry'));
      final cold = ids(plan(weather: {'uv_index': 1, 'humidity': 60, 'temperature': 4}), morning);
      expect(cold, isNot(contains('hot')));
    });

    test('makyaj: temizlenmediyse temizleme, mendil/suyla temizlendiyse yeterlilik sorusu', () {
      expect(ids(plan(progress: {'makeup': {'logged': true, 'used': true, 'removed': false}}), evening), contains('makeupPending'));
      final light = ids(plan(progress: {'makeup': {'logged': true, 'used': true, 'removed': true, 'removal_method': 'wipe'}}), evening);
      expect(light, contains('makeupLight'));
      expect(light, isNot(contains('makeupPending')));
      expect(ids(plan(progress: {'makeup': {'logged': true, 'used': true, 'removed': true, 'removal_method': 'double'}}), evening),
          isNot(anyOf(contains('makeupPending'), contains('makeupLight'))));
      expect(ids(plan(progress: {'makeup': {'logged': true, 'used': false}}), evening), isNot(contains('makeupPending')));
    });

    test('beslenme: şekerli, süt ürünü, abur cubur sırasıyla tek soru', () {
      expect(ids(plan(progress: {'nutrition': {'sweets': true, 'dairy': true, 'snacks': true}}), morning), contains('sweets'));
      final dairy = ids(plan(progress: {'nutrition': {'dairy': true, 'snacks': true}}), morning);
      expect(dairy, contains('dairy'));
      expect(dairy, isNot(contains('snacks')));
      expect(ids(plan(progress: {'nutrition': {'fried_food': true}}), morning), contains('snacks'));
      expect(ids(plan(progress: {'nutrition': {'junk_food': true}}), morning), contains('snacks'), reason: 'eski kayıt');
      expect(ids(plan(progress: {'nutrition': {'balanced': true}}), morning), isNot(anyOf(contains('sweets'), contains('snacks'))));
    });

    test('az su sorusu yalnızca öğleden sonra ve hedefin %40ının altındaysa', () {
      final low = plan(progress: {'water_ml_total': 300});
      expect(ids(low, morning), isNot(contains('lowWater')));
      expect(ids(low, evening), contains('lowWater'));
      expect(ids(plan(progress: {'water_ml_total': 1200}), evening), isNot(contains('lowWater')));
    });

    test('en çok dört öneri, önem sırasıyla; az olunca genel sorularla üçe tamamlanır', () {
      final busy = plan(
        weather: {'uv_index': 9, 'humidity': 20, 'temperature': 34},
        progress: {
          'water_ml_total': 100,
          'makeup': {'logged': true, 'used': true, 'removed': false},
          'nutrition': {'sweets': true},
        },
      );
      expect(ids(busy, evening), ['uvHigh', 'hot', 'dry', 'makeupPending']);

      final one = ids(plan(progress: {'nutrition': {'dairy': true}}), morning);
      expect(one, ['dairy', 'generic1', 'generic2']);
    });

    test('İngilizce metinler gelir', () {
      loadTestI18n('en');
      final s = chatSuggestions(plan(weather: {'uv_index': 8, 'humidity': 50, 'temperature': 22}), morning, I18n.instance).first;
      expect(s.text, 'UV is 8 today. How often should I reapply sunscreen?');
    });
  });

  group('sohbet ekranı', () {
    Map<String, dynamic> richPlan(FakeBackend b) => {
          ...b.todayPlan,
          'weather': {'uv_index': 8, 'humidity': 30, 'temperature': 31},
          'weather_source': 'live',
          'progress': {
            'makeup': {'logged': true, 'used': true, 'removed': false},
          },
        };

    testWidgets('boş sohbette bugünün verisinden öneriler görünür; dokunmak mesajı gönderir', (tester) async {
      final backend = FakeBackend();
      backend.todayPlan = richPlan(backend);
      final h = await pumpApp(tester, location: '/dashboard/chat', backend: backend);

      expect(find.text(tr('mobileChat.suggestionsTitle')), findsOneWidget);
      final uv = tr('mobileChat.suggestions.uvHigh', {'uv': 8});
      expect(find.text(uv), findsOneWidget);
      expect(find.text(tr('mobileChat.suggestions.makeupPending')), findsOneWidget);

      await tapText(tester, uv);
      final body = h.backend.bodyOf('/chat_general');
      expect(body['message'], uv);
      expect(body['history'], [
        {'role': 'user', 'content': uv},
      ]);
      expect(find.textContaining('Niasinamid bariyeri destekler.'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty, reason: 'yazı alanına dokunulmaz');
    });

    testWidgets('sohbet gönderimi kullanıcının saat farkını taşır', (tester) async {
      final h = await pumpApp(tester, location: '/dashboard/chat');
      await tester.enterText(find.byType(TextField), 'Merhaba');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await settle(tester);
      expect(h.backend.bodyOf('/chat_general')['utc_offset_minutes'], DateTime.now().timeZoneOffset.inMinutes);
    });

    testWidgets('konuşma sürerken öneriler giriş alanının üstünde kalır; yazarken ve beklerken gizlenir', (tester) async {
      final backend = FakeBackend();
      backend.todayPlan = richPlan(backend);
      await pumpApp(tester, location: '/dashboard/chat', backend: backend);
      await tapText(tester, tr('mobileChat.suggestions.makeupPending'));
      expect(find.text(tr('chat.emptyTitle')), findsNothing, reason: 'konuşma başladı');
      expect(find.text(tr('mobileChat.suggestions.makeupPending')), findsWidgets, reason: 'şerit hâlâ var');
      expect(find.text(tr('mobileChat.suggestionsTitle')), findsNothing, reason: 'başlık yalnızca boş durumda');

      await tester.enterText(find.byType(TextField), 'bir şey yazıyorum');
      await tester.pump();
      expect(find.text(tr('mobileChat.suggestions.uvHigh', {'uv': 8})), findsNothing, reason: 'yazarken gizlenir');
    });

    testWidgets('anonim sohbette genel öneriler çıkar ve plan istenmez', (tester) async {
      final h = await pumpApp(tester, location: '/rebi', loggedIn: false);
      expect(find.text(tr('mobileChat.suggestions.generic1')), findsOneWidget);
      expect(h.backend.calls('/today/plan'), isEmpty);
    });

    testWidgets('plan alınamazsa genel öneriler kalır', (tester) async {
      final backend = FakeBackend()..planFails = true;
      await pumpApp(tester, location: '/dashboard/chat', backend: backend);
      expect(find.text(tr('mobileChat.suggestions.generic1')), findsOneWidget);
      expect(find.text(tr('chat.emptyTitle')), findsOneWidget);
    });

    testWidgets('kota dolunca öneri çipleri mesaj göndermez', (tester) async {
      final backend = FakeBackend()..quotaAfter = 0;
      await pumpApp(tester, location: '/dashboard/chat', backend: backend);
      await tapText(tester, tr('mobileChat.suggestions.generic1'));
      expect(find.text(tr('chat.paywallTitleDay')), findsOneWidget);
      expect(find.text(tr('mobileChat.suggestions.generic2')), findsNothing, reason: 'paywall açıkken öneri şeridi gizlenir');
    });
  });
}
