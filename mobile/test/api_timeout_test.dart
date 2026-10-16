import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rebi/core/api.dart';

/// Yanıt vermeyen bir sunucu: istek hiç tamamlanmaz.
http.Client _silentServer(List<Uri> seen) => MockClient((request) {
      seen.add(request.url);
      return Completer<http.Response>().future;
    });

void main() {
  test('kısa uçlar 20 sn, yapay zekâ uçları 120 sn bekler', () {
    expect(apiTimeout, const Duration(seconds: 20));
    expect(apiLongTimeout, const Duration(seconds: 120));
  });

  testWidgets('okuma çağrısı yanıt gelmezse 20 sn sonra bırakılır (ekran iki dakika dönmez)', (tester) async {
    apiHttpClient = _silentServer([]);
    Object? error;
    unawaited(apiGet('/today/plan', auth: false).then<void>((_) {}, onError: (Object e) => error = e));

    await tester.pump(const Duration(seconds: 19));
    expect(error, isNull);
    await tester.pump(const Duration(seconds: 2));
    expect(error, isA<TimeoutException>());
    expect(isNetworkError(error!), isTrue); // olay kuyruğu bunu "ağ yok" sayıp yeniden dener
  });

  testWidgets('olay kaydı (POST) de 20 sn sonra bırakılır', (tester) async {
    apiHttpClient = _silentServer([]);
    Object? error;
    unawaited(apiPost('/daily_tracking/ingest', {'type': 'water_intake'}, auth: false)
        .then<void>((_) {}, onError: (Object e) => error = e));

    await tester.pump(const Duration(seconds: 21));
    expect(error, isA<TimeoutException>());
  });

  testWidgets('uzun zaman aşımı verilen yapay zekâ çağrısı 20 sn sonra bırakılmaz', (tester) async {
    apiHttpClient = _silentServer([]);
    Object? error;
    var finished = false;
    unawaited(apiPost('/chat_general', {'message': 'merhaba'}, auth: false, timeout: apiLongTimeout)
        .then<void>((_) => finished = true, onError: (Object e) => error = e));

    await tester.pump(const Duration(seconds: 60));
    expect(error, isNull);
    expect(finished, isFalse);

    await tester.pump(const Duration(seconds: 61));
    expect(error, isA<TimeoutException>());
  });
}
