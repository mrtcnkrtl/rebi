import 'package:flutter/material.dart';

import '../tw.dart';

/// Açılış, karşılama ve giriş ekranlarının tasarım dili: "klinik sıcaklık".
/// Krem kâğıt zemin, derin orman yeşili mürekkep, nane ve pudra tonları; turkuaz yalnızca vurguda.
class Brand {
  Brand._();

  static bool get dark => Tw.dark;

  /// Splash ve ana düğmenin derin yeşili.
  static const forest = Color(0xFF0B3D38);
  static const forestDeep = Color(0xFF062B27);
  static const teal = Color(0xFF14B8A6);
  static const tealDeep = Color(0xFF0D9488);

  /// Sayfa zemini (krem kâğıt).
  static Color get paper => dark ? const Color(0xFF071A18) : const Color(0xFFF7F3EC);

  /// Kart yüzeyi.
  static Color get surface => dark ? const Color(0xFF0F2A27) : Colors.white;

  /// Ana metin ve çizgi rengi.
  static Color get ink => dark ? const Color(0xFFEAF3EF) : forest;
  static Color get inkSoft => ink.withValues(alpha: .74);
  static Color get inkFaint => ink.withValues(alpha: .12);

  /// Ana düğme: açıkta orman yeşili, koyuda krem.
  static Color get buttonBg => dark ? const Color(0xFFF1EDE4) : forest;
  static Color get buttonFg => dark ? forest : Colors.white;

  /// Karşılama sahnelerinin zemin tonları (açık / koyu).
  static Color tint(int i) {
    const light = [Color(0xFFD3E7DF), Color(0xFFF2DACD), Color(0xFFEDE0C8)];
    const night = [Color(0xFF0F302B), Color(0xFF2A201D), Color(0xFF28251B)];
    return (dark ? night : light)[i.clamp(0, 2)];
  }

  static const _serifFallback = ['Georgia', 'serif'];

  /// Başlık yazı tipi (Fraunces). Optik boyut, puntoya göre ayarlanır; Türkçe karakterleri destekler.
  static TextStyle serif(double size, {int weight = 500, Color? color, double h = 1.12, double ls = -.6}) {
    return TextStyle(
      fontFamily: 'Fraunces',
      fontFamilyFallback: _serifFallback,
      fontSize: size,
      fontWeight: FontWeight.values[(weight ~/ 100 - 1).clamp(0, 8)],
      fontVariations: [FontVariation('opsz', size.clamp(9, 144).toDouble()), const FontVariation('SOFT', 40), const FontVariation('WONK', 0)],
      color: color ?? ink,
      height: h,
      letterSpacing: ls,
    );
  }
}

/// Sayfa ve kart başlıkları: Fraunces serif, mürekkep rengi. Gövde metni `tx()` (Inter) ile yazılır;
/// başlık yalnızca kısa ve insani olmalı, sayılar ve etiketler için kullanılmaz.
TextStyle heading(double size, {Color? c, int w = 500, double? h}) =>
    Brand.serif(size, weight: w, color: c ?? Tw.gray900, h: h ?? 1.15, ls: size >= 28 ? -.6 : -.3);
