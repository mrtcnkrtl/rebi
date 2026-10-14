import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Uygulama ikonundaki "R" monogramı: turkuaz karo üstünde beyaz harf.
/// [progress] harfin ne kadarının çizildiğini (0–1), [sparkle] köşedeki parıltının büyüklüğünü verir
/// (splash animasyonunda harf çizilerek belirir).
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 40, this.progress = 1, this.sparkle = 1, this.shadow = false});

  final double size;
  final double progress;
  final double sparkle;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * .3),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF2DD4BF), Color(0xFF0D9488)]),
        boxShadow: shadow ? [BoxShadow(color: const Color(0xFF14B8A6).withValues(alpha: .35), blurRadius: size * .5, offset: Offset(0, size * .14))] : null,
      ),
      child: CustomPaint(painter: _RPainter(progress, sparkle)),
    );
  }
}

class _RPainter extends CustomPainter {
  _RPainter(this.progress, this.sparkle);

  final double progress;
  final double sparkle;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * .125
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(s * .35, s * .75)
      ..lineTo(s * .35, s * .26)
      ..lineTo(s * .53, s * .26)
      ..cubicTo(s * .75, s * .26, s * .75, s * .53, s * .53, s * .53)
      ..lineTo(s * .35, s * .53)
      ..moveTo(s * .54, s * .54)
      ..lineTo(s * .70, s * .75);
    var remaining = path.computeMetrics().fold<double>(0, (a, m) => a + m.length) * progress.clamp(0.0, 1.0);
    for (final m in path.computeMetrics()) {
      if (remaining <= 0) break;
      final len = math.min(m.length, remaining);
      canvas.drawPath(m.extractPath(0, len), paint);
      remaining -= len;
    }
    if (sparkle > 0) _star(canvas, Offset(s * .78, s * .22), s * .075 * sparkle);
  }

  /// Dört uçlu küçük yıldız.
  void _star(Canvas canvas, Offset c, double r) {
    final path = Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r)
      ..close();
    canvas.drawPath(path, Paint()..color = Colors.white.withValues(alpha: .95));
  }

  @override
  bool shouldRepaint(covariant _RPainter old) => old.progress != progress || old.sparkle != sparkle;
}
