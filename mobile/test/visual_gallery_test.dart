import 'dart:async';

import 'package:flutter/material.dart' show Size, TextField, TextInputAction;
import 'package:flutter/painting.dart' show debugDisableShadows;
import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/core/device_location.dart';
import 'package:rebi/screens/profile_screen.dart' show debugAccountAvailable;
import 'package:rebi/screens/today/today_clock.dart';
import 'package:rebi/ui/tw.dart';

import 'helpers/app_harness.dart';
import 'helpers/demo_data.dart';
import 'helpers/notification_fakes.dart';
import 'helpers/visual.dart';

/// Ana ekranların açık/koyu görünümü, gerçek yazı tipleriyle `build/screenshots/` altına yazılır.
/// Yalnızca `REBI_SCREENSHOTS=1` ile çalışır (bkz. `helpers/visual.dart`); verisi API sözleşmesindeki
/// gerçek örnek yanıtlardan gelir, böylece ekranlar dolu ve gerçekçi görünür.
void main() {
  Map<String, Object> acceptedPrefs() => demoPrefs();

  FakeBackend populated() => demoBackend();

  setUpAll(() async {
    if (screenshotsEnabled) await loadBrandFonts();
  });
  setUp(() {
    todayPanelClock = () => DateTime(2026, 10, 10, 9, 15);
    debugAccountAvailable = true; // hesap ekranı Supabase yapılandırması olmadan da çizilsin
  });
  tearDown(() {
    todayPanelClock = DateTime.now;
    debugAccountAvailable = null;
    Tw.dark = false;
  });

  const screens = <(String, String, bool)>[
    ('bugun', '/dashboard', true),
    ('rutin', '/dashboard/routine', true),
    ('sohbet', '/dashboard/chat', true),
    ('sohbet-davet', '/rebi', false),
    ('gecmis', '/dashboard/history', true),
    ('ben', '/dashboard/profile', true),
    ('hesap', '/dashboard/account', true),
    ('gorunum', '/dashboard/themes', true),
    ('hatirlaticilar', '/dashboard/reminders', true),
    ('rafim', '/dashboard/shelf', true),
    ('checkin', '/dashboard/checkin', true),
    ('abonelik', '/dashboard/subscribe', true),
    ('analiz', '/dashboard/analyze', true),
    ('karsilama', '/', false),
    ('giris', '/auth', false),
    ('yasal', '/kvkk', false),
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

  // Hatırlatıcılar (Faz E): kendi saat aralığı, sessiz saatler, "bildirimler gelmiyor mu" kartı ve saat sayfası.
  FakeBackend withCustomWindows() {
    final b = populated();
    b.reminderSettings = {
      ...b.reminderSettings,
      'windows': {
        'routine_morning': {'start': '08:00', 'end': '09:30'},
        'lip_balm': {'start': '15:00', 'end': '16:00'},
      },
      'quiet': {'start': '13:00', 'end': '14:30'},
    };
    return b;
  }

  for (final dark in [false, true]) {
    testWidgets('${dark ? 'koyu' : 'acik'} · hatirlaticilar-uzun', (tester) async {
      Tw.dark = dark;
      debugDisableShadows = false;
      try {
        final h = await pumpApp(
          tester,
          location: '/dashboard/reminders',
          prefs: acceptedPrefs(),
          backend: withCustomWindows(),
          notifier: FakeReminderNotifier(),
          realFonts: true,
          size: const Size(390, 2500),
        );
        unawaited(h.notifications.enable());
        await settle(tester);
        await shoot(tester, '${dark ? 'koyu' : 'acik'}-hatirlaticilar-uzun', width: 585);
      } finally {
        debugDisableShadows = true;
      }
    }, skip: !screenshotsEnabled);

    testWidgets('${dark ? 'koyu' : 'acik'} · sayfa saat-araligi', (tester) async {
      Tw.dark = dark;
      debugDisableShadows = false;
      try {
        await pumpApp(
          tester,
          location: '/dashboard/reminders',
          prefs: acceptedPrefs(),
          backend: withCustomWindows(),
          realFonts: true,
        );
        await tapText(tester, tr('mobileReminders.categories.routine.title'));
        await shoot(tester, '${dark ? 'koyu' : 'acik'}-sayfa-saat-araligi');
      } finally {
        debugDisableShadows = true;
      }
    }, skip: !screenshotsEnabled);
  }

  // Uzun ekranlar (kaydırmadan tek görüntü): Faz F'de yeniden kurulan ekranlar.
  const tall = <(String, String, double)>[
    ('rutin-uzun', '/dashboard/routine', 3600),
    ('sohbet-uzun', '/dashboard/chat', 1500),
    ('gecmis-uzun', '/dashboard/history', 3400),
    ('ben-uzun', '/dashboard/profile', 1900),
    ('hesap-uzun', '/dashboard/account', 4200),
    ('checkin-uzun', '/dashboard/checkin', 2600),
    ('abonelik-uzun', '/dashboard/subscribe', 2600),
  ];
  for (final dark in [false, true]) {
    for (final (name, path, height) in tall) {
      testWidgets('${dark ? 'koyu' : 'acik'} · $name', (tester) async {
        Tw.dark = dark;
        debugDisableShadows = false;
        try {
          await pumpApp(
            tester,
            location: path,
            prefs: acceptedPrefs(),
            backend: populated(),
            realFonts: true,
            size: Size(390, height),
          );
          await shoot(tester, '${dark ? 'koyu' : 'acik'}-$name', width: 585);
        } finally {
          debugDisableShadows = true;
        }
      }, skip: !screenshotsEnabled);
    }
  }

  // Sohbet durumları (Faz F1): konuşma, hata kartı, hak doldu kartı.
  final chatCases = <(String, FakeBackend Function())>[
    (
      'konusma',
      () => populated()
        ..chatReply = 'Niasinamid bariyeri destekler ve gözenek görünümünü dengeler.\n\nŞunlara dikkat et:\n'
            '• Yeni ürünü önce kolunda dene\n• Aynı akşam güçlü asitlerle karıştırma\n• Sabah güneş kremi şart',
    ),
    ('hata', () => populated()..chatFailTimes = 1),
    ('limit', () => populated()..quotaAfter = 0),
  ];
  for (final dark in [false, true]) {
    for (final (name, make) in chatCases) {
      testWidgets('${dark ? 'koyu' : 'acik'} · sohbet-$name', (tester) async {
        Tw.dark = dark;
        debugDisableShadows = false;
        try {
          await pumpApp(tester, location: '/dashboard/chat', prefs: acceptedPrefs(), backend: make(), realFonts: true);
          await tester.enterText(find.byType(TextField), 'Niasinamid ne işe yarar?');
          await tester.testTextInput.receiveAction(TextInputAction.send);
          await settle(tester);
          await shoot(tester, '${dark ? 'koyu' : 'acik'}-sohbet-$name');
        } finally {
          debugDisableShadows = true;
        }
      }, skip: !screenshotsEnabled);
    }
  }

  // Analiz sihirbazı (yeni kullanıcı): karşılama. Soru ekranlarının görselleri `analyze_flow_test`'te.
  for (final dark in [false, true]) {
    testWidgets('${dark ? 'koyu' : 'acik'} · analiz-adim1', (tester) async {
      Tw.dark = dark;
      debugDisableShadows = false;
      try {
        await pumpApp(tester, location: '/dashboard/analyze', backend: FakeBackend(), realFonts: true, size: const Size(390, 1500));
        await shoot(tester, '${dark ? 'koyu' : 'acik'}-analiz-adim1', width: 585);
      } finally {
        debugDisableShadows = true;
      }
    }, skip: !screenshotsEnabled);
  }

  // İlk açılış (Faz F4): konum önerisi, ardından bildirim önerisi.
  for (final dark in [false, true]) {
    testWidgets('${dark ? 'koyu' : 'acik'} · bugun-konum', (tester) async {
      Tw.dark = dark;
      debugDisableShadows = false;
      setLocationAccess(read: () async => LocationAccess.askable);
      try {
        final b = populated();
        b.snapshot = {
          ...b.snapshot,
          'consent': {...(b.snapshot['consent'] as Map).cast<String, dynamic>(), 'location_processing_allowed': true},
        };
        await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs(), backend: b, realFonts: true, notifier: FakeReminderNotifier());
        await shoot(tester, '${dark ? 'koyu' : 'acik'}-bugun-konum');
      } finally {
        resetLocationAccess();
        debugDisableShadows = true;
      }
    }, skip: !screenshotsEnabled);
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
