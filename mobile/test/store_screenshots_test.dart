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
/// Çıktı: `build/store/apple-6.9/` (1320×2868) ve `build/store/play-telefon/` (1080×2160, en-boy oranı 2:1 sınırında).
/// Gerçek yazı tipleri ve gerçek ekran kodu kullanılır; durum çubuğu ve cihaz çerçevesi yoktur. Veri, ekranların dolu
/// görünmesi için örnek hesaptır (`helpers/demo_data.dart`); sohbet yanıtı örnek metindir, gerçek cihazdan alınmış sayılmaz.
void main() {
  const formats = <(String, Size)>[
    ('apple-6.9', Size(440, 956)),
    ('play-telefon', Size(360, 720)),
  ];

  setUpAll(() async {
    if (storeShotsEnabled) await loadBrandFonts();
  });
  setUp(() => todayPanelClock = () => DateTime(2026, 10, 10, 9, 15));
  tearDown(() {
    todayPanelClock = DateTime.now;
    Tw.dark = false;
  });

  FakeBackend backend({bool windows = false, bool chat = false}) {
    final b = demoBackend();
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
      b.chatReply = 'Niasinamid bariyeri destekler ve gözenek görünümünü dengeler.\n\nŞunlara dikkat et:\n'
          '• Yeni ürünü önce kolunda dene\n• Aynı akşam güçlü asitlerle karıştırma\n• Sabah güneş kremi şart';
    }
    return b;
  }

  final shots = <(String, Future<void> Function(WidgetTester, Size, Directory))>[
    ('01-bugun', (t, size, dir) async {
      await pumpApp(t, location: '/dashboard', prefs: demoPrefs(), backend: backend(), realFonts: true, size: size);
      await shoot(t, '01-bugun', width: size.width * 3, into: dir);
    }),
    ('02-rutin', (t, size, dir) async {
      await pumpApp(t, location: '/dashboard/routine', prefs: demoPrefs(), backend: backend(), realFonts: true, size: size);
      await shoot(t, '02-rutin', width: size.width * 3, into: dir);
    }),
    ('03-sohbet', (t, size, dir) async {
      await pumpApp(t, location: '/dashboard/chat', prefs: demoPrefs(), backend: backend(chat: true), realFonts: true, size: size);
      await t.enterText(find.byType(TextField), 'Niasinamid ne işe yarar?');
      await t.testTextInput.receiveAction(TextInputAction.send);
      await settle(t);
      await shoot(t, '03-sohbet', width: size.width * 3, into: dir);
    }),
    ('04-gecmis', (t, size, dir) async {
      await pumpApp(t, location: '/dashboard/history', prefs: demoPrefs(), backend: backend(), realFonts: true, size: size);
      await shoot(t, '04-gecmis', width: size.width * 3, into: dir);
    }),
    ('05-hatirlaticilar', (t, size, dir) async {
      final h = await pumpApp(
        t,
        location: '/dashboard/reminders',
        prefs: demoPrefs(),
        backend: backend(windows: true),
        notifier: FakeReminderNotifier(),
        realFonts: true,
        size: size,
      );
      unawaited(h.notifications.enable());
      await settle(t);
      await shoot(t, '05-hatirlaticilar', width: size.width * 3, into: dir);
    }),
    ('06-rafim', (t, size, dir) async {
      await pumpApp(t, location: '/dashboard/shelf', prefs: demoPrefs(), backend: backend(), realFonts: true, size: size);
      await shoot(t, '06-rafim', width: size.width * 3, into: dir);
    }),
    ('07-su', (t, size, dir) async {
      await pumpApp(t, location: '/dashboard', prefs: demoPrefs(), backend: backend(), realFonts: true, size: size);
      await tapText(t, tr('mobileToday.actions.waterMore'));
      await shoot(t, '07-su', width: size.width * 3, into: dir);
    }),
    ('08-bugun-koyu', (t, size, dir) async {
      Tw.dark = true;
      await pumpApp(t, location: '/dashboard', prefs: demoPrefs(), backend: backend(), realFonts: true, size: size);
      await shoot(t, '08-bugun-koyu', width: size.width * 3, into: dir);
    }),
  ];

  for (final (format, size) in formats) {
    for (final (name, run) in shots) {
      testWidgets('$format · $name', (tester) async {
        // flutter_test gölgeleri bulanıksız çizer; cihazdaki gibi görünmesi için açılır, test bitmeden geri alınır.
        debugDisableShadows = false;
        try {
          await run(tester, size, Directory('build/store/$format'));
        } finally {
          debugDisableShadows = true;
        }
      }, skip: !storeShotsEnabled);
    }
  }
}
