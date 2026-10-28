import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart' show Checkbox, Key, Size, TextField, TextFormField, TextInputAction;
import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/core/device_location.dart';
import 'package:rebi/core/routine_tracking.dart';
import 'package:rebi/screens/today/today_clock.dart';
import 'package:rebi/ui/tw.dart';

import 'auth_flow_test.dart' show FakeAuth;
import 'helpers/a11y.dart';
import 'helpers/analyze_walk.dart';
import 'helpers/app_harness.dart';
import 'helpers/notification_fakes.dart';

/// Faz G3: erişilebilirlik. Her ana ekran ve durum, açık ve koyu temada Flutter'ın üç kuralından geçer:
/// dokunma hedefi (Android 48 dp, iOS 44 dp), dokunulabilir öğenin okunabilir etiketi ve metin kontrastı (AA).
/// Bir ekran bu testi kırarsa: hedefi büyüt (görünümü değil dokunma alanını), etiket ekle ya da metin için `gray500`/`theme.fg` kullan.
void main() {
  final routine = routineFixture['routine'] as List;

  Map<String, Object> accepted() => {
        trackAcceptedKey(testUserId): '1',
        trackSnapshotKey(testUserId): jsonEncode({
          'routine': routine,
          'userName': 'Ayşe Test',
          'weather': routineFixture['weather'],
          'flowDebug': routineFixture['flow_debug'],
          'activePlan': routineFixture['active_plan'],
          'acceptedAt': DateTime.now().millisecondsSinceEpoch - 3 * 86400000,
        }),
      };

  FakeBackend populated() {
    final b = FakeBackend();
    b.todayPlan = {
      ...b.todayPlan,
      'weather_source': 'live',
      'weather': {'uv_index': 6, 'temperature': 18, 'humidity': 38},
      'has_routine': true,
    };
    b.waterMl = 750;
    b.productsOut = [
      {'product': 'SPF 50', 'step_order': 40, 'finished_at': '2026-10-08T10:00:00+00:00', 'log_date': '2026-10-08', 'days_out': 2},
    ];
    final now = DateTime.now();
    String day(int ago) => DateTime(now.year, now.month, now.day - ago).toIso8601String().substring(0, 10);
    b.history = {
      ...b.history,
      'days': [
        {
          'log_date': day(0),
          'tracking': {'events_count': 4, 'water_ml_total': 1500, 'routine_morning_done': true, 'nutrition': {'junk_food': true}, 'makeup': {'logged': true, 'used': true, 'removed': true}},
          'checkin': {'skin_feeling': 'iyi', 'sleep_hours': 7, 'stress_level': 2, 'risk_score': 1},
        },
        {'log_date': day(2), 'tracking': {'events_count': 2, 'water_ml_total': 900}},
      ],
      'assessments': [
        {'concern': 'acne', 'severity_score': 4, 'created_at': now.toIso8601String()},
      ],
      'synced': true,
    };
    return b;
  }

  Future<void> ask(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await settle(tester);
  }

  /// Bugün ekranı günün saatine göre değişir (şimdi kartı, akşam rutini, gün akışı); sonuç saate bağlı olmasın diye saat sabitlenir.
  void clockAt(int hour, [int minute = 0]) {
    final d = DateTime.now();
    todayPanelClock = () => DateTime(d.year, d.month, d.day, hour, minute);
  }

  tearDown(() => todayPanelClock = DateTime.now);

  final scenarios = <(String, Future<void> Function(WidgetTester))>[
    ('Bugün', (t) {
      clockAt(9, 15);
      return pumpApp(t, location: '/dashboard', prefs: accepted(), backend: populated());
    }),
    ('Bugün · öğleden sonra', (t) {
      clockAt(14, 30);
      return pumpApp(t, location: '/dashboard', prefs: accepted(), backend: populated());
    }),
    ('Bugün · akşam', (t) {
      clockAt(21, 0);
      return pumpApp(t, location: '/dashboard', prefs: accepted(), backend: populated());
    }),
    ('Bugün · konum ve bildirim önerisi', (t) async {
      clockAt(9, 15);
      setLocationAccess(read: () async => LocationAccess.askable);
      addTearDown(resetLocationAccess);
      final b = populated();
      b.snapshot = {
        ...b.snapshot,
        'consent': {...(b.snapshot['consent'] as Map).cast<String, dynamic>(), 'location_processing_allowed': true},
      };
      await pumpApp(t, location: '/dashboard', prefs: accepted(), backend: b, notifier: FakeReminderNotifier());
    }),
    ('Bugün · su sayfası', (t) async {
      clockAt(9, 15);
      await pumpApp(t, location: '/dashboard', prefs: accepted(), backend: populated());
      await tapText(t, tr('mobileToday.actions.waterMore'));
    }),
    ('Bugün · makyaj temizleme sayfası', (t) async {
      clockAt(9, 15);
      await pumpApp(t, location: '/dashboard', prefs: accepted(), backend: populated());
      await tapText(t, tr('mobileToday.actions.yes'));
      await tapText(t, tr('mobileToday.actions.removed'));
    }),
    ('Bugün · ürün bitti sayfası', (t) async {
      clockAt(9, 15);
      await pumpApp(t, location: '/dashboard', prefs: accepted(), backend: populated());
      await tapText(t, tr('mobileToday.productFinished'));
    }),
    ('Rutin', (t) => pumpApp(t, location: '/dashboard/routine', prefs: accepted(), backend: populated())),
    ('Rutin · açık adım ayrıntısı', (t) async {
      await pumpApp(t, location: '/dashboard/routine', prefs: accepted(), backend: populated());
      await tapFinder(t, find.text(tr('dashboard.whySkincareButton')).first);
    }),
    ('Sohbet · boş', (t) => pumpApp(t, location: '/dashboard/chat', prefs: accepted(), backend: populated())),
    ('Sohbet · konuşma', (t) async {
      await pumpApp(t, location: '/dashboard/chat', prefs: accepted(), backend: populated()..chatReply = 'Yanıt:\n• Birinci madde\n• İkinci madde');
      await ask(t, 'Merhaba');
    }),
    ('Sohbet · hata kartı', (t) async {
      await pumpApp(t, location: '/dashboard/chat', prefs: accepted(), backend: populated()..chatFailTimes = 1);
      await ask(t, 'Merhaba');
    }),
    ('Sohbet · limit kartı', (t) async {
      await pumpApp(t, location: '/dashboard/chat', prefs: accepted(), backend: populated()..quotaAfter = 0);
      await ask(t, 'Merhaba');
    }),
    ('Geçmiş', (t) => pumpApp(t, location: '/dashboard/history', prefs: accepted(), backend: populated())),
    ('Ben', (t) => pumpApp(t, location: '/dashboard/profile', prefs: accepted(), backend: populated())),
    ('Hatırlatıcılar', (t) async {
      final h = await pumpApp(t, location: '/dashboard/reminders', prefs: accepted(), backend: populated(), notifier: FakeReminderNotifier());
      unawaited(h.notifications.enable());
      await settle(t);
    }),
    ('Hatırlatıcılar · saat sayfası', (t) async {
      await pumpApp(t, location: '/dashboard/reminders', prefs: accepted(), backend: populated());
      await tapText(t, tr('mobileReminders.categories.routine.title'));
    }),
    ('Rafım', (t) => pumpApp(t, location: '/dashboard/shelf', prefs: accepted(), backend: populated())),
    ('Temalar', (t) => pumpApp(t, location: '/dashboard/themes', prefs: accepted(), backend: populated())),
    ('Check-in', (t) => pumpApp(t, location: '/dashboard/checkin', prefs: accepted(), backend: populated())),
    ('Abonelik', (t) => pumpApp(t, location: '/dashboard/subscribe', prefs: accepted(), backend: populated())),
    ('Analiz · hazır', (t) => pumpApp(t, location: '/dashboard/analyze', prefs: accepted(), backend: populated())),
    ('Analiz · karşılama', (t) => pumpApp(t, location: '/dashboard/analyze', backend: FakeBackend())),
    ('Analiz · ad ve yaş', (t) async {
      await pumpApp(t, location: '/dashboard/analyze');
      await analyzeWalkTo(t, 'basics');
    }),
    ('Analiz · cilt tipi (tek seçim)', (t) async {
      await pumpApp(t, location: '/dashboard/analyze');
      await analyzeWalkTo(t, 'skinType');
    }),
    ('Analiz · sorunlar (çoklu seçim)', (t) async {
      await pumpApp(t, location: '/dashboard/analyze');
      await analyzeWalkTo(t, 'concerns');
    }),
    ('Analiz · şiddet sorusu', (t) async {
      await pumpApp(t, location: '/dashboard/analyze');
      await analyzeWalkTo(t, 'severity');
    }),
    ('Analiz · su ve uyku', (t) async {
      await pumpApp(t, location: '/dashboard/analyze');
      await analyzeWalkTo(t, 'waterSleep');
    }),
    ('Analiz · stres testi daveti', (t) async {
      await pumpApp(t, location: '/dashboard/analyze');
      await analyzeWalkTo(t, 'stressIntro');
    }),
    ('Analiz · sigara', (t) async {
      await pumpApp(t, location: '/dashboard/analyze');
      await analyzeWalkTo(t, 'smoking');
    }),
    ('Analiz · tıraş (erkek)', (t) async {
      await pumpApp(t, location: '/dashboard/analyze');
      await analyzeWalkTo(t, 'shaving');
    }),
    ('Analiz · ürün tepkileri', (t) async {
      await pumpApp(t, location: '/dashboard/analyze');
      await analyzeWalkTo(t, 'tolerance');
    }),
    ('Analiz · fotoğraf', (t) async {
      await pumpApp(t, location: '/dashboard/analyze');
      await analyzeWalkTo(t, 'photo');
    }),
    ('Analiz · özet', (t) async {
      await pumpApp(t, location: '/dashboard/analyze');
      await analyzeWalkTo(t, 'summary');
    }),
    ('Giriş', (t) => pumpApp(t, location: '/auth', loggedIn: false)),
    ('Giriş · e-posta kodu', (t) async {
      await pumpApp(t, location: '/auth?mode=signup', loggedIn: false, authController: FakeAuth());
      await t.enterText(find.byType(TextFormField).at(0), 'Ayşe Test');
      await t.enterText(find.byType(TextFormField).at(1), 'ayse@ornek.com');
      await t.enterText(find.byType(TextFormField).at(2), 'parola123');
      await settle(t, 4);
      await tapFinder(t, find.byType(Checkbox).at(0));
      await tapFinder(t, find.byType(Checkbox).at(1));
      await tapFinder(t, find.byKey(const Key('auth-submit')).first);
    }),
    ('Açılış', (t) => pumpApp(t, location: '/', loggedIn: false)),
    ('KVKK metni', (t) => pumpApp(t, location: '/kvkk', loggedIn: false)),
  ];

  for (final dark in [false, true]) {
    for (final (name, setup) in scenarios) {
      testWidgets('$name · ${dark ? 'koyu' : 'açık'}', (tester) async {
        Tw.dark = dark;
        addTearDown(() => Tw.dark = false);
        final handle = tester.ensureSemantics();
        List<String> findings;
        try {
          await setup(tester);
          // Uzun listeler tembel çizilir: tüm öğelerin anlamsal düğümü olsun diye ekranı yükselt.
          tester.view.physicalSize = const Size(390, 3600) * 3;
          await tester.pump(const Duration(milliseconds: 200));
          findings = await a11yFindings(tester);
        } finally {
          handle.dispose();
        }
        expect(findings, isEmpty, reason: findings.join('\n'));
      });
    }
  }
}
