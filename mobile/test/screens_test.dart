import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:rebi/core/i18n.dart';
import 'package:rebi/core/local_store.dart';
import 'package:rebi/core/routine_tracking.dart';
import 'package:rebi/screens/analyze/analyze_screen.dart';
import 'package:rebi/screens/today/today_header.dart';
import 'package:rebi/ui/shell/app_shell.dart';
import 'package:rebi/ui/components/severity_test.dart';

import 'helpers/app_harness.dart';

/// Ekran akışları: web'deki kullanıcı yolculuklarının mobilde aynı çalıştığını doğrular.
/// Her test gerçek router + kabuk + ekranları telefon boyutunda (390×844) çizer;
/// taşma veya çizim hatası olursa test kırılır.
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

  group('giriş yapmamış kullanıcı', () {
    testWidgets('landing: ana eylem kayıt ekranını açar ve analize yönlendirmeyi taşır', (tester) async {
      final h = await pumpApp(tester, location: '/', loggedIn: false);
      expect(find.text(tr('mobileLanding.heroTitle')), findsOneWidget);
      await tapText(tester, tr('landing.ctaBuildRoutine'));
      expect(h.router.routeInformationProvider.value.uri.toString(), '/auth?next=%2Fdashboard%2Fanalyze&mode=signup');
      expect(find.text(tr('auth.createAccount')), findsOneWidget);
      expect(find.text(tr('auth.fullName')), findsOneWidget);
    });

    testWidgets('landing: "Giriş yap" bağlantısı giriş modunu açar', (tester) async {
      final h = await pumpApp(tester, location: '/', loggedIn: false);
      await tapText(tester, tr('auth.login'));
      expect(h.router.routeInformationProvider.value.uri.path, '/auth');
      expect(find.text(tr('auth.welcome')), findsOneWidget);
      expect(find.text(tr('auth.fullName')), findsNothing);
    });

    testWidgets('landing: Rebi ile konuş anonim sohbete gider', (tester) async {
      final h = await pumpApp(tester, location: '/', loggedIn: false);
      await tapText(tester, tr('landing.ctaChat'));
      expect(h.router.routeInformationProvider.value.uri.path, '/rebi');
      expect(find.text(tr('chat.emptyTitle')), findsOneWidget);
    });

    testWidgets('landing: tek kahraman, tek ana eylem; kaydırmalı sahne, yüzen kart ve ilerleme göstergesi yoktur', (tester) async {
      await pumpApp(tester, location: '/', loggedIn: false);
      expect(find.byType(PageView), findsNothing, reason: 'sahneler arasında kaydırma yok');
      expect(find.text(tr('mobileLanding.heroTitle')), findsOneWidget);
      expect(find.text(tr('mobileLanding.heroSub')), findsOneWidget);
      // Ana düğme tek: dolu (krem) düğme yalnızca "Rutini oluştur"dur; geri kalanlar sessiz metin eylemleridir.
      expect(find.text(tr('landing.ctaBuildRoutine')), findsOneWidget);
      expect(find.text(tr('auth.login')), findsOneWidget);
      expect(find.text(tr('landing.ctaChat')), findsOneWidget);
      expect(find.text(tr('legal.kvkkTitle')), findsOneWidget);
      expect(find.text(tr('legal.rizaTitle')), findsOneWidget);
    });

    testWidgets('landing: oturum açıkken ana eylem panele götürür', (tester) async {
      final h = await pumpApp(tester, location: '/');
      expect(find.text(tr('auth.login')), findsNothing);
      await tapText(tester, tr('mobileLanding.openApp'));
      expect(h.router.routeInformationProvider.value.uri.path, '/dashboard');
    });

    testWidgets('korumalı rota girişe yönlendirir ve next parametresini taşır', (tester) async {
      final h = await pumpApp(tester, location: '/dashboard/chat', loggedIn: false);
      expect(h.router.routeInformationProvider.value.uri.toString(), '/auth?next=%2Fdashboard%2Fchat');
    });

    // KVKK ve açık rıza yalnızca kayıt ekranında alınır (girişte kutu yok: test/auth_flow_test.dart).
    testWidgets('auth (kayıt): onay kutuları işaretlenmeden gönderilemez, form doğrulaması çalışır', (tester) async {
      await pumpApp(tester, location: '/auth?mode=signup', loggedIn: false);
      final submit = find.byKey(const Key('auth-submit'));
      await tester.ensureVisible(submit.first);
      await tester.tap(submit.first, warnIfMissed: false);
      await settle(tester, 3);
      expect(find.text('Lütfen bu alanı doldurun.'), findsNothing, reason: 'onaysız düğme pasif olmalı');

      // İsteğe bağlı izinler varsayılan olarak katlıdır; açılınca konum ve fotoğraf kutuları görünür, ikisi de işaretsizdir.
      expect(find.text(tr('auth.locationConsent')), findsNothing);
      expect(find.byType(Checkbox), findsNWidgets(2));
      await tapText(tester, tr('auth.optionalPermissions'));
      expect(find.byType(Checkbox), findsNWidgets(4));
      await tapText(tester, tr('auth.locationConsent'));
      expect(find.text('1/2'), findsOneWidget, reason: 'açık izin sayısı satırda görünür');
      final boxes = find.byType(Checkbox);
      await tapFinder(tester, boxes.at(0));
      await tapFinder(tester, boxes.at(1));
      await tapFinder(tester, submit.first);
      expect(find.text('Lütfen bu alanı doldurun.'), findsNWidgets(3), reason: 'ad, e-posta, parola');

      await tester.enterText(find.byType(TextFormField).at(1), 'yanlis-eposta');
      await tester.enterText(find.byType(TextFormField).at(2), '123');
      await settle(tester, 4); // alanın ekrana kaydırma animasyonu bitsin
      await tapFinder(tester, submit.first);
      expect(find.text('Lütfen geçerli bir e-posta adresi girin.'), findsOneWidget);
      expect(find.textContaining('en az 6 karakter'), findsOneWidget);
    });

    testWidgets('auth (kayıt): KVKK bağlantısı formu kaybetmeden üstte açılır', (tester) async {
      final h = await pumpApp(tester, location: '/auth?mode=signup', loggedIn: false);
      await tester.enterText(find.byType(TextFormField).at(1), 'ayse@ornek.com');
      final rich = find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText().contains(tr('auth.kvkkLink')));
      await tester.ensureVisible(rich.first);
      await tester.pump();
      h.router.push('/kvkk');
      await settle(tester, 4);
      expect(find.text(tr('legal.kvkkTitle')), findsWidgets);
      expect(find.text('1. Veri sorumlusu'), findsOneWidget);
      await tapText(tester, tr('legal.backToAuth'));
      expect(find.text('ayse@ornek.com'), findsOneWidget);
    });

    testWidgets('kayıt moduna geçiş ad alanını gösterir', (tester) async {
      await pumpApp(tester, location: '/auth', loggedIn: false);
      await tapText(tester, tr('auth.signup'));
      expect(find.text(tr('auth.fullName')), findsOneWidget);
      expect(find.text(tr('auth.createAccount')), findsOneWidget);
    });
  });

  group('panel', () {
    testWidgets('rutin yoksa analiz çağrısı ve kişisel karşılama', (tester) async {
      await pumpApp(tester, location: '/dashboard');
      expect(find.text(tr('dashboard.noAnalyzeTitle', {'name': 'Ayşe Test'})), findsOneWidget);
      expect(find.text(tr('dashboard.startAnalyze')), findsOneWidget);
    });

    testWidgets('yapay zekâ beyanı bir kez onaylanır ve kalıcıdır', (tester) async {
      await pumpApp(tester, location: '/dashboard', acknowledgeAi: false);
      expect(find.text(tr('common.aiDisclaimerTitle')), findsOneWidget);
      await tapText(tester, tr('common.aiDisclaimerAck'));
      expect(find.text(tr('common.aiDisclaimerTitle')), findsNothing);
      expect(LocalStore.instance.getString('rebi-ai-disclaimer-ack-v1'), '1');
    });

    testWidgets('kabul edilmiş rutin: takip modu, günün planı ve hızlı kayıt', (tester) async {
      final h = await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs());
      expect(find.byType(TodayHeader), findsOneWidget);
      expect(find.text(tr('dashboard.dailyCheckinTitle')), findsOneWidget);
      expect(find.text(tr('dashboard.dailyBalanceTitle')), findsOneWidget);

      await tapText(tester, tr('mobileToday.spf.done'));
      final body = h.backend.bodyOf('/daily_tracking/ingest');
      expect(body['type'], 'spf_refresh');
      expect(body['payload'], isEmpty);
      expect(body['user_id'], testUserId);
      expect(body['source'], 'mobile');
      expect(body['client_event_id'], isNotEmpty);
      expect(find.text(tr('mobileToday.toast.spf')), findsOneWidget);

      // Tüm hafta artık Rutin sekmesinde; Bugün'e alt sekmeyle dönülür.
      await tapText(tester, tr('mobileToday.showFullPlan'));
      expect(h.router.routeInformationProvider.value.uri.path, '/dashboard/routine');
      expect(find.text(tr('dashboard.routineByDayTitle')), findsOneWidget);
      expect(find.text(tr('dashboard.backToTracking')), findsNothing, reason: 'Rutin sekmesinde geri bağlantısı yok');
      expect(find.byType(TodayHeader), findsNothing);
      await tapText(tester, tr('mobileNav.today'));
      expect(h.router.routeInformationProvider.value.uri.path, '/dashboard');
      expect(find.byType(TodayHeader), findsOneWidget);
    });

    testWidgets('tam plan: adım detayı açılır, sabah uyarısı görünür', (tester) async {
      await pumpApp(tester, location: '/dashboard', extra: {'routine': routine, 'userName': 'Ayşe'});
      expect(find.text(tr('dashboard.acceptBanner')), findsOneWidget);
      expect(find.text(tr('dashboard.morningUsageTitle')), findsOneWidget);
      final why = find.text(tr('dashboard.whySkincareButton'));
      expect(why, findsWidgets);
      await tester.ensureVisible(why.first);
      await tester.tap(why.first);
      await settle(tester, 3);
      expect(find.text(tr('common.hide')), findsOneWidget);
    });

    testWidgets('İngilizce arayüz: tarih ve başlıklar İngilizce', (tester) async {
      await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs(), lang: 'en');
      final greeting = find.byWidgetPredicate(
        (w) => w is Text && RegExp(r'^Good (morning|afternoon|evening|night), Ayşe$').hasMatch(w.data ?? ''),
      );
      expect(greeting, findsOneWidget);
      expect(find.text(tr('mobileToday.bar.mark.morning')).evaluate().length + find.text(tr('mobileToday.bar.mark.evening')).evaluate().length, 1);
    });
  });

  testWidgets('analiz sihirbazı uçtan uca: backend gövdesi web ile aynı, rutin kabul edilir', (tester) async {
    final h = await pumpApp(tester, location: '/dashboard/analyze');

    // Adım 1
    expect(find.text(packS('step1.title')), findsOneWidget);
    expect(find.text('Ayşe Test'), findsOneWidget, reason: 'ad oturumdan gelir');
    await tester.enterText(find.widgetWithText(TextField, '25'), '28');
    await tapText(tester, packS('gender.female'));
    await tapText(tester, packS('step1.hormonal_pregnant'));
    await tapText(tester, tr('analyze.continue'));

    // Adım 2
    expect(find.text(packS('step2.title')), findsOneWidget);
    await tapText(tester, packS('skinPicker.oily.label'));
    await tapText(tester, packS('concern.acne'));
    await tapText(tester, packS('zone.forehead'));
    await tapText(tester, packS('makeup.frequency.3'));
    await tapText(tester, tr('common.continue'));

    // Adım 3 — aktif deneyim → şiddet → tetikleyici → tedavi → beklenti
    expect(find.text(packS('step3.activesTitle')), findsOneWidget);
    await tapText(tester, packS('activesExperience.regular'));
    await tapText(tester, tr('common.continue'));
    expect(find.byType(SeverityTest), findsOneWidget);
    final questions = severityQuestions('acne');
    var index = 0;
    for (final q in questions) {
      final count = (q['options'] as List).length;
      final options = find.descendant(of: find.byType(SeverityTest), matching: find.byType(InkWell));
      await tapFinder(tester, options.at(index + count - 1)); // her sorunun en şiddetli seçeneği
      index += count;
    }
    expect(find.text('10/10'), findsOneWidget);
    await tapText(tester, packS('duration.3-6'));
    await tapText(tester, tr('common.continue'));
    await tapText(tester, packS('trigger.stress'));
    await tapText(tester, tr('common.continue'));
    await tapText(tester, tr('common.continue'));
    await tapText(tester, tr('analyze.continue'));

    // Adım 4
    expect(find.text(tr('analyze.finalStep')), findsOneWidget);
    await tapText(tester, packS('tolerance.bad'));
    await tapText(tester, packS('step4.createRoutineCta'));
    await settle(tester, 20);

    final body = h.backend.bodyOf('/generate_routine');
    expect(body['user_id'], testUserId);
    expect(body['full_name'], 'Ayşe Test');
    expect(body['age'], 28);
    expect(body['gender'], 'female');
    expect(body['concern'], 'acne');
    expect(body['skin_type'], 'oily');
    expect(body['is_pregnant'], true);
    expect(body['cycle_phase'], '');
    expect(body['acne_zones'], ['forehead']);
    expect(body['severity_score'], 10, reason: 'anket tamamlanınca hesaplanan skor gider');
    expect(body['stress_score'], 6, reason: 'PSS varsayılan 0 → (16*16/40) yuvarlanır');
    expect(body['water_intake'], 2);
    expect(body['sleep_hours'], 7);
    expect(body['smoking'], false);
    expect(body['alcohol'], false);
    expect(body['makeup_frequency'], 3);
    expect(body['makeup_removal'], 'cleanser');
    expect(body['actives_experience'], 'regular');
    expect((body['actives_tolerance'] as Map).length, strongActiveFamilyIds.length);
    expect((body['actives_tolerance'] as Map)['retinol'], 'bad');
    expect(body['special_flags'], isNull);
    expect(body['photo_url'], isNull);
    expect(body['location_lat'], isNull);
    expect(body.keys.toSet(), {
      'user_id', 'full_name', 'age', 'gender', 'concern', 'skin_type', 'severity_score', 'water_intake',
      'sleep_hours', 'stress_score', 'smoking', 'smoking_per_day', 'smoking_years', 'alcohol',
      'alcohol_frequency', 'alcohol_amount', 'location_lat', 'location_lon', 'photo_url', 'is_pregnant',
      'cycle_phase', 'acne_zones', 'actives_experience', 'actives_tolerance', 'makeup_frequency',
      'makeup_removal', 'special_flags',
    }, reason: 'web Analyze.jsx ile aynı alan kümesi');

    // Panel: kabul çubuğu → takip modu
    expect(h.router.routeInformationProvider.value.uri.path, '/dashboard');
    expect(find.text(tr('dashboard.acceptBanner')), findsOneWidget);
    await tapText(tester, tr('dashboard.acceptCta'));
    expect(find.byType(TodayHeader), findsOneWidget);
    expect(isRoutineTrackingAccepted(testUserId), isTrue);
    expect(getRoutineSnapshot(testUserId)?['acceptedAt'], isA<int>());
    expect((getRoutineSnapshot(testUserId)?['routine'] as List).length, routine.length);
  });

  testWidgets('analiz: ilk analizden sonra kısa ekran, istenirse tam form', (tester) async {
    await pumpApp(tester, location: '/dashboard/analyze', prefs: acceptedPrefs());
    expect(find.text(tr('analyze.routineReadyTitle')), findsOneWidget);
    await tapText(tester, tr('analyze.newAnalyzeFull'));
    expect(find.text(packS('step1.title')), findsOneWidget);
  });

  testWidgets('check-in: rutin kabul edilmeden açılmaz', (tester) async {
    final h = await pumpApp(tester, location: '/dashboard/checkin');
    expect(h.router.routeInformationProvider.value.uri.path, '/dashboard');
    expect(find.text(tr('dashboard.acceptHint')), findsOneWidget);
  });

  testWidgets('check-in uçtan uca: ek sorular, gövde, rapor, geri bildirim, panele dönüş', (tester) async {
    final h = await pumpApp(tester, location: '/dashboard/checkin', prefs: acceptedPrefs());
    expect(find.text(tr('checkin.title')), findsOneWidget);
    await tapText(tester, 'İrritasyon');
    expect(find.text(tr('checkin.reactionSeverityTitle')), findsOneWidget);
    await tapText(tester, tr('checkin.symptomBurning'));

    final water = find.widgetWithText(TextField, 'Örn. 2000 (8 bardak)');
    await tester.ensureVisible(water);
    await tester.enterText(water, '1500');
    await settle(tester, 2);
    expect(find.text('1.500 ml → yaklaşık 6 bardak'), findsOneWidget);
    await tapText(tester, '+½ bardak (+125 ml)');
    expect(find.text('1.625 ml → yaklaşık 6.5 bardak'), findsOneWidget);

    // Makyaj: Evet → yöntem
    final makeupYes = find.text('Evet');
    await tester.ensureVisible(makeupYes.at(1));
    await tester.tap(makeupYes.at(1));
    await settle(tester, 2);
    await tapText(tester, 'Çift aşama');
    // Akneye özel ilk soru: Evet
    final extraYes = find.text(tr('common.yes'));
    await tester.ensureVisible(extraYes.at(2));
    await tester.tap(extraYes.at(2));
    await settle(tester, 2);

    await tapText(tester, tr('checkin.submit'));
    final body = h.backend.bodyOf('/daily_checkin');
    expect(body['user_id'], testUserId);
    expect(body['sleep_hours'], 7);
    expect(body['stress_today'], 3);
    expect(body['skin_feeling'], 'irritasyon');
    expect(body['applied_routine'], true);
    expect(body['notes'], isNull);
    expect(body['water_ml_today'], 1625);
    expect(body['makeup_used_today'], true);
    expect(body['makeup_removal_today'], 'double');
    expect(body['picked_skin_today'], true);
    expect(body.containsKey('heavy_dairy_today'), isFalse, reason: 'atlanan sorular gönderilmez');
    expect(body['symptom_tags'], ['burning_stinging']);
    expect(body['active_reaction_severity'], 2);

    expect(find.text(tr('checkin.todayReport')), findsOneWidget);
    expect(find.text('Bugün bariyeri dinlendir.'), findsOneWidget);
    expect(find.text('Değişiklikler'), findsOneWidget);
    await tapText(tester, 'OK');
    final fb = h.backend.bodyOf('/daily_tracking/ingest');
    expect(fb['type'], 'checkin_feedback');
    expect((fb['payload'] as Map)['helpful'], 'helpful');
    expect(find.text(tr('checkin.feedbackThanks')), findsOneWidget);

    await tapText(tester, tr('checkin.backToDashboard'));
    expect(h.router.routeInformationProvider.value.uri.path, '/dashboard');
    expect(find.text('Bugün bariyeri dinlendir.'), findsOneWidget, reason: 'son check-in notu panelde');
    final log = LocalStore.instance.getJson('rebi_checkin_log_$testUserId') as List;
    expect(log.single['applied'], true);
  });

  testWidgets('check-in: bugün yapıldıysa bilgi ekranı', (tester) async {
    final backend = FakeBackend()..checkinStatus = {'already_checked_in': true};
    await pumpApp(tester, location: '/dashboard/checkin', prefs: acceptedPrefs(), backend: backend);
    expect(find.text(tr('checkin.alreadyTitle')), findsOneWidget);
  });

  group('sohbet', () {
    testWidgets('mesaj gönderilir, yanıt ve kota rozeti görünür, kota dolunca paywall açılır', (tester) async {
      withPlusPurchasable();
      final backend = FakeBackend()..quotaAfter = 1;
      final h = await pumpApp(tester, location: '/dashboard/chat', backend: backend);
      expect(find.text(tr('chat.emptyTitle')), findsOneWidget);
      expect(find.text(tr('chat.usageBadgeDay', {'rem': 4, 'lim': 5})), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Niasinamid ne işe yarar?');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await settle(tester);
      final body = h.backend.bodyOf('/chat_general');
      expect(body['message'], 'Niasinamid ne işe yarar?');
      expect(body['history'], [
        {'role': 'user', 'content': 'Niasinamid ne işe yarar?'},
      ]);
      expect(find.textContaining('Niasinamid bariyeri destekler.'), findsOneWidget);
      expect(find.text(tr('chat.usageBadgeDay', {'rem': 3, 'lim': 5})), findsOneWidget);
      final stored = LocalStore.instance.getJson('rebi-chat-history_$testUserId') as List;
      expect(stored, hasLength(2));

      await tester.enterText(find.byType(TextField), 'Bir soru daha');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await settle(tester);
      expect(find.text(tr('chat.paywallTitleDay')), findsOneWidget);
      await tapText(tester, tr('mobileChat.limit.notNow'));
      expect(find.text(tr('chat.paywallTitleDay')), findsNothing);

      await tapText(tester, tr('chat.clear'));
      expect(h.backend.calls('/chat/history').any((r) => r.method == 'DELETE'), isTrue);
      expect(find.text(tr('chat.emptyTitle')), findsOneWidget);
    });

    testWidgets('rıza kaydı yoksa onay kutusu açılır ve kayıt alınır', (tester) async {
      final backend = FakeBackend()..consentMissing = true;
      final h = await pumpApp(tester, location: '/dashboard/chat', backend: backend);
      await tester.enterText(find.byType(TextField), 'Merhaba');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await settle(tester);
      expect(find.text(tr('common.consentRecoveryTitle')), findsOneWidget);
      final boxes = find.byType(Checkbox);
      await tapFinder(tester, boxes.at(0));
      await tapFinder(tester, boxes.at(1));
      await tapText(tester, tr('common.consentRecoveryCta'));
      final accept = h.backend.bodyOf('/legal-consent/accept');
      expect(accept['kvkk_accepted'], true);
      expect(accept['ai_processing_accepted'], true);
      expect(accept['document_version'], 'v2');
      expect(find.text(tr('common.consentRecoveryTitle')), findsNothing);
    });

    testWidgets('anonim sohbet demo kimliğiyle gider', (tester) async {
      final h = await pumpApp(tester, location: '/rebi', loggedIn: false);
      await tester.enterText(find.byType(TextField), 'Selam');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await settle(tester);
      expect(h.backend.bodyOf('/chat_general')['user_id'], '00000000-0000-4000-8000-000000000001');
    });
  });

  group('tema ve abonelik', () {
    testWidgets('ücretsiz tema seçilir, premium tema aboneliğe yönlendirir', (tester) async {
      withPlusPurchasable();
      final h = await pumpApp(tester, location: '/dashboard/themes');
      await tapText(tester, 'Pudra');
      expect(h.theme.themeId, 'pink');
      expect(LocalStore.instance.getString('rebi-theme'), 'pink');
      await tapText(tester, 'Gün Batımı');
      expect(h.router.routeInformationProvider.value.uri.path, '/dashboard/subscribe');
      expect(h.theme.themeId, 'pink');
    });

    testWidgets('Plus kullanıcı premium temayı seçebilir; Plus bitince teal\'e döner', (tester) async {
      final h = await pumpApp(
        tester,
        location: '/dashboard/themes',
        user: fakeUser(appMetadata: {'rebi_plus': true}),
      );
      await tapText(tester, 'Gün Batımı');
      expect(h.theme.themeId, 'sunset');
      h.auth.debugSetUser(fakeUser());
      await settle(tester, 2);
      expect(h.theme.themeId, 'teal');
    });

    testWidgets('abonelik ekranı Plus durumunu gösterir', (tester) async {
      await pumpApp(tester, location: '/dashboard/subscribe', user: fakeUser(appMetadata: {'subscription_tier': 'PLUS'}));
      expect(find.text('Plus aktif'), findsOneWidget);
      expect(find.text('Neler dahil?'), findsOneWidget);
    });
  });

  Finder tabButton(String label) => find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == label && w.properties.button == true && w.properties.selected != null,
      );

  group('alt sekmeler', () {
    testWidgets('beş sekme gezinir; hamburger menüsü uygulama içinde yoktur', (tester) async {
      final h = await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs());
      expect(find.byIcon(LucideIcons.menu), findsNothing);
      for (final (key, path) in [
        ('mobileNav.routine', '/dashboard/routine'),
        ('mobileNav.chat', '/dashboard/chat'),
        ('mobileNav.history', '/dashboard/history'),
        ('mobileNav.me', '/dashboard/profile'),
        ('mobileNav.today', '/dashboard'),
      ]) {
        await tester.tap(tabButton(tr(key)).first);
        await settle(tester);
        expect(h.router.routeInformationProvider.value.uri.path, path, reason: key);
      }
    });

    testWidgets('check-in kabul yoksa Bugün\'e uyarıyla döner', (tester) async {
      final h = await pumpApp(tester, location: '/dashboard/checkin');
      expect(h.router.routeInformationProvider.value.uri.path, '/dashboard');
      expect(find.text(tr('dashboard.acceptHint')), findsOneWidget);
    });

    testWidgets('alt sayfada geri çubuğu sekmesine döndürür', (tester) async {
      final h = await pumpApp(tester, location: '/dashboard/themes');
      expect(find.text(tr('mobileNav.back')), findsOneWidget);
      await tapText(tester, tr('mobileNav.back'));
      expect(h.router.routeInformationProvider.value.uri.path, '/dashboard/profile');
    });

    testWidgets('sekme köklerinde geri çubuğu yoktur', (tester) async {
      await pumpApp(tester, location: '/dashboard/chat');
      expect(find.text(tr('mobileNav.back')), findsNothing);
    });

    test('yol → sekme eşlemesi', () {
      expect(tabForPath('/dashboard'), AppTab.today);
      expect(tabForPath('/dashboard/checkin'), AppTab.today);
      expect(tabForPath('/dashboard/routine'), AppTab.routine);
      expect(tabForPath('/dashboard/analyze'), AppTab.routine);
      expect(tabForPath('/dashboard/chat'), AppTab.chat);
      expect(tabForPath('/dashboard/history'), AppTab.history);
      expect(tabForPath('/dashboard/profile'), AppTab.me);
      for (final p in ['/dashboard/account', '/dashboard/themes', '/dashboard/subscribe', '/dashboard/reminders']) {
        expect(tabForPath(p), AppTab.me, reason: p);
      }
      expect(tabForPath('/'), isNull);
      expect(tabForPath('/auth'), isNull);
      expect(tabForPath('/rebi'), isNull);
      expect(isSubPage('/dashboard/checkin'), isTrue);
      expect(isSubPage('/dashboard/analyze'), isTrue);
      expect(isSubPage('/dashboard/profile'), isFalse);
      expect(isSubPage('/dashboard'), isFalse);
    });
  });

  group('Rutin sekmesi', () {
    testWidgets('haftalık plan gün seçiciyle gösterilir; takip çubuğu ve geri bağlantısı yoktur', (tester) async {
      await pumpApp(tester, location: '/dashboard/routine', prefs: acceptedPrefs());
      expect(find.text(tr('dashboard.routineByDayTitle')), findsOneWidget);
      expect(find.text(tr('dashboard.backToTracking')), findsNothing);
      expect(find.text(tr('mobileToday.bar.mark.morning')), findsNothing);
      expect(find.byType(TodayHeader), findsNothing);
    });

    testWidgets('gün seçilince o günün planı açılır', (tester) async {
      await pumpApp(tester, location: '/dashboard/routine', prefs: acceptedPrefs());
      final days = I18n.instance.tList('dashboard.weekDays', const []);
      expect(days, hasLength(7));
      final other = days[(DateTime.now().weekday) % 7];
      final chip = find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == other && w.properties.button == true && w.properties.selected == false,
      );
      expect(chip, findsOneWidget);
      final before = find.text(other).evaluate().length;
      await tapFinder(tester, chip);
      expect(find.text(other).evaluate().length, before + 1, reason: 'seçilen günün kartı başlığı eklenir');
    });

    testWidgets('rutin yoksa analize çağırır', (tester) async {
      await pumpApp(tester, location: '/dashboard/routine');
      expect(find.text(tr('dashboard.startAnalyze')), findsOneWidget);
    });
  });

  testWidgets('Ben sekmesi: hesap özeti, ayar satırları ve çıkış', (tester) async {
    withPlusPurchasable();
    final h = await pumpApp(tester, location: '/dashboard/profile');
    expect(find.text('Ayşe Test'), findsOneWidget);
    expect(find.text('test@rebi.app'), findsOneWidget);
    for (final key in [
      'mobileMe.account.title',
      'mobileReminders.open',
      'mobileMe.reanalyze.title',
      'mobileAppearance.title',
      'mobileMe.themes.title',
      'mobileMe.plus.title',
      'mobileMe.logout',
    ]) {
      expect(find.text(tr(key)), findsOneWidget, reason: key);
    }
    for (final (key, path) in [
      ('mobileMe.account.title', '/dashboard/account'),
      ('mobileReminders.open', '/dashboard/reminders'),
      ('mobileMe.reanalyze.title', '/dashboard/analyze'),
      ('mobileMe.themes.title', '/dashboard/themes'),
      ('mobileMe.plus.title', '/dashboard/subscribe'),
    ]) {
      h.router.go('/dashboard/profile');
      await settle(tester);
      await tapText(tester, tr(key));
      expect(h.router.routeInformationProvider.value.uri.path, path, reason: key);
    }
  });

  testWidgets('Ben sekmesi: Plus rozeti yalnızca aboneye görünür', (tester) async {
    withPlusPurchasable();
    await pumpApp(tester, location: '/dashboard/profile');
    expect(find.text(tr('mobileMe.plusBadge')), findsNothing);
    expect(find.text(tr('mobileMe.plus.hint')), findsOneWidget);
  });

  testWidgets('Ben sekmesi: Plus aboneliğinde rozet ve etkin mesajı görünür', (tester) async {
    await pumpApp(tester, location: '/dashboard/profile', user: fakeUser(appMetadata: {'subscription_tier': 'PLUS'}));
    expect(find.text(tr('mobileMe.plusBadge')), findsOneWidget);
    expect(find.text(tr('mobileMe.plus.active')), findsOneWidget);
  });

  testWidgets('açılış: dil rozetinden İngilizceye çevrilir ve kalıcıdır', (tester) async {
    await pumpApp(tester, location: '/', loggedIn: false);
    await tester.tap(find.byIcon(LucideIcons.globe));
    await settle(tester, 4);
    expect(find.text('Türkçe'), findsOneWidget);
    await tester.tap(find.text('English'));
    await settle(tester, 4);
    expect(LocalStore.instance.getString('rebi-lang'), 'en');
    expect(find.text(tr('mobileLanding.heroTitle')), findsOneWidget);
  });

  testWidgets('hızlı foto yükleme: Supabase yoksa açıklama gösterir', (tester) async {
    await pumpApp(tester, location: '/dashboard/analyze?photo=1');
    expect(find.text(packS('errors.supabaseAnalyzeMissing')), findsOneWidget);
  });

  group('tablet düzeni', () {
    for (final loc in ['/', '/dashboard', '/dashboard/chat', '/dashboard/themes', '/dashboard/subscribe', '/dashboard/routine', '/dashboard/profile', '/dashboard/history']) {
      testWidgets('$loc 820×1180 çizilir', (tester) async {
        await pumpApp(tester, location: loc, prefs: acceptedPrefs(), size: const Size(820, 1180), loggedIn: loc != '/');
        expect(tester.takeException(), isNull);
      });
    }
  });

  testWidgets('küçük telefon: kadın + düzenli döngü alanları taşmaz', (tester) async {
    await pumpApp(tester, location: '/dashboard/analyze', size: const Size(320, 568));
    await tapText(tester, packS('gender.female'));
    await tapText(tester, packS('step1.hormonal_regular'));
    expect(find.text(packS('step1.periodHint')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('küçük telefon (320×568) taşma kontrolü', () {
    for (final loc in ['/', '/auth', '/dashboard', '/dashboard/analyze', '/dashboard/checkin', '/dashboard/chat', '/dashboard/themes', '/dashboard/subscribe']) {
      testWidgets(loc, (tester) async {
        await pumpApp(
          tester,
          location: loc,
          prefs: loc == '/dashboard/analyze' ? const {} : acceptedPrefs(),
          size: const Size(320, 568),
          loggedIn: loc != '/' && loc != '/auth',
        );
        expect(tester.takeException(), isNull);
      });
    }
  });
}
