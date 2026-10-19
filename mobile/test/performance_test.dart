import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rebi/core/api.dart';
import 'package:rebi/core/device_location.dart';
import 'package:rebi/core/event_outbox.dart';
import 'package:rebi/core/local_store.dart';
import 'package:rebi/state/today_plan_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Faz G2: yavaş ağda ve soğuk açılışta ekranın boş beklememesi.
/// (Gerçek cihazdaki süre ölçümleri `docs/MOBIL-CIHAZ-TESTI.md` §7'de.)
String _planJson() => File('../contract/today_plan.json').readAsStringSync();

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalStore.init();
  });
  tearDown(() {
    resetDeviceLocationLookup();
    apiHttpClient = http.Client();
  });

  group('Bugün planı soğuk açılışta', () {
    testWidgets('konum bulunamıyorsa plan 2,5 sn sonra konumsuz istenir (GPS beklemesi ekranı tutmaz)', (tester) async {
      final seen = <Uri>[];
      apiHttpClient = MockClient((request) async {
        seen.add(request.url);
        return http.Response(_planJson(), 200, headers: {'content-type': 'application/json; charset=utf-8'});
      });
      deviceLocationLookup = () => Completer<Coordinates?>().future; // GPS hiç yanıt vermez
      final controller = TodayPlanController(userId: 'u1', outbox: EventOutbox());

      unawaited(controller.load(useLocation: true));
      await tester.pump(const Duration(seconds: 2));
      expect(seen, isEmpty, reason: 'sınır dolmadan istek atılmaz');
      expect(controller.loading, isTrue);

      await tester.pump(const Duration(milliseconds: 700));
      await _settle(tester);
      expect(seen, hasLength(1));
      expect(seen.single.queryParameters.containsKey('lat'), isFalse, reason: 'konum yokken koordinat gönderilmez');
      expect(controller.plan, isNotNull);
      expect(controller.loading, isFalse);
      expect(controller.failed, isFalse);
      controller.dispose();
    });

    testWidgets('konum hızlı gelirse beklemeden, koordinatla istenir', (tester) async {
      final seen = <Uri>[];
      apiHttpClient = MockClient((request) async {
        seen.add(request.url);
        return http.Response(_planJson(), 200, headers: {'content-type': 'application/json; charset=utf-8'});
      });
      deviceLocationLookup = () async => (lat: 41.01, lon: 28.97);
      final controller = TodayPlanController(userId: 'u1', outbox: EventOutbox());

      unawaited(controller.load(useLocation: true));
      await _settle(tester);
      expect(seen.single.queryParameters['lat'], '41.01');
      expect(controller.plan, isNotNull);
      controller.dispose();
    });
  });

  group('yavaş ağ', () {
    testWidgets('tazeleme yanıt vermezse eldeki plan ekranda kalır; hata ekranı çıkmaz', (tester) async {
      var calls = 0;
      apiHttpClient = MockClient((request) {
        calls++;
        if (calls == 1) {
          return Future.value(http.Response(_planJson(), 200, headers: {'content-type': 'application/json; charset=utf-8'}));
        }
        return Completer<http.Response>().future; // ikinci istek asılı kalır
      });
      final controller = TodayPlanController(userId: 'u1', outbox: EventOutbox());

      unawaited(controller.load(useLocation: false));
      await _settle(tester);
      final firstDate = controller.plan?.logDate;
      expect(firstDate, isNotNull);

      unawaited(controller.reload());
      await tester.pump(const Duration(seconds: 19));
      expect(controller.plan?.logDate, firstDate, reason: 'bekleme sürerken ekran değişmez');
      expect(controller.failed, isFalse);
      await tester.pump(const Duration(seconds: 2));
      await _settle(tester);
      expect(controller.plan, isNotNull, reason: '20 sn sonra bırakılır ama eldeki plan silinmez');
      expect(controller.failed, isFalse);
      controller.dispose();
    });

    testWidgets('ilk açılışta ağ hiç yoksa yükleme biter ve "alınamadı" durumu çıkar (sonsuz dönmez)', (tester) async {
      apiHttpClient = MockClient((request) => Completer<http.Response>().future);
      final controller = TodayPlanController(userId: 'u1', outbox: EventOutbox());

      unawaited(controller.load(useLocation: false));
      await _settle(tester);
      expect(controller.loading, isTrue);
      await tester.pump(const Duration(seconds: 21));
      await _settle(tester);
      expect(controller.loading, isFalse);
      expect(controller.failed, isTrue);
      expect(controller.plan, isNull);
      controller.dispose();
    });
  });

  group('kaydırma akıcılığı (kod kuralı)', () {
    test('kaydırılan ekranlarda pahalı çizim yok: bulanıklık, gölge-maske, kırpılmış filtre', () {
      final banned = RegExp(r'\b(BackdropFilter|ShaderMask|ImageFiltered|ColorFiltered)\s*\(');
      final hits = <String>[];
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
        final lines = const LineSplitter().convert(f.readAsStringSync());
        for (var i = 0; i < lines.length; i++) {
          if (banned.hasMatch(lines[i])) hits.add('${f.path}:${i + 1}');
        }
      }
      expect(hits, isEmpty, reason: 'Her kare yeniden çizilen katman filtreleri düşük cihazda kaydırmayı takıltır');
    });
  });
}
