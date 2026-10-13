import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:rebi/core/api.dart';
import 'package:rebi/core/consent_recovery.dart';
import 'package:rebi/core/event_outbox.dart';
import 'package:rebi/core/notification_ports.dart';
import 'package:rebi/core/i18n.dart';
import 'package:rebi/core/local_store.dart';
import 'package:rebi/router.dart';
import 'package:rebi/state/auth_controller.dart';
import 'package:rebi/state/home_sync_controller.dart';
import 'package:rebi/state/notifications_controller.dart';
import 'package:rebi/state/outbox_sync_controller.dart';
import 'package:rebi/state/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notification_fakes.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

const testUserId = '7c1e2d3a-0000-4000-8000-00000000abcd';

Map<String, dynamic> _json(String path) => (jsonDecode(File(path).readAsStringSync()) as Map).cast<String, dynamic>();

final Map<String, dynamic> routineFixture = _json('test/fixtures/generate_routine_response.json');

/// Backend'e giden istekleri kaydeden sahte istemci.
class FakeBackend {
  final List<http.Request> requests = [];
  int chatCalls = 0;
  int quotaAfter = 999;

  /// true: yapay zekâ uçları rıza kaydı yokmuş gibi 403 döner.
  bool consentMissing = false;
  Map<String, dynamic> checkinStatus = {'already_checked_in': false, 'log_date': '2026-10-10'};

  /// `GET /me/snapshot` yanıtı; testler istediği alanı değiştirir.
  Map<String, dynamic> snapshot = {
    'user_id': testUserId,
    'server_time': '2026-10-10T10:00:00Z',
    'log_date': '2026-10-10',
    'profile': <String, dynamic>{},
    'has_routine': false,
    'routine': <dynamic>[],
    'routine_created_at': null,
    'progress': <String, dynamic>{},
    'checkin_done': false,
    'chat_cursor': null,
    'consent': {
      'legal_version': 'v2',
      'legal_accepted': true,
      'ai_processing_allowed': true,
      'location_processing_allowed': false,
      'photo_processing_allowed': false,
    },
    'plus': false,
    'synced': true,
  };

  /// `GET /today/plan` yanıtı; su toplamı `waterMl` ile birlikte güncel tutulur.
  Map<String, dynamic> todayPlan = {
    'user_id': testUserId,
    'log_date': '2026-10-10',
    'has_routine': false,
    'routine': <dynamic>[],
    'weather': {'uv_index': 3, 'humidity': 50, 'temperature': 20},
    'weather_source': 'default',
    'environment_advice': <dynamic>[],
    'reminders': <dynamic>[],
    'progress': <String, dynamic>{},
    'checkin_done': false,
  };

  /// `GET /me/reminder-settings` içeriği; `PUT` gelen alanları buna işler.
  Map<String, dynamic> reminderSettings = {
    'wake_time': '07:30',
    'sleep_time': '23:00',
    'water_every_minutes': 120,
    'enabled': {
      for (final c in const ['routine', 'water', 'makeup', 'nutrition', 'spf', 'lip_balm', 'checkin']) c: true,
    },
  };

  /// Hatırlatıcı ayarı okuma hata döndürsün.
  bool reminderSettingsFails = false;

  /// Doluysa `PUT /me/reminder-settings` bu durum koduyla (ve `reminderSettingsPutDetail` ile) yanıtlanır.
  int? reminderSettingsPutStatus;
  String reminderSettingsPutDetail = 'Geçersiz değer.';

  /// Açılış paketi isteği hata (ör. çevrimdışı sunucu) döndürsün.
  bool snapshotFails = false;

  /// Günün planı isteği hata döndürsün.
  bool planFails = false;

  /// Sunucudaki bugünkü su toplamı; `water_intake` kayıtlarıyla artar.
  int waterMl = 0;

  /// `POST /devices/register` yanıtındaki `push_configured` (sunucuda FCM açık mı).
  bool pushConfigured = false;

  /// Cihaz kaydı uçlarına ağ yokmuş gibi davranır.
  bool devicesOffline = false;

  /// `GET /me/profile` içeriği; `PATCH` gelen alanları buna işler.
  Map<String, dynamic> profile = {
    'full_name': 'Ayşe Test',
    'skin_type': 'dry',
    'age': 29,
    'gender': 'female',
    'city': 'İstanbul',
    'updated_at': '2026-10-01T10:00:00Z',
  };

  /// Profil yanıtlarındaki `synced` (false: kullanıcı verisi sunucuda tutulmuyor).
  bool profileSynced = true;

  /// `GET /me/profile` hata döndürsün.
  bool profileFails = false;

  /// Profil uçlarına ağ yokmuş gibi davranır (bağlantı hatası fırlatır).
  bool profileOffline = false;

  /// Doluysa `PATCH /me/profile` bu durum koduyla (ve `profilePatchDetail` ile) yanıtlanır.
  int? profilePatchStatus;
  String profilePatchDetail = 'Geçersiz değer.';

  /// `GET /me/history` içeriği.
  Map<String, dynamic> history = {
    'user_id': testUserId,
    'from_date': '2026-09-11',
    'to_date': '2026-10-10',
    'days': <dynamic>[],
    'assessments': <dynamic>[],
    'synced': true,
  };

  /// `GET /me/history` hata döndürsün.
  bool historyFails = false;

  /// Gün içi kayıt uçlarına ağ yokmuş gibi davranır (istek atılır, bağlantı hatası döner).
  bool ingestOffline = false;

  /// Doluysa gün içi kayıt bu durum koduyla yanıtlanır (ör. 500 geçici, 422 kalıcı hata).
  int? ingestStatus;

  /// Sunucuya yazılan olayların `client_event_id` değerleri (tekrar gelenler yazılmaz).
  final Set<String> storedEventIds = {};

  /// Sunucuya yazılan olaylar (tip + yük); ilerleme bunlardan hesaplanır.
  final List<Map<String, dynamic>> storedEvents = [];

  /// Sunucudaki `_aggregate_daily_events` özeti: `todayPlan['progress']` başlangıç durumudur,
  /// yazılan olaylar üstüne işlenir.
  Map<String, dynamic> get progress {
    final base = (todayPlan['progress'] as Map).cast<String, dynamic>();
    final out = <String, dynamic>{...base, 'water_ml_total': waterMl};
    final steps = <String, Set<int>>{
      'morning': {...?(((base['routine_steps'] as Map?)?['morning']) as List?)?.cast<int>()},
      'evening': {...?(((base['routine_steps'] as Map?)?['evening']) as List?)?.cast<int>()},
    };
    var nutrition = <String, dynamic>{...?(base['nutrition'] as Map?)?.cast<String, dynamic>()};
    var nutritionLogged = base['nutrition_logged'] == true;
    var spf = (base['spf_refreshes'] as num?)?.toInt() ?? 0;
    final makeup = <String, dynamic>{...?(base['makeup'] as Map?)?.cast<String, dynamic>()};
    final finished = <Map<String, dynamic>>[...?(base['products_finished'] as List?)?.cast<Map<String, dynamic>>()];
    for (final e in storedEvents) {
      final p = (e['payload'] as Map).cast<String, dynamic>();
      switch (e['type']) {
        case 'routine_step':
          final block = '${p['block']}';
          if (steps.containsKey(block) && p['step_order'] is num) {
            final step = (p['step_order'] as num).toInt();
            p['done'] == true ? steps[block]!.add(step) : steps[block]!.remove(step);
          }
        case 'routine_completed_block':
          if (p.containsKey('morning')) out['routine_morning_done'] = p['morning'] == true;
          if (p.containsKey('evening')) out['routine_evening_done'] = p['evening'] == true;
        case 'spf_refresh':
          spf++;
        case 'nutrition':
          nutritionLogged = true;
          nutrition = {...nutrition, ...p};
        case 'makeup':
          makeup['logged'] = true;
          if (p['used'] != null) makeup['used'] = p['used'] == true;
          if (p['removed'] == true) {
            makeup['used'] = true;
            makeup['removed'] = true;
          }
          final method = '${p['method'] ?? ''}';
          if (const {'double', 'cleanser', 'water', 'wipe', 'none'}.contains(method)) {
            makeup['removal_method'] = method;
            if (method != 'none') {
              makeup['used'] = true;
              makeup['removed'] = true;
            }
          }
        case 'product_finished':
          finished.add({'product': p['product'], 'step_order': p['step_order']});
      }
    }
    return {
      ...out,
      'routine_steps': {for (final b in steps.keys) b: (steps[b]!.toList()..sort())},
      'nutrition': nutrition,
      'nutrition_logged': nutritionLogged,
      'spf_refreshes': spf,
      if (makeup.isNotEmpty) 'makeup': makeup,
      'products_finished': finished,
    };
  }

  /// API tabanındaki `/api` öneki atılır (varsayılan taban canlı adres: `…/api`).
  static String pathOf(http.BaseRequest r) => r.url.path.replaceFirst(RegExp('^/api'), '');

  Map<String, dynamic> bodyOf(String path) =>
      (jsonDecode(requests.lastWhere((r) => pathOf(r) == path).body) as Map).cast<String, dynamic>();

  List<http.Request> calls(String path) => requests.where((r) => pathOf(r) == path).toList();

  MockClient get client => MockClient((req) async {
        requests.add(req);
        http.Response ok(Object body) =>
            http.Response.bytes(utf8.encode(jsonEncode(body)), 200, headers: {'content-type': 'application/json'});
        switch ('${req.method} ${pathOf(req)}') {
          case 'GET /me/profile':
            if (profileOffline) throw const SocketException('çevrimdışı');
            if (profileFails) return http.Response('{"detail":"hata"}', 502);
            return ok({'user_id': testUserId, ...profile, 'synced': profileSynced});
          case 'PATCH /me/profile':
            if (profileOffline) throw const SocketException('çevrimdışı');
            if (profilePatchStatus != null) {
              return http.Response.bytes(utf8.encode(jsonEncode({'detail': profilePatchDetail})), profilePatchStatus!,
                  headers: {'content-type': 'application/json'});
            }
            final patch = (jsonDecode(req.body) as Map).cast<String, dynamic>()..remove('user_id');
            profile = {...profile, ...patch};
            return ok({'user_id': testUserId, ...profile, 'synced': profileSynced});
          case 'GET /me/reminder-settings':
            if (reminderSettingsFails) return http.Response('{"detail":"hata"}', 502);
            return ok({'user_id': testUserId, 'settings': reminderSettings, 'synced': true});
          case 'PUT /me/reminder-settings':
            if (reminderSettingsPutStatus != null) {
              return http.Response.bytes(utf8.encode(jsonEncode({'detail': reminderSettingsPutDetail})),
                  reminderSettingsPutStatus!, headers: {'content-type': 'application/json'});
            }
            final put = (jsonDecode(req.body) as Map).cast<String, dynamic>()..remove('user_id');
            reminderSettings = {
              ...reminderSettings,
              ...put,
              'enabled': {
                ...(reminderSettings['enabled'] as Map).cast<String, dynamic>(),
                ...((put['enabled'] as Map?)?.cast<String, dynamic>() ?? const {}),
              },
            };
            return ok({'user_id': testUserId, 'settings': reminderSettings, 'synced': true});
          case 'GET /me/history':
            if (historyFails) return http.Response('{"detail":"hata"}', 502);
            return ok(history);
          case 'POST /devices/register':
            if (devicesOffline) throw const SocketException('çevrimdışı');
            return ok({'ok': true, 'push_configured': pushConfigured, 'synced': true});
          case 'DELETE /devices/register':
            if (devicesOffline) throw const SocketException('çevrimdışı');
            return ok({'ok': true});
          case 'GET /me/snapshot':
            if (snapshotFails) return http.Response('{"detail":"hata"}', 502);
            return ok(snapshot);
          case 'GET /today/plan':
            if (planFails) return http.Response('{"detail":"hata"}', 502);
            return ok({'reminder_settings': reminderSettings, ...todayPlan, 'progress': progress});
          case 'GET /chat_usage':
            return ok({'kind': 'free_daily', 'remaining': 4, 'limit': 5, 'period': 'day'});
          case 'GET /chat/history':
            return ok({'messages': [], 'cursor': null});
          case 'POST /chat_general':
            if (consentMissing) {
              return http.Response.bytes(utf8.encode(jsonEncode({'detail': 'AI işleme izni gerekli'})), 403,
                  headers: {'content-type': 'application/json'});
            }
            chatCalls++;
            if (chatCalls > quotaAfter) {
              return ok({
                'reply': 'Bugünkü ücretsiz Rebi AI mesaj hakkın doldu.',
                'chat_quota_exceeded': true,
                'usage_kind': 'free_daily',
                'usage_remaining': 0,
                'usage_limit': 5,
              });
            }
            return ok({
              'reply': 'Niasinamid bariyeri destekler.\nGünde 1-2 kez kullanılabilir.',
              'chat_quota_exceeded': false,
              'usage_kind': 'free_daily',
              'usage_remaining': 3,
              'usage_limit': 5,
            });
          case 'POST /generate_routine':
            return ok(routineFixture);
          case 'GET /daily_checkin/status':
            return ok(checkinStatus);
          case 'POST /daily_checkin':
            return ok({
              'risk_level': 'orta',
              'adaptation_type': 'major',
              'ai_note': 'Bugün bariyeri dinlendir.',
              'changes': [
                {'item': 'BHA tonik', 'old': 'Haftada 2', 'new': 'Ara ver', 'reason': 'İrritasyon bildirdin.'},
              ],
              'today_routine': routineFixture['routine'],
            });
          case 'POST /daily_tracking/ingest':
            if (ingestOffline) throw const SocketException('çevrimdışı');
            if (ingestStatus != null) return http.Response('{"detail":"hata"}', ingestStatus!);
            final sent = (jsonDecode(req.body) as Map).cast<String, dynamic>();
            // Sunucu aynı client_event_id'yi ikinci kez yazmaz (docs/MOBIL-API.md).
            final fresh = storedEventIds.add('${sent['client_event_id']}');
            if (fresh) {
              final payload = (sent['payload'] as Map).cast<String, dynamic>();
              if (sent['type'] == 'water_intake') waterMl = math.max(0, waterMl + (payload['ml'] as num).toInt());
              storedEvents.add({'type': sent['type'], 'payload': payload});
            }
            return ok({'ok': true, 'log_date': '2026-10-10', 'aggregated': progress});
          case 'POST /legal-consent/accept':
            consentMissing = false;
            return ok({'ok': true, 'accepted_at': '2026-10-10T10:00:00Z'});
        }
        return http.Response('{"detail":"yok"}', 404);
      });
}

/// Birim testlerinde (widget çizmeden) çeviri sözlüklerini yükler.
void loadTestI18n([String lang = 'tr']) {
  Map<String, Map<String, dynamic>> read(String dir, String name, List<String> langs) =>
      {for (final l in langs) l: _json('assets/$dir/$l/$name.json')};
  I18n.instance.debugLoad(
    common: read('locales', 'common', ['tr', 'en']),
    analyzeWizard: read('locales', 'analyzeWizard', ['tr', 'en']),
    mobile: read('mobile_locales', 'mobile', ['tr', 'en']),
    lang: lang,
  );
}

/// Tek bir bileşeni (Supabase gerektiren tam ekran olmadan) kullanıcı oturumu, çeviriler ve
/// sahte sunucuyla çizer.
Future<FakeBackend> pumpStandalone(
  WidgetTester tester,
  Widget Function(RebiTheme theme) build, {
  FakeBackend? backend,
  String lang = 'tr',
  Size size = const Size(390, 844),
  Map<String, Object> prefs = const {},
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({'rebi-lang': lang, ...prefs});
  await tester.runAsync(() async {
    await LocalStore.init();
    await initializeDateFormatting();
  });
  loadTestI18n(lang);
  final fb = backend ?? FakeBackend();
  apiHttpClient = fb.client;
  final auth = AuthController()..debugSetUser(fakeUser());
  addTearDown(auth.dispose);
  final theme = ThemeController(auth);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<I18n>.value(value: I18n.instance),
      ChangeNotifierProvider<AuthController>.value(value: auth),
      ChangeNotifierProvider<ThemeController>.value(value: theme),
    ],
    child: MaterialApp(
      locale: Locale(lang),
      supportedLocales: [for (final l in supportedLangs) Locale(l)],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Scaffold(body: SingleChildScrollView(child: build(theme.theme))),
    ),
  ));
  await settle(tester);
  return fb;
}

User fakeUser({Map<String, dynamic> appMetadata = const {}, String id = testUserId}) => User(
      id: id,
      appMetadata: appMetadata,
      userMetadata: const {'full_name': 'Ayşe Test'},
      aud: 'authenticated',
      createdAt: '2026-09-01T10:00:00Z',
      email: 'test@rebi.app',
    );

class Harness {
  Harness(this.auth, this.theme, this.router, this.backend, this.sync, this.outbox, this.notifications, this.notifier);

  final AuthController auth;
  final ThemeController theme;
  final GoRouter router;
  final FakeBackend backend;
  final HomeSyncController sync;
  final OutboxSyncController outbox;
  final NotificationsController notifications;
  final FakeReminderNotifier notifier;
}

/// Uygulamanın gerçek yönlendirme + kabuk + ekranlarını telefon boyutunda (390×844) kurar.
Future<Harness> pumpApp(
  WidgetTester tester, {
  required String location,
  Object? extra,
  bool loggedIn = true,
  User? user,
  Map<String, Object> prefs = const {},
  bool acknowledgeAi = true,
  String lang = 'tr',
  FakeBackend? backend,
  FakeReminderNotifier? notifier,
  PushClient? push,
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  resetConsentRecovery();
  EventOutbox.instance.debugReset();
  SharedPreferences.setMockInitialValues({
    if (acknowledgeAi) 'rebi-ai-disclaimer-ack-v1': '1',
    'rebi-lang': lang,
    ...prefs,
  });
  final fb = backend ?? FakeBackend();
  apiHttpClient = fb.client;
  await tester.runAsync(() async {
    await LocalStore.init();
    await initializeDateFormatting();
    Map<String, Map<String, dynamic>> ns(String name) => {
          for (final l in supportedLangs) l: _json('assets/locales/$l/$name.json'),
        };
    I18n.instance.debugLoad(
      common: ns('common'),
      analyzeWizard: ns('analyzeWizard'),
      severityTests: ns('severityTests'),
      mobile: {
        for (final l in const ['tr', 'en']) l: _json('assets/mobile_locales/$l/mobile.json'),
      },
      lang: lang,
    );
  });

  final auth = AuthController();
  if (loggedIn) auth.debugSetUser(user ?? fakeUser());
  final theme = ThemeController(auth);
  final sync = HomeSyncController(auth);
  addTearDown(sync.dispose);
  final outbox = OutboxSyncController(auth, retryDelays: const []);
  addTearDown(outbox.dispose);
  // Varsayılan: bildirimler bu platformda desteklenmiyor (öneri kartı çıkmaz); ilgili testler destekli sahte verir.
  final fakeNotifier = notifier ?? FakeReminderNotifier(supported: false);
  final notifications = NotificationsController(
    auth,
    notifier: fakeNotifier,
    push: push ?? const NoPushClient(),
    platform: () => 'android',
  );
  addTearDown(notifications.dispose);
  final router = buildRouter(auth);

  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<I18n>.value(value: I18n.instance),
      ChangeNotifierProvider<AuthController>.value(value: auth),
      ChangeNotifierProvider<ThemeController>.value(value: theme),
      ChangeNotifierProvider<HomeSyncController>.value(value: sync),
      ChangeNotifierProvider<OutboxSyncController>.value(value: outbox),
      ChangeNotifierProvider<NotificationsController>.value(value: notifications),
    ],
    child: Consumer<I18n>(
      builder: (context, i18n, _) => MaterialApp.router(
        routerConfig: router,
        locale: Locale(i18n.lang),
        supportedLocales: [for (final l in supportedLangs) Locale(l)],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ThemeData(useMaterial3: true),
      ),
    ),
  ));
  router.go(location, extra: extra);
  await settle(tester);
  return Harness(auth, theme, router, fb, sync, outbox, notifications, fakeNotifier);
}

/// Sonsuz animasyonlar (landing) yüzünden `pumpAndSettle` yerine sabit kare ilerletir.
Future<void> settle(WidgetTester tester, [int frames = 12]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  // Ağ yanıtları gerçek zamanlı Future; kısa bekleyip tekrar çiz.
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Kaydırılabilir alanda bir metni görünür kılıp dokunur.
Future<void> tapText(WidgetTester tester, String text, {bool exact = true}) async {
  final f = exact ? find.text(text) : find.textContaining(text);
  expect(f, findsWidgets, reason: '"$text" bulunamadı');
  await tester.ensureVisible(f.first);
  await tester.pump();
  await tester.tap(f.first, warnIfMissed: false);
  await settle(tester, 4);
}

String tr(String key, [Map<String, Object?> vars = const {}]) => I18n.instance.t(key, vars);

Map<String, dynamic> pack(String path) {
  final v = Pack(I18n.instance.analyzeWizardPack).raw(path);
  return v is Map ? v.cast<String, dynamic>() : {};
}

String packS(String path) => Pack(I18n.instance.analyzeWizardPack).s(path);

List<Map> severityQuestions(String concern) =>
    ((I18n.instance.severityTestsPack[concern] as Map)['questions'] as List).cast<Map>();

/// Bulucuyu görünür kılıp dokunur (kaydırılabilir formlarda ekran dışı dokunuşları önler).
Future<void> tapFinder(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await settle(tester, 3);
}
