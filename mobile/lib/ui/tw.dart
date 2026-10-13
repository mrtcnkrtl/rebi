import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Webde kullanılan Tailwind renkleri (yalnızca projede geçen tonlar).
class Tw {
  Tw._();

  /// Koyu mod açık mı. Uygulama kökü tema değişince günceller; renk alıcıları buna bakar.
  static bool dark = false;

  /// Sayfa zemini.
  static Color get background => dark ? const Color(0xFF0B1118) : Colors.white;

  /// Kart ve yüzey rengi (açık modda beyaz).
  static Color get surface => dark ? const Color(0xFF141B25) : Colors.white;

  /// Alt sayfa, menü gibi yükseltilmiş yüzey.
  static Color get surfaceRaised => dark ? const Color(0xFF1B2430) : Colors.white;

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

  /// Mavi vurgu metni: açık modda koyu, koyu modda açık mavi (iki zeminde de AA kontrast).
  static Color get blueText => dark ? const Color(0xFF60A5FA) : const Color(0xFF1D4ED8);

  /// Her iki modda da koyu kalan bölümler (Plus tanıtımı, perde) için sabit tonlar; ters çevrilmez.
  static const fixedSlate950 = Color(0xFF020617);
  static const fixedSlate900 = Color(0xFF0F172A);
  static const fixedViolet950 = Color(0xFF2E1065);

  static Color get gray50 => dark ? const Color(0xFF1A222D) : const Color(0xFFF9FAFB);
  static Color get gray100 => dark ? const Color(0xFF222C39) : const Color(0xFFF3F4F6);
  static Color get gray200 => dark ? const Color(0xFF2E3A4A) : const Color(0xFFE5E7EB);
  static Color get gray300 => dark ? const Color(0xFF3D4B5F) : const Color(0xFFD1D5DB);
  static Color get gray400 => dark ? const Color(0xFF74839A) : const Color(0xFF9CA3AF);
  static Color get gray500 => dark ? const Color(0xFF93A1B5) : const Color(0xFF6B7280);
  static Color get gray600 => dark ? const Color(0xFFA9B5C6) : const Color(0xFF4B5563);
  static Color get gray700 => dark ? const Color(0xFFC4CDDA) : const Color(0xFF374151);
  static Color get gray800 => dark ? const Color(0xFFE3E8F0) : const Color(0xFF1F2937);
  static Color get gray900 => dark ? const Color(0xFFF3F6FA) : const Color(0xFF111827);

  static Color get slate50 => dark ? const Color(0xFF1A222D) : const Color(0xFFF8FAFC);
  static Color get slate100 => dark ? const Color(0xFF222C39) : const Color(0xFFF1F5F9);
  static Color get slate600 => dark ? const Color(0xFFA9B5C6) : const Color(0xFF475569);
  static Color get slate800 => dark ? const Color(0xFFE3E8F0) : const Color(0xFF1E293B);
  static Color get slate900 => dark ? const Color(0xFFF3F6FA) : const Color(0xFF0F172A);
  static Color get slate950 => dark ? const Color(0xFFF8FAFC) : const Color(0xFF020617);

  static Color get teal50 => dark ? const Color(0xFF16362E) : const Color(0xFFF0FDFA);
  static Color get teal100 => dark ? const Color(0xFF1A473D) : const Color(0xFFCCFBF1);
  static Color get teal200 => dark ? const Color(0xFF096654) : const Color(0xFF99F6E4);
  static Color get teal300 => dark ? const Color(0xFF15A18B) : const Color(0xFF5EEAD4);
  static Color get teal400 => dark ? const Color(0xFF2DD4BF) : const Color(0xFF2DD4BF);
  static Color get teal500 => dark ? const Color(0xFF14B8A6) : const Color(0xFF14B8A6);
  static Color get teal600 => dark ? const Color(0xFF0D9488) : const Color(0xFF0D9488);
  static Color get teal700 => dark ? const Color(0xFF89F0E8) : const Color(0xFF0F766E);
  static Color get teal800 => dark ? const Color(0xFFA1EEE9) : const Color(0xFF115E59);
  static Color get teal900 => dark ? const Color(0xFFB1ECE8) : const Color(0xFF134E4A);

  static Color get emerald50 => dark ? const Color(0xFF163828) : const Color(0xFFECFDF5);
  static Color get emerald100 => dark ? const Color(0xFF1A442F) : const Color(0xFFD1FAE5);
  static Color get emerald200 => dark ? const Color(0xFF0C5835) : const Color(0xFFA7F3D0);
  static Color get emerald300 => dark ? const Color(0xFF189161) : const Color(0xFF6EE7B7);
  static Color get emerald500 => dark ? const Color(0xFF10B981) : const Color(0xFF10B981);
  static Color get emerald700 => dark ? const Color(0xFF87FBDA) : const Color(0xFF047857);
  static Color get emerald800 => dark ? const Color(0xFFA0F9E0) : const Color(0xFF065F46);
  static Color get emerald900 => dark ? const Color(0xFFB1F9E6) : const Color(0xFF064E3B);

  static Color get amber50 => dark ? const Color(0xFF3C3311) : const Color(0xFFFFFBEB);
  static Color get amber100 => dark ? const Color(0xFF4B4017) : const Color(0xFFFEF3C7);
  static Color get amber200 => dark ? const Color(0xFF755E02) : const Color(0xFFFDE68A);
  static Color get amber300 => dark ? const Color(0xFFB28903) : const Color(0xFFFCD34D);
  static Color get amber400 => dark ? const Color(0xFFFBBF24) : const Color(0xFFFBBF24);
  static Color get amber500 => dark ? const Color(0xFFF59E0B) : const Color(0xFFF59E0B);
  static Color get amber600 => dark ? const Color(0xFFD97706) : const Color(0xFFD97706);
  static Color get amber700 => dark ? const Color(0xFFF69850) : const Color(0xFFB45309);
  static Color get amber800 => dark ? const Color(0xFFF19F6D) : const Color(0xFF92400E);
  static Color get amber900 => dark ? const Color(0xFFF0AD87) : const Color(0xFF78350F);
  static Color get amber950 => dark ? const Color(0xFFFCD1BA) : const Color(0xFF451A03);

  static Color get red50 => dark ? const Color(0xFF361414) : const Color(0xFFFEF2F2);
  static Color get red100 => dark ? const Color(0xFF3F1414) : const Color(0xFFFEE2E2);
  static Color get red200 => dark ? const Color(0xFF491717) : const Color(0xFFFECACA);
  static Color get red500 => dark ? const Color(0xFFEF4444) : const Color(0xFFEF4444);
  static Color get red600 => dark ? const Color(0xFFDC2626) : const Color(0xFFDC2626);
  static Color get red700 => dark ? const Color(0xFFE76060) : const Color(0xFFB91C1C);
  static Color get red800 => dark ? const Color(0xFFE46666) : const Color(0xFF991B1B);
  static Color get red900 => dark ? const Color(0xFFE28080) : const Color(0xFF7F1D1D);
  static Color get red950 => dark ? const Color(0xFFF5BABA) : const Color(0xFF450A0A);

  static Color get orange50 => dark ? const Color(0xFF3B2811) : const Color(0xFFFFF7ED);
  static Color get orange100 => dark ? const Color(0xFF453014) : const Color(0xFFFFEDD5);
  static Color get orange200 => dark ? const Color(0xFF552E01) : const Color(0xFFFED7AA);
  static Color get orange300 => dark ? const Color(0xFF8B4802) : const Color(0xFFFDBA74);
  static Color get orange500 => dark ? const Color(0xFFF97316) : const Color(0xFFF97316);
  static Color get orange600 => dark ? const Color(0xFFEA580C) : const Color(0xFFEA580C);
  static Color get orange700 => dark ? const Color(0xFFF48152) : const Color(0xFFC2410C);
  static Color get orange800 => dark ? const Color(0xFFED8765) : const Color(0xFF9A3412);

  static Color get yellow100 => dark ? const Color(0xFF4C4817) : const Color(0xFFFEF9C3);
  static Color get yellow700 => dark ? const Color(0xFFF8B95E) : const Color(0xFFA16207);

  static Color get green50 => dark ? const Color(0xFF163620) : const Color(0xFFF0FDF4);
  static Color get green100 => dark ? const Color(0xFF174025) : const Color(0xFFDCFCE7);
  static Color get green200 => dark ? const Color(0xFF1F4E2F) : const Color(0xFFBBF7D0);
  static Color get green500 => dark ? const Color(0xFF22C55E) : const Color(0xFF22C55E);
  static Color get green600 => dark ? const Color(0xFF16A34A) : const Color(0xFF16A34A);
  static Color get green700 => dark ? const Color(0xFF7FEAA7) : const Color(0xFF15803D);

  static Color get sky50 => dark ? const Color(0xFF11293A) : const Color(0xFFF0F9FF);
  static Color get sky100 => dark ? const Color(0xFF142E40) : const Color(0xFFE0F2FE);
  static Color get sky200 => dark ? const Color(0xFF193D50) : const Color(0xFFBAE6FD);
  static Color get sky500 => dark ? const Color(0xFF0EA5E9) : const Color(0xFF0EA5E9);
  static Color get sky700 => dark ? const Color(0xFF5EC4FC) : const Color(0xFF0369A1);
  static Color get sky800 => dark ? const Color(0xFF7ACCF8) : const Color(0xFF075985);
  static Color get sky900 => dark ? const Color(0xFF91CFF3) : const Color(0xFF0C4A6E);
  static Color get sky950 => dark ? const Color(0xFFB6DDF7) : const Color(0xFF082F49);

  /// Mavi dolgu (üstüne beyaz yazı): iki modda da aynı, beyaz yazıyla AA kontrast.
  static const blue600 = Color(0xFF2563EB);

  static Color get blue50 => dark ? const Color(0xFF11233A) : const Color(0xFFEFF6FF);
  static Color get blue100 => dark ? const Color(0xFF152842) : const Color(0xFFDBEAFE);
  static Color get blue500 => dark ? const Color(0xFF3B82F6) : const Color(0xFF3B82F6);

  static Color get cyan50 => dark ? const Color(0xFF11393B) : const Color(0xFFECFEFF);
  static Color get cyan200 => dark ? const Color(0xFF03515A) : const Color(0xFFA5F3FC);
  static Color get cyan500 => dark ? const Color(0xFF06B6D4) : const Color(0xFF06B6D4);

  static Color get indigo50 => dark ? const Color(0xFF111B3B) : const Color(0xFFEEF2FF);
  static Color get indigo100 => dark ? const Color(0xFF131D41) : const Color(0xFFE0E7FF);
  static Color get indigo200 => dark ? const Color(0xFF17214B) : const Color(0xFFC7D2FE);
  static Color get indigo400 => dark ? const Color(0xFF818CF8) : const Color(0xFF818CF8);
  static Color get indigo500 => dark ? const Color(0xFF6366F1) : const Color(0xFF6366F1);
  static Color get indigo600 => dark ? const Color(0xFF4F46E5) : const Color(0xFF4F46E5);

  static Color get violet50 => dark ? const Color(0xFF171038) : const Color(0xFFF5F3FF);
  static Color get violet100 => dark ? const Color(0xFF1B143B) : const Color(0xFFEDE9FE);
  static Color get violet200 => dark ? const Color(0xFF1D1544) : const Color(0xFFDDD6FE);
  static Color get violet400 => dark ? const Color(0xFFA78BFA) : const Color(0xFFA78BFA);
  static Color get violet800 => dark ? const Color(0xFF9564E3) : const Color(0xFF5B21B6);
  static Color get violet900 => dark ? const Color(0xFF996AE2) : const Color(0xFF4C1D95);
  static Color get violet950 => dark ? const Color(0xFFB89AEF) : const Color(0xFF2E1065);

  static Color get purple50 => dark ? const Color(0xFF241038) : const Color(0xFFFAF5FF);
  static Color get purple100 => dark ? const Color(0xFF27123D) : const Color(0xFFF3E8FF);
  static Color get purple500 => dark ? const Color(0xFFA855F7) : const Color(0xFFA855F7);
  static Color get purple600 => dark ? const Color(0xFF9333EA) : const Color(0xFF9333EA);
  static Color get purple700 => dark ? const Color(0xFFA861E5) : const Color(0xFF7E22CE);

  static Color get fuchsia50 => dark ? const Color(0xFF311038) : const Color(0xFFFDF4FF);
  static Color get fuchsia100 => dark ? const Color(0xFF34123D) : const Color(0xFFFAE8FF);
  static Color get fuchsia200 => dark ? const Color(0xFF3D1647) : const Color(0xFFF5D0FE);
  static Color get fuchsia300 => dark ? const Color(0xFF480354) : const Color(0xFFF0ABFC);
  static Color get fuchsia400 => dark ? const Color(0xFFE879F9) : const Color(0xFFE879F9);
  static Color get fuchsia500 => dark ? const Color(0xFFD946EF) : const Color(0xFFD946EF);

  static Color get pink50 => dark ? const Color(0xFF341627) : const Color(0xFFFDF2F8);
  static Color get pink100 => dark ? const Color(0xFF3A172B) : const Color(0xFFFCE7F3);
  static Color get pink200 => dark ? const Color(0xFF461932) : const Color(0xFFFBCFE8);
  static Color get pink400 => dark ? const Color(0xFFF472B6) : const Color(0xFFF472B6);
  static Color get pink500 => dark ? const Color(0xFFEC4899) : const Color(0xFFEC4899);
  static Color get pink600 => dark ? const Color(0xFFDB2777) : const Color(0xFFDB2777);
  static Color get pink700 => dark ? const Color(0xFFEA5C97) : const Color(0xFFBE185D);
  static Color get pink800 => dark ? const Color(0xFFE86298) : const Color(0xFF9D174D);

  static Color get rose50 => dark ? const Color(0xFF391114) : const Color(0xFFFFF1F2);
  static Color get rose200 => dark ? const Color(0xFF48161C) : const Color(0xFFFECDD3);
  static Color get rose400 => dark ? const Color(0xFFFB7185) : const Color(0xFFFB7185);
  static Color get rose500 => dark ? const Color(0xFFF43F5E) : const Color(0xFFF43F5E);
  static Color get rose600 => dark ? const Color(0xFFE11D48) : const Color(0xFFE11D48);
  static Color get rose900 => dark ? const Color(0xFFEC779B) : const Color(0xFF881337);

  static Color get warm50 => dark ? const Color(0xFF1D2128) : const Color(0xFFFDF8F0);
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

/// Emojiler her zaman renkli çizilsin: ☀ gibi bazı karakterleri metin yazı tipi de içerir ve
/// tek renkli sembol olarak basar. Tarayıcı bu durumda emoji yazı tipine düşüyordu.
TextStyle emojiStyle(double size) => TextStyle(
      fontSize: size,
      height: 1.15,
      fontFamily: defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS
          ? 'Apple Color Emoji'
          : 'Noto Color Emoji',
    );

Widget emojiText(String emoji, double size) => Text(emoji, style: emojiStyle(size));
