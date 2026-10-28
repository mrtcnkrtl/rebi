import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' show AppLifecycleState, Key, MaterialLocalizations, Scaffold, Size, TextField;
import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/core/device_location.dart';
import 'package:rebi/screens/analyze/analyze_form.dart';
import 'package:rebi/ui/tw.dart';

import 'helpers/app_harness.dart';

/// Analiz sihirbazı: tek soru tek ekran akışı, koşullu sorular, geri/kapat davranışı ve backend gövdesi.
/// Uçtan uca (sade yol) `screens_test.dart` içindedir; burada dallar ve uç durumlar var.
Future<void> _key(WidgetTester t, String k) => tapFinder(t, find.byKey(Key(k)));
Future<void> _next(WidgetTester t) => _key(t, 'flow-next');
Future<void> _back(WidgetTester t) => tapFinder(t, find.byTooltip(tr('common.back')));

/// Karşılamadan geçip ad (oturumdan gelir) + yaş sorusunu doldurur ve cinsiyet sorusuna gelir.
Future<void> _toGender(WidgetTester t) async {
  await _key(t, 'flow-start');
  await t.enterText(find.widgetWithText(TextField, '25'), '28');
  await settle(t, 3);
  await _next(t);
}

/// En uzun yol: kadın + düzenli döngü (adet tarihi sorusu) kontrolünden sonra menopoza dönüp tüm koşullu sorulardan geçer.
/// [check] her sayfada çağrılır (taşma denetimi için).
Future<void> _walkEverything(WidgetTester t, {required void Function() check}) async {
  await _toGender(t);
  check();
  await tapText(t, packS('gender.female'));
  check();
  await tapText(t, packS('step1.hormonal_regular'));
  expect(find.text(tr('mobileAnalyze.period.title')), findsOneWidget);
  check();
  await _back(t);
  await tapText(t, packS('step1.hormonal_menopause'));
  check();
  await tapText(t, packS('skinPicker.oily.label'));
  check();
  for (final c in ['acne', 'aging', 'sensitivity']) {
    await tapText(t, packS('concern.$c'));
  }
  check();
  await _next(t);
  expect(find.text(tr('mobileAnalyze.primary.title')), findsOneWidget);
  check();
  await tapText(t, packS('concern.acne'));
  expect(find.text(tr('mobileAnalyze.zones.title')), findsOneWidget);
  check();
  await tapText(t, packS('zone.forehead'));
  await _next(t);
  expect(find.text(tr('mobileAnalyze.flags.title')), findsOneWidget);
  check();
  await tapText(t, packS('step2.aging_frown'));
  await _next(t);
  for (final q in severityQuestions('acne')) {
    check();
    await tapText(t, ((q['options'] as List).last as Map)['label'].toString());
  }
  expect(find.text(tr('mobileAnalyze.life.title')), findsOneWidget);
  check();
  await _next(t);
  check();
  await _next(t); // "Testi çöz"
  for (var i = 0; i < 10; i++) {
    check();
    await tapText(t, tr('mobileAnalyze.stress.scale.${i % 5}'));
  }
  expect(find.text(tr('mobileAnalyze.smoking.title')), findsOneWidget);
  check();
  await tapText(t, packS('smokingAmount.15'));
  check();
  await _next(t);
  await tapText(t, packS('alcoholFreq.3'));
  check();
  await _next(t);
  await tapText(t, packS('makeup.frequency.3'));
  check();
  await _next(t);
  check();
  await tapText(t, packS('activesExperience.regular'));
  check();
  await _next(t); // ürün tepkileri → fotoğraf
  check();
  await _next(t); // fotoğraf → özet
  expect(find.text(tr('mobileAnalyze.summary.create')), findsOneWidget);
  check();
}

void main() {
  tearDown(() => Tw.dark = false);

  group('cevap modeli (AnalyzeForm)', () {
    test('genel bakım diğer sorunlarla birlikte seçilmez; seçimi kalkan sorunun işaretleri temizlenir', () {
      final f = AnalyzeForm();
      addTearDown(f.dispose);
      f
        ..toggleConcern('acne')
        ..toggleConcern('aging');
      f.specialFlags['frown_lines'] = true;
      f.toggleConcern('general');
      expect(f.concerns, ['general'], reason: '"yüz sorunum yok" diğerleriyle bir arada anlamsız');
      expect(f.specialFlags['frown_lines'], isFalse, reason: 'yaşlanma seçimi kalktı: işareti de gider');
      f.toggleConcern('acne');
      expect(f.concerns, ['acne']);
      expect(f.primaryConcern, 'acne');
    });

    test('öncelikli sorun başa alınır; seçim yoksa genel bakım', () {
      final f = AnalyzeForm();
      addTearDown(f.dispose);
      expect(f.primaryConcern, 'general');
      f
        ..toggleConcern('acne')
        ..toggleConcern('dryness')
        ..setPrimary('dryness');
      expect(f.concerns, ['dryness', 'acne']);
      expect(f.primaryConcern, 'dryness');
    });

    test('şiddet skoru yalnızca öncelikli sorunun tamamlanmış anketinden hesaplanır', () {
      final f = AnalyzeForm();
      addTearDown(f.dispose);
      final pack = (jsonDecode(File('assets/locales/tr/severityTests.json').readAsStringSync()) as Map).cast<String, dynamic>();
      f.toggleConcern('acne');
      expect(f.severityScore(pack), isNull, reason: 'cevap yok');
      final qs = severityQuestionsFor(pack, 'acne');
      f.severityAnswers['acne'] = {for (final q in qs.take(qs.length - 1)) q['id'].toString(): 0};
      expect(f.severityScore(pack), isNull, reason: 'eksik anket skor üretmez');
      f.severityAnswers['acne'] = {
        for (final q in qs) q['id'].toString(): ((q['options'] as List).last as Map)['score'] as num,
      };
      expect(f.severityScore(pack), 10);
      f.toggleConcern('general');
      expect(f.severityScore(pack), isNull, reason: 'genel bakımın anketi yok');
    });

    test('gövde: genel bakımda bölge gitmez; işaret yoksa special_flags null', () {
      final f = AnalyzeForm(name: 'Ayşe');
      addTearDown(f.dispose);
      f.age.text = '30';
      f.zones.add('forehead');
      var body = f.toBody(userId: 'u', photoPath: null, severity: null);
      expect(body['acne_zones'], isEmpty, reason: 'sorunsuz ciltte bölge sorulmaz, eski cevap gitmez');
      expect(body['severity_score'], 5);
      expect(body['special_flags'], isNull);
      f
        ..toggleConcern('aging')
        ..specialFlags['frown_lines'] = true;
      body = f.toBody(userId: 'u', photoPath: 'p.jpg', severity: 7);
      expect(body['acne_zones'], ['forehead']);
      expect((body['special_flags'] as Map)['frown_lines'], true);
      expect(body['photo_url'], 'p.jpg');
      expect(body['severity_score'], 7);
      expect(body['concern'], 'aging');
    });
  });

  group('akış', () {
    testWidgets('erkek: hormonal durum sorulmaz; sorunsuz ciltte bölge, işaret ve anket yoktur', (tester) async {
      final h = await pumpApp(tester, location: '/dashboard/analyze');
      await _toGender(tester);
      await tapText(tester, packS('gender.male'));
      expect(find.text(tr('mobileAnalyze.hormonal.title')), findsNothing);
      expect(find.text(tr('mobileAnalyze.skinType.title')), findsOneWidget);
      await tapText(tester, packS('skinPicker.normal.label'));
      await tapText(tester, packS('concern.general'));
      await _next(tester);
      expect(find.text(tr('mobileAnalyze.zones.title')), findsNothing);
      expect(find.text(tr('mobileAnalyze.life.title')), findsOneWidget, reason: 'genel bakımda doğrudan günlük hayata geçilir');
      expect(h.router.routeInformationProvider.value.uri.path, '/dashboard/analyze');
    });

    testWidgets('akış tam ekrandır: alt sekme çubuğu yok', (tester) async {
      await pumpApp(tester, location: '/dashboard/analyze');
      expect(find.text(tr('mobileNav.chat')), findsNothing);
      await _key(tester, 'flow-start');
      expect(find.text(tr('mobileNav.chat')), findsNothing);
    });

    testWidgets('hızlı fotoğraf yükleme kabuklu kalır (alt sekme çubuğu var)', (tester) async {
      await pumpApp(tester, location: '/dashboard/analyze?photo=1');
      expect(find.text(tr('mobileNav.chat')), findsOneWidget);
    });

    testWidgets('düzenli döngü: adet tarihi seçilmeden devam edilemez; tarih seçilince ilerler ve evre hesaplanır', (tester) async {
      final h = await pumpApp(tester, location: '/dashboard/analyze');
      await _toGender(tester);
      await tapText(tester, packS('gender.female'));
      await tapText(tester, packS('step1.hormonal_regular'));
      expect(find.text(tr('mobileAnalyze.period.title')), findsOneWidget);
      await _next(tester);
      expect(find.text(tr('mobileAnalyze.period.title')), findsOneWidget, reason: 'tarih yok: devam kapalı');

      await _key(tester, 'flow-date');
      final ok = MaterialLocalizations.of(tester.element(find.byType(Scaffold).first)).okButtonLabel;
      await tapText(tester, ok);
      await _next(tester);
      expect(find.text(tr('mobileAnalyze.skinType.title')), findsOneWidget);
      expect(h.backend.calls('/generate_routine'), isEmpty);
    });

    testWidgets('birden çok sorun: öncelikli olan sorulur, anket ona göre gelir ve gövdedeki sorun odur', (tester) async {
      final h = await pumpApp(tester, location: '/dashboard/analyze');
      await _toGender(tester);
      await tapText(tester, packS('gender.male'));
      await tapText(tester, packS('skinPicker.dry.label'));
      await tapText(tester, packS('concern.acne'));
      await tapText(tester, packS('concern.dryness'));
      await _next(tester);
      expect(find.text(tr('mobileAnalyze.primary.title')), findsOneWidget);
      await tapText(tester, packS('concern.dryness'));
      await _next(tester); // bölgeler → anket ilk soru
      expect(find.text(severityQuestions('dryness').first['text'].toString()), findsOneWidget, reason: 'anket öncelikli sorunundur');

      for (final q in severityQuestions('dryness')) {
        await tapText(tester, ((q['options'] as List).first as Map)['label'].toString());
      }
      await _next(tester); // su-uyku
      await _key(tester, 'flow-skip');
      await tapText(tester, packS('smokingAmount.0'));
      await tapText(tester, packS('alcoholFreq.0'));
      await tapText(tester, packS('makeup.frequency.0'));
      await tapText(tester, packS('activesExperience.none'));
      await _next(tester); // ürün tepkileri
      await _next(tester); // fotoğraf
      await _next(tester); // özet → oluştur
      await settle(tester, 20);
      final body = h.backend.bodyOf('/generate_routine');
      expect(body['concern'], 'dryness');
      expect(body['severity_score'], 1, reason: 'en hafif seçenekler → 1/10');
      expect(body['gender'], 'male');
      expect(body['is_pregnant'], false);
    });

    testWidgets('stres testi isteğe bağlı: çözülürse 10 soru gelir ve skora yansır; atlanırsa varsayılan kalır', (tester) async {
      final h = await pumpApp(tester, location: '/dashboard/analyze');
      await _toGender(tester);
      await tapText(tester, packS('gender.male'));
      await tapText(tester, packS('skinPicker.normal.label'));
      await tapText(tester, packS('concern.general'));
      await _next(tester);
      await _next(tester); // su-uyku
      expect(find.text(tr('mobileAnalyze.stress.title')), findsOneWidget);
      await _next(tester); // "Testi çöz"
      for (var i = 0; i < 10; i++) {
        expect(find.text(tr('mobileAnalyze.stress.caption', {'n': i + 1, 'total': 10})), findsOneWidget);
        await _next(tester);
        expect(find.text(tr('mobileAnalyze.stress.caption', {'n': i + 1, 'total': 10})), findsOneWidget, reason: 'cevap seçilmeden ilerlenmez');
        await tapText(tester, tr('mobileAnalyze.stress.scale.4'));
      }
      expect(find.text(tr('mobileAnalyze.smoking.title')), findsOneWidget);
      await tapText(tester, packS('smokingAmount.0'));
      await tapText(tester, packS('alcoholFreq.0'));
      await tapText(tester, packS('makeup.frequency.0'));
      await tapText(tester, packS('activesExperience.none'));
      for (var i = 0; i < 3; i++) {
        await _next(tester); // ürün tepkileri, fotoğraf, özet → oluştur
      }
      await settle(tester, 20);
      // Tümü "çok sık": normal maddeler 4×6 = 24, ters maddeler 0 → 24/40 × 16 ≈ 10
      expect(h.backend.bodyOf('/generate_routine')['stress_score'], 10);
    });

    testWidgets('sigara ve alkol: kullanılıyorsa alt soru açılır ve kendiliğinden ilerlenmez; içmiyorum hemen ilerler', (tester) async {
      await pumpApp(tester, location: '/dashboard/analyze');
      await _toGender(tester);
      await tapText(tester, packS('gender.male'));
      await tapText(tester, packS('skinPicker.normal.label'));
      await tapText(tester, packS('concern.general'));
      await _next(tester);
      await _next(tester);
      await _key(tester, 'flow-skip');
      expect(find.text(tr('mobileAnalyze.smoking.title')), findsOneWidget);
      await tapText(tester, packS('smokingAmount.5'));
      expect(find.text(tr('mobileAnalyze.smoking.title')), findsOneWidget, reason: 'alt soru bekliyor');
      expect(find.text(packS('step2.smokingYears')), findsOneWidget);
      await tapText(tester, packS('smokingYears.5'));
      await tapText(tester, packS('smokingAmount.0'));
      expect(find.text(tr('mobileAnalyze.alcohol.title')), findsOneWidget, reason: 'içmiyorum → hemen sonraki soru');
    });

    testWidgets('geri: soru soru geri gider; ilk sorudan karşılamaya, karşılamadan çıkışa', (tester) async {
      final h = await pumpApp(tester, location: '/dashboard/analyze');
      await _toGender(tester);
      expect(find.text(tr('mobileAnalyze.gender.title')), findsOneWidget);
      await _back(tester);
      expect(find.text(tr('mobileAnalyze.basics.title')), findsOneWidget);
      expect(find.text('28'), findsOneWidget, reason: 'cevap geri dönünce durur');
      // Android geri tuşu aynı davranır.
      await tester.binding.handlePopRoute();
      await settle(tester, 6);
      expect(find.text(tr('mobileAnalyze.intro.title')), findsOneWidget);
      await _back(tester);
      await settle(tester, 6);
      expect(h.router.routeInformationProvider.value.uri.path, '/dashboard/routine', reason: 'karşılamadan geri = çıkış');
    });

    testWidgets('kapat: ilk sorudan sonra onay sorar, vazgeçilirse kalır, çıkılırsa rutin sekmesine döner', (tester) async {
      final h = await pumpApp(tester, location: '/dashboard/analyze');
      await _toGender(tester);
      await tapText(tester, packS('gender.male'));
      await tapFinder(tester, find.byTooltip(tr('common.close')));
      expect(find.text(tr('mobileAnalyze.leaveTitle')), findsOneWidget);
      await _key(tester, 'flow-stay');
      expect(find.text(tr('mobileAnalyze.leaveTitle')), findsNothing);
      expect(find.text(tr('mobileAnalyze.skinType.title')), findsOneWidget);

      await tapFinder(tester, find.byTooltip(tr('common.close')));
      await _key(tester, 'flow-leave');
      await settle(tester, 6);
      expect(h.router.routeInformationProvider.value.uri.path, '/dashboard/routine');
    });

    testWidgets('ekran okuyucu açıkken kendiliğinden ilerlenmez; "Devam et" ile ilerlenir', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(accessibleNavigation: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await pumpApp(tester, location: '/dashboard/analyze');
      await _toGender(tester);
      await tapText(tester, packS('gender.male'));
      expect(find.text(tr('mobileAnalyze.gender.title')), findsOneWidget, reason: 'odak kaybolmasın: sayfa yerinde kalır');
      await _next(tester);
      expect(find.text(tr('mobileAnalyze.skinType.title')), findsOneWidget);
    });

    /// Özet ekranına kadar en kısa yol (erkek, normal cilt, genel bakım, hepsi "yok").
    Future<void> toSummary(WidgetTester tester) async {
      await _toGender(tester);
      await tapText(tester, packS('gender.male'));
      await tapText(tester, packS('skinPicker.normal.label'));
      await tapText(tester, packS('concern.general'));
      await _next(tester);
      await _next(tester);
      await _key(tester, 'flow-skip');
      await tapText(tester, packS('smokingAmount.0'));
      await tapText(tester, packS('alcoholFreq.0'));
      await tapText(tester, packS('makeup.frequency.0'));
      await tapText(tester, packS('activesExperience.none'));
      await _next(tester); // ürün tepkileri
      await _next(tester); // fotoğraf
    }

    setUp(() => setDeviceLocationAcquirer(acquire: () async => (at: (lat: 41.01, lon: 28.97), failure: null)));
    tearDown(resetDeviceLocationAcquirer);

    testWidgets('konum: sunucuda izin açıksa doğrudan alınır ve rutine koordinat olarak gider', (tester) async {
      final backend = FakeBackend()..privacyLocation = true;
      final h = await pumpApp(tester, location: '/dashboard/analyze', backend: backend);
      await toSummary(tester);
      await _key(tester, 'flow-location');
      await settle(tester, 8);
      expect(find.text(tr('mobileAnalyze.summary.locationSet')), findsOneWidget);
      expect(backend.calls('/privacy-preferences').where((r) => r.method == 'POST'), isEmpty, reason: 'izin zaten açık: tekrar sorulmaz');
      await _next(tester);
      await settle(tester, 20);
      final body = h.backend.bodyOf('/generate_routine');
      expect(body['location_lat'], 41.01);
      expect(body['location_lon'], 28.97);
    });

    testWidgets('konum: sunucuda izin kapalıysa önce nedeni söylenip istenir; onaylanırsa kaydedilir ve konum alınır', (tester) async {
      final backend = FakeBackend()..privacyPhoto = true;
      await pumpApp(tester, location: '/dashboard/analyze', backend: backend);
      await toSummary(tester);
      await _key(tester, 'flow-location');
      expect(find.text(tr('mobileAnalyze.location.consentTitle')), findsOneWidget);
      await _key(tester, 'flow-location-allow');
      await settle(tester, 8);
      expect(backend.privacyLocation, isTrue);
      expect(backend.privacyPhoto, isTrue, reason: 'fotoğraf izni bozulmaz');
      expect(find.text(tr('mobileAnalyze.summary.locationSet')), findsOneWidget);
    });

    testWidgets('konum: izin istenince "şimdi değil" denirse konum alınmaz, hata da gösterilmez', (tester) async {
      final backend = FakeBackend();
      await pumpApp(tester, location: '/dashboard/analyze', backend: backend);
      await toSummary(tester);
      await _key(tester, 'flow-location');
      await _key(tester, 'flow-location-later');
      await settle(tester, 6);
      expect(backend.privacyLocation, isFalse);
      expect(find.text(tr('mobileAnalyze.summary.locationSet')), findsNothing);
      expect(find.text(tr('mobileAnalyze.location.consentFailed')), findsNothing);
      expect(find.text(tr('mobileAnalyze.summary.location')), findsOneWidget, reason: 'satır yeniden denenebilir kalır');
    });

    testWidgets('konum: izin durumu okunamazsa neden söylenir', (tester) async {
      final backend = FakeBackend()..privacyFails = true;
      await pumpApp(tester, location: '/dashboard/analyze', backend: backend);
      await toSummary(tester);
      await _key(tester, 'flow-location');
      await settle(tester, 8);
      expect(find.text(tr('mobileAnalyze.location.consentFailed')), findsOneWidget);
    });

    for (final failure in LocationFailure.values) {
      testWidgets('konum: ${failure.name} → nedenine özel cümle; rutin yine oluşturulabilir', (tester) async {
        setDeviceLocationAcquirer(acquire: () async => (at: null, failure: failure));
        final backend = FakeBackend()..privacyLocation = true;
        final h = await pumpApp(tester, location: '/dashboard/analyze', backend: backend);
        await toSummary(tester);
        await _key(tester, 'flow-location');
        await settle(tester, 8);
        expect(find.text(tr('mobileAnalyze.location.${failure.name}')), findsOneWidget);
        expect(find.text(packS('errors.locationFailed')), findsNothing, reason: 'genel "alınamadı" yerine neden söylenir');
        final fix = switch (failure) {
          LocationFailure.serviceOff => 'mobileAnalyze.location.openSettings',
          LocationFailure.blocked => 'mobileAnalyze.location.openAppSettings',
          _ => 'mobileAnalyze.location.retry',
        };
        expect(find.text(tr(fix)), findsOneWidget, reason: 'satır çözümü söyler');
        await _next(tester);
        await settle(tester, 20);
        expect(h.backend.bodyOf('/generate_routine')['location_lat'], isNull);
      });
    }

    testWidgets('konum: servis kapalıyken satır ayarı açar; ayardan dönülünce satır yeniden "konumumu paylaş" olur', (tester) async {
      final opened = <LocationFailure>[];
      setDeviceLocationAcquirer(
        acquire: () async => (at: null, failure: LocationFailure.serviceOff),
        openSettings: (f) async {
          opened.add(f);
          return true;
        },
      );
      await pumpApp(tester, location: '/dashboard/analyze', backend: FakeBackend()..privacyLocation = true);
      await toSummary(tester);
      await _key(tester, 'flow-location');
      await settle(tester, 6);
      await _key(tester, 'flow-location');
      expect(opened, [LocationFailure.serviceOff]);

      // Kullanıcı ayardan uygulamaya döner.
      for (final st in const [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(st);
      }
      await settle(tester, 6);
      expect(find.text(tr('mobileAnalyze.summary.location')), findsOneWidget);
      expect(find.text(tr('mobileAnalyze.location.serviceOff')), findsNothing);
    });

    testWidgets('bağlantı hatasında analiz özette kalır, hata gösterilir ve tekrar denenebilir', (tester) async {
      final backend = FakeBackend()..generateFails = true;
      await pumpApp(tester, location: '/dashboard/analyze', backend: backend);
      await _toGender(tester);
      await tapText(tester, packS('gender.male'));
      await tapText(tester, packS('skinPicker.normal.label'));
      await tapText(tester, packS('concern.general'));
      await _next(tester);
      await _next(tester);
      await _key(tester, 'flow-skip');
      await tapText(tester, packS('smokingAmount.0'));
      await tapText(tester, packS('alcoholFreq.0'));
      await tapText(tester, packS('makeup.frequency.0'));
      await tapText(tester, packS('activesExperience.none'));
      await _next(tester); // ürün tepkileri
      await _next(tester); // fotoğraf
      await _next(tester); // özet → oluştur
      await settle(tester, 20);
      expect(find.text(tr('analyze.generateFailedTitle')), findsOneWidget);
      expect(find.text(tr('mobileAnalyze.summary.create')), findsOneWidget, reason: 'özet ekranı yerinde: tekrar denenebilir');
    });
  });

  group('taşma', () {
    for (final (scale, size) in [(1.0, const Size(390, 844)), (1.0, const Size(320, 568)), (1.5, const Size(360, 780)), (2.0, const Size(320, 640))]) {
      for (final dark in [false, true]) {
        testWidgets('en uzun yol: ${size.width.toInt()}×${size.height.toInt()}, yazı %${(scale * 100).round()}, ${dark ? 'koyu' : 'açık'}', (tester) async {
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          Tw.dark = dark;
          await pumpApp(tester, location: '/dashboard/analyze', size: size);
          expect(tester.takeException(), isNull, reason: 'karşılama');
          await _walkEverything(tester, check: () => expect(tester.takeException(), isNull));
        });
      }
    }
  });
}
