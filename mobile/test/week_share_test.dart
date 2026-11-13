import 'dart:typed_data';

import 'package:flutter/material.dart' show BottomSheet, Size;
import 'package:flutter/rendering.dart' show debugDisableShadows;
import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/core/history_trends.dart';
import 'package:rebi/core/user_history.dart';
import 'package:rebi/screens/history/week_share.dart';

import 'helpers/app_harness.dart';
import 'helpers/visual.dart';

/// Geçmiş → "Bu hafta" → paylaşılabilir haftalık özet görseli.
void main() {
  final original = weekImageSharer;
  tearDown(() => weekImageSharer = original);

  final today = dateOnly(DateTime.now());
  String ago(int n) => dayKey(DateTime(today.year, today.month, today.day - n));

  Map<String, dynamic> day(int back, {bool morning = false, bool evening = false, int water = 0, int spf = 0}) => {
        'log_date': ago(back),
        'tracking': {
          'events_count': 1,
          'routine_morning_done': morning,
          'routine_evening_done': evening,
          'water_ml_total': water,
          'spf_refreshes': spf,
        },
      };

  FakeBackend backend() {
    final b = FakeBackend();
    b.history = {
      ...b.history,
      'days': [
        day(0, morning: true, water: 1800),
        day(1, morning: true, evening: true, water: 2200, spf: 2),
        day(2, morning: true, evening: true, water: 2000, spf: 1),
        day(4, morning: true, evening: true, water: 2400),
        day(9, morning: true, evening: true, water: 3000),
      ],
    };
    return b;
  }

  test('son 7 gün eskiden yeniye; kaydı olmayan gün boş', () {
    final days = shareWeekDays([
      HistoryDay.fromJson(day(1, morning: true, evening: true)),
      HistoryDay.fromJson(day(3, morning: true)),
      HistoryDay.fromJson(day(8, morning: true, evening: true)),
    ], DateTime.now());
    expect(days, hasLength(7));
    expect(days.last.date, today);
    expect([for (final d in days) d.full], [false, false, false, false, false, true, false]);
    expect([for (final d in days) d.any], [false, false, false, true, false, true, false]);
  });

  testWidgets('"Paylaş" önizleme açar; paylaşılan görsel PNG ve metin yalnızca rutin özetini içerir', (tester) async {
    Uint8List? png;
    String? text;
    weekImageSharer = (bytes, t) async {
      png = bytes;
      text = t;
    };
    await pumpApp(tester, location: '/dashboard/history', backend: backend());
    await tapText(tester, tr('mobileShare.button'));
    expect(find.text(tr('mobileShare.title')), findsOneWidget);
    expect(find.text(tr('mobileShare.routineCaption')), findsOneWidget);

    // Görseli PNG'ye çevirmek gerçek motor çağrısıdır: sahte zamanın dışında beklenir.
    await tester.tap(find.descendant(of: find.byType(BottomSheet), matching: find.text(tr('mobileShare.share'))).last);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
    await tester.pump();

    expect(png, isNotNull);
    expect(png!.sublist(1, 4), [0x50, 0x4E, 0x47], reason: 'PNG imzası');
    expect(text, tr('mobileShare.shareText', {'n': 3}));
  });

  group('görsel', () {
    setUpAll(() async {
      if (screenshotsEnabled) await loadBrandFonts();
    });

    testWidgets('hafta-paylas', (tester) async {
      if (!screenshotsEnabled) return;
      debugDisableShadows = false;
      try {
        await pumpApp(tester, location: '/dashboard/history', backend: backend(), realFonts: true, size: const Size(390, 900));
        await tapText(tester, tr('mobileShare.button'));
        await shoot(tester, 'hafta-paylas');
      } finally {
        debugDisableShadows = true;
      }
    });
  });
}
