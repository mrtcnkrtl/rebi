import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart' show Key, Size, TextField;
import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/core/api.dart';
import 'package:rebi/core/device_location.dart';
import 'package:rebi/core/event_outbox.dart';
import 'package:rebi/core/local_store.dart';
import 'package:rebi/core/routine_tracking.dart';
import 'package:rebi/core/weather_location.dart';
import 'package:rebi/screens/today/today_header.dart';
import 'package:rebi/state/today_plan_controller.dart';
import 'package:rebi/state/weather_place_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/app_harness.dart';

/// Hava durumunun kullanıcıya her koşulda ulaşması: geç gelen konumun yakalanması, konumun sunucuya kaydı, seçilen şehir,
/// "hava yok" durumunda uydurma sayı yerine yer seçtiren panel ve yer seçme sayfası.
void main() {
  const ankara = Place(name: 'Ankara', region: 'Ankara', country: 'Türkiye', lat: 39.92, lon: 32.85);

  Iterable<Map<String, dynamic>> patches(FakeBackend fb) => fb
      .calls('/me/profile')
      .where((r) => r.method == 'PATCH')
      .map((r) => (jsonDecode(r.body) as Map).cast<String, dynamic>());

  group('TodayPlanController · konum', () {
    late FakeBackend fb;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await LocalStore.init();
      fb = FakeBackend();
      apiHttpClient = fb.client;
    });
    tearDown(resetDeviceLocationLookup);

    testWidgets('konum 2,5 sn içinde gelmezse plan konumsuz istenir; sonradan gelince plan bir kez konumla yenilenir', (tester) async {
      final gps = Completer<Coordinates?>();
      deviceLocationLookup = () => gps.future;
      final c = TodayPlanController(userId: testUserId, outbox: EventOutbox());

      unawaited(c.load(useLocation: true));
      await tester.pump(const Duration(milliseconds: 2600));
      await settle(tester, 3);
      expect(fb.calls('/today/plan').single.url.queryParameters.containsKey('lat'), isFalse);
      expect(c.placeKnown, isFalse, reason: 'yer henüz belli değil');

      gps.complete((lat: 41.01, lon: 28.97));
      await settle(tester);

      final plans = fb.calls('/today/plan');
      expect(plans, hasLength(2), reason: 'geç gelen konumla tek bir yenileme');
      expect(plans.last.url.queryParameters['lat'], '41.01');
      expect(c.placeKnown, isTrue);
      c.dispose();
    });

    testWidgets('geç gelen konum sonsuz yenileme döngüsü başlatmaz', (tester) async {
      var lookups = 0;
      deviceLocationLookup = () async {
        lookups++;
        await Future<void>.delayed(const Duration(seconds: 4)); // her aramada 2,5 sn sınırını aşar
        return (lat: 41.01, lon: 28.97);
      };
      final c = TodayPlanController(userId: testUserId, outbox: EventOutbox());

      unawaited(c.load(useLocation: true));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(seconds: 1));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      }

      expect(fb.calls('/today/plan').length, lessThanOrEqualTo(3), reason: 'yük başına en çok bir geç yenileme');
      expect(lookups, lessThanOrEqualTo(3));
      c.dispose();
    });

    testWidgets('bulunan cihaz konumu profile bir kez kaydedilir; aynı yerde yeniden yazılmaz, ~5 km taşınınca yeniden kaydedilir', (tester) async {
      var at = (lat: 41.01, lon: 28.97);
      deviceLocationLookup = () async => at;
      final c = TodayPlanController(userId: testUserId, outbox: EventOutbox());

      unawaited(c.load(useLocation: true));
      await settle(tester);
      expect(patches(fb), hasLength(1));
      expect(patches(fb).single['location_lat'], 41.01);
      expect(patches(fb).single['location_lon'], 28.97);
      expect(patches(fb).single.containsKey('city'), isFalse, reason: 'cihaz konumu şehir adını ezmez');

      unawaited(c.reload());
      await settle(tester);
      expect(patches(fb), hasLength(1), reason: 'aynı yerde profil yazılmaz');

      at = (lat: 41.2, lon: 29.0);
      unawaited(c.reload());
      await settle(tester);
      expect(patches(fb), hasLength(2), reason: 'yer değişti');
      c.dispose();
    });

    testWidgets('kayıt başarısızsa işaret konmaz: sonraki yüklemede yeniden denenir', (tester) async {
      deviceLocationLookup = () async => (lat: 41.01, lon: 28.97);
      fb.profilePatchStatus = 403;
      final c = TodayPlanController(userId: testUserId, outbox: EventOutbox());

      unawaited(c.load(useLocation: true));
      await settle(tester);
      expect(patches(fb), hasLength(1));
      expect(shouldSaveDeviceLocation(testUserId, (lat: 41.01, lon: 28.97)), isTrue);

      fb.profilePatchStatus = null;
      unawaited(c.reload());
      await settle(tester);
      expect(patches(fb), hasLength(2));
      expect(shouldSaveDeviceLocation(testUserId, (lat: 41.01, lon: 28.97)), isFalse);
      c.dispose();
    });

    testWidgets('kullanıcı şehir seçtiyse cihaz konumu hiç sorulmaz ve gönderilmez (seçim cihazı ezer)', (tester) async {
      var lookups = 0;
      deviceLocationLookup = () async {
        lookups++;
        return (lat: 41.01, lon: 28.97);
      };
      await setManualWeatherPlace(testUserId, ankara);
      final c = TodayPlanController(userId: testUserId, outbox: EventOutbox());

      unawaited(c.load(useLocation: true));
      await settle(tester);

      expect(lookups, 0);
      expect(fb.calls('/today/plan').single.url.queryParameters.containsKey('lat'), isFalse);
      expect(c.placeKnown, isTrue, reason: 'yer seçildi: hava gelmezse sorun servis/bağlantıdır');
      expect(patches(fb), isEmpty);
      c.dispose();
    });

    testWidgets('konum izni yoksa (arama boş döner) yer belli değildir', (tester) async {
      deviceLocationLookup = () async => null;
      final c = TodayPlanController(userId: testUserId, outbox: EventOutbox());

      unawaited(c.load(useLocation: true));
      await settle(tester);

      expect(c.placeKnown, isFalse);
      expect(patches(fb), isEmpty);
      c.dispose();
    });

    testWidgets('konum işleme izni kapalıysa konum aranmaz', (tester) async {
      var lookups = 0;
      deviceLocationLookup = () async {
        lookups++;
        return (lat: 41.01, lon: 28.97);
      };
      final c = TodayPlanController(userId: testUserId, outbox: EventOutbox());

      unawaited(c.load(useLocation: false));
      await settle(tester);

      expect(lookups, 0);
      expect(c.placeKnown, isFalse);
      c.dispose();
    });
  });

  group('WeatherPlaceController', () {
    late FakeBackend fb;
    var changed = 0;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await LocalStore.init();
      fb = FakeBackend();
      apiHttpClient = fb.client;
      changed = 0;
    });
    tearDown(() {
      resetDeviceLocationAcquirer();
      resetLocationAccess();
    });

    WeatherPlaceController make() => WeatherPlaceController(
          userId: testUserId,
          consentAllowed: true,
          onChanged: () async => changed++,
          debounce: const Duration(milliseconds: 100),
        );

    testWidgets('yazı beklemeden sonra aranır; art arda yazışlar tek istek olur; iki harften kısa aranmaz', (tester) async {
      final c = make();

      c.setQuery('A');
      expect(c.phase, PlaceSearchPhase.idle);

      c.setQuery('An');
      c.setQuery('Ank');
      expect(c.phase, PlaceSearchPhase.searching);
      await tester.pump(const Duration(milliseconds: 150));
      await settle(tester, 2);

      expect(fb.calls('/weather/search'), hasLength(1));
      final url = fb.calls('/weather/search').single.url;
      expect(url.queryParameters['q'], 'Ank');
      expect(url.queryParameters['user_id'], testUserId);
      expect(url.queryParameters['lang'], 'tr');
      expect(c.phase, PlaceSearchPhase.results);
      expect(c.results.map((p) => p.name), ['Ankara', 'Ankara']);
      expect(c.results.first.label, 'Ankara, Türkiye', reason: 'bölge adı şehirle aynıysa tekrarlanmaz');
      c.dispose();
    });

    testWidgets('bulunamadı ile servis hatası ayrı durumlardır', (tester) async {
      final c = make();
      fb.placeResults = [];
      c.setQuery('Yokyer');
      await tester.pump(const Duration(milliseconds: 150));
      await settle(tester, 2);
      expect(c.phase, PlaceSearchPhase.empty);

      fb.placesStatus = 502;
      c.setQuery('Yokyer2');
      await tester.pump(const Duration(milliseconds: 150));
      await settle(tester, 2);
      expect(c.phase, PlaceSearchPhase.failed);
      expect(c.error, isNotNull);
      c.dispose();
    });

    testWidgets('şehir seçimi: koordinat ve şehir adı sunucuya kaydedilir, cihazda "seçilen şehir" olur, plan yenilenir', (tester) async {
      final c = make();

      final ok = await tester.runAsync(() => c.choose(ankara));

      expect(ok, isTrue);
      final sent = patches(fb).single;
      expect((sent['location_lat'], sent['location_lon'], sent['city']), (39.92, 32.85, 'Ankara'));
      expect(weatherPlacePref(testUserId).manual, isTrue);
      expect(weatherPlacePref(testUserId).name, 'Ankara');
      expect(changed, 1);
      c.dispose();
    });

    testWidgets('şehir kaydedilemezse hata söylenir, seçim ve plan değişmez', (tester) async {
      fb.profilePatchStatus = 403;
      fb.profilePatchDetail = 'Konum işleme izni gerekli.';
      final c = make();

      final ok = await tester.runAsync(() => c.choose(ankara));

      expect(ok, isFalse);
      expect(c.error, contains('Konum işleme izni gerekli.'));
      expect(weatherPlacePref(testUserId).manual, isFalse);
      expect(changed, 0);
      c.dispose();
    });

    testWidgets('telefonun konumuna dönmek seçilen şehri kaldırır, konumu kaydeder ve planı yeniler', (tester) async {
      await setManualWeatherPlace(testUserId, ankara);
      setDeviceLocationAcquirer(acquire: () async => (at: (lat: 41.01, lon: 28.97), failure: null));
      final c = make();
      expect(c.pref.manual, isTrue);

      final ok = await tester.runAsync(() => c.useDevice());

      expect(ok, isTrue);
      expect(c.pref.manual, isFalse);
      expect(weatherPlacePref(testUserId).manual, isFalse);
      expect(patches(fb).single['location_lat'], 41.01);
      expect(patches(fb).single.containsKey('city'), isFalse);
      expect(changed, 1);
      c.dispose();
    });

    for (final failure in LocationFailure.values) {
      testWidgets('konum alınamazsa ($failure) neden söylenir; seçim ve plan değişmez', (tester) async {
        setDeviceLocationAcquirer(acquire: () async => (at: null, failure: failure));
        setLocationAccess(read: () async => LocationAccess.blocked);
        final c = make();

        final ok = await tester.runAsync(() => c.useDevice());

        expect(ok, isFalse);
        expect(c.deviceFailure, failure);
        expect(patches(fb), isEmpty);
        expect(changed, 0);
        c.dispose();
      });
    }
  });

  group('Bugün · hava paneli', () {
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

    FakeBackend backend({bool consent = true}) {
      final b = FakeBackend();
      b.snapshot = {
        ...b.snapshot,
        'consent': {...(b.snapshot['consent'] as Map).cast<String, dynamic>(), 'location_processing_allowed': consent},
      };
      b.locationMakesWeatherLive = true;
      return b;
    }

    setUp(() {
      // İlk-açılış konum önerisi karışmasın: izin zaten verilmiş.
      setLocationAccess(read: () async => LocationAccess.granted);
    });
    tearDown(() {
      resetDeviceLocationLookup();
      resetDeviceLocationAcquirer();
      resetLocationAccess();
    });

    Finder inHeader(String text) => find.descendant(of: find.byType(TodayHeader), matching: find.text(text));

    testWidgets('yer belli değilken uydurma sayı yok: "Hava için bir yer seç" ve "Yer seç" düğmesi', (tester) async {
      deviceLocationLookup = () async => null;
      await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs(), backend: backend());

      expect(find.byKey(const Key('weather-missing')), findsOneWidget);
      expect(inHeader(tr('mobileWeatherPlace.missingTitle')), findsOneWidget);
      expect(inHeader(tr('mobileWeatherPlace.pick')), findsOneWidget);
      expect(inHeader('20°'), findsNothing, reason: 'varsayılan 20° gerçek hava gibi gösterilmez');
    });

    testWidgets('yer belli ama hava gelmiyorsa: "Hava şu an alınamadı", "Yeniden dene" planı yeniden okur', (tester) async {
      deviceLocationLookup = () async => (lat: 41.01, lon: 28.97);
      final b = backend()..locationMakesWeatherLive = false; // sunucu yer biliyor ama hava servisi yanıt vermiyor
      final h = await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs(), backend: b);
      expect(inHeader(tr('mobileWeatherPlace.unavailableTitle')), findsOneWidget);
      final before = h.backend.calls('/today/plan').length;

      await tapText(tester, tr('mobileWeatherPlace.retry'));

      expect(h.backend.calls('/today/plan').length, greaterThan(before));
      expect(inHeader(tr('mobileWeatherPlace.pick')), findsOneWidget, reason: 'yeri değiştirmek de sunulur');
    });

    testWidgets('"Yer seç" sayfası açılır; şehir aranır, seçilir; hava gelir ve yer düğmesi şehri gösterir', (tester) async {
      deviceLocationLookup = () async => null;
      final h = await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs(), backend: backend());

      await tapText(tester, tr('mobileWeatherPlace.pick'));
      expect(find.text(tr('mobileWeatherPlace.title')), findsOneWidget);
      expect(find.text(tr('mobileWeatherPlace.device.title')), findsOneWidget);

      await tester.enterText(find.byKey(const Key('weather-place-search')), 'Ank');
      await tester.pump(const Duration(milliseconds: 600));
      await settle(tester, 4);
      expect(find.text('Ankara'), findsNWidgets(2));

      await tapFinder(tester, find.text('Ankara').first);
      await settle(tester);

      expect(find.text(tr('mobileWeatherPlace.title')), findsNothing, reason: 'sayfa kapandı');
      expect(patches(h.backend).single['city'], 'Ankara');
      expect(find.byKey(const Key('weather-missing')), findsNothing);
      expect(inHeader('18°'), findsOneWidget, reason: 'sunucu seçilen yerden gerçek havayı verdi');
      expect(inHeader('Ankara'), findsOneWidget, reason: 'yer düğmesi seçilen şehri gösterir');
      final lastPlan = h.backend.calls('/today/plan').last;
      expect(lastPlan.url.queryParameters.containsKey('lat'), isFalse, reason: 'seçilen şehir varken cihaz konumu gönderilmez');
    });

    testWidgets('canlı havada yer düğmesi ("Konumum") sayfayı açar; telefonun konumuna dönülebilir', (tester) async {
      deviceLocationLookup = () async => (lat: 41.01, lon: 28.97);
      setDeviceLocationAcquirer(acquire: () async => (at: (lat: 41.01, lon: 28.97), failure: null));
      final b = backend();
      b.todayPlan = {
        ...b.todayPlan,
        'weather': {'uv_index': 6, 'humidity': 38, 'temperature': 18},
        'weather_source': 'live',
      };
      final h = await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs(), backend: b);
      expect(inHeader('18°'), findsOneWidget);

      await tapText(tester, tr('mobileWeatherPlace.chipDevice'));
      expect(find.text(tr('mobileWeatherPlace.title')), findsOneWidget);

      await tapFinder(tester, find.byKey(const Key('weather-place-device')));
      await settle(tester);

      expect(find.text(tr('mobileWeatherPlace.title')), findsNothing);
      expect(patches(h.backend).last['location_lat'], 41.01);
    });

    testWidgets('konum alınamazsa sayfada neden ve ayar bağlantısı çıkar; şehir seçmek yine mümkündür', (tester) async {
      deviceLocationLookup = () async => null;
      setLocationAccess(read: () async => LocationAccess.askable);
      var settingsOpened = 0;
      setDeviceLocationAcquirer(
        acquire: () async => (at: null, failure: LocationFailure.blocked),
        openSettings: (_) async {
          settingsOpened++;
          return true;
        },
      );
      await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs(), backend: backend());
      await tapText(tester, tr('mobileWeatherPlace.pick'));

      await tapFinder(tester, find.byKey(const Key('weather-place-device')));

      expect(find.text(tr('mobileWeatherPlace.device.fail.blocked')), findsOneWidget);
      expect(find.byKey(const Key('weather-place-search')), findsOneWidget, reason: 'şehir seçimi izin gerektirmez');
      await tapText(tester, tr('mobileWeatherPlace.device.openSettings'));
      expect(settingsOpened, 1);
    });

    testWidgets('gizlilik onayında konum kapalıysa sayfa nedenini söyler ve Gizlilik izinlerine götürür; arama kutusu yok', (tester) async {
      deviceLocationLookup = () async => null;
      final h = await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs(), backend: backend(consent: false));
      await tapText(tester, tr('mobileWeatherPlace.pick'));

      expect(find.text(tr('mobileWeatherPlace.consent.title')), findsOneWidget);
      expect(find.byKey(const Key('weather-place-search')), findsNothing);

      await tapText(tester, tr('mobileWeatherPlace.consent.cta'));
      expect(h.router.routerDelegate.currentConfiguration.uri.path, '/dashboard/account');
    });

    testWidgets('arama hatası ve "bulunamadı" kullanıcıya söylenir', (tester) async {
      deviceLocationLookup = () async => null;
      final b = backend();
      await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs(), backend: b);
      await tapText(tester, tr('mobileWeatherPlace.pick'));

      b.placeResults = [];
      await tester.enterText(find.byKey(const Key('weather-place-search')), 'Yokyer');
      await tester.pump(const Duration(milliseconds: 600));
      await settle(tester, 4);
      expect(find.text(tr('mobileWeatherPlace.noResults')), findsOneWidget);

      b.placesStatus = 502;
      await tester.enterText(find.byKey(const Key('weather-place-search')), 'Yokyer2');
      await tester.pump(const Duration(milliseconds: 600));
      await settle(tester, 4);
      expect(find.text(tr('mobileWeatherPlace.noResults')), findsNothing);
      expect(tester.widget<TextField>(find.byKey(const Key('weather-place-search'))).enabled, isNot(false));
    });

    for (final lang in ['tr', 'en']) {
      testWidgets('$lang: hava paneli ve yer sayfası 320 px ve %200 yazıda taşmaz', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2.0;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        deviceLocationLookup = () async => null;
        await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs(), backend: backend(), lang: lang, size: const Size(320, 568));
        expect(tester.takeException(), isNull);

        await tapText(tester, tr('mobileWeatherPlace.pick'));
        expect(find.text(tr('mobileWeatherPlace.title')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
