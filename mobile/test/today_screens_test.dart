import 'dart:convert';

import 'package:flutter/material.dart' show Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/core/daily_tracking.dart';
import 'package:rebi/core/device_location.dart';
import 'package:rebi/core/routine_tracking.dart';
import 'package:rebi/screens/dashboard_today.dart';

import 'helpers/app_harness.dart';

/// Açılış paketi (`/me/snapshot`) ve bugünün planı (`/today/plan`): panelin "bugün" bölümü.
/// Sözleşme: `docs/MOBIL-API.md`.
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

  Map<String, dynamic> reminder(
    String id,
    String title,
    String start,
    String end, {
    String? logEvent,
    int? every,
    String body = 'Gövde',
  }) =>
      {'id': id, 'title': title, 'body': body, 'start': start, 'end': end, 'every_minutes': every, 'log_event': logEvent};

  setUp(() => todayPanelClock = () => DateTime(2026, 10, 10, 9, 15));
  tearDown(() {
    todayPanelClock = DateTime.now;
    resetDeviceLocationLookup();
  });

  group('açılış paketi', () {
    testWidgets('rutin ilk açılışta /me/snapshot ile gelir', (tester) async {
      final backend = FakeBackend();
      backend.snapshot = {...backend.snapshot, 'has_routine': true, 'routine': routine};
      final h = await pumpApp(tester, location: '/dashboard', backend: backend);

      expect(h.backend.calls('/me/snapshot'), isNotEmpty);
      expect(h.backend.calls('/me/snapshot').first.url.queryParameters['user_id'], testUserId);
      expect(find.text(tr('dashboard.acceptBanner')), findsOneWidget, reason: 'sunucudaki rutin panelde görünür');
      expect(find.text(tr('dashboard.noAnalyzeDesc')), findsNothing);
    });

    testWidgets('paket alınamazsa panel çökmez, rutin yoksa analiz çağrısı çıkar', (tester) async {
      final backend = FakeBackend()..snapshotFails = true;
      await pumpApp(tester, location: '/dashboard', backend: backend);
      expect(find.text(tr('dashboard.startAnalyze')), findsOneWidget);
      expect(find.text(tr('common.consentRecoveryTitle')), findsNothing);
    });

    testWidgets('rıza kaydı yoksa açılışta onay kutusu çıkar', (tester) async {
      final backend = FakeBackend();
      backend.snapshot = {
        ...backend.snapshot,
        'consent': {'legal_accepted': false, 'ai_processing_allowed': false},
      };
      await pumpApp(tester, location: '/dashboard', backend: backend);
      expect(find.text(tr('common.consentRecoveryTitle')), findsOneWidget);
    });

    testWidgets('rıza tamamsa onay kutusu çıkmaz', (tester) async {
      await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs());
      expect(find.text(tr('common.consentRecoveryTitle')), findsNothing);
    });
  });

  group('bugünün planı', () {
    testWidgets('şu an açık hatırlatıcı eylemiyle gelir, sıradakiler listelenir', (tester) async {
      final backend = FakeBackend();
      backend.todayPlan = {
        ...backend.todayPlan,
        'reminders': [
          reminder('routine_morning', 'Sabah rutini', '07:30', '09:30', logEvent: 'routine_completed_block'),
          reminder('makeup_log', 'Bugün makyaj yaptın mı?', '10:00', '11:00', logEvent: 'makeup'),
          reminder('water_intake', 'Su içme zamanı', '09:00', '21:00', logEvent: 'water_intake', every: 120),
          reminder('routine_evening', 'Akşam rutini', '21:00', '23:00', logEvent: 'routine_completed_block'),
          reminder('lip_balm', 'Dudak balsamı', '07:00', '08:00'),
        ],
      };
      final h = await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs(), backend: backend);

      expect(h.backend.calls('/today/plan'), hasLength(1));
      expect(find.text(tr('mobileToday.title')), findsOneWidget);
      expect(find.text('Sabah rutini'), findsOneWidget, reason: '09:15 sabah penceresinde');
      expect(find.text('10:00 · Bugün makyaj yaptın mı?'), findsOneWidget);
      expect(find.text('21:00 · Akşam rutini'), findsOneWidget);
      expect(find.text('Dudak balsamı'), findsNothing, reason: 'penceresi geçmiş');
      expect(find.text('Su içme zamanı'), findsNothing, reason: 'su ayrı satırda gösterilir');

      await tapText(tester, tr('mobileToday.actions.done'));
      final body = h.backend.bodyOf('/daily_tracking/ingest');
      expect(body['type'], 'routine_completed_block');
      expect(body['payload'], {'morning': true});
      expect(body['source'], 'mobile');
      expect(h.backend.calls('/today/plan'), hasLength(2), reason: 'kayıttan sonra plan tazelenir');
    });

    testWidgets('su kaydı ilerlemeyi hemen günceller', (tester) async {
      final h = await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs());
      expect(find.text(tr('mobileToday.waterProgress', {'ml': 0, 'target': 2000})), findsOneWidget);

      await tapText(tester, tr('mobileToday.actions.water250'));
      expect(h.backend.bodyOf('/daily_tracking/ingest')['type'], 'water_intake');
      expect(h.backend.bodyOf('/daily_tracking/ingest')['payload'], {'ml': 250});
      expect(find.text(tr('mobileToday.waterProgress', {'ml': 250, 'target': 2000})), findsOneWidget);

      await tapText(tester, tr('mobileToday.actions.water500'));
      expect(find.text(tr('mobileToday.waterProgress', {'ml': 750, 'target': 2000})), findsOneWidget);
    });

    testWidgets('su hedefi dolunca düğmeler kalkar', (tester) async {
      final backend = FakeBackend()..waterMl = 2000;
      await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs(), backend: backend);
      expect(find.text(tr('mobileToday.waterGoalReached')), findsOneWidget);
      expect(find.text(tr('mobileToday.actions.water250')), findsNothing);
    });

    testWidgets('yapılan işler rozet olarak görünür, check-in tamamlandı yazar', (tester) async {
      final backend = FakeBackend();
      backend.todayPlan = {
        ...backend.todayPlan,
        'checkin_done': true,
        'progress': {
          'routine_morning_done': true,
          'spf_refreshes': 2,
          'makeup': {'logged': true, 'used': true, 'removed': false},
        },
      };
      await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs(), backend: backend);
      expect(find.text(tr('mobileToday.morningDone')), findsOneWidget);
      expect(find.text(tr('mobileToday.spfRefreshed', {'n': 2})), findsOneWidget);
      expect(find.text(tr('mobileToday.makeupUsed')), findsOneWidget);
      expect(find.text(tr('mobileToday.eveningDone')), findsNothing);
      expect(find.text(tr('mobileToday.checkinDoneToday')), findsOneWidget);
    });

    testWidgets('check-in hatırlatıcısı ekrana götürür', (tester) async {
      final backend = FakeBackend();
      backend.todayPlan = {
        ...backend.todayPlan,
        'reminders': [reminder('daily_checkin', 'Günlük check-in', '08:00', '22:30')],
      };
      final h = await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs(), backend: backend);
      await tapText(tester, tr('mobileToday.actions.open'));
      expect(h.router.state.uri.path, '/dashboard/checkin');
    });

    testWidgets('makyaj ve beslenme eylemleri sözleşmedeki yüklerle gider', (tester) async {
      final backend = FakeBackend();
      backend.todayPlan = {
        ...backend.todayPlan,
        'reminders': [
          reminder('makeup_log', 'Bugün makyaj yaptın mı?', '09:00', '11:00', logEvent: 'makeup'),
          reminder('nutrition_log', 'Beslenme kaydı', '09:00', '11:00', logEvent: 'nutrition'),
        ],
      };
      final h = await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs(), backend: backend);

      await tapText(tester, tr('mobileToday.actions.no'));
      var body = h.backend.bodyOf('/daily_tracking/ingest');
      expect(body['type'], 'makeup');
      expect(body['payload'], {'used': false});

      await tapText(tester, tr('mobileToday.actions.junkYes'));
      body = h.backend.bodyOf('/daily_tracking/ingest');
      expect(body['type'], 'nutrition');
      expect(body['payload'], {'junk_food': true});
    });

    testWidgets('İngilizce arayüzde hatırlatıcılar çevrilir, çevirisi olmayan olduğu gibi kalır', (tester) async {
      final backend = FakeBackend();
      backend.todayPlan = {
        ...backend.todayPlan,
        'weather': {'uv_index': 7, 'humidity': 40, 'temperature': 24},
        'reminders': [
          reminder('routine_morning', 'Sabah rutini', '07:30', '09:30'),
          reminder('spf_refresh', 'Güneş kremini yenile', '09:00', '16:00', body: 'UV 7. Dışarıdaysan 2 saatte bir tazele.'),
          reminder('yeni_hatirlatici', 'Yeni bir hatırlatıcı', '09:00', '10:00', body: 'Sunucudan'),
        ],
      };
      await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs(), backend: backend, lang: 'en');

      expect(find.text('Morning routine'), findsOneWidget);
      expect(find.text('Sabah rutini'), findsNothing);
      expect(find.text("UV 7. If you're outside, reapply every 2 hours."), findsOneWidget);
      expect(find.text('Yeni bir hatırlatıcı'), findsOneWidget);
      expect(find.text('Sunucudan'), findsOneWidget);
    });

    testWidgets('havaya göre öneriler ve kaynağı gösterilir', (tester) async {
      final backend = FakeBackend();
      backend.todayPlan = {
        ...backend.todayPlan,
        'weather': {'uv_index': 8, 'humidity': 30, 'temperature': 31},
        'weather_source': 'live',
        'environment_advice': [
          {'time': 'Sabah', 'category': 'Koruma', 'icon': '☀️', 'action': 'SPF 50 sürün', 'detail': 'UV çok yüksek', 'priority': 1},
        ],
      };
      await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs(), backend: backend);
      expect(find.text(tr('mobileToday.advice.title')), findsOneWidget);
      expect(find.text('SPF 50 sürün'), findsOneWidget);
      expect(find.text('UV çok yüksek'), findsOneWidget);
      expect(find.text(tr('mobileToday.advice.weatherLine', {'temp': 31, 'uv': 8, 'humidity': 30})), findsOneWidget);
      expect(find.text(tr('mobileToday.advice.source.live')), findsOneWidget);
      expect(find.text(tr('mobileToday.advice.locationHint')), findsNothing, reason: 'gerçek hava varken ipucu yok');
    });

    testWidgets('varsayılan hava kullanılıyorsa konum ipucu görünür', (tester) async {
      await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs());
      expect(find.text(tr('mobileToday.advice.source.default')), findsOneWidget);
      expect(find.text(tr('mobileToday.advice.locationHint')), findsOneWidget);
    });

    testWidgets('plan yüklenemezse uyarı ve tekrar dene çıkar, tekrar denenince gelir', (tester) async {
      final backend = FakeBackend()..planFails = true;
      final h = await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs(), backend: backend);
      expect(find.text(tr('mobileToday.loadFailed')), findsOneWidget);
      expect(find.text(tr('dashboard.trackingTitle')), findsOneWidget, reason: 'panelin geri kalanı çalışır');

      h.backend.planFails = false;
      await tapText(tester, tr('mobileToday.retry'));
      expect(find.text(tr('mobileToday.loadFailed')), findsNothing);
      expect(find.text(tr('mobileToday.title')), findsOneWidget);
    });
  });

  group('çevrimdışı kuyruk', () {
    String queuedWater(String id, int ml) => jsonEncode([
          {
            'id': id,
            'user_id': testUserId,
            'type': 'water_intake',
            'payload': {'ml': ml},
            'timestamp': localIsoTimestamp(),
            'queued_at': DateTime.now().millisecondsSinceEpoch,
            'attempts': 0,
          },
        ]);

    testWidgets('bağlantı yokken kayıt hemen görünür; bağlantı gelince her biri bir kez gönderilir', (tester) async {
      final backend = FakeBackend()..ingestOffline = true;
      final h = await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs(), backend: backend);
      expect(find.text(tr('mobileToday.pending', {'count': 1})), findsNothing);

      await tapText(tester, tr('mobileToday.actions.water250'));
      expect(find.text(tr('mobileToday.waterProgress', {'ml': 250, 'target': 2000})), findsOneWidget,
          reason: 'sunucu yanıt vermese de ilerleme güncel görünür');
      expect(find.text(tr('mobileToday.queuedHint')), findsOneWidget);
      expect(find.text(tr('mobileToday.pending', {'count': 1})), findsOneWidget);

      await tapText(tester, tr('mobileToday.actions.water500'));
      expect(find.text(tr('mobileToday.waterProgress', {'ml': 750, 'target': 2000})), findsOneWidget);
      expect(find.text(tr('mobileToday.pending', {'count': 2})), findsOneWidget);
      expect(backend.waterMl, 0, reason: 'sunucuya henüz hiçbir şey yazılmadı');

      backend.ingestOffline = false;
      await tapText(tester, tr('mobileToday.pendingRetry'));
      await settle(tester);

      expect(backend.waterMl, 750);
      expect(backend.storedEventIds, hasLength(2));
      expect(find.text(tr('mobileToday.pending', {'count': 2})), findsNothing);
      expect(find.text(tr('mobileToday.pendingRetry')), findsNothing);
      expect(find.text(tr('mobileToday.waterProgress', {'ml': 750, 'target': 2000})), findsOneWidget,
          reason: 'sunucudan gelen toplam bekleyenlerle çift sayılmaz');
      expect(h.outbox.pendingCount, 0);
    });

    testWidgets('kalıcı olarak reddedilen kayıt kuyruğa girmez ve ilerlemeyi değiştirmez', (tester) async {
      final backend = FakeBackend()..ingestStatus = 422;
      await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs(), backend: backend);
      await tapText(tester, tr('mobileToday.actions.water250'));
      expect(find.text(tr('mobileToday.waterProgress', {'ml': 0, 'target': 2000})), findsOneWidget);
      expect(find.text(tr('mobileToday.pending', {'count': 1})), findsNothing);
      expect(find.text(tr('mobileToday.queuedHint')), findsNothing);
    });

    testWidgets('önceki oturumdan kalan kayıtlar açılışta gönderilir', (tester) async {
      final backend = FakeBackend();
      await pumpApp(
        tester,
        location: '/dashboard',
        prefs: {...acceptedPrefs(), 'rebi_event_outbox_v1_$testUserId': queuedWater('eski-1', 250)},
        backend: backend,
      );
      await settle(tester);
      expect(backend.storedEventIds, {'eski-1'});
      expect(backend.waterMl, 250);
      expect(find.text(tr('mobileToday.pending', {'count': 1})), findsNothing);
      expect(find.text(tr('mobileToday.waterProgress', {'ml': 250, 'target': 2000})), findsOneWidget);
    });

    testWidgets('bağlantı yokken önceki oturumdan kalanlar bekleyen olarak görünür', (tester) async {
      final backend = FakeBackend()..ingestOffline = true;
      await pumpApp(
        tester,
        location: '/dashboard',
        prefs: {...acceptedPrefs(), 'rebi_event_outbox_v1_$testUserId': queuedWater('eski-1', 500)},
        backend: backend,
      );
      expect(find.text(tr('mobileToday.pending', {'count': 1})), findsOneWidget);
      expect(find.text(tr('mobileToday.waterProgress', {'ml': 500, 'target': 2000})), findsOneWidget);
    });

    testWidgets('dünden kalan bekleyen kayıt bugünün ilerlemesine eklenmez', (tester) async {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final stale = jsonEncode([
        {
          'id': 'dun-1',
          'user_id': testUserId,
          'type': 'water_intake',
          'payload': {'ml': 500},
          'timestamp': localIsoTimestamp(yesterday),
          'queued_at': DateTime.now().millisecondsSinceEpoch,
          'attempts': 0,
        },
      ]);
      final backend = FakeBackend()..ingestOffline = true;
      await pumpApp(
        tester,
        location: '/dashboard',
        prefs: {...acceptedPrefs(), 'rebi_event_outbox_v1_$testUserId': stale},
        backend: backend,
      );
      expect(find.text(tr('mobileToday.pending', {'count': 1})), findsOneWidget);
      expect(find.text(tr('mobileToday.waterProgress', {'ml': 0, 'target': 2000})), findsOneWidget);
    });

    testWidgets('bekleyen satırı 320 genişlikte taşmaz', (tester) async {
      final backend = FakeBackend()..ingestOffline = true;
      await pumpApp(
        tester,
        location: '/dashboard',
        prefs: {...acceptedPrefs(), 'rebi_event_outbox_v1_$testUserId': queuedWater('eski-1', 500)},
        backend: backend,
        size: const Size(320, 568),
      );
      expect(find.text(tr('mobileToday.pending', {'count': 1})), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('küçük ekran', () {
    for (final lang in ['tr', 'en']) {
      testWidgets('dolu plan 320×568 çizilir ve taşmaz ($lang)', (tester) async {
        final backend = FakeBackend();
        backend.waterMl = 750;
        backend.todayPlan = {
          ...backend.todayPlan,
          'weather_source': 'live',
          'checkin_done': true,
          'weather': {'uv_index': 9, 'humidity': 22, 'temperature': 37},
          'environment_advice': [
            {
              'time': 'Sabah',
              'category': 'Koruma',
              'icon': '☀️',
              'action': 'SPF 50+ geniş spektrumlu güneş koruyucu (yüze ve boyna cömert miktarda)',
              'detail': 'UV çok yüksek olduğu için gün içinde iki saatte bir tekrar uygula ve gölgede kalmaya özen göster.',
              'priority': 1,
            },
          ],
          'progress': {
            'routine_morning_done': true,
            'routine_evening_done': true,
            'spf_refreshes': 2,
            'makeup': {'logged': true, 'used': true, 'removed': true},
          },
          'reminders': [
            reminder('routine_morning', 'Sabah rutini', '07:30', '09:30', logEvent: 'routine_completed_block'),
            reminder('makeup_log', 'Bugün makyaj yaptın mı?', '09:00', '11:00', logEvent: 'makeup'),
            reminder('nutrition_log', 'Beslenme kaydı', '09:00', '11:00', logEvent: 'nutrition'),
            reminder('spf_refresh', 'Güneş kremini yenile', '09:00', '16:00', logEvent: 'spf_refresh', every: 120),
            reminder('daily_checkin', 'Günlük check-in', '09:00', '22:30'),
            reminder('routine_evening', 'Akşam rutini', '21:00', '23:00', logEvent: 'routine_completed_block'),
          ],
        };
        await pumpApp(
          tester,
          location: '/dashboard',
          prefs: acceptedPrefs(),
          backend: backend,
          lang: lang,
          size: const Size(320, 568),
        );
        expect(find.text(tr('mobileToday.title')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('konum', () {
    Map<String, dynamic> withLocationConsent(Map<String, dynamic> snapshot) => {
          ...snapshot,
          'consent': {
            'legal_accepted': true,
            'ai_processing_allowed': true,
            'location_processing_allowed': true,
            'photo_processing_allowed': false,
          },
        };

    testWidgets('konum izni varsa plan isteği koordinatları taşır', (tester) async {
      deviceLocationLookup = () async => (lat: 41.01, lon: 28.97);
      final backend = FakeBackend();
      backend.snapshot = withLocationConsent(backend.snapshot);
      final h = await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs(), backend: backend);
      final q = h.backend.calls('/today/plan').first.url.queryParameters;
      expect(q['user_id'], testUserId);
      expect(q['lat'], '41.01');
      expect(q['lon'], '28.97');
    });

    testWidgets('konum izni yoksa cihaz konumu hiç gönderilmez', (tester) async {
      deviceLocationLookup = () async => (lat: 41.01, lon: 28.97);
      final h = await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs());
      final q = h.backend.calls('/today/plan').first.url.queryParameters;
      expect(q.containsKey('lat'), isFalse);
      expect(q.containsKey('lon'), isFalse);
    });

    testWidgets('konum alınamazsa plan konumsuz istenir', (tester) async {
      deviceLocationLookup = () async => null;
      final backend = FakeBackend();
      backend.snapshot = withLocationConsent(backend.snapshot);
      final h = await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs(), backend: backend);
      expect(h.backend.calls('/today/plan').first.url.queryParameters.containsKey('lat'), isFalse);
    });
  });

  group('hızlı kayıt', () {
    testWidgets('makyaj ve abur cubur olayları gider', (tester) async {
      final h = await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs());

      await tapText(tester, tr('mobileToday.quick.makeup'));
      var body = h.backend.bodyOf('/daily_tracking/ingest');
      expect(body['type'], 'makeup');
      expect(body['payload'], {'used': true});

      await tapText(tester, tr('mobileToday.quick.makeupRemoved'));
      body = h.backend.bodyOf('/daily_tracking/ingest');
      expect(body['payload'], {'removed': true, 'method': 'double'});

      await tapText(tester, tr('mobileToday.quick.junk'));
      body = h.backend.bodyOf('/daily_tracking/ingest');
      expect(body['type'], 'nutrition');
      expect(body['payload'], {'junk_food': true});
      expect(body['client_event_id'], isNotEmpty);
    });

    testWidgets('ürün bitti: adım bilgisiyle product_finished gönderilir', (tester) async {
      final h = await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs());
      expect(find.text(tr('mobileToday.productFinished')), findsWidgets);

      await tapText(tester, tr('mobileToday.productFinished'));
      final body = h.backend.bodyOf('/daily_tracking/ingest');
      expect(body['type'], 'product_finished');
      final payload = (body['payload'] as Map).cast<String, dynamic>();
      expect(payload['product'], isNotEmpty);
      expect(payload['step_order'], isA<int>());
      expect(find.text(tr('mobileToday.productFinishedLogged')), findsOneWidget);
    });

    testWidgets('tam plan görünümünde "ürün bitti" düğmesi yoktur', (tester) async {
      await pumpApp(tester, location: '/dashboard', extra: {'routine': routine, 'userName': 'Ayşe'});
      expect(find.text(tr('mobileToday.productFinished')), findsNothing);
    });
  });
}
