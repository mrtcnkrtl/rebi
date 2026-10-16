import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/core/local_store.dart';
import 'package:rebi/state/auth_controller.dart';
import 'package:rebi/state/theme_controller.dart';
import 'package:rebi/ui/brand/glyphs.dart';
import 'package:rebi/ui/tw.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tasarım dilinin kuralları: kod bunlara uymazsa test kırılır, böylece yeni ekran eski dile kayamaz.
/// Dil için bkz. `docs/MOBIL-TASARIM-DILI.md`.
double _luminance(Color c) {
  double channel(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a), lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  tearDown(() => Tw.dark = false);

  group('vurgu renkleri (temalar)', () {
    test('ücretsiz dört, Plus için üç renk; çocuksu temalar yok', () {
      final themes = rebiThemes.values.toList();
      expect(themes.where((t) => !t.premium).map((t) => t.id), ['teal', 'green', 'pink', 'lavender']);
      expect(themes.where((t) => t.premium).map((t) => t.id), ['sunset', 'ocean', 'noir']);
      expect(rebiThemes.containsKey('cat'), isFalse);
      expect(rebiThemes.containsKey('teddy'), isFalse);
    });

    test('her temanın düğme rengi üstünde beyaz yazı AA (4.5:1) kontrastında okunur', () {
      for (final dark in [false, true]) {
        Tw.dark = dark;
        for (final t in rebiThemes.values) {
          expect(_contrast(Colors.white, t.primary), greaterThanOrEqualTo(4.5), reason: '${t.id} dark=$dark');
        }
      }
    });

    test('tema adları düz metindir (emoji yok)', () {
      final emoji = RegExp('[\u{1F300}-\u{1FAFF}☀-➿]', unicode: true);
      for (final t in rebiThemes.values) {
        expect(emoji.hasMatch(t.label), isFalse, reason: t.label);
      }
    });

    test('kaldırılmış tema kayıtlıysa varsayılana (Orman) dönülür', () async {
      SharedPreferences.setMockInitialValues({'rebi-theme': 'cat'});
      await LocalStore.init();
      final auth = AuthController();
      final ctrl = ThemeController(auth);
      expect(ctrl.themeId, 'teal');
      expect(ctrl.theme.label, 'Orman');
      ctrl.dispose();
      auth.dispose();
    });
  });

  group('ikonlar', () {
    test('backend emojileri çizgi ikona çevrilir, bilinmeyen emoji yedek ikona düşer', () {
      expect(glyphForEmoji('☀️'), isNot(glyphForEmoji('🌙')));
      expect(glyphForEmoji('🧴'), glyphForEmoji('🧴️'), reason: 'değişken seçici fark yaratmaz');
      expect(glyphForEmoji('🦄', fallback: Icons.circle), Icons.circle);
      expect(glyphForEmoji(null, fallback: Icons.circle), Icons.circle);
    });

    test('her temizleme yöntemi, beslenme seçimi ve cilt derdi bir ikona sahiptir', () {
      for (final m in const ['double', 'cleanser', 'water', 'wipe', 'none']) {
        expect(cleansingGlyph(m), isA<IconData>());
      }
      for (final c in const ['snacks', 'sweets', 'fried_food', 'dairy', 'balanced']) {
        expect(nutritionGlyph(c), isA<IconData>());
      }
      expect(concernGlyph('acne'), isNot(concernGlyph('dryness')));
    });
  });

  group('kod kuralları', () {
    // Emoji platforma göre farklı çizilir ve tipografiyle uyuşmaz; arayüz çizgi ikonlarla kurulur.
    // İzinli yerler: backend emoji eşlemesi (anahtar olarak) ve rutin metnindeki "duraklatıldı" işareti ayrıştırma.
    const allowed = {'lib/ui/brand/glyphs.dart', 'lib/core/routine_logic.dart'};
    final emoji = RegExp('[\u{1F300}-\u{1FAFF}☀-➿⭐⏸]', unicode: true);

    test('arayüz kodunda emoji yok', () {
      final offenders = <String>[];
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
        final path = f.path.replaceAll('\\', '/');
        if (!path.endsWith('.dart') || allowed.contains(path)) continue;
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i].trimLeft();
          if (line.startsWith('//')) continue;
          if (emoji.hasMatch(line)) offenders.add('$path:${i + 1}');
        }
      }
      expect(offenders, isEmpty, reason: 'Emoji yerine `ui/brand/glyphs.dart` ikonlarını kullan.');
    });

    test('ham Tailwind neon tonu (0xFF3B82F6 vb.) arayüze sızmaz', () {
      const banned = ['0xFF3B82F6', '0xFF2563EB', '0xFFEC4899', '0xFFA855F7', '0xFF06B6D4', '0xFF6366F1'];
      final offenders = <String>[];
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
        final path = f.path.replaceAll('\\', '/');
        if (!path.endsWith('.dart')) continue;
        final text = f.readAsStringSync();
        for (final b in banned) {
          if (text.contains(b)) offenders.add('$path: $b');
        }
      }
      expect(offenders, isEmpty, reason: 'Renk için `Tw` alıcılarını ya da `Brand`ı kullan.');
    });
  });
}
