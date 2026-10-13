import 'dart:convert';

import 'package:flutter/material.dart' show Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/core/routine_tracking.dart';
import 'package:rebi/ui/tw.dart';

import 'helpers/app_harness.dart';

/// Erişilebilirlik: sistem yazı boyutu büyütüldüğünde (yaşlı kullanıcılar, görme zorluğu) ekranlar
/// taşmadan çizilmeli. Eşik: %150 yazı ölçeği, 360 genişlik; uç durum: %200, 320 genişlik.
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

  tearDown(() => Tw.dark = false);

  for (final (scale, size) in [(1.5, const Size(360, 780)), (2.0, const Size(320, 640))]) {
    for (final dark in [false, true]) {
      for (final loc in [
        '/dashboard',
        '/dashboard/routine',
        '/dashboard/chat',
        '/dashboard/history',
        '/dashboard/profile',
        '/dashboard/reminders',
        '/dashboard/themes',
        '/dashboard/checkin',
      ]) {
        testWidgets('$loc yazı ölçeği %${(scale * 100).round()} ${size.width.toInt()} px ${dark ? 'koyu' : 'açık'}', (tester) async {
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          Tw.dark = dark;
          await pumpApp(tester, location: loc, prefs: acceptedPrefs(), size: size);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
