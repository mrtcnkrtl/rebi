import 'package:flutter/material.dart';

import '../../ui/tw.dart';

/// Gün içi kayıt düğmesi: yuvarlak hap, en az 48 dp yüksekliğinde dokunma alanı.
class TodayPill extends StatelessWidget {
  const TodayPill({
    super.key,
    required this.label,
    required this.onTap,
    required this.color,
    this.filled = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onTap;
  final Color color;

  /// Dolu (vurgulu) ya da hafif tonlu.
  final bool filled;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    // Dolu düğmede beyaz yazı, hafif düğmede tint üstünde koyu/açık metin: ikisi de AA kontrastında.
    final tint = Color.alphaBlend(color.withValues(alpha: .08), Tw.surface);
    final fill = Tw.fillWithWhiteText(color);
    final fg = filled ? Colors.white : Tw.readable(color, bg: tint);
    return Opacity(
      opacity: onTap == null ? .5 : 1,
      child: Material(
        color: filled ? fill : color.withValues(alpha: .08),
        shape: StadiumBorder(side: BorderSide(color: filled ? fill : color.withValues(alpha: .3))),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[Icon(icon, size: 15, color: fg), const SizedBox(width: 6)],
                  Flexible(child: Text(label, style: tx(12, w: 6, c: fg), textAlign: TextAlign.center)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Kartın solundaki renkli simge kutusu.
class TodayIconBadge extends StatelessWidget {
  const TodayIconBadge({super.key, required this.icon, required this.color, this.size = 40});

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(size * .32)),
        child: Icon(icon, size: size * .5, color: color),
      );
}

/// Bölüm etiketi: küçük, aralıklı, soluk ("GÜN İÇİ"). Büyük harf çevirisi yapılmaz (Türkçe İ/ı sorunu); metin zaten yazıldığı gibi gelir.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
        child: Row(
          children: [
            Expanded(child: Text(text, style: tx(11.5, w: 7, c: Tw.gray500, ls: 1.1))),
            ?trailing,
          ],
        ),
      );
}

/// Kart içi ince ayırıcı çizgi.
class Hairline extends StatelessWidget {
  const Hairline({super.key, this.indent = 0});

  final double indent;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(left: indent),
        child: Container(height: 1, color: Tw.gray100),
      );
}
