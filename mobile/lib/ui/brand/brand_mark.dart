import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Yol komutu: `('M', [x, y])`, `('L', [x, y])`, `('C', [x1, y1, x2, y2, x, y])`, `('Q', [x1, y1, x, y])`, `('Z', [])`.
typedef BrandSeg = (String, List<double>);

/// "R" monogramının geometrisi, 1×1'lik birim karede. Uygulama içi çizim ([BrandGlyphPainter]), uygulama ikonu,
/// bildirim simgesi ve Android açılış vektörü (`test/brand_assets_test.dart`) aynı sayılardan üretilir; logo her yerde
/// birebir aynı kalır. Burayı değiştirince ikonları yeniden üretin (bkz. o dosyanın başındaki açıklama).
class BrandGlyph {
  BrandGlyph._();

  /// Harfin orta çizgisi; [stroke] kalınlığında, yuvarlak uç ve köşeyle çizilir.
  static const List<BrandSeg> letter = [
    ('M', [.35, .75]),
    ('L', [.35, .26]),
    ('L', [.53, .26]),
    ('C', [.75, .26, .75, .53, .53, .53]),
    ('L', [.35, .53]),
    ('M', [.54, .54]),
    ('L', [.70, .75]),
  ];

  /// Çizgi kalınlığı (birim kare oranı).
  static const double stroke = .125;

  /// Köşedeki parıltının merkezi ve yarıçapı (birim kare oranı).
  static const Offset sparkleAt = Offset(.78, .22);
  static const double sparkleSize = .075;

  /// Dört uçlu küçük yıldız.
  static List<BrandSeg> star(Offset c, double r) => [
        ('M', [c.dx, c.dy - r]),
        ('Q', [c.dx, c.dy, c.dx + r, c.dy]),
        ('Q', [c.dx, c.dy, c.dx, c.dy + r]),
        ('Q', [c.dx, c.dy, c.dx - r, c.dy]),
        ('Q', [c.dx, c.dy, c.dx, c.dy - r]),
        ('Z', []),
      ];

  /// Komutları `s` kenarlı bir karede [Path]'e çevirir.
  static Path path(List<BrandSeg> segs, double s) {
    final p = Path();
    for (final (cmd, v) in segs) {
      switch (cmd) {
        case 'M':
          p.moveTo(v[0] * s, v[1] * s);
        case 'L':
          p.lineTo(v[0] * s, v[1] * s);
        case 'C':
          p.cubicTo(v[0] * s, v[1] * s, v[2] * s, v[3] * s, v[4] * s, v[5] * s);
        case 'Q':
          p.quadraticBezierTo(v[0] * s, v[1] * s, v[2] * s, v[3] * s);
        case 'Z':
          p.close();
      }
    }
    return p;
  }

  /// SVG / Android VectorDrawable yol verisi: her koordinat [scale] ile çarpılır, [at] kadar kaydırılır.
  static String svg(List<BrandSeg> segs, {double scale = 1, Offset at = Offset.zero}) {
    String n(double v) {
      final r = double.parse(v.toStringAsFixed(3));
      return r == r.roundToDouble() ? r.round().toString() : r.toString();
    }

    return segs.map((seg) {
      final (cmd, v) = seg;
      final xy = [for (var i = 0; i < v.length; i += 2) ...[n(v[i] * scale + at.dx), n(v[i + 1] * scale + at.dy)]];
      return '$cmd${xy.join(' ')}';
    }).join(' ');
  }
}

/// Uygulama ikonundaki "R" monogramı: turkuaz karo üstünde beyaz harf.
/// [progress] harfin ne kadarının çizildiğini (0–1), [sparkle] köşedeki parıltının büyüklüğünü verir
/// (splash animasyonunda harf çizilerek belirir).
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 40, this.progress = 1, this.sparkle = 1, this.shadow = false});

  final double size;
  final double progress;
  final double sparkle;
  final bool shadow;

  /// Karonun çapraz turkuaz geçişi (ikon ve açılış vektörü de bunu kullanır).
  static const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF2DD4BF), Color(0xFF0D9488)],
  );

  /// Karonun köşe yuvarlaklığı (kenar oranı).
  static const cornerRadius = .3;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * cornerRadius),
        gradient: gradient,
        boxShadow: shadow ? [BoxShadow(color: const Color(0xFF14B8A6).withValues(alpha: .35), blurRadius: size * .5, offset: Offset(0, size * .14))] : null,
      ),
      child: CustomPaint(painter: BrandGlyphPainter(progress, sparkle)),
    );
  }
}

/// Yalnızca harfi ve parıltıyı çizer (karo olmadan): [BrandMark] içinde ve ikon üretiminde kullanılır.
class BrandGlyphPainter extends CustomPainter {
  const BrandGlyphPainter(this.progress, this.sparkle, {this.color = Colors.white});

  final double progress;
  final double sparkle;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * BrandGlyph.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = BrandGlyph.path(BrandGlyph.letter, s);
    var remaining = path.computeMetrics().fold<double>(0, (a, m) => a + m.length) * progress.clamp(0.0, 1.0);
    for (final m in path.computeMetrics()) {
      if (remaining <= 0) break;
      final len = math.min(m.length, remaining);
      canvas.drawPath(m.extractPath(0, len), paint);
      remaining -= len;
    }
    if (sparkle > 0) {
      final star = BrandGlyph.path(BrandGlyph.star(BrandGlyph.sparkleAt, BrandGlyph.sparkleSize * sparkle), s);
      canvas.drawPath(star, Paint()..color = color.withValues(alpha: color.a * .95));
    }
  }

  @override
  bool shouldRepaint(covariant BrandGlyphPainter old) => old.progress != progress || old.sparkle != sparkle || old.color != color;
}
