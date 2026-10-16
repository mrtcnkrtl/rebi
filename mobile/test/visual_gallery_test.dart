import 'dart:convert';
import 'dart:io';

import 'package:flutter/painting.dart' show debugDisableShadows;
import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/core/routine_tracking.dart';
import 'package:rebi/screens/today/today_clock.dart';
import 'package:rebi/ui/tw.dart';

import 'helpers/app_harness.dart';
import 'helpers/visual.dart';

/// Ana ekranların açık/koyu görünümü, gerçek yazı tipleriyle `build/screenshots/` altına yazılır.
/// Yalnızca `REBI_SCREENSHOTS=1` ile çalışır (bkz. `helpers/visual.dart`); verisi API sözleşmesindeki
/// gerçek örnek yanıtlardan gelir, böylece ekranlar dolu ve gerçekçi görünür.
Map<String, dynamic> _contract(String name) =>
    (jsonDecode(File('../contract/$name.json').readAsStringSync()) as Map).cast<String, dynamic>();

void main() {
  final routine = routineFixture['routine'] as List;

  Map<String, Object> acceptedPrefs() => {
        trackAcceptedKey(testUserId): '1',
        trackSnapshotKey(testUserId): jsonEncode({
          'routine': routine,
          'userName': 'Ayşe',
          'weather': routineFixture['weather'],
          'flowDebug': routineFixture['flow_debug'],
          'acceptedAt': DateTime.now().millisecondsSinceEpoch - 3 * 86400000,
        }),
      };

  FakeBackend populated() {
    final b = FakeBackend();
    final plan = _contract('today_plan');
    b.todayPlan = {...plan, 'user_id': testUserId, 'log_date': '2026-10-10', 'routine': routine, 'has_routine': true};
    b.waterMl = 750;
    b.snapshot = {
      ...b.snapshot,
      'has_routine': true,
      'routine': routine,
      'profile': {'full_name': 'Ayşe Yılmaz', 'skin_type': 'oily', 'age': 29, 'gender': 'female', 'city': 'İstanbul'},
    };
    b.profile = {'full_name': 'Ayşe Yılmaz', 'skin_type': 'oily', 'age': 29, 'gender': 'female', 'city': 'İstanbul'};
    b.history = {...b.history, ..._contract('me_history'), 'user_id': testUserId};
    return b;
  }

  setUpAll(() async {
    if (screenshotsEnabled) await loadBrandFonts();
  });
  setUp(() => todayPanelClock = () => DateTime(2026, 10, 10, 9, 15));
  tearDown(() {
    todayPanelClock = DateTime.now;
    Tw.dark = false;
  });

  const screens = <(String, String, bool)>[
    ('bugun', '/dashboard', true),
    ('rutin', '/dashboard/routine', true),
    ('sohbet', '/dashboard/chat', true),
    ('gecmis', '/dashboard/history', true),
    ('ben', '/dashboard/profile', true),
    ('gorunum', '/dashboard/themes', true),
    ('hatirlaticilar', '/dashboard/reminders', true),
    ('checkin', '/dashboard/checkin', true),
    ('karsilama', '/', false),
    ('giris', '/auth', false),
  ];

  for (final dark in [false, true]) {
    for (final (name, path, signedIn) in screens) {
      testWidgets('${dark ? 'koyu' : 'acik'} · $name', (tester) async {
        Tw.dark = dark;
        // flutter_test gölgeleri bulanıksız, düz çizer; cihazda öyle değildir. Test bitmeden eski haline döner
        // (çerçeve, test sonunda bu değişkenin değişmemiş olmasını şart koşar).
        debugDisableShadows = false;
        try {
          await pumpApp(
            tester,
            location: path,
            loggedIn: signedIn,
            prefs: acceptedPrefs(),
            backend: populated(),
            realFonts: true,
          );
          await shoot(tester, '${dark ? 'koyu' : 'acik'}-$name');
        } finally {
          debugDisableShadows = true;
        }
      }, skip: !screenshotsEnabled);
    }
  }

  // Bugün ekranının alt sayfaları (açık + koyu).
  final sheets = <(String, String)>[
    ('su', 'mobileToday.actions.waterMore'),
    ('temizleme', 'mobileToday.actions.removed'),
    ('beslenme', 'mobileToday.actions.edit'),
    ('urun-bitti', 'mobileToday.productFinished'),
  ];
  for (final dark in [false, true]) {
    for (final (name, key) in sheets) {
      testWidgets('${dark ? 'koyu' : 'acik'} · sayfa $name', (tester) async {
        Tw.dark = dark;
        debugDisableShadows = false;
        try {
          await pumpApp(
            tester,
            location: '/dashboard',
            prefs: acceptedPrefs(),
            backend: populated(),
            realFonts: true,
          );
          await tapText(tester, tr(key));
          await shoot(tester, '${dark ? 'koyu' : 'acik'}-sayfa-$name');
        } finally {
          debugDisableShadows = true;
        }
      }, skip: !screenshotsEnabled);
    }
  }
}
