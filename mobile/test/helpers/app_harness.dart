import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:rebi/core/api.dart';
import 'package:rebi/core/i18n.dart';
import 'package:rebi/core/local_store.dart';
import 'package:rebi/router.dart';
import 'package:rebi/state/auth_controller.dart';
import 'package:rebi/state/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
            return ok({'ok': true, 'log_date': '2026-10-10', 'aggregated': {}});
          case 'POST /legal-consent/accept':
            consentMissing = false;
            return ok({'ok': true, 'accepted_at': '2026-10-10T10:00:00Z'});
        }
        return http.Response('{"detail":"yok"}', 404);
      });
}

User fakeUser({Map<String, dynamic> appMetadata = const {}}) => User(
      id: testUserId,
      appMetadata: appMetadata,
      userMetadata: const {'full_name': 'Ayşe Test'},
      aud: 'authenticated',
      createdAt: '2026-09-01T10:00:00Z',
      email: 'test@rebi.app',
    );

class Harness {
  Harness(this.auth, this.theme, this.router, this.backend);

  final AuthController auth;
  final ThemeController theme;
  final GoRouter router;
  final FakeBackend backend;
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
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

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
      lang: lang,
    );
  });

  final auth = AuthController();
  if (loggedIn) auth.debugSetUser(user ?? fakeUser());
  final theme = ThemeController(auth);
  final router = buildRouter(auth);

  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<I18n>.value(value: I18n.instance),
      ChangeNotifierProvider<AuthController>.value(value: auth),
      ChangeNotifierProvider<ThemeController>.value(value: theme),
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
  return Harness(auth, theme, router, fb);
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
