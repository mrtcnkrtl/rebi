import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Uygulamanın renk katmanı. Adlar webden gelen Tailwind adlarıdır ve 40'tan fazla dosya bunları
/// kullandığı için korunur; DEĞERLER ise "klinik sıcaklık" paletindendir (bkz. `docs/MOBIL-TASARIM-DILI.md`):
/// - `gray*` / `slate*`: orman yeşili mürekkep ölçeği (gray900 = `Brand.forest`, krem kâğıt üzerinde okunur),
/// - `blue/sky/cyan` = su, `indigo/violet/purple/fuchsia` = lavanta, `pink/rose` = pudra,
///   `emerald/green` = adaçayı, `amber/yellow` = bal, `orange` = kil, `teal` = orman; `red` hata renginin kendisidir.
/// Doygun neon Tailwind tonları kullanılmaz; yeni kodda ham renk yazmak yerine bu alıcılar ya da `Brand` kullanılır.
/// Ana tonlar (400–600) iki modda aynıdır; tint ve metin tonları moda göre değişir. Metin/zemin çiftleri
/// WCAG AA (4.5:1) ölçütünü sağlar (`test/dark_mode_test.dart`).
class Tw {
  Tw._();

  /// Koyu mod açık mı. Uygulama kökü tema değişince günceller; renk alıcıları buna bakar.
  static bool dark = false;

  /// Sayfa zemini.
  static Color get background => dark ? const Color(0xFF071A18) : const Color(0xFFF7F3EC);

  /// Kart ve yüzey rengi (açık modda beyaz).
  static Color get surface => dark ? const Color(0xFF0F2A27) : Colors.white;

  /// Alt sayfa, menü gibi yükseltilmiş yüzey.
  static Color get surfaceRaised => dark ? const Color(0xFF163632) : Colors.white;

  /// WCAG bağıl parlaklık.
  static double _luminance(Color c) {
    double channel(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
  }

  /// İki renk arasındaki WCAG kontrast oranı (1–21).
  static double contrastRatio(Color a, Color b) {
    final la = _luminance(a), lb = _luminance(b);
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  /// [c] rengini metin olarak [bg] üzerinde en az [min]:1 kontrasta getirir: açık zeminde koyulaştırır, koyu zeminde
  /// açar. Kategori renkleri (su mavisi, bal sarısı…) tint zeminde metin olarak kullanılacaksa bundan geçirilir.
  static Color readable(Color c, {Color? bg, double min = 4.5}) {
    final base = bg ?? surface;
    if (contrastRatio(c, base) >= min) return c;
    final target = _luminance(base) > .5 ? const Color(0xFF000000) : const Color(0xFFFFFFFF);
    for (var step = 1; step <= 20; step++) {
      final next = Color.lerp(c, target, step * .05)!;
      if (contrastRatio(next, base) >= min) return next;
    }
    return target;
  }

  /// [c] rengini dolgu olarak kullanırken üstündeki beyaz yazı en az [min]:1 olsun diye gerekirse koyulaştırır.
  static Color fillWithWhiteText(Color c, {double min = 4.5}) {
    if (contrastRatio(Colors.white, c) >= min) return c;
    for (var step = 1; step <= 20; step++) {
      final next = Color.lerp(c, const Color(0xFF000000), step * .04)!;
      if (contrastRatio(Colors.white, next) >= min) return next;
    }
    return Color.lerp(c, const Color(0xFF000000), .8)!;
  }

  /// Koyu moda uyarlanmış açık tint (kullanıcı temalarının açık zemin / kenarlık tonları).
  static Color adapt(Color light) => dark ? _invert(light, text: false) : light;

  /// Koyu moda uyarlanmış koyu metin tonu (açık metin olur).
  static Color adaptText(Color light) => dark ? _invert(light, text: true) : light;

  static Color _invert(Color c, {required bool text}) {
    final hsl = HSLColor.fromColor(c);
    final l = hsl.lightness;
    var sat = hsl.saturation;
    double nl;
    if (text) {
      nl = (1.0 - l).clamp(0.64, 0.92);
    } else {
      if (l > 0.85) {
        nl = 0.13 + (1.0 - l) * 0.55;
        sat *= 0.55;
      } else {
        nl = 1.0 - l;
      }
      nl = nl.clamp(0.10, 0.40);
    }
    return hsl.withLightness(nl).withSaturation(sat.clamp(0.0, 1.0)).toColor().withValues(alpha: c.a);
  }

  /// Su tonunda vurgu metni: açık modda koyu, koyu modda açık (iki zeminde de AA kontrast).
  static Color get blueText => dark ? const Color(0xFF9BC6D0) : const Color(0xFF1F5F6D);

  /// Her iki modda da koyu kalan bölümler (Plus tanıtımı, perde) için sabit tonlar; ters çevrilmez.
  static const fixedSlate950 = Color(0xFF020617);
  static const fixedSlate900 = Color(0xFF0F172A);
  static const fixedViolet950 = Color(0xFF2E1065);

  static Color get gray50 => dark ? const Color(0xFF12302C) : const Color(0xFFF4F0E7);
  static Color get gray100 => dark ? const Color(0xFF183832) : const Color(0xFFEAE5DA);
  static Color get gray200 => dark ? const Color(0xFF21463F) : const Color(0xFFDDD6C8);
  static Color get gray300 => dark ? const Color(0xFF2E5A52) : const Color(0xFFC6BEAE);
  static Color get gray400 => dark ? const Color(0xFF6E8F87) : const Color(0xFF8D9B95);
  static Color get gray500 => dark ? const Color(0xFF91ABA4) : const Color(0xFF566F68);
  static Color get gray600 => dark ? const Color(0xFFA9BFB9) : const Color(0xFF435C56);
  static Color get gray700 => dark ? const Color(0xFFC3D4CF) : const Color(0xFF2B4741);
  static Color get gray800 => dark ? const Color(0xFFDCE8E4) : const Color(0xFF17403B);
  static Color get gray900 => dark ? const Color(0xFFEAF3EF) : const Color(0xFF0B3D38);
  static Color get slate50 => dark ? const Color(0xFF12302C) : const Color(0xFFF4F0E7);
  static Color get slate100 => dark ? const Color(0xFF183832) : const Color(0xFFEAE5DA);
  static Color get slate600 => dark ? const Color(0xFFA9BFB9) : const Color(0xFF435C56);
  static Color get slate800 => dark ? const Color(0xFFDCE8E4) : const Color(0xFF17403B);
  static Color get slate900 => dark ? const Color(0xFFEAF3EF) : const Color(0xFF0B3D38);
  static Color get slate950 => dark ? const Color(0xFFEAF3EF) : const Color(0xFF0B3D38);
  static Color get teal50 => dark ? const Color(0xFF103C38) : const Color(0xFFEAF4F0);
  static Color get teal100 => dark ? const Color(0xFF10453F) : const Color(0xFFD3E7DF);
  static Color get teal200 => dark ? const Color(0xFF105049) : const Color(0xFFB5D6CB);
  static Color get teal300 => dark ? const Color(0xFF11635A) : const Color(0xFF8FC2B3);
  static Color get teal400 => dark ? const Color(0xFF4FAE9C) : const Color(0xFF4FAE9C);
  static Color get teal500 => dark ? const Color(0xFF14B8A6) : const Color(0xFF14B8A6);
  static Color get teal600 => dark ? const Color(0xFF0F766E) : const Color(0xFF0F766E);
  static Color get teal700 => dark ? const Color(0xFFA6E4DD) : const Color(0xFF0B5F58);
  static Color get teal800 => dark ? const Color(0xFFB8EAE4) : const Color(0xFF0B4A45);
  static Color get teal900 => dark ? const Color(0xFFCBEFEB) : const Color(0xFF0B3D38);
  static Color get emerald50 => dark ? const Color(0xFF19392F) : const Color(0xFFEEF4EA);
  static Color get emerald100 => dark ? const Color(0xFF1E3F32) : const Color(0xFFDDE9D6);
  static Color get emerald200 => dark ? const Color(0xFF244837) : const Color(0xFFC3D8B9);
  static Color get emerald300 => dark ? const Color(0xFF2F573F) : const Color(0xFFA3C497);
  static Color get emerald500 => dark ? const Color(0xFF5E9A62) : const Color(0xFF5E9A62);
  static Color get emerald700 => dark ? const Color(0xFFC2D9C3) : const Color(0xFF366A3E);
  static Color get emerald800 => dark ? const Color(0xFFCFE1D0) : const Color(0xFF2B5532);
  static Color get emerald900 => dark ? const Color(0xFFDCE9DC) : const Color(0xFF22442A);
  static Color get amber50 => dark ? const Color(0xFF273628) : const Color(0xFFFBF3E1);
  static Color get amber100 => dark ? const Color(0xFF313C28) : const Color(0xFFF5E4BE);
  static Color get amber200 => dark ? const Color(0xFF404428) : const Color(0xFFEBD08F);
  static Color get amber300 => dark ? const Color(0xFF575029) : const Color(0xFFDDB65E);
  static Color get amber400 => dark ? const Color(0xFFCFA043) : const Color(0xFFCFA043);
  static Color get amber500 => dark ? const Color(0xFFC48A2B) : const Color(0xFFC48A2B);
  static Color get amber600 => dark ? const Color(0xFFB0761D) : const Color(0xFFB0761D);
  static Color get amber700 => dark ? const Color(0xFFE9D3AE) : const Color(0xFF8E5B12);
  static Color get amber800 => dark ? const Color(0xFFEDDCBF) : const Color(0xFF6F470E);
  static Color get amber900 => dark ? const Color(0xFFF2E5D0) : const Color(0xFF56380C);
  static Color get amber950 => dark ? const Color(0xFFF8F1E6) : const Color(0xFF3A2606);
  static Color get red50 => dark ? const Color(0xFF292F2A) : const Color(0xFFFCEFEC);
  static Color get red100 => dark ? const Color(0xFF34322C) : const Color(0xFFF8DDD8);
  static Color get red200 => dark ? const Color(0xFF44352D) : const Color(0xFFF1C0B8);
  static Color get red500 => dark ? const Color(0xFFD4533F) : const Color(0xFFD4533F);
  static Color get red600 => dark ? const Color(0xFFBE3F2D) : const Color(0xFFBE3F2D);
  static Color get red700 => dark ? const Color(0xFFEFBEB6) : const Color(0xFF9E3022);
  static Color get red800 => dark ? const Color(0xFFF2CBC5) : const Color(0xFF80281D);
  static Color get red900 => dark ? const Color(0xFFF6D9D5) : const Color(0xFF66211A);
  static Color get red950 => dark ? const Color(0xFFFAEAE8) : const Color(0xFF40130F);
  static Color get orange50 => dark ? const Color(0xFF28352D) : const Color(0xFFFAEFE8);
  static Color get orange100 => dark ? const Color(0xFF333A30) : const Color(0xFFF4DDCF);
  static Color get orange200 => dark ? const Color(0xFF434033) : const Color(0xFFEBC3AB);
  static Color get orange300 => dark ? const Color(0xFF5C4B39) : const Color(0xFFDFA383);
  static Color get orange500 => dark ? const Color(0xFFCF7C54) : const Color(0xFFCF7C54);
  static Color get orange600 => dark ? const Color(0xFFB96339) : const Color(0xFFB96339);
  static Color get orange700 => dark ? const Color(0xFFEDCDBE) : const Color(0xFF964D2B);
  static Color get orange800 => dark ? const Color(0xFFF1D8CC) : const Color(0xFF773E24);
  static Color get yellow100 => dark ? const Color(0xFF313C28) : const Color(0xFFF5E4BE);
  static Color get yellow700 => dark ? const Color(0xFFE9D3AE) : const Color(0xFF8E5B12);
  static Color get green50 => dark ? const Color(0xFF19392F) : const Color(0xFFEEF4EA);
  static Color get green100 => dark ? const Color(0xFF1E3F32) : const Color(0xFFDDE9D6);
  static Color get green200 => dark ? const Color(0xFF244837) : const Color(0xFFC3D8B9);
  static Color get green500 => dark ? const Color(0xFF5E9A62) : const Color(0xFF5E9A62);
  static Color get green600 => dark ? const Color(0xFF47804E) : const Color(0xFF47804E);
  static Color get green700 => dark ? const Color(0xFFC2D9C3) : const Color(0xFF366A3E);
  static Color get sky50 => dark ? const Color(0xFF153636) : const Color(0xFFEAF3F4);
  static Color get sky100 => dark ? const Color(0xFF183C3D) : const Color(0xFFD5E7EA);
  static Color get sky200 => dark ? const Color(0xFF1C4446) : const Color(0xFFB7D6DB);
  static Color get sky500 => dark ? const Color(0xFF3E8A9A) : const Color(0xFF3E8A9A);
  static Color get sky700 => dark ? const Color(0xFFB6D3D9) : const Color(0xFF1F5F6D);
  static Color get sky800 => dark ? const Color(0xFFC5DCE1) : const Color(0xFF174C58);
  static Color get sky900 => dark ? const Color(0xFFD5E5E9) : const Color(0xFF123E48);
  static Color get sky950 => dark ? const Color(0xFFE8F1F3) : const Color(0xFF0D2F37);
  /// Su tonunda dolgu (üstüne beyaz yazı): iki modda da aynı, beyaz yazıyla AA kontrast.
  static const blue600 = Color(0xFF2F7686);

  static Color get blue50 => dark ? const Color(0xFF153636) : const Color(0xFFEAF3F4);
  static Color get blue100 => dark ? const Color(0xFF183C3D) : const Color(0xFFD5E7EA);
  static Color get blue500 => dark ? const Color(0xFF3E8A9A) : const Color(0xFF3E8A9A);
  static Color get cyan50 => dark ? const Color(0xFF153636) : const Color(0xFFEAF3F4);
  static Color get cyan200 => dark ? const Color(0xFF1C4446) : const Color(0xFFB7D6DB);
  static Color get cyan500 => dark ? const Color(0xFF3E8A9A) : const Color(0xFF3E8A9A);
  static Color get indigo50 => dark ? const Color(0xFF1E3439) : const Color(0xFFF1EEF6);
  static Color get indigo100 => dark ? const Color(0xFF253842) : const Color(0xFFE4DFEE);
  static Color get indigo200 => dark ? const Color(0xFF2F3E4D) : const Color(0xFFD2CAE3);
  static Color get indigo400 => dark ? const Color(0xFF9B8CC4) : const Color(0xFF9B8CC4);
  static Color get indigo500 => dark ? const Color(0xFF8575B5) : const Color(0xFF8575B5);
  static Color get indigo600 => dark ? const Color(0xFF6C5AA0) : const Color(0xFF6C5AA0);
  static Color get violet50 => dark ? const Color(0xFF1E3439) : const Color(0xFFF1EEF6);
  static Color get violet100 => dark ? const Color(0xFF253842) : const Color(0xFFE4DFEE);
  static Color get violet200 => dark ? const Color(0xFF2F3E4D) : const Color(0xFFD2CAE3);
  static Color get violet400 => dark ? const Color(0xFF9B8CC4) : const Color(0xFF9B8CC4);
  static Color get violet800 => dark ? const Color(0xFFDAD6E9) : const Color(0xFF4A3B70);
  static Color get violet900 => dark ? const Color(0xFFE4E1EF) : const Color(0xFF3B2E58);
  static Color get violet950 => dark ? const Color(0xFFF0EEF6) : const Color(0xFF2B2142);
  static Color get purple50 => dark ? const Color(0xFF1E3439) : const Color(0xFFF1EEF6);
  static Color get purple100 => dark ? const Color(0xFF253842) : const Color(0xFFE4DFEE);
  static Color get purple500 => dark ? const Color(0xFF8575B5) : const Color(0xFF8575B5);
  static Color get purple600 => dark ? const Color(0xFF6C5AA0) : const Color(0xFF6C5AA0);
  static Color get purple700 => dark ? const Color(0xFFD1CBE3) : const Color(0xFF5A4985);
  static Color get fuchsia50 => dark ? const Color(0xFF1E3439) : const Color(0xFFF1EEF6);
  static Color get fuchsia100 => dark ? const Color(0xFF253842) : const Color(0xFFE4DFEE);
  static Color get fuchsia200 => dark ? const Color(0xFF2F3E4D) : const Color(0xFFD2CAE3);
  static Color get fuchsia300 => dark ? const Color(0xFF3E4860) : const Color(0xFFBAAED4);
  static Color get fuchsia400 => dark ? const Color(0xFF9B8CC4) : const Color(0xFF9B8CC4);
  static Color get fuchsia500 => dark ? const Color(0xFF8575B5) : const Color(0xFF8575B5);
  static Color get pink50 => dark ? const Color(0xFF283333) : const Color(0xFFF8EDEF);
  static Color get pink100 => dark ? const Color(0xFF333839) : const Color(0xFFF1DCE0);
  static Color get pink200 => dark ? const Color(0xFF423E41) : const Color(0xFFE7C4CB);
  static Color get pink400 => dark ? const Color(0xFFD98FA0) : const Color(0xFFD98FA0);
  static Color get pink500 => dark ? const Color(0xFFCC7387) : const Color(0xFFCC7387);
  static Color get pink600 => dark ? const Color(0xFFB85A70) : const Color(0xFFB85A70);
  static Color get pink700 => dark ? const Color(0xFFECCAD1) : const Color(0xFF94435A);
  static Color get pink800 => dark ? const Color(0xFFF0D5DB) : const Color(0xFF7A3548);
  static Color get rose50 => dark ? const Color(0xFF283333) : const Color(0xFFF8EDEF);
  static Color get rose200 => dark ? const Color(0xFF423E41) : const Color(0xFFE7C4CB);
  static Color get rose400 => dark ? const Color(0xFFD98FA0) : const Color(0xFFD98FA0);
  static Color get rose500 => dark ? const Color(0xFFCC7387) : const Color(0xFFCC7387);
  static Color get rose600 => dark ? const Color(0xFFB85A70) : const Color(0xFFB85A70);
  static Color get rose900 => dark ? const Color(0xFFF4E0E5) : const Color(0xFF5E2938);
  static Color get warm50 => dark ? const Color(0xFF13302C) : const Color(0xFFFAF5EA);
}

/// Tailwind metin boyutları ve kalınlıkları için kısa yol: `tx(14, w: 7, c: Tw.gray900)`.
/// `w` 4=normal, 5=medium, 6=semibold, 7=bold, 8=extrabold, 9=black.
TextStyle tx(double size, {int w = 4, Color? c, double? h, double? ls, FontStyle? style}) {
  const weights = {
    4: FontWeight.w400,
    5: FontWeight.w500,
    6: FontWeight.w600,
    7: FontWeight.w700,
    8: FontWeight.w800,
    9: FontWeight.w900,
  };
  return TextStyle(
    fontSize: size,
    fontWeight: weights[w] ?? FontWeight.w400,
    color: c ?? Tw.gray900,
    height: h,
    letterSpacing: ls,
    fontStyle: style,
  );
}

/// `leading-relaxed`
const double relaxed = 1.625;

/// `leading-snug`
const double snug = 1.375;

/// `leading-tight`
const double tight = 1.25;

Color withA(Color c, double a) => c.withValues(alpha: a);
