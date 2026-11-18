import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n.dart';
import '../tw.dart';
import 'brand_caps.dart';
import 'motion.dart';
import 'palette.dart';

/// Rebi Plus'ın premium alt dili: "klinik sıcaklık" paletine tek bir şampanya altını eklenir. Altın yalnızca vurgu
/// (çizgi, ikon, ana düğme) için kullanılır; zemin hâlâ orman yeşili ve krem. Neon, cam, yoğun gradyan yok.
class PlusPalette {
  PlusPalette._();

  /// Altın düğme zemini ve ikon dolgusu.
  static const gold = Color(0xFFD2B06A);

  /// Koyu zeminde altın yazı ve çizgi.
  static const goldSoft = Color(0xFFE6CF9C);

  /// Açık zeminde okunur altın yazı (krem kâğıtta ~5:1).
  static const goldDeep = Color(0xFF7E5F22);

  /// Altın düğmenin üstündeki yazı.
  static const onGold = Color(0xFF0B2F2B);

  /// Zemine göre okunur altın yazı rengi.
  static Color get text => Tw.dark ? goldSoft : goldDeep;

  /// Zemine göre yumuşak altın dolgu (karşılaştırmadaki Plus sütunu, rozetler).
  static Color get wash => Tw.dark ? goldSoft.withValues(alpha: .08) : const Color(0xFFF6ECD6);

  /// Altın ince çizgi.
  static Color get line => Tw.dark ? goldSoft.withValues(alpha: .28) : const Color(0xFFE2CC9C);

  /// Üyelik kartı ve seçili paketin koyu orman zemini (her iki temada aynı).
  static const cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF145249), Color(0xFF0B3D38), Color(0xFF062724)],
    stops: [0, .55, 1],
  );
}

/// Altın daire içinde taç: Plus'ın küçük işareti (menü kartı, sohbet kartı).
class PlusMark extends StatelessWidget {
  const PlusMark({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFE9D3A0), PlusPalette.gold, Color(0xFFB8924C)],
          ),
        ),
        child: Icon(LucideIcons.crown, size: size * .46, color: PlusPalette.onGold),
      ),
    );
  }
}

/// Ana satın alma düğmesi: altın zemin, orman yeşili yazı, tam yuvarlak uçlar. Açılışta bir kez ışık bandı geçer.
class PlusButton extends StatelessWidget {
  const PlusButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.loading = false,
    this.height = 56,
    this.icon = LucideIcons.crown,
    this.shimmer = true,
  });

  final VoidCallback? onPressed;
  final String label;
  final bool loading;
  final double height;
  final IconData? icon;
  final bool shimmer;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final content = loading
        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: PlusPalette.onGold))
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[ExcludeSemantics(child: Icon(icon, size: 18, color: PlusPalette.onGold)), const SizedBox(width: 10)],
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: tx(16, w: 7, c: PlusPalette.onGold, ls: .1),
                ),
              ),
            ],
          );
    Widget button = Container(
      constraints: BoxConstraints(minHeight: height),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(height / 2),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFE2C68A), PlusPalette.gold],
        ),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: const Color(0xFF8A6A2B).withValues(alpha: Tw.dark ? .35 : .28),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: content,
    );
    if (shimmer && enabled) {
      button = ShimmerOnce(delay: const Duration(milliseconds: 900), radius: height / 2, color: Colors.white, child: button);
    }
    return Semantics(
      button: true,
      enabled: enabled,
      child: AnimatedOpacity(
        opacity: enabled || loading ? 1 : .45,
        duration: const Duration(milliseconds: 200),
        child: Pressable(onTap: enabled ? onPressed : null, scale: .98, impact: true, child: button),
      ),
    );
  }
}

/// Üyelik kartı: orman yeşili zeminde altın gravür çizgileri, Fraunces "Rebi" ve aralıklı "PLUS". Sayfanın odak
/// noktasıdır; sahnenin üstüne biner. [label] / [value] kartın altındaki iki satırdır (ücretsizde vaat, abonede paket).
class PlusMembershipCard extends StatelessWidget {
  const PlusMembershipCard({super.key, required this.label, required this.value, this.active = false});

  final String label;
  final String value;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final lang = context.i18n.lang;
    const radius = 24.0;
    final card = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: PlusPalette.cardGradient,
        border: Border.all(color: PlusPalette.goldSoft.withValues(alpha: .55), width: 1),
        boxShadow: [BoxShadow(color: const Color(0xFF021412).withValues(alpha: .38), blurRadius: 34, offset: const Offset(0, 18))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: CustomPaint(
          painter: const PlusEngravingPainter(),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.end,
                        spacing: 10,
                        children: [
                          Text('Rebi', style: Brand.serif(30, color: Brand.cream, h: 1, ls: -.6)),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text('PLUS', style: tx(12, w: 7, c: PlusPalette.goldSoft, ls: 3.2)),
                          ),
                        ],
                      ),
                    ),
                    ExcludeSemantics(child: Icon(LucideIcons.crown, size: 22, color: PlusPalette.goldSoft)),
                  ],
                ),
                const SizedBox(height: 58),
                Text(
                  brandCaps(label, lang),
                  style: tx(10.5, w: 7, c: Brand.cream.withValues(alpha: .62), ls: brandTracking(lang, 1.8)),
                ),
                const SizedBox(height: 5),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (active) ...[
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(color: PlusPalette.gold, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Flexible(
                      child: Text(value, style: tx(17, w: 6, c: Brand.cream, h: 1.25)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return Semantics(
      container: true,
      label: 'Rebi Plus',
      child: ShimmerOnce(
        delay: const Duration(milliseconds: 350),
        duration: const Duration(milliseconds: 1500),
        radius: radius,
        color: PlusPalette.goldSoft,
        child: card,
      ),
    );
  }
}

/// Kartın gravürü: sağ alt köşeden yayılan ince altın yaylar ve sol üstte yumuşak bir ışık.
class PlusEngravingPainter extends CustomPainter {
  const PlusEngravingPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final glow = Paint()
      ..shader = RadialGradient(colors: [Colors.white.withValues(alpha: .10), Colors.white.withValues(alpha: 0)])
          .createShader(Rect.fromCircle(center: Offset(size.width * .1, -size.height * .1), radius: size.width * .7));
    canvas.drawRect(Offset.zero & size, glow);

    final origin = Offset(size.width * 1.02, size.height * 1.08);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .8;
    final maxR = size.width * .95;
    for (var r = size.width * .16; r < maxR; r += 9) {
      final t = r / maxR;
      line.color = PlusPalette.goldSoft.withValues(alpha: .20 * (1 - t) + .03);
      canvas.drawArc(Rect.fromCircle(center: origin, radius: r), math.pi, math.pi / 2, false, line);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Küçük altın hap etiket ("En çok tercih edilen", "%17 tasarruf").
class PlusPill extends StatelessWidget {
  const PlusPill(this.text, {super.key, this.onDark = false});

  final String text;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: onDark ? PlusPalette.gold : PlusPalette.wash,
        borderRadius: BorderRadius.circular(99),
        border: onDark ? null : Border.all(color: PlusPalette.line),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: tx(10.5, w: 7, c: onDark ? PlusPalette.onGold : PlusPalette.text, ls: .2),
      ),
    );
  }
}

/// Plus'a davet kartı ("Ben" sekmesi): üyelik kartının küçük kardeşi. Orman yeşili zemin, altın gravür, taç işareti,
/// serif başlık ve tek satırlık vaat; tamamı dokunulabilir.
class PlusPromoCard extends StatelessWidget {
  const PlusPromoCard({super.key, required this.title, required this.hint, required this.onTap});

  final String title;
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const radius = 22.0;
    return Semantics(
      button: true,
      child: Pressable(
        onTap: onTap,
        scale: .985,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: PlusPalette.cardGradient,
            border: Border.all(color: PlusPalette.goldSoft.withValues(alpha: .5)),
            boxShadow: [BoxShadow(color: const Color(0xFF021412).withValues(alpha: .22), blurRadius: 22, offset: const Offset(0, 10))],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: CustomPaint(
              painter: const PlusEngravingPainter(),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 14, 16),
                child: Row(
                  children: [
                    const PlusMark(size: 44),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: Brand.serif(20, color: Brand.cream, h: 1.15, ls: -.3)),
                          const SizedBox(height: 3),
                          Text(hint, style: tx(13, c: Brand.cream.withValues(alpha: .74), h: 1.4)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    ExcludeSemantics(child: Icon(LucideIcons.chevronRight, size: 20, color: PlusPalette.goldSoft)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
