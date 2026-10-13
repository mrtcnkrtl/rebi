import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/core/api.dart';
import 'package:rebi/core/daily_tracking.dart';
import 'package:rebi/core/demo_user.dart';
import 'package:rebi/core/event_outbox.dart';
import 'package:rebi/core/local_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/app_harness.dart';

OutboxEvent event(
  String id, {
  String userId = testUserId,
  String type = 'water_intake',
  Map<String, dynamic> payload = const {'ml': 250},
  int? queuedAt,
  int attempts = 0,
}) =>
    OutboxEvent(
      id: id,
      userId: userId,
      type: type,
      payload: payload,
      timestamp: '2026-10-10T09:00:00+03:00',
      queuedAt: queuedAt ?? DateTime.now().millisecondsSinceEpoch,
      attempts: attempts,
    );

void main() {
  late FakeBackend backend;
  late EventOutbox outbox;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalStore.init();
    backend = FakeBackend();
    apiHttpClient = backend.client;
    outbox = EventOutbox.instance..debugReset();
  });

  List<String> sentIds() => [
        for (final r in backend.calls('/daily_tracking/ingest')) (jsonDecode(r.body) as Map)['client_event_id'] as String,
      ];

  group('classifyIngestStatus', () {
    test('2xx ulaştı; geçici hatalar yeniden denenir; kalıcı 4xx düşer', () {
      for (final s in [200, 201, 204]) {
        expect(classifyIngestStatus(s), DeliveryKind.delivered, reason: '$s');
      }
      for (final s in [401, 408, 425, 429, 500, 502, 503, 504]) {
        expect(classifyIngestStatus(s), DeliveryKind.retry, reason: '$s');
      }
      for (final s in [400, 403, 404, 413, 422]) {
        expect(classifyIngestStatus(s), DeliveryKind.drop, reason: '$s');
      }
    });
  });

  group('OutboxEvent', () {
    test('JSON gidiş-dönüşü ve istek gövdesi sözleşmeye uyar', () {
      final e = event('abc', type: 'makeup', payload: {'used': true}, attempts: 2);
      final back = OutboxEvent.fromJson(jsonDecode(jsonEncode(e.toJson())) as Map<String, dynamic>);
      expect(back.id, 'abc');
      expect(back.payload, {'used': true});
      expect(back.attempts, 2);
      expect(back.queuedAt, e.queuedAt);
      expect(e.toRequest(), {
        'user_id': testUserId,
        'type': 'makeup',
        'payload': {'used': true},
        'source': 'mobile',
        'timestamp': '2026-10-10T09:00:00+03:00',
        'client_event_id': 'abc',
      });
    });

    test('bozuk kayıt çökmeden boş değerlere düşer', () {
      final e = OutboxEvent.fromJson({'payload': 'x', 'attempts': 'y'});
      expect(e.id, '');
      expect(e.payload, isEmpty);
      expect(e.attempts, 0);
    });

    test('at: zaman damgasını yerel ana çevirir', () {
      expect(event('a').at, DateTime.parse('2026-10-10T09:00:00+03:00').toLocal());
      expect(OutboxEvent.fromJson({'timestamp': 'bozuk'}).at, isNull);
    });
  });

  group('kuyruk', () {
    test('olaylar cihazda kalıcıdır ve uygulama yeniden açılınca geri gelir', () async {
      await outbox.add(event('a'));
      await outbox.add(event('b'));
      outbox.debugReset(); // bellek önbelleği gitti, SharedPreferences durur
      expect(outbox.pending(testUserId).map((e) => e.id), ['a', 'b']);
    });

    test('kullanıcılar ayrı tutulur', () async {
      await outbox.add(event('a'));
      await outbox.add(event('x', userId: 'baska-kullanici'));
      expect(outbox.pending(testUserId).map((e) => e.id), ['a']);
      expect(outbox.pending('baska-kullanici').map((e) => e.id), ['x']);
    });

    test('aynı kimlik ikinci kez eklenmez', () async {
      await outbox.add(event('a'));
      await outbox.add(event('a'));
      expect(outbox.pendingCount(testUserId), 1);
    });

    test('7 günden eski olaylar ayıklanır', () async {
      final old = DateTime.now().subtract(const Duration(days: 8)).millisecondsSinceEpoch;
      await outbox.add(event('eski', queuedAt: old));
      await outbox.add(event('yeni'));
      outbox.debugReset();
      expect(outbox.pending(testUserId).map((e) => e.id), ['yeni']);
    });

    test('kuyruk 200 olayı aşınca en eskiler atılır', () async {
      for (var i = 0; i < EventOutbox.maxQueue + 5; i++) {
        await outbox.add(event('e$i'));
      }
      final ids = outbox.pending(testUserId).map((e) => e.id).toList();
      expect(ids, hasLength(EventOutbox.maxQueue));
      expect(ids.first, 'e5');
      expect(ids.last, 'e${EventOutbox.maxQueue + 4}');
    });

    test('clear kullanıcının bekleyenlerini diskten de siler', () async {
      await outbox.add(event('a'));
      await outbox.clear(testUserId);
      outbox.debugReset();
      expect(outbox.pendingCount(testUserId), 0);
    });

    test('bozuk disk verisi çökertmez', () async {
      await LocalStore.instance.setString('rebi_event_outbox_v1_$testUserId', '{bozuk');
      outbox.debugReset();
      expect(outbox.pendingCount(testUserId), 0);
    });
  });

  group('flush', () {
    test('eskiden yeniye sırayla gönderir ve gönderilenleri siler', () async {
      for (final id in ['a', 'b', 'c']) {
        await outbox.add(event(id));
      }
      final before = outbox.deliveries;
      expect(await outbox.flush(testUserId), 3);
      expect(sentIds(), ['a', 'b', 'c']);
      expect(outbox.pendingCount(testUserId), 0);
      expect(outbox.deliveries, before + 1, reason: 'tek flush tek tazeleme işareti verir');
      expect(backend.waterMl, 750);
    });

    test('ilk geçici hatada durur, kalanlar yerinde ve sıralı kalır', () async {
      for (final id in ['a', 'b', 'c']) {
        await outbox.add(event(id));
      }
      backend.ingestOffline = true;
      expect(await outbox.flush(testUserId), 0);
      expect(backend.calls('/daily_tracking/ingest'), hasLength(1), reason: 'sunucu boşuna yorulmaz');
      final left = outbox.pending(testUserId);
      expect(left.map((e) => e.id), ['a', 'b', 'c']);
      expect(left.first.attempts, 1);
      expect(left.last.attempts, 0);
    });

    test('yeniden denemede aynı kimlik ve zaman damgası gider, sunucu iki kez saymaz', () async {
      await outbox.add(event('a'));
      backend.ingestOffline = true;
      await outbox.flush(testUserId);
      backend.ingestOffline = false;
      await outbox.flush(testUserId);

      final bodies = [for (final r in backend.calls('/daily_tracking/ingest')) jsonDecode(r.body) as Map];
      expect(bodies, hasLength(2));
      expect(bodies[0]['client_event_id'], bodies[1]['client_event_id']);
      expect(bodies[0]['timestamp'], bodies[1]['timestamp']);
      expect(backend.waterMl, 250);
    });

    test('ağ gönderimi sunucuda yazılmış ama yanıtı kaybolmuşsa tekrar sayılmaz', () async {
      // Sunucu olayı yazdı ama yanıt istemciye ulaşmadı: istemci olayı kuyrukta tutar, tekrar gönderir.
      await outbox.add(event('a'));
      await backend.client.post(Uri.parse('$apiUrl/daily_tracking/ingest'), body: jsonEncode(event('a').toRequest()));
      expect(backend.waterMl, 250);
      await outbox.flush(testUserId);
      expect(backend.waterMl, 250, reason: 'aynı client_event_id ikinci kez yazılmadı');
      expect(outbox.pendingCount(testUserId), 0);
    });

    test('kalıcı hata alan olay düşer, kuyruk ilerler', () async {
      await outbox.add(event('a', type: 'water_intake'));
      await outbox.add(event('b'));
      backend.ingestStatus = 422;
      expect(await outbox.flush(testUserId), 0);
      expect(outbox.pendingCount(testUserId), 0, reason: 'tekrar denemekle düzelmeyen olay kuyruğu tıkamaz');
      expect(backend.calls('/daily_tracking/ingest'), hasLength(2));
    });

    test('geçici sunucu hatası (500) olayı kuyrukta tutar', () async {
      await outbox.add(event('a'));
      backend.ingestStatus = 500;
      await outbox.flush(testUserId);
      expect(outbox.pending(testUserId).single.attempts, 1);
    });

    test('çok denenen olay sonunda atılır', () async {
      await outbox.add(event('a', attempts: EventOutbox.maxAttempts - 1));
      await outbox.add(event('b'));
      backend.ingestOffline = true;
      await outbox.flush(testUserId);
      expect(outbox.pending(testUserId).map((e) => e.id), ['b']);
    });

    test('aynı anda tek gönderim çalışır', () async {
      await outbox.add(event('a'));
      final first = outbox.flush(testUserId);
      final second = outbox.flush(testUserId);
      expect(await first, await second);
      expect(backend.calls('/daily_tracking/ingest'), hasLength(1));
    });

    test('gönderim sürerken eklenen olay kaybolmaz', () async {
      await outbox.add(event('a'));
      backend.ingestOffline = true;
      final flushing = outbox.flush(testUserId);
      await outbox.add(event('b'));
      await flushing;
      expect(outbox.pending(testUserId).map((e) => e.id), ['a', 'b']);
    });

    test('boş kuyrukta istek atılmaz', () async {
      expect(await outbox.flush(testUserId), 0);
      expect(backend.requests, isEmpty);
    });
  });

  group('ingestDailyTrackingEvent', () {
    test('çevrimiçi: doğrudan gider, kuyruğa girmez, sözleşmedeki alanları taşır', () async {
      final r = await ingestDailyTrackingEvent(testUserId, 'water_intake', {'ml': 250});
      expect(r.ok, isTrue);
      expect(r.queued, isFalse);
      expect(r.data['aggregated'], isNotNull);
      expect(outbox.pendingCount(testUserId), 0);

      final body = backend.bodyOf('/daily_tracking/ingest');
      expect(body['user_id'], testUserId);
      expect(body['type'], 'water_intake');
      expect(body['payload'], {'ml': 250});
      expect(body['source'], 'mobile');
      expect(body['client_event_id'], isNotEmpty);
      expect(body['timestamp'], matches(RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{2}:\d{2}$')));
    });

    test('çevrimdışı: olay kuyruğa alınır, kullanıcıya "kaydedildi" denir', () async {
      backend.ingestOffline = true;
      final r = await ingestDailyTrackingEvent(testUserId, 'water_intake', {'ml': 500});
      expect(r.ok, isTrue);
      expect(r.queued, isTrue);

      final queued = outbox.pending(testUserId).single;
      expect(queued.type, 'water_intake');
      expect(queued.payload, {'ml': 500});
      expect(queued.id, jsonDecode(backend.calls('/daily_tracking/ingest').single.body)['client_event_id']);
    });

    test('sunucu hatası (503) da kuyruğa alır', () async {
      backend.ingestStatus = 503;
      final r = await ingestDailyTrackingEvent(testUserId, 'spf_refresh');
      expect(r.queued, isTrue);
      expect(outbox.pendingCount(testUserId), 1);
    });

    test('kalıcı red (422) kuyruğa girmez ve başarısız döner', () async {
      backend.ingestStatus = 422;
      final r = await ingestDailyTrackingEvent(testUserId, 'water_intake', {'ml': 250});
      expect(r.ok, isFalse);
      expect(r.queued, isFalse);
      expect(outbox.pendingCount(testUserId), 0);
    });

    test('demo ve oturumsuz kullanıcıda hiçbir şey gönderilmez', () async {
      expect((await ingestDailyTrackingEvent(demoUserId, 'water_intake')).skipped, isTrue);
      expect((await ingestDailyTrackingEvent(null, 'water_intake')).skipped, isTrue);
      expect((await ingestDailyTrackingEvent('', 'water_intake')).skipped, isTrue);
      expect(backend.requests, isEmpty);
      expect(outbox.pendingCount(demoUserId), 0);
    });

    test('bağlantı dönünce yeni kayıt birikmiş olanları da boşaltır', () async {
      backend.ingestOffline = true;
      await ingestDailyTrackingEvent(testUserId, 'water_intake', {'ml': 250});
      await ingestDailyTrackingEvent(testUserId, 'water_intake', {'ml': 250});
      expect(outbox.pendingCount(testUserId), 2);

      backend.ingestOffline = false;
      final r = await ingestDailyTrackingEvent(testUserId, 'water_intake', {'ml': 500});
      expect(r.queued, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(outbox.pendingCount(testUserId), 0);
      expect(backend.waterMl, 1000, reason: 'üç kayıt da tam bir kez sayıldı');
      expect(backend.storedEventIds, hasLength(3));
    });
  });
}
