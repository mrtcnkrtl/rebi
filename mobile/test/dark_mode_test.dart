import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/app.dart';
import 'package:rebi/core/local_store.dart';
import 'package:rebi/core/routine_tracking.dart';
import 'package:rebi/state/auth_controller.dart';
import 'package:rebi/state/theme_controller.dart';
import 'package:rebi/ui/components/appearance_card.dart';
import 'package:rebi/ui/brand/palette.dart';
import 'package:rebi/ui/tw.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/app_harness.dart';

double _luminance(Color c) {
  double channel(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

/// WCAG kontrast oranı.
double contrast(Color a, Color b) {
  final la = _luminance(a), lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  final routine = routineFixture['routine'] as List;

  tearDown(() => Tw.dark = false);

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

  group('renk alıcıları', () {
    test('açık mod klinik sıcaklık paletini verir (orman mürekkebi, krem kâğıt, beyaz kart)', () {
      Tw.dark = false;
      expect(Tw.gray900, const Color(0xFF0B3D38), reason: 'mürekkep = Brand.forest');
      expect(Tw.teal50, const Color(0xFFEAF4F0));
      expect(Tw.surface, Colors.white);
      expect(Tw.background, const Color(0xFFF7F3EC), reason: 'krem kâğıt');
    });

    test('tema renkleri Brand ile aynı kaynaktan gelir', () {
      for (final dark in [false, true]) {
        Tw.dark = dark;
        expect(Tw.background, Brand.paper);
        expect(Tw.surface, Brand.surface);
        expect(Tw.gray900, Brand.ink);
      }
    });

    test('koyu modda zemin ve yüzey koyu, gri sırası ters döner', () {
      Tw.dark = true;
      expect(_luminance(Tw.background), lessThan(.02));
      expect(_luminance(Tw.surface), lessThan(.03));
      expect(_luminance(Tw.surface), greaterThan(_luminance(Tw.background)), reason: 'kart zeminden bir tık açık');
      expect(_luminance(Tw.gray900), greaterThan(_luminance(Tw.gray500)));
      expect(_luminance(Tw.gray500), greaterThan(_luminance(Tw.gray100)));
    });

    test('marka ve vurgu tonları (orta tonlar) iki modda da aynıdır', () {
      Tw.dark = false;
      final light = [Tw.teal500, Tw.teal600, Tw.amber500, Tw.blue500, Tw.red600, Tw.emerald500];
      Tw.dark = true;
      final dark = [Tw.teal500, Tw.teal600, Tw.amber500, Tw.blue500, Tw.red600, Tw.emerald500];
      expect(dark, light);
    });

    test('açık tint zeminler koyu modda koyulaşır, koyu metin tonları açılır', () {
      Tw.dark = false;
      final lightTint = _luminance(Tw.teal50);
      final lightText = _luminance(Tw.teal700);
      Tw.dark = true;
      expect(_luminance(Tw.teal50), lessThan(.05), reason: 'tint koyu zeminde koyu kalır');
      expect(_luminance(Tw.teal50), lessThan(lightTint));
      expect(_luminance(Tw.teal700), greaterThan(lightText), reason: 'metin tonu koyu zeminde açılır');
    });

    test('adapt yalnızca koyu modda uygular ve alfa kanalını korur', () {
      const tint = Color(0xFFCCFBF1);
      Tw.dark = false;
      expect(Tw.adapt(tint), tint);
      Tw.dark = true;
      final adapted = Tw.adapt(tint.withValues(alpha: .5));
      expect(_luminance(adapted), lessThan(_luminance(tint)));
      expect(adapted.a, closeTo(.5, .01));
    });
  });

  group('okunabilirlik (WCAG AA 4.5:1)', () {
    for (final dark in [false, true]) {
      test('${dark ? 'koyu' : 'açık'} modda metin hiyerarşisi yüzeyde okunur', () {
        Tw.dark = dark;
        for (final (name, fg) in [
          ('gray900', Tw.gray900),
          ('gray800', Tw.gray800),
          ('gray700', Tw.gray700),
          ('gray600', Tw.gray600),
          ('gray500', Tw.gray500),
        ]) {
          expect(contrast(fg, Tw.surface), greaterThanOrEqualTo(4.5), reason: '$name / yüzey');
          expect(contrast(fg, Tw.background), greaterThanOrEqualTo(4.5), reason: '$name / zemin');
        }
      });

      test('${dark ? 'koyu' : 'açık'} modda vurgu metinleri kendi tint zeminlerinde okunur', () {
        Tw.dark = dark;
        for (final (name, fg, bg) in [
          ('teal', Tw.teal700, Tw.teal50),
          ('amber', Tw.amber900, Tw.amber50),
          ('emerald', Tw.emerald700, Tw.emerald50),
          ('red', Tw.red700, Tw.red50),
          ('blue', Tw.blueText, Tw.surface),
        ]) {
          expect(contrast(fg, bg), greaterThanOrEqualTo(4.5), reason: name);
        }
      });
    }

    test('birincil düğmede beyaz yazı iki modda da okunur', () {
      for (final dark in [false, true]) {
        Tw.dark = dark;
        expect(contrast(Colors.white, Tw.teal600), greaterThanOrEqualTo(3.5), reason: 'dark=$dark');
      }
    });
  });

  group('kullanıcı temaları', () {
    test('koyu modda tint ve koyu tonlar uyarlanır, ana renk aynı kalır', () {
      Tw.dark = false;
      final light = rebiThemes['pink']!;
      Tw.dark = true;
      final dark = rebiThemes['pink']!;
      expect(dark.primary, light.primary);
      expect(dark.accent, light.accent);
      expect(_luminance(dark.primaryLight), lessThan(_luminance(light.primaryLight)));
      expect(_luminance(dark.primaryDark), greaterThan(_luminance(light.primaryDark)));
      expect(identical(rebiThemes['pink'], dark), isTrue, reason: 'mod başına bir kez hesaplanır');
    });

    test('her temanın gradyan zemini koyu modda koyudur', () {
      Tw.dark = true;
      for (final t in rebiThemes.values) {
        final colors = (t.bg as LinearGradient).colors;
        for (final c in colors) {
          final opaque = Color.alphaBlend(c, Tw.background);
          expect(_luminance(opaque), lessThan(.12), reason: t.id);
        }
      }
    });
  });

  group('görünüm modu', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await LocalStore.init();
    });

    test('kayıtlı ad doğru moda çevrilir; bilinmeyen sistem olur', () {
      expect(themeModeFromName('light'), ThemeMode.light);
      expect(themeModeFromName('dark'), ThemeMode.dark);
      expect(themeModeFromName('system'), ThemeMode.system);
      expect(themeModeFromName(null), ThemeMode.system);
      expect(themeModeFromName('uydurma'), ThemeMode.system);
    });

    test('seçim kalıcıdır ve aynı değer tekrar yazılınca bildirim gitmez', () async {
      final auth = AuthController();
      final ctrl = ThemeController(auth);
      var notified = 0;
      ctrl.addListener(() => notified++);
      expect(ctrl.mode, ThemeMode.system, reason: 'varsayılan: sistemi izle');

      ctrl.setMode(ThemeMode.dark);
      ctrl.setMode(ThemeMode.dark);
      expect(notified, 1);
      expect(LocalStore.instance.getString('rebi-theme-mode'), 'dark');
      expect(ThemeController(auth).mode, ThemeMode.dark, reason: 'yeniden açılışta korunur');
      ctrl.dispose();
      auth.dispose();
    });

    test('Material teması iki modda da kurulur ve Tw.dark eski değerine döner', () {
      Tw.dark = false;
      final dark = buildRebiTheme(Brightness.dark, fonts: false);
      expect(Tw.dark, isFalse, reason: 'hesap sırasında geçici olarak değişir, sonra geri konur');
      final light = buildRebiTheme(Brightness.light, fonts: false);
      expect(dark.brightness, Brightness.dark);
      expect(light.brightness, Brightness.light);
      expect(dark.scaffoldBackgroundColor, const Color(0xFF071A18));
      expect(light.scaffoldBackgroundColor, const Color(0xFFF7F3EC));
      expect(dark.colorScheme.surface, isNot(light.colorScheme.surface));
    });
  });

  group('ekranlar koyu modda', () {
    testWidgets('görünüm kartı üç seçenek sunar ve seçimi kaydeder', (tester) async {
      await pumpStandalone(tester, (theme) => AppearanceCard(theme: theme));
      expect(find.text(tr('mobileAppearance.title')), findsOneWidget);
      for (final key in ['system', 'light', 'dark']) {
        expect(find.text(tr('mobileAppearance.$key')), findsOneWidget);
      }
      await tapText(tester, tr('mobileAppearance.dark'));
      expect(LocalStore.instance.getString('rebi-theme-mode'), 'dark');
    });

    for (final size in [const Size(390, 844), const Size(320, 568)]) {
      for (final loc in [
        '/',
        '/auth',
        '/dashboard',
        '/dashboard/analyze',
        '/dashboard/checkin',
        '/dashboard/chat',
        '/dashboard/themes',
        '/dashboard/subscribe',
        '/dashboard/history',
        '/dashboard/reminders',
        '/dashboard/routine',
        '/dashboard/profile',
        '/dashboard/account',
      ]) {
        testWidgets('$loc ${size.width.toInt()}×${size.height.toInt()} çizilir ve taşmaz', (tester) async {
          Tw.dark = true;
          await pumpApp(tester, location: loc, prefs: acceptedPrefs(), size: size);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('sayfa zemini koyu modda koyu yüzeydir', (tester) async {
      Tw.dark = true;
      await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs());
      final background = tester.widgetList<Scaffold>(find.byType(Scaffold)).map((w) => w.backgroundColor);
      expect(background, contains(Tw.background));
      expect(Tw.background, const Color(0xFF071A18));
    });
  });
}
