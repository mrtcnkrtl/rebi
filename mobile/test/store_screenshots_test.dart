import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart' show Size, TextField, TextInputAction;
import 'package:flutter/painting.dart' show debugDisableShadows;
import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/screens/today/today_clock.dart';
import 'package:rebi/ui/tw.dart';

import 'helpers/app_harness.dart';
import 'helpers/demo_data.dart';
import 'helpers/notification_fakes.dart';
import 'helpers/visual.dart';

/// Faz G4: mağaza ekran görüntüleri. Yalnızca `REBI_STORE_SHOTS=1` ile çalışır:
///
///     cd mobile && REBI_STORE_SHOTS=1 flutter test test/store_screenshots_test.dart
///
/// Çıktı: `build/store/<dil>/<biçim>/`; biçimler ve piksel boyutları aşağıdaki `formats` listesinde.
/// Gerçek yazı tipleri ve gerçek ekran kodu kullanılır; durum çubuğu ve cihaz çerçevesi yoktur. Veri, ekranların dolu
/// görünmesi için örnek hesaptır (`helpers/demo_data.dart`); sohbet yanıtı örnek metindir, gerçek cihazdan alınmış sayılmaz.
/// Uygulamanın arayüz dilleri (`supportedLangs`): her biri için ayrı klasör.
const storeLangs = ['tr', 'en'];

void main() {
  // (klasör, mantıksal boyut, çıktı ölçeği): çıktı piksel boyutu = mantıksal × ölçek.
  const formats = <(String, Size, double)>[
    ('apple-6.9', Size(440, 956), 3), // 1320×2868
    ('apple-6.3', Size(402, 874), 3), // 1206×2622 (Apple'ın zorunlu iPhone boyutu)
    ('apple-duo-dis', Size(466, 678), 3), // iPhone Duo dış ekran 1398×2034
    ('apple-duo-ic', Size(669, 951), 3), // iPhone Duo iç ekran 2007×2853
    ('apple-ipad-13', Size(1032, 1376), 2), // iPad 13" 2064×2752
    ('play-telefon', Size(360, 720), 3), // 1080×2160
  ];

  setUpAll(() async {
    if (storeShotsEnabled) await loadBrandFonts();
  });
  setUp(() => todayPanelClock = () => DateTime(2026, 10, 10, 9, 15));
  tearDown(() {
    todayPanelClock = DateTime.now;
    Tw.dark = false;
  });

  FakeBackend backend(String lang, {bool windows = false, bool chat = false}) {
    final b = demoBackend(lang: lang, store: true);
    if (windows) {
      b.reminderSettings = {
        ...b.reminderSettings,
        'windows': {
          'routine_morning': {'start': '08:00', 'end': '09:30'},
          'lip_balm': {'start': '15:00', 'end': '16:00'},
        },
        'quiet': {'start': '13:00', 'end': '14:30'},
      };
    }
    if (chat) {
      b.chatReply = lang == 'en'
          ? 'Niacinamide supports your skin barrier and helps balance the look of pores.\n\nKeep in mind:\n'
              '• Patch-test a new product on your arm first\n• Don\'t pair it with strong acids the same evening\n• Sunscreen every morning'
          : 'Niasinamid bariyeri destekler ve gözenek görünümünü dengeler.\n\nŞunlara dikkat et:\n'
              '• Yeni ürünü önce kolunda dene\n• Aynı akşam güçlü asitlerle karıştırma\n• Sabah güneş kremi şart';
    }
    return b;
  }

  final shots = <(String, Future<void> Function(WidgetTester, Size, double, Directory, String))>[
    ('01-bugun', (t, size, scale, dir, lang) async {
      await pumpApp(t, location: '/dashboard', lang: lang, prefs: demoPrefs(lang: lang, store: true), backend: backend(lang), realFonts: true, size: size);
      await shoot(t, '01-bugun', width: size.width * scale, into: dir);
    }),
    ('02-rutin', (t, size, scale, dir, lang) async {
      await pumpApp(t, location: '/dashboard/routine', lang: lang, prefs: demoPrefs(lang: lang, store: true), backend: backend(lang), realFonts: true, size: size);
      await shoot(t, '02-rutin', width: size.width * scale, into: dir);
    }),
    ('03-sohbet', (t, size, scale, dir, lang) async {
      await pumpApp(t, location: '/dashboard/chat', lang: lang, prefs: demoPrefs(lang: lang, store: true), backend: backend(lang, chat: true), realFonts: true, size: size);
      await t.enterText(find.byType(TextField), lang == 'en' ? 'What does niacinamide do?' : 'Niasinamid ne işe yarar?');
      await t.testTextInput.receiveAction(TextInputAction.send);
      await settle(t);
      await shoot(t, '03-sohbet', width: size.width * scale, into: dir);
    }),
    ('04-gecmis', (t, size, scale, dir, lang) async {
      await pumpApp(t, location: '/dashboard/history', lang: lang, prefs: demoPrefs(lang: lang, store: true), backend: backend(lang), realFonts: true, size: size);
      await shoot(t, '04-gecmis', width: size.width * scale, into: dir);
    }),
    ('05-hatirlaticilar', (t, size, scale, dir, lang) async {
      final h = await pumpApp(
        t,
        location: '/dashboard/reminders',
        lang: lang,
        prefs: demoPrefs(lang: lang, store: true),
        backend: backend(lang, windows: true),
        notifier: FakeReminderNotifier(),
        realFonts: true,
        size: size,
      );
      unawaited(h.notifications.enable());
      await settle(t);
      await shoot(t, '05-hatirlaticilar', width: size.width * scale, into: dir);
    }),
    ('06-rafim', (t, size, scale, dir, lang) async {
      await pumpApp(t, location: '/dashboard/shelf', lang: lang, prefs: demoPrefs(lang: lang, store: true), backend: backend(lang), realFonts: true, size: size);
      await shoot(t, '06-rafim', width: size.width * scale, into: dir);
    }),
    ('07-su', (t, size, scale, dir, lang) async {
      await pumpApp(t, location: '/dashboard', lang: lang, prefs: demoPrefs(lang: lang, store: true), backend: backend(lang), realFonts: true, size: size);
      await tapText(t, tr('mobileToday.actions.waterMore'));
      await shoot(t, '07-su', width: size.width * scale, into: dir);
    }),
    ('08-bugun-koyu', (t, size, scale, dir, lang) async {
      Tw.dark = true;
      await pumpApp(t, location: '/dashboard', lang: lang, prefs: demoPrefs(lang: lang, store: true), backend: backend(lang), realFonts: true, size: size);
      await shoot(t, '08-bugun-koyu', width: size.width * scale, into: dir);
    }),
  ];

  for (final lang in storeLangs) {
    for (final (format, size, scale) in formats) {
      for (final (name, run) in shots) {
        testWidgets('$lang · $format · $name', (tester) async {
          // flutter_test gölgeleri bulanıksız çizer; cihazdaki gibi görünmesi için açılır, test bitmeden geri alınır.
          debugDisableShadows = false;
          try {
            await run(tester, size, scale, Directory('build/store/$lang/$format'), lang);
          } finally {
            debugDisableShadows = true;
          }
        }, skip: !storeShotsEnabled);
      }
    }
  }
}
