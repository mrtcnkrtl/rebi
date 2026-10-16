import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' show Size;
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
    // Rafım: rutindeki güneş kremi bitti, bir de rutin dışı ürün.
    b.productsOut = [
      {'product': 'SPF 30+ (mat bitişli, yağsız SPF)', 'step_order': 40, 'finished_at': '2026-10-08T10:00:00+00:00', 'log_date': '2026-10-08', 'days_out': 2},
      {'product': 'Gece kremi', 'step_order': null, 'finished_at': '2026-10-02T10:00:00+00:00', 'log_date': '2026-10-02', 'days_out': 8},
    ];
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
    ('rafim', '/dashboard/shelf', true),
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

  // Bugün'ün tamamı (kaydırmadan): yüksek bir ekranla tek görüntüde.
  for (final dark in [false, true]) {
    testWidgets('${dark ? 'koyu' : 'acik'} · bugun-uzun', (tester) async {
      Tw.dark = dark;
      debugDisableShadows = false;
      try {
        await pumpApp(
          tester,
          location: '/dashboard',
          prefs: acceptedPrefs(),
          backend: populated(),
          realFonts: true,
          size: const Size(390, 3100),
        );
        await shoot(tester, '${dark ? 'koyu' : 'acik'}-bugun-uzun', width: 585);
      } finally {
        debugDisableShadows = true;
      }
    }, skip: !screenshotsEnabled);
  }

  // Bugün'ün durumları (açık): tamamlanmış gün, yüklenemedi, yükleniyor, boş rutin.
  final states = <(String, FakeBackend Function(), bool)>[
    (
      'tamam',
      () {
        final b = populated();
        b.todayPlan = {
          ...b.todayPlan,
          'progress': {
            ...(b.todayPlan['progress'] as Map).cast<String, dynamic>(),
            'routine_morning_done': true,
            'nutrition': {'junk_food': false},
            'nutrition_logged': true,
            'makeup': {'logged': true, 'used': true, 'removed': true, 'removal_method': 'double'},
          },
          'checkin_done': true,
        };
        b.waterMl = 2300;
        return b;
      },
      false,
    ),
    ('hata', () => populated()..planFails = true, false),
    ('yukleniyor', () => populated()..planGate = Completer<void>(), false),
    (
      'bos',
      () {
        final b = populated();
        b.snapshot = {...b.snapshot, 'has_routine': false, 'routine': <dynamic>[]};
        b.todayPlan = {...b.todayPlan, 'has_routine': false, 'routine': <dynamic>[]};
        return b;
      },
      true,
    ),
  ];
  for (final (name, make, noRoutinePrefs) in states) {
    testWidgets('acik · bugun-$name', (tester) async {
      Tw.dark = false;
      debugDisableShadows = false;
      try {
        final backend = make();
        await pumpApp(
          tester,
          location: '/dashboard',
          prefs: noRoutinePrefs ? const {} : acceptedPrefs(),
          backend: backend,
          realFonts: true,
          size: const Size(390, 1700),
        );
        await shoot(tester, 'acik-bugun-$name', width: 585);
        // Yükleniyor durumunda bekleyen istek bırakılmasın (20 sn'lik zaman aşımı sayacı açık kalır).
        backend.planGate?.complete();
        await settle(tester);
      } finally {
        debugDisableShadows = true;
      }
    }, skip: !screenshotsEnabled);
  }
}
