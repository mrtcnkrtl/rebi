import 'dart:convert';

import 'package:flutter/material.dart' show BottomSheet, MaterialLocalizations, Size, TextField;
import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/core/daily_tracking.dart';
import 'package:rebi/core/device_location.dart';
import 'package:rebi/core/routine_tracking.dart';
import 'package:rebi/core/day_log.dart';
import 'package:rebi/core/routine_logic.dart';
import 'package:rebi/core/routine_usage.dart';
import 'package:rebi/screens/today/today_clock.dart';
import 'package:rebi/screens/today/today_widgets.dart';
import 'package:rebi/ui/widgets/common.dart';

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
      expect(find.text(tr('mobileToday.now')), findsOneWidget);
      // Sabah rutini kahraman kartın başlığıdır; "şimdi" listesinde ikinci kez yer almaz.
      expect(find.text('Sabah rutini'), findsOneWidget, reason: 'yalnızca kahraman kartta');
      expect(find.text(tr('mobileToday.actions.done')), findsNothing, reason: 'rutin eylemi alt çubukta');
      expect(find.text('10:00 · Bugün makyaj yaptın mı?'), findsOneWidget);
      expect(find.text('21:00 · Akşam rutini'), findsOneWidget);
      expect(find.text('Dudak balsamı'), findsNothing, reason: 'penceresi geçmiş');
      expect(find.text('Su içme zamanı'), findsNothing, reason: 'su ayrı satırda gösterilir');

      await tapText(tester, tr('mobileToday.bar.mark.morning'));
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

    testWidgets('yapılan işler kartlarda görünür, check-in tamamlandı yazar', (tester) async {
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
      expect(find.text(tr('mobileToday.bar.done.morning')), findsOneWidget, reason: 'sabah rutini tamam');
      expect(find.text(tr('mobileToday.bar.done.evening')), findsNothing);
      expect(find.text(tr('mobileToday.spfRefreshed', {'n': 2})), findsOneWidget);
      expect(find.text(tr('mobileToday.makeup.usedPending')), findsOneWidget);
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

      // "Evet, yedim" ne yendiğini soran seçim ekranını açar; kayıt oradan gider.
      await tapText(tester, tr('mobileToday.actions.junkYes'));
      expect(find.text(tr('mobileToday.sheets.nutrition.title')), findsOneWidget);
      await tapText(tester, tr('mobileToday.nutrition.choices.snacks.title'));
      await tapText(tester, tr('mobileToday.sheets.save'));
      body = h.backend.bodyOf('/daily_tracking/ingest');
      expect(body['type'], 'nutrition');
      expect(body['payload'], nutritionPayload({'snacks'}));
      expect((body['payload'] as Map)['junk_food'], true);
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

    group('havaya göre üç karar', () {
      Map<String, dynamic> decisions({
        String level = 'high',
        bool refresh = true,
        Map<String, dynamic>? window = const {'start': '11:00', 'end': '16:00', 'peak': '13:00'},
        String kind = 'boost',
        bool nightMask = false,
        bool lip = true,
        String? lipReason = 'cold',
      }) =>
          {
            'spf': {'spf': '50', 'level': level, 'uv': 6, 'refresh': refresh, 'refresh_every_minutes': refresh ? 120 : null, 'window': window},
            'moisture': {'kind': kind, 'humidity': 38, 'temperature': 6, 'night_mask': nightMask},
            'lip_balm': {'needed': lip, 'reason': lipReason},
          };

      FakeBackend backendWith(Map<String, dynamic> d, {String source = 'live'}) {
        final b = FakeBackend();
        b.todayPlan = {
          ...b.todayPlan,
          'weather': {'uv_index': 6, 'humidity': 38, 'temperature': 6},
          'weather_source': source,
          'weather_decisions': d,
        };
        return b;
      }

      testWidgets('güneş kremi, nemlendirici ve dudak balsamı karar + gerekçeyle görünür', (tester) async {
        await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs(), backend: backendWith(decisions()));

        expect(find.text(tr('mobileToday.advice.title')), findsOneWidget);
        expect(find.text(tr('mobileToday.decisions.spf.headline', {'spf': '50'})), findsOneWidget);
        expect(find.text(tr('mobileToday.decisions.spf.reason.high', {'uv': 6})), findsOneWidget);
        expect(find.text(tr('mobileToday.decisions.spf.refreshWindow', {'start': '11:00', 'end': '16:00'})), findsOneWidget);
        expect(find.text(tr('mobileToday.decisions.moisture.headline.boost')), findsOneWidget);
        expect(find.text(tr('mobileToday.decisions.moisture.reason.boost', {'humidity': 38, 'temperature': 6})), findsOneWidget);
        expect(find.text(tr('mobileToday.decisions.lip.headline.needed')), findsOneWidget);
        expect(find.text(tr('mobileToday.decisions.lip.reason.cold', {'temperature': '6', 'humidity': '38'})), findsOneWidget);
        expect(find.text(tr('mobileToday.advice.source.live')), findsOneWidget);
      });

      testWidgets("UV aralığı bilinmiyorsa genel tazeleme cümlesi çıkar", (tester) async {
        await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs(), backend: backendWith(decisions(window: null)));
        expect(find.text(tr('mobileToday.decisions.spf.refreshAny')), findsOneWidget);
        expect(find.textContaining('–16:00'), findsNothing);
      });

      testWidgets('tazeleme gerekmiyorsa cümle çıkmaz; balsam gerekmiyorsa soluk "gerekmiyor" satırı', (tester) async {
        final d = decisions(level: 'moderate', refresh: false, window: null, lip: false, lipReason: null);
        await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs(), backend: backendWith(d));

        expect(find.text(tr('mobileToday.decisions.spf.refreshAny')), findsNothing);
        expect(find.text(tr('mobileToday.decisions.lip.headline.notNeeded')), findsOneWidget);
        expect(find.text(tr('mobileToday.decisions.lip.reason.none')), findsOneWidget);
      });

      testWidgets('çok kuru havada gece maskesi önerilir', (tester) async {
        await pumpApp(
          tester,
          location: '/dashboard',
          prefs: acceptedPrefs(),
          backend: backendWith(decisions(kind: 'intense', nightMask: true)),
        );
        expect(find.text(tr('mobileToday.decisions.moisture.headline.intense')), findsOneWidget);
        expect(find.text(tr('mobileToday.decisions.moisture.nightMask')), findsOneWidget);
      });

      testWidgets('"Yeniledim" güneş kremi kaydı gönderir ve sayaç artar', (tester) async {
        final h = await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs(), backend: backendWith(decisions()));

        await tapText(tester, tr('mobileToday.spf.done'));

        expect(h.backend.bodyOf('/daily_tracking/ingest')['type'], 'spf_refresh');
        expect(find.text(tr('mobileToday.spfRefreshed', {'n': 1})), findsOneWidget);
      });

      testWidgets('tahmini hava: kaynak ve konum ipucu görünür, başlıktaki hap "tahmini" der', (tester) async {
        await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs(), backend: backendWith(decisions(), source: 'default'));

        expect(find.text(tr('mobileToday.advice.locationHint')), findsOneWidget);
        expect(find.textContaining(tr('mobileToday.weatherPillEstimated')), findsOneWidget);
      });

      testWidgets('İngilizce arayüzde cümleler İngilizce kurulur', (tester) async {
        await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs(), backend: backendWith(decisions()), lang: 'en');

        expect(find.text('Light gel moisturizer'), findsNothing);
        expect(find.text('Extra hydration layer'), findsOneWidget);
        expect(find.text("UV peaks 11:00–16:00; reapply every 2 hours if you're outside."), findsOneWidget);
      });
    });

    group('su hedefi kullanıcının ayarından gelir', () {
      FakeBackend withTarget(int target, {int ml = 750}) {
        final b = FakeBackend()..waterMl = ml;
        b.todayPlan = {
          ...b.todayPlan,
          'reminder_settings': {'water_target_ml': target},
        };
        return b;
      }

      testWidgets('ilerleme ve halka kendi hedefine göre', (tester) async {
        await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs(), backend: withTarget(2500));

        expect(find.text(tr('mobileToday.waterProgress', {'ml': 750, 'target': 2500})), findsOneWidget);
        expect(find.text(tr('mobileToday.waterProgress', {'ml': 750, 'target': 2000})), findsNothing);
      });

      testWidgets('hedefe ulaşınca "hedefe ulaştın" çıkar', (tester) async {
        await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs(), backend: withTarget(1500, ml: 1600));
        expect(find.text(tr('mobileToday.waterGoalReached')), findsOneWidget);
        expect(find.text(tr('mobileToday.actions.water250')), findsNothing, reason: 'hedef dolunca hızlı ekleme kalkar');
      });

      testWidgets('aynı su, daha yüksek hedefte yetmez: hedef çıkmaz', (tester) async {
        await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs(), backend: withTarget(3000, ml: 1600));
        expect(find.text(tr('mobileToday.waterGoalReached')), findsNothing);
        expect(find.text(tr('mobileToday.actions.water250')), findsOneWidget);
      });

      testWidgets('ayar yoksa varsayılan 2000 ml', (tester) async {
        await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs());
        expect(find.text(tr('mobileToday.waterProgress', {'ml': 0, 'target': 2000})), findsOneWidget);
      });
    });

    testWidgets('başlıkta tek satırlık hava özeti görünür', (tester) async {
      final b = FakeBackend();
      b.todayPlan = {
        ...b.todayPlan,
        'weather': {'uv_index': 6, 'humidity': 38, 'temperature': 18},
        'weather_source': 'live',
      };
      await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs(), backend: b);
      expect(find.text(tr('mobileToday.weatherPill', {'temp': '18', 'uv': '6', 'humidity': '38'})), findsOneWidget);
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
      expect(find.text(tr('mobileToday.greet.morning', {'name': 'Ayşe'})), findsOneWidget, reason: 'panelin geri kalanı çalışır');

      h.backend.planFails = false;
      await tapText(tester, tr('mobileToday.retry'));
      expect(find.text(tr('mobileToday.loadFailed')), findsNothing);
      expect(find.text(tr('mobileToday.now')), findsOneWidget);
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
        expect(find.text(tr('mobileToday.now')), findsOneWidget);
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

  // Bugünün sabah ürünleri (haftanın gününe göre süzülmüş): ekrandaki kontrol listesi bunlardır.
  List<RoutineItem> todaysMorning() => RoutineView(asRoutine(routine)).routineByDay[getTurkeyWeekdayIndex()]!.morning;

  /// Alt sayfanın içindeki bir metni bulur (alttaki sayfada aynı metin olabilir).
  Finder inSheet(String text) => find.descendant(of: find.byType(BottomSheet), matching: find.text(text));

  Future<void> tapInSheet(WidgetTester tester, String text) => tapFinder(tester, inSheet(text).first);

  Map<String, dynamic> lastIngest(Harness h) => h.backend.bodyOf('/daily_tracking/ingest');

  group('günün rutini', () {
    testWidgets('adım işaretlenir, işareti kaldırılır', (tester) async {
      final first = todaysMorning().first;
      final h = await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs());

      await tapText(tester, pickAction(first, localized: false));
      var body = lastIngest(h);
      expect(body['type'], 'routine_step');
      expect(body['payload'], {'done': true, 'block': 'morning', 'step_order': stepOrder(first).round()});
      expect((h.backend.progress['routine_steps'] as Map)['morning'], [stepOrder(first).round()]);

      await tapText(tester, pickAction(first, localized: false));
      body = lastIngest(h);
      expect(body['payload'], {'done': false, 'block': 'morning', 'step_order': stepOrder(first).round()});
      expect((h.backend.progress['routine_steps'] as Map)['morning'], isEmpty);
    });

    testWidgets('son adım işaretlenince blok kendiliğinden tamamlanır', (tester) async {
      final steps = todaysMorning();
      final h = await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs());
      expect(find.text(tr('mobileToday.bar.mark.morning')), findsOneWidget);

      for (final step in steps) {
        await tapText(tester, pickAction(step, localized: false));
      }
      expect(lastIngest(h)['type'], 'routine_completed_block');
      expect(lastIngest(h)['payload'], {'morning': true});
      expect(h.backend.progress['routine_morning_done'], isTrue);
      expect(find.text(tr('mobileToday.bar.done.morning')), findsOneWidget);
    });

    testWidgets('sabah rutini "yaptım" ile tamamlananda adımlar işaretli görünür, biri kalkınca blok yeniden açılır',
        (tester) async {
      final steps = todaysMorning();
      expect(steps.length, greaterThan(1), reason: 'fixture bu gün için en az iki sabah adımı taşımalı');
      final h = await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs());

      await tapText(tester, tr('mobileToday.bar.mark.morning'));
      expect(h.backend.progress['routine_morning_done'], isTrue);

      // Tamamlanan blokta adımlar sakin bir özetin arkasına çekilir; istenirse açılır.
      expect(find.text(tr('mobileToday.hero.doneTitle.morning')), findsOneWidget);
      expect(find.text(pickAction(steps.first, localized: false)), findsNothing);
      await tapText(tester, tr('mobileToday.hero.showSteps'));

      // Tamamlanmış blokta bir adımın işaretini kaldırmak bloğu açar, diğer adımlar tek tek işaretli kalır.
      await tapText(tester, pickAction(steps.first, localized: false));
      expect(h.backend.progress['routine_morning_done'], isFalse);
      final done = ((h.backend.progress['routine_steps'] as Map)['morning'] as List).cast<int>();
      expect(done, [for (final s in steps.skip(1)) stepOrder(s).round()]..sort());
      expect(find.text(tr('mobileToday.bar.mark.morning')), findsOneWidget);
    });

    testWidgets('"yaptım" çubuğu bloğu tamamlar; "geri al" yeniden açar', (tester) async {
      final h = await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs());

      await tapText(tester, tr('mobileToday.bar.mark.morning'));
      var body = lastIngest(h);
      expect(body['type'], 'routine_completed_block');
      expect(body['payload'], {'morning': true});
      expect(find.text(tr('mobileToday.toast.blockDone.morning')), findsOneWidget);
      expect(find.text(tr('mobileToday.bar.done.morning')), findsOneWidget);

      await tapText(tester, tr('mobileToday.toast.undo'));
      body = lastIngest(h);
      expect(body['payload'], {'morning': false});
      expect(find.text(tr('mobileToday.bar.mark.morning')), findsOneWidget);
    });

    testWidgets('tamamlanmış rutine dokunmak yanlışlıkla bozmaz, yeniden aç seçeneği sunar', (tester) async {
      final backend = FakeBackend();
      backend.todayPlan = {
        ...backend.todayPlan,
        'progress': {'routine_morning_done': true},
      };
      final h = await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs(), backend: backend);
      final before = h.backend.calls('/daily_tracking/ingest').length;

      await tapText(tester, tr('mobileToday.bar.done.morning'));
      expect(h.backend.calls('/daily_tracking/ingest'), hasLength(before), reason: 'dokunmak tek başına kayıt göndermez');
      expect(find.text(tr('mobileToday.toast.blockAlreadyDone')), findsOneWidget);

      // "Yeniden aç" hem kahraman kartta hem uyarıda durur; uyarıdakine dokun (sonuncu).
      await tapFinder(tester, find.text(tr('mobileToday.toast.reopen')).last);
      expect(lastIngest(h)['payload'], {'morning': false});
    });

    testWidgets('tamamlanan rutin kahraman kartta özet olur; "yeniden aç" adımları tek tek işaretli bırakır', (tester) async {
      final steps = todaysMorning();
      final backend = FakeBackend();
      backend.todayPlan = {
        ...backend.todayPlan,
        'progress': {'routine_morning_done': true},
      };
      final h = await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs(), backend: backend);

      expect(find.text(tr('mobileToday.hero.doneTitle.morning')), findsOneWidget);
      expect(find.text(tr('mobileToday.hero.doneBody')), findsOneWidget);

      await tapFinder(tester, find.text(tr('mobileToday.hero.reopen')).first);
      expect(h.backend.progress['routine_morning_done'], isFalse, reason: 'blok yeniden açıldı');
      final done = ((h.backend.progress['routine_steps'] as Map)['morning'] as List).cast<int>();
      expect(done, [for (final s in steps) stepOrder(s).round()]..sort(), reason: 'hiçbir iş kaybolmaz');
      expect(find.text(tr('mobileToday.hero.doneTitle.morning')), findsNothing);
    });

    testWidgets('akşam saatinde akşam rutini öne çıkar, sekmeyle değiştirilir', (tester) async {
      todayPanelClock = () => DateTime(2026, 10, 10, 20, 30);
      final h = await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs());
      expect(find.text(tr('mobileToday.bar.mark.evening')), findsOneWidget);

      await tapText(tester, tr('mobileToday.checklist.morning'));
      expect(find.text(tr('mobileToday.bar.mark.morning')), findsOneWidget);

      await tapText(tester, tr('mobileToday.bar.mark.morning'));
      expect(lastIngest(h)['payload'], {'morning': true});
    });

    testWidgets('adımın nedeni ve nasıl uygulanacağı açılır', (tester) async {
      await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs());
      final why = find.text(tr('dashboard.whySkincareButton'));
      expect(why, findsWidgets);
      await tapFinder(tester, why.first);
      expect(find.text(tr('common.hide')), findsOneWidget);
      expect(find.textContaining(tr('dashboard.howToApply')), findsWidgets);
    });
  });

  group('makyaj', () {
    testWidgets('yaptım → nasıl temizledin seçimi kaydedilir', (tester) async {
      final h = await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs());
      expect(find.text(tr('mobileToday.makeup.ask')), findsOneWidget);

      await tapText(tester, tr('mobileToday.actions.yes'));
      expect(lastIngest(h)['type'], 'makeup');
      expect(lastIngest(h)['payload'], {'used': true});
      expect(find.text(tr('mobileToday.makeup.usedPending')), findsOneWidget);

      await tapText(tester, tr('mobileToday.actions.removed'));
      expect(find.text(tr('mobileToday.sheets.cleansing.title')), findsOneWidget);
      for (final method in cleansingMethods) {
        expect(inSheet(tr('mobileToday.cleansing.$method.title')), findsOneWidget, reason: method);
      }

      await tapInSheet(tester, tr('mobileToday.cleansing.wipe.title'));
      expect(lastIngest(h)['payload'], {'removed': true, 'method': 'wipe'});
      expect(find.text(tr('mobileToday.sheets.cleansing.title')), findsNothing, reason: 'seçince sayfa kapanır');
      expect(
        find.text(tr('mobileToday.makeup.cleanedWith', {'method': tr('mobileToday.cleansing.wipe.title')})),
        findsOneWidget,
      );
    });

    testWidgets('"temizlemedim" makyajı temizlenmedi bırakır ve hatırlatmaya devam eder', (tester) async {
      final h = await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs());
      await tapText(tester, tr('mobileToday.actions.yes'));
      await tapText(tester, tr('mobileToday.actions.removed'));
      await tapInSheet(tester, tr('mobileToday.cleansing.none.title'));

      expect(lastIngest(h)['payload'], {'removed': false, 'method': 'none'});
      expect(find.text(tr('mobileToday.makeup.notCleaned')), findsOneWidget);
      expect(find.text(tr('mobileToday.actions.removed')), findsOneWidget, reason: 'sonradan temizleyebilir');
    });

    testWidgets('makyaj yok → sonradan "yaptım" denebilir', (tester) async {
      final h = await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs());
      await tapText(tester, tr('mobileToday.actions.no'));
      expect(lastIngest(h)['payload'], {'used': false});
      expect(find.text(tr('mobileToday.makeup.none')), findsOneWidget);

      await tapText(tester, tr('mobileToday.makeup.changeToUsed'));
      expect(lastIngest(h)['payload'], {'used': true});
    });

    testWidgets('akşam hatırlatıcısı da yöntemi sorar, varsayılan yöntem göndermez', (tester) async {
      todayPanelClock = () => DateTime(2026, 10, 10, 21, 30);
      final backend = FakeBackend();
      backend.todayPlan = {
        ...backend.todayPlan,
        'progress': {
          'makeup': {'logged': true, 'used': true, 'removed': false},
        },
        'reminders': [reminder('makeup_removal', 'Makyaj temizliği', '21:00', '23:00', logEvent: 'makeup')],
      };
      final h = await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs(), backend: backend);
      final before = h.backend.calls('/daily_tracking/ingest').length;

      // Hatırlatıcı kartındaki ve makyaj kartındaki "Temizledim" düğmesi aynı sayfayı açar.
      await tapText(tester, tr('mobileToday.actions.removed'));
      expect(find.text(tr('mobileToday.sheets.cleansing.title')), findsOneWidget);
      expect(h.backend.calls('/daily_tracking/ingest'), hasLength(before));
    });
  });

  group('beslenme', () {
    testWidgets('"hayır" tek dokunuşla kaydedilir', (tester) async {
      final h = await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs());
      await tapFinder(tester, find.widgetWithText(TodayPill, tr('mobileToday.actions.junkNo')).last);
      expect(lastIngest(h)['type'], 'nutrition');
      expect(lastIngest(h)['payload'], {'junk_food': false});
      expect(find.text(tr('mobileToday.nutrition.clean')), findsOneWidget);
    });

    testWidgets('neler yendiği seçilir; düzenlerken seçimler geri gelir, "dengeli" diğerlerini temizler', (tester) async {
      final h = await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs());
      await tapText(tester, tr('mobileToday.actions.junkYes'));
      expect(find.text(tr('mobileToday.sheets.nutrition.title')), findsOneWidget);
      expect(find.widgetWithText(PrimaryButton, tr('mobileToday.sheets.save')), findsOneWidget);

      await tapInSheet(tester, tr('mobileToday.nutrition.choices.snacks.title'));
      await tapInSheet(tester, tr('mobileToday.nutrition.choices.sweets.title'));
      await tapInSheet(tester, tr('mobileToday.sheets.save'));
      expect(lastIngest(h)['payload'], nutritionPayload({'snacks', 'sweets'}));
      expect(
        find.text('${tr('mobileToday.nutrition.choices.snacks.title')}, ${tr('mobileToday.nutrition.choices.sweets.title')}'),
        findsOneWidget,
      );

      await tapText(tester, tr('mobileToday.actions.edit'));
      await tapInSheet(tester, tr('mobileToday.nutrition.choices.balanced.title'));
      await tapInSheet(tester, tr('mobileToday.sheets.save'));
      expect(lastIngest(h)['payload'], nutritionPayload({'balanced'}));
      expect(find.text(tr('mobileToday.nutrition.balanced')), findsOneWidget);
    });

    testWidgets('hiçbir şey seçilmeden kaydedilemez', (tester) async {
      final h = await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs());
      await tapText(tester, tr('mobileToday.actions.junkYes'));
      final before = h.backend.calls('/daily_tracking/ingest').length;
      await tapInSheet(tester, tr('mobileToday.sheets.save'));
      expect(h.backend.calls('/daily_tracking/ingest'), hasLength(before));
      expect(find.text(tr('mobileToday.sheets.nutrition.title')), findsOneWidget, reason: 'sayfa açık kalır');
    });
  });

  group('su sayfası', () {
    testWidgets('hızlı miktar, özel miktar ve düzeltme', (tester) async {
      final h = await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs());
      await tapText(tester, tr('mobileToday.actions.waterMore'));
      expect(find.text(tr('mobileToday.sheets.water.title')), findsOneWidget);

      await tapInSheet(tester, '+330 ml');
      expect(lastIngest(h)['payload'], {'ml': 330});
      expect(inSheet(tr('mobileToday.waterProgress', {'ml': 330, 'target': 2000})), findsOneWidget);

      await tester.enterText(find.byType(TextField), '150');
      await tapInSheet(tester, tr('mobileToday.sheets.water.addButton'));
      expect(lastIngest(h)['payload'], {'ml': 150});
      expect(h.backend.waterMl, 480);

      await tapInSheet(tester, '−100 ml');
      expect(lastIngest(h)['payload'], {'ml': -100});
      expect(h.backend.waterMl, 380);
      expect(inSheet(tr('mobileToday.waterProgress', {'ml': 380, 'target': 2000})), findsOneWidget);
    });

    testWidgets('geçersiz miktar kaydedilmez ve uyarır', (tester) async {
      final h = await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs());
      await tapText(tester, tr('mobileToday.actions.waterMore'));
      final before = h.backend.calls('/daily_tracking/ingest').length;

      await tester.enterText(find.byType(TextField), '5000');
      await tapInSheet(tester, tr('mobileToday.sheets.water.addButton'));
      expect(find.text(tr('mobileToday.sheets.water.invalid', {'max': maxCustomWaterMl})), findsOneWidget);
      expect(h.backend.calls('/daily_tracking/ingest'), hasLength(before));
    });

    testWidgets('düzeltme toplamdan fazla düşürmez', (tester) async {
      final backend = FakeBackend()..waterMl = 100;
      final h = await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs(), backend: backend);
      await tapText(tester, tr('mobileToday.actions.waterMore'));
      await tapInSheet(tester, '−500 ml');
      expect(lastIngest(h)['payload'], {'ml': -100});
      expect(h.backend.waterMl, 0);
    });

    testWidgets('su eklenince "geri al" miktarı geri düşer', (tester) async {
      final h = await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs());
      await tapText(tester, tr('mobileToday.actions.water250'));
      expect(find.text(tr('mobileToday.toast.water', {'ml': 250})), findsOneWidget);
      await tapText(tester, tr('mobileToday.toast.undo'));
      expect(lastIngest(h)['payload'], {'ml': -250});
      expect(h.backend.waterMl, 0);
      expect(find.text(tr('mobileToday.waterProgress', {'ml': 0, 'target': 2000})), findsOneWidget);
    });

    testWidgets('sonraki hatırlatma saati görünür', (tester) async {
      final backend = FakeBackend();
      backend.todayPlan = {
        ...backend.todayPlan,
        'reminders': [reminder('water_intake', 'Su içme zamanı', '09:00', '21:00', logEvent: 'water_intake', every: 120)],
      };
      await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs(), backend: backend);
      expect(find.text(tr('mobileToday.water.next', {'time': '11:00'})), findsOneWidget);
    });
  });

  group('güneş kremi', () {
    testWidgets('yenilendi olayı gider, sayaç artar', (tester) async {
      final h = await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs());
      await tapText(tester, tr('mobileToday.spf.done'));
      expect(lastIngest(h)['type'], 'spf_refresh');
      expect(find.text(tr('mobileToday.spfRefreshed', {'n': 1})), findsOneWidget);
    });
  });

  group('ürün bitti', () {
    List<RoutineItem> finishable() {
      final view = RoutineView(asRoutine(routine));
      final seen = <String>{};
      return [
        for (final it in [...view.morningProducts, ...view.eveningProducts])
          if (isSkincareStep(it) && seen.add(str(it['action']).trim().toLowerCase())) it,
      ];
    }

    testWidgets('alt çubuktan açılır, seçilen ürünler product_finished olarak gider', (tester) async {
      final products = finishable();
      expect(products, isNotEmpty);
      final h = await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs());

      await tapText(tester, tr('mobileToday.productFinished'));
      expect(find.text(tr('mobileToday.sheets.products.title')), findsOneWidget);
      expect(find.widgetWithText(PrimaryButton, tr('mobileToday.sheets.products.save')), findsOneWidget,
          reason: 'seçim yokken kaydet kapalı');

      await tapInSheet(tester, pickAction(products.first, localized: false));
      await tapInSheet(tester, tr('mobileToday.sheets.products.saveCount', {'n': 1}));

      final body = lastIngest(h);
      expect(body['type'], 'product_finished');
      final payload = (body['payload'] as Map).cast<String, dynamic>();
      expect(payload['product'], str(products.first['action']).trim());
      expect(payload['step_order'], stepOrder(products.first).round());
      expect(find.text(tr('mobileToday.toast.productsFinished', {'n': 1})), findsOneWidget);
    });

    testWidgets('birden fazla ürün seçilince her biri ayrı kayıt olur', (tester) async {
      final products = finishable();
      expect(products.length, greaterThan(1));
      final h = await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs());
      await tapText(tester, tr('mobileToday.productFinished'));

      await tapInSheet(tester, pickAction(products[0], localized: false));
      await tapInSheet(tester, pickAction(products[1], localized: false));
      await tapInSheet(tester, tr('mobileToday.sheets.products.saveCount', {'n': 2}));

      final sent = h.backend.storedEvents.where((e) => e['type'] == 'product_finished').toList();
      expect(sent, hasLength(2));
      expect(find.text(tr('mobileToday.toast.productsFinished', {'n': 2})), findsOneWidget);
    });

    testWidgets('bugün bitti işaretlenen ürün tekrar seçilemez', (tester) async {
      final products = finishable();
      final name = str(products.first['action']).trim();
      final backend = FakeBackend()
        ..productsOut = [
          {'product': name, 'step_order': 10, 'finished_at': '2026-10-08T10:00:00+00:00', 'log_date': '2026-10-08', 'days_out': 2},
        ];
      await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs(), backend: backend);
      await tapText(tester, tr('mobileToday.productFinished'));
      expect(inSheet(tr('mobileToday.sheets.products.already')), findsOneWidget);
      expect(inSheet(tr('mobileToday.sheets.products.restock')), findsOneWidget, reason: 'biten ürün "aldım" ile geri açılır');
    });

    testWidgets('tam plan görünümünde "ürün bitti" çubuğu yoktur', (tester) async {
      await pumpApp(tester, location: '/dashboard', extra: {'routine': routine, 'userName': 'Ayşe'});
      expect(find.text(tr('mobileToday.productFinished')), findsNothing);
    });
  });

  group('kayıt hatası ve küçük ekran', () {
    testWidgets('sunucu reddedince kullanıcıya hata söylenir, ilerleme değişmez', (tester) async {
      final backend = FakeBackend()..ingestStatus = 422;
      await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs(), backend: backend);
      await tapText(tester, tr('mobileToday.actions.yes'));
      expect(find.text(tr('mobileToday.toast.failed')), findsOneWidget);
      expect(find.text(tr('mobileToday.makeup.ask')), findsOneWidget);
    });

    for (final lang in ['tr', 'en']) {
      testWidgets('seçim sayfaları 320×568 çizilir ve taşmaz ($lang)', (tester) async {
        await pumpApp(
          tester,
          location: '/dashboard',
          prefs: acceptedPrefs(),
          size: const Size(320, 568),
          lang: lang,
        );
        expect(find.text(tr('mobileToday.bar.mark.morning')), findsOneWidget);
        expect(tester.takeException(), isNull);

        for (final entry in [
          (tr('mobileToday.actions.waterMore'), tr('mobileToday.sheets.water.title')),
          (tr('mobileToday.actions.junkYes'), tr('mobileToday.sheets.nutrition.title')),
          (tr('mobileToday.productFinished'), tr('mobileToday.sheets.products.title')),
        ]) {
          await tapText(tester, entry.$1);
          expect(find.text(entry.$2), findsOneWidget);
          expect(tester.takeException(), isNull, reason: entry.$2);
          await tapFinder(tester, find.byTooltip(MaterialLocalizations.of(tester.element(find.byType(BottomSheet))).closeButtonTooltip));
          expect(find.text(entry.$2), findsNothing);
        }
      });
    }
  });
}
