import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n.dart';
import '../tw.dart';
import 'motion.dart';
import 'palette.dart';

// Karşılama sahnelerinin illüstrasyonları. Hepsi 100×100'lük birim tuvalde çizilir, sol üstten gelen
// tek bir ışık yönü ve sınırlı bir palet kullanır. Sahne öne çıktığında kendi animasyonunu oynatır;
// kaydırma sırasında katmanlar farklı hızda kayar (paralaks).

const _ink = Color(0xFF0B3D38);
const _inkMid = Color(0xFF1B6F65);
const _teal = Color(0xFF0D9488);
const _cream = Color(0xFFFBF7F0);

Paint _paint(Color c) => Paint()..color = c;

Paint _grad(Rect r, List<Color> colors, {Alignment begin = Alignment.topCenter, Alignment end = Alignment.bottomCenter, List<double>? stops}) =>
    Paint()..shader = LinearGradient(begin: begin, end: end, colors: colors, stops: stops).createShader(r);

Paint _blur(Color c, double sigma) => Paint()
  ..color = c
  ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma);

/// Başlangıç noktasından +x yönüne uzanan yaprak.
Path _leafPath(double len, double wid) => Path()
  ..moveTo(0, 0)
  ..quadraticBezierTo(len * .45, -wid, len, 0)
  ..quadraticBezierTo(len * .45, wid, 0, 0)
  ..close();

/// Eğri bir sap boyunca dönüşümlü yapraklar dizer (zeytin dalı).
void _sprig(Canvas c, {required Offset from, required Offset to, required Offset bend, required int leaves, required double leaf, required List<Color> colors, double stem = .7}) {
  final path = Path()
    ..moveTo(from.dx, from.dy)
    ..quadraticBezierTo(bend.dx, bend.dy, to.dx, to.dy);
  final metric = path.computeMetrics().first;
  c.drawPath(path, Paint()..style = PaintingStyle.stroke..strokeWidth = stem..strokeCap = StrokeCap.round..color = colors.last);
  for (var i = 0; i < leaves; i++) {
    final t = (i + 1.4) / (leaves + .6);
    final tan = metric.getTangentForOffset(metric.length * t.clamp(0.0, 1.0));
    if (tan == null) continue;
    final side = i.isEven ? -1.0 : 1.0;
    final size = leaf * (1 - .35 * t);
    c.save();
    c.translate(tan.position.dx, tan.position.dy);
    c.rotate(-tan.angle + 0 + side * .95);
    final lp = _leafPath(size, size * .34);
    c.drawPath(lp, _grad(Rect.fromLTWH(0, -size * .4, size, size * .8), colors, begin: Alignment.centerLeft, end: Alignment.centerRight));
    c.restore();
  }
  // uçtaki yaprak
  final end = metric.getTangentForOffset(metric.length);
  if (end != null) {
    c.save();
    c.translate(end.position.dx, end.position.dy);
    c.rotate(-end.angle);
    final size = leaf * .62;
    c.drawPath(_leafPath(size, size * .34), _paint(colors.first));
    c.restore();
  }
}

Path _archPath(double l, double r, double top, double bottom) {
  final w = r - l;
  return Path()
    ..moveTo(l, bottom)
    ..lineTo(l, top + w / 2)
    ..arcTo(Rect.fromLTWH(l, top, w, w), math.pi, math.pi, false)
    ..lineTo(r, bottom)
    ..close();
}

/// 100×100 birim tuvale ölçeklenen boyayıcı tabanı.
abstract class _UnitPainter extends CustomPainter {
  _UnitPainter(Listenable repaint) : super(repaint: repaint);

  void paintUnit(Canvas canvas);

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);
    canvas.save();
    canvas.translate((size.width - s) / 2, (size.height - s) / 2);
    canvas.scale(s / 100);
    paintUnit(canvas);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _UnitPainter old) => true;
}

double _iv(double t, double a, double b, [Curve curve = Curves.easeOutCubic]) => curve.transform(Interval(a, b).transform(t));

/// Grubu [opacity] ile birlikte soldurur.
void _group(Canvas c, double opacity, VoidCallback draw) {
  if (opacity <= 0) return;
  if (opacity >= .999) {
    draw();
    return;
  }
  c.saveLayer(const Rect.fromLTWH(-30, -30, 160, 160), Paint()..color = Color.fromRGBO(255, 255, 255, opacity));
  draw();
  c.restore();
}

// ---------------------------------------------------------------------------------------------
// Çerçeve: sahne öne çıkınca animasyonu oynatır
// ---------------------------------------------------------------------------------------------

class ArtFrame extends StatefulWidget {
  const ArtFrame({super.key, required this.active, required this.duration, required this.builder});

  final bool active;
  final Duration duration;
  final Widget Function(BuildContext context, Animation<double> t, double side) builder;

  @override
  State<ArtFrame> createState() => _ArtFrameState();
}

class _ArtFrameState extends State<ArtFrame> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration);
  bool _didStart = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didStart) return;
    _didStart = true;
    if (reduceMotion(context)) {
      _c.value = 1;
    } else if (widget.active) {
      _c.forward();
    }
  }

  @override
  void didUpdateWidget(covariant ArtFrame old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active && !reduceMotion(context)) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final s = math.min(box.maxWidth, box.maxHeight);
        return Center(
          child: SizedBox.square(
            dimension: s,
            child: Stack(clipBehavior: Clip.none, children: [Positioned.fill(child: widget.builder(context, _c, s))]),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Etiketler (küçük bilgi kartları)
// ---------------------------------------------------------------------------------------------

class ArtTag extends StatelessWidget {
  const ArtTag({super.key, required this.t, required this.from, required this.icon, required this.iconColor, required this.title, this.sub, this.rise = 10});

  final Animation<double> t;
  final double from;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? sub;
  final double rise;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: t,
      builder: (context, child) {
        final p = _iv(t.value, from, math.min(1, from + .35));
        return Opacity(opacity: p, child: Transform.translate(offset: Offset(0, (1 - p) * rise), child: child));
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 7, 13, 7),
        decoration: BoxDecoration(
          color: Brand.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: Brand.dark ? .35 : .09), blurRadius: 22, offset: const Offset(0, 10)),
            BoxShadow(color: Colors.black.withValues(alpha: Brand.dark ? .2 : .04), blurRadius: 3, offset: const Offset(0, 1)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(color: iconColor.withValues(alpha: .14), shape: BoxShape.circle),
              child: Icon(icon, size: 15, color: iconColor),
            ),
            const SizedBox(width: 9),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: tx(12.5, w: 7, c: Brand.ink, h: 1.15)),
                if (sub != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(sub!, style: tx(10.5, w: 5, c: Brand.inkSoft, h: 1.1))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Sahne 1 — tarama aynası
// ---------------------------------------------------------------------------------------------

class MirrorArt extends StatelessWidget {
  const MirrorArt({super.key, required this.active, required this.delta});

  final bool active;
  final double delta;

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    return ArtFrame(
      active: active,
      duration: const Duration(milliseconds: 2600),
      builder: (context, t, s) => Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: CustomPaint(painter: _MirrorPainter(t, delta, Brand.dark))),
          Positioned(left: s * (.0 + delta * .10), top: s * .20, child: ArtTag(t: t, from: .45, icon: LucideIcons.sun, iconColor: const Color(0xFFE08A1E), title: i18n.t('mobileLanding.chipUv'))),
          Positioned(right: s * (.0 - delta * .10), top: s * .66, child: ArtTag(t: t, from: .6, icon: LucideIcons.droplets, iconColor: _teal, title: i18n.t('mobileLanding.chipHumidity'))),
        ],
      ),
    );
  }
}

class _MirrorPainter extends _UnitPainter {
  _MirrorPainter(this.t, this.delta, this.night) : super(t);

  final Animation<double> t;
  final double delta;
  final bool night;

  @override
  void paintUnit(Canvas c) {
    final e = _iv(t.value, 0, .38);
    final scan = _iv(t.value, .36, .86, Curves.easeInOut);
    final pop = t.value;
    const center = Offset(50, 45);

    // Arka katman: hale
    c.save();
    c.translate(delta * 14, 0);
    c.drawCircle(center, 42 * (.9 + .1 * e), _paint(Colors.white.withValues(alpha: (night ? .05 : .30) * e)));
    c.drawCircle(center, 33 * (.9 + .1 * e), _paint(Colors.white.withValues(alpha: (night ? .06 : .32) * e)));
    c.restore();

    // Orta katman: ayna
    c.save();
    c.translate(0, (1 - e) * 7);
    _group(c, e, () {
      c.drawCircle(center.translate(1.2, 4.2), 27, _blur(Colors.black.withValues(alpha: night ? .35 : .17), 2.6));
      // sap
      final handle = RRect.fromLTRBR(46.2, 68, 53.8, 94, const Radius.circular(3.8));
      c.drawRRect(handle, _grad(handle.outerRect, const [_inkMid, _ink], begin: Alignment.centerLeft, end: Alignment.centerRight));
      final band = RRect.fromLTRBR(45.6, 73, 54.4, 76.4, const Radius.circular(1.6));
      c.drawRRect(band, _grad(band.outerRect, const [Color(0xFFEBD299), Color(0xFFB88F4C)]));
      // çerçeve
      c.drawCircle(center, 27.6, _grad(Rect.fromCircle(center: center, radius: 27.6), const [Color(0xFF2E897D), _ink], begin: Alignment.topLeft, end: Alignment.bottomRight));
      c.drawCircle(center, 24.6, _paint(const Color(0x33FFFFFF)));
      // cam
      final glass = Rect.fromCircle(center: center, radius: 23.8);
      c.drawCircle(
        center,
        23.8,
        Paint()
          ..shader = const RadialGradient(center: Alignment(-.35, -.45), radius: 1.15, colors: [Colors.white, Color(0xFFDDF0EA), Color(0xFFBBDCD2)], stops: [0, .55, 1]).createShader(glass),
      );
      c.save();
      c.clipPath(Path()..addOval(glass));
      // parlama bandı
      c.save();
      c.translate(center.dx - 3, center.dy - 9);
      c.rotate(-.62);
      final bandRect = const Rect.fromLTWH(-34, -4.5, 68, 9);
      c.drawRect(bandRect, _grad(bandRect, [Colors.white.withValues(alpha: 0), Colors.white.withValues(alpha: .6), Colors.white.withValues(alpha: 0)]));
      c.restore();
      // algılanan noktalar
      void target(Offset o, double r, double from) {
        final p = _iv(pop, from, math.min(1, from + .22), Curves.easeOutBack);
        if (p <= 0) return;
        final ring = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0
          ..color = _teal.withValues(alpha: .95);
        c.drawCircle(o, r * p, ring);
        c.drawCircle(o, .9 * p, _paint(_teal));
        final arm = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = .7
          ..strokeCap = StrokeCap.round
          ..color = _teal.withValues(alpha: .8);
        final a = r * p + 1.2;
        final b = r * p + 2.6;
        for (final d in const [Offset(1, 0), Offset(-1, 0), Offset(0, 1), Offset(0, -1)]) {
          c.drawLine(o + d * a, o + d * b, arm);
        }
      }

      target(const Offset(43, 38), 3.6, .5);
      target(const Offset(57.5, 47), 2.8, .62);
      target(const Offset(45.5, 55.5), 2.3, .74);
      // tarama çizgisi
      if (scan > 0 && scan < 1) {
        final y = glass.top + scan * glass.height;
        final fade = math.sin(math.pi * scan);
        final glow = Rect.fromLTRB(glass.left, y - 6, glass.right, y + 6);
        c.drawRect(glow, _grad(glow, [_teal.withValues(alpha: 0), _teal.withValues(alpha: .32 * fade), _teal.withValues(alpha: 0)]));
        c.drawLine(Offset(glass.left, y), Offset(glass.right, y), Paint()..strokeWidth = 1.0..color = _teal.withValues(alpha: .95 * fade));
      }
      c.restore();
    });
    c.restore();

    // Ön katman: tarama köşeleri
    c.save();
    c.translate(-delta * 10, 0);
    final inset = (1 - e) * 5;
    final br = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.9
      ..strokeCap = StrokeCap.round
      ..color = _teal.withValues(alpha: e);
    const half = 37.0;
    final l = center.dx - half + inset, r = center.dx + half - inset;
    final tp = center.dy - half + inset, bt = center.dy + half - inset;
    const len = 8.0;
    c.drawPath(Path()..moveTo(l, tp + len)..lineTo(l, tp)..lineTo(l + len, tp), br);
    c.drawPath(Path()..moveTo(r - len, tp)..lineTo(r, tp)..lineTo(r, tp + len), br);
    c.drawPath(Path()..moveTo(l, bt - len)..lineTo(l, bt)..lineTo(l + len, bt), br);
    c.drawPath(Path()..moveTo(r - len, bt)..lineTo(r, bt)..lineTo(r, bt - len), br);
    c.restore();

    // Parıltılar
    void star(Offset o, double r0, double from) {
      final p = _iv(pop, from, math.min(1, from + .25), Curves.easeOutBack);
      if (p <= 0) return;
      final rr = r0 * p;
      final path = Path()
        ..moveTo(o.dx, o.dy - rr)
        ..quadraticBezierTo(o.dx, o.dy, o.dx + rr, o.dy)
        ..quadraticBezierTo(o.dx, o.dy, o.dx, o.dy + rr)
        ..quadraticBezierTo(o.dx, o.dy, o.dx - rr, o.dy)
        ..quadraticBezierTo(o.dx, o.dy, o.dx, o.dy - rr)
        ..close();
      c.drawPath(path, _paint(night ? Colors.white.withValues(alpha: .85) : _teal));
    }

    star(const Offset(82, 14), 3.4, .55);
    star(const Offset(15, 77), 2.4, .7);
  }
}

// ---------------------------------------------------------------------------------------------
// Sahne 2 — podyum üstünde ürünler
// ---------------------------------------------------------------------------------------------

class PodiumArt extends StatelessWidget {
  const PodiumArt({super.key, required this.active, required this.delta});

  final bool active;
  final double delta;

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    return ArtFrame(
      active: active,
      duration: const Duration(milliseconds: 2200),
      builder: (context, t, s) => Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: CustomPaint(painter: _PodiumPainter(t, delta, Brand.dark))),
          Positioned(left: s * (-.01 + delta * .10), top: s * .27, child: ArtTag(t: t, from: .5, icon: LucideIcons.flaskConical, iconColor: _teal, title: i18n.t('mobileLanding.chipActive'))),
          Positioned(right: s * (.0 - delta * .10), top: s * .07, child: ArtTag(t: t, from: .62, icon: LucideIcons.shieldCheck, iconColor: const Color(0xFFE08A1E), title: i18n.t('mobileLanding.chipSpf'))),
        ],
      ),
    );
  }
}

class _PodiumPainter extends _UnitPainter {
  _PodiumPainter(this.t, this.delta, this.night) : super(t);

  final Animation<double> t;
  final double delta;
  final bool night;

  static const _goldA = Color(0xFFEBD299);
  static const _goldB = Color(0xFFB88F4C);

  void _contact(Canvas c, double cx, double cy, double rx) =>
      c.drawOval(Rect.fromCenter(center: Offset(cx, cy), width: rx * 2, height: rx * .42), _blur(Colors.black.withValues(alpha: .22), 1.1));

  void _pump(Canvas c, double cx, double base) {
    _contact(c, cx + 1, base, 9.5);
    final body = RRect.fromLTRBR(cx - 8, base - 30, cx + 8, base, const Radius.circular(5));
    c.drawRRect(body, _grad(body.outerRect, const [Color(0xFFF9DDD0), Color(0xFFF1C2AE), Color(0xFFE4A38B)], begin: Alignment.centerLeft, end: Alignment.centerRight, stops: const [0, .5, 1]));
    c.drawRRect(RRect.fromLTRBR(cx - 3.3, base - 34, cx + 3.3, base - 29.6, const Radius.circular(1)), _paint(_ink));
    c.drawRect(Rect.fromLTRB(cx - 1.1, base - 38.6, cx + 1.1, base - 34), _paint(_ink));
    c.drawRRect(RRect.fromLTRBR(cx - 6.8, base - 41.8, cx + 3.6, base - 38.4, const Radius.circular(1.5)), _paint(_ink));
    c.drawRect(Rect.fromLTRB(cx - 8.8, base - 41.2, cx - 6.4, base - 39.6), _paint(_ink));
    c.drawRRect(RRect.fromLTRBR(cx - 6.3, base - 27, cx - 4.6, base - 5, const Radius.circular(.9)), _paint(Colors.white.withValues(alpha: .5)));
    final label = RRect.fromLTRBR(cx - 4.6, base - 19, cx + 4.6, base - 8.5, const Radius.circular(1.3));
    c.drawRRect(label, _paint(_cream.withValues(alpha: .92)));
    c.drawRect(Rect.fromLTWH(cx - 3, base - 16, 5.2, .9), _paint(_ink.withValues(alpha: .5)));
    c.drawRect(Rect.fromLTWH(cx - 3, base - 14, 6, .9), _paint(_ink.withValues(alpha: .35)));
    c.drawCircle(Offset(cx, base - 11), 1.1, _paint(_teal));
  }

  void _dropper(Canvas c, double cx, double base) {
    _contact(c, cx + 1, base, 9);
    final body = RRect.fromLTRBR(cx - 7.6, base - 22, cx + 7.6, base, const Radius.circular(4.6));
    c.drawRRect(body, _grad(body.outerRect, const [Color(0xFF8CC1B2), Color(0xFFC6E4DA), Color(0xFF74AC9C)], begin: Alignment.centerLeft, end: Alignment.centerRight, stops: const [0, .45, 1]));
    c.drawRect(Rect.fromLTRB(cx - 3.6, base - 26.4, cx + 3.6, base - 21.4), _paint(const Color(0xFF74AC9C)));
    final collar = RRect.fromLTRBR(cx - 4.5, base - 30.4, cx + 4.5, base - 26, const Radius.circular(1.3));
    c.drawRRect(collar, _grad(collar.outerRect, const [_goldA, _goldB]));
    final bulb = RRect.fromLTRBR(cx - 2.8, base - 42, cx + 2.8, base - 30, const Radius.circular(2.8));
    c.drawRRect(bulb, _grad(bulb.outerRect, const [_inkMid, _ink], begin: Alignment.centerLeft, end: Alignment.centerRight));
    c.drawRRect(RRect.fromLTRBR(cx - 1.7, base - 40.6, cx - .7, base - 32, const Radius.circular(.5)), _paint(Colors.white.withValues(alpha: .35)));
    c.drawRRect(RRect.fromLTRBR(cx - 5.9, base - 19.5, cx - 4.4, base - 3.5, const Radius.circular(.8)), _paint(Colors.white.withValues(alpha: .5)));
    final label = RRect.fromLTRBR(cx - 5, base - 17, cx + 5, base - 6, const Radius.circular(1.3));
    c.drawRRect(label, _paint(_cream.withValues(alpha: .95)));
    c.drawRect(Rect.fromLTWH(cx - 3.4, base - 14, 5.6, .9), _paint(_ink.withValues(alpha: .5)));
    c.drawRect(Rect.fromLTWH(cx - 3.4, base - 12, 6.6, .9), _paint(_ink.withValues(alpha: .35)));
    c.drawRect(Rect.fromLTWH(cx - 3.4, base - 10, 4.2, .9), _paint(_ink.withValues(alpha: .25)));
  }

  void _jar(Canvas c, double cx, double base) {
    _contact(c, cx + 1.4, base, 12);
    final body = RRect.fromLTRBR(cx - 10, base - 11, cx + 10, base, const Radius.circular(3.4));
    c.drawRRect(body, _grad(body.outerRect, const [Color(0xFFE6DAC5), Colors.white, Color(0xFFF0E7D7), Color(0xFFDDCFB6)], begin: Alignment.centerLeft, end: Alignment.centerRight, stops: const [0, .3, .68, 1]));
    c.drawRect(Rect.fromLTRB(cx - 5.5, base - 5.6, cx + 5.5, base - 4.9), _paint(_teal.withValues(alpha: .7)));
    final lid = RRect.fromLTRBR(cx - 10.7, base - 17.6, cx + 10.7, base - 11.1, const Radius.circular(2.2));
    c.drawRRect(lid, _grad(lid.outerRect, const [_inkMid, Color(0xFF0F4F48), _ink], begin: Alignment.centerLeft, end: Alignment.centerRight));
    c.drawRRect(RRect.fromLTRBR(cx - 9, base - 17.1, cx + 9, base - 15.8, const Radius.circular(.7)), _paint(Colors.white.withValues(alpha: .22)));
  }

  @override
  void paintUnit(Canvas c) {
    final e = _iv(t.value, 0, .45);
    final rise = _iv(t.value, .1, .7);

    // Arka katman: güneş ve kemerler
    c.save();
    c.translate(delta * 13, 0);
    _group(c, e, () {
      final sunC = Offset(69, 32 + (1 - e) * 5);
      c.drawCircle(sunC, 9.4, _grad(Rect.fromCircle(center: sunC, radius: 9.4), const [Color(0xFFFAD0AE), Color(0xFFF2A07C)], begin: Alignment.topLeft, end: Alignment.bottomRight));
      final arch = _archPath(20, 80, 14, 82);
      c.drawPath(arch, _grad(const Rect.fromLTRB(20, 14, 80, 82), [Colors.white.withValues(alpha: night ? .09 : .62), Colors.white.withValues(alpha: night ? .02 : .12)]));
      final inner = _archPath(28, 72, 21, 82);
      c.drawPath(inner, _grad(const Rect.fromLTRB(28, 21, 72, 82), [Colors.white.withValues(alpha: night ? .06 : .30), Colors.white.withValues(alpha: 0)]));
    });
    c.restore();

    // Orta katman: podyum
    c.drawOval(Rect.fromCenter(center: const Offset(52, 91.5), width: 88, height: 9), _blur(Colors.black.withValues(alpha: night ? .45 : .17), 3));
    final bodyRect = Rect.fromCenter(center: const Offset(50, 88), width: 72, height: 13);
    final body = Path()
      ..moveTo(14, 74)
      ..lineTo(14, 88)
      ..arcTo(bodyRect, math.pi, -math.pi, false)
      ..lineTo(86, 74)
      ..close();
    c.drawPath(body, _grad(const Rect.fromLTRB(14, 74, 86, 94), const [Color(0xFFE5D9C4), Color(0xFFFBF7F0), Color(0xFFF1E8D8), Color(0xFFDDCFB6)], begin: Alignment.centerLeft, end: Alignment.centerRight, stops: const [0, .28, .66, 1]));
    final topRect = Rect.fromCenter(center: const Offset(50, 74), width: 72, height: 13);
    c.drawOval(topRect, Paint()..shader = const RadialGradient(center: Alignment(-.3, -.4), radius: 1.1, colors: [Colors.white, Color(0xFFF3EBDD)]).createShader(topRect));
    c.drawOval(topRect, Paint()..style = PaintingStyle.stroke..strokeWidth = .7..color = Colors.white.withValues(alpha: .8));

    // Zeytin dalı (podyumun arkasında)
    c.save();
    c.translate(delta * 4, 0);
    _group(c, rise, () {
      _sprig(c, from: const Offset(75, 73.5), to: const Offset(88, 45), bend: const Offset(90, 64), leaves: 7, leaf: 8.2, colors: const [Color(0xFF8CC1B2), Color(0xFF4E8C7E)]);
    });
    c.restore();

    // Ürünler (önce arkadakiler); yükselerek yerine otururlar
    c.save();
    c.translate(-delta * 7, 0);
    c.save();
    c.translate(0, (1 - _iv(t.value, .12, .6)) * -9);
    _group(c, _iv(t.value, .12, .5), () => _pump(c, 58.5, 71));
    c.restore();
    c.save();
    c.translate(0, (1 - _iv(t.value, .2, .68)) * -9);
    _group(c, _iv(t.value, .2, .58), () => _dropper(c, 38.5, 75.5));
    c.restore();
    c.save();
    c.translate(0, (1 - _iv(t.value, .3, .78)) * -9);
    _group(c, _iv(t.value, .3, .66), () {
      _jar(c, 63.5, 78);
      _contact(c, 31.5, 78.4, 5.5);
      final pebble = Rect.fromCenter(center: const Offset(31.5, 77.4), width: 8.8, height: 6.4);
      c.drawOval(pebble, _grad(pebble, const [Color(0xFFF7CDB9), Color(0xFFE59F85)], begin: Alignment.topLeft, end: Alignment.bottomRight));
      c.drawOval(Rect.fromCenter(center: const Offset(30, 76), width: 3, height: 1.7), _paint(Colors.white.withValues(alpha: .5)));
    });
    c.restore();
    c.restore();
  }
}

// ---------------------------------------------------------------------------------------------
// Sahne 3 — günlük halkalar
// ---------------------------------------------------------------------------------------------

class RingsArt extends StatelessWidget {
  const RingsArt({super.key, required this.active, required this.delta});

  final bool active;
  final double delta;

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    return ArtFrame(
      active: active,
      duration: const Duration(milliseconds: 2400),
      builder: (context, t, s) => Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: CustomPaint(painter: _RingsArtPainter(t, delta, Brand.ink, Brand.dark))),
          Positioned(
            left: s * .5 - 12,
            top: s * .42 - 12,
            child: AnimatedBuilder(
              animation: t,
              builder: (context, child) => Opacity(opacity: _iv(t.value, .4, .7), child: child),
              child: const SizedBox(width: 24, height: 24, child: Icon(LucideIcons.sun, size: 22, color: Color(0xFFE08A1E))),
            ),
          ),
          Positioned(left: s * (-.03 + delta * .10), top: s * .02, child: ArtTag(t: t, from: .55, icon: LucideIcons.check, iconColor: _teal, title: i18n.t('mobileLanding.tagMorning'), sub: i18n.t('mobileLanding.tagMorningSub'))),
          Positioned(right: s * (-.02 - delta * .10), top: s * .84, child: ArtTag(t: t, from: .7, icon: LucideIcons.bell, iconColor: const Color(0xFFE08A1E), title: i18n.t('mobileLanding.tagSpf'), sub: i18n.t('mobileLanding.tagSpfSub'))),
        ],
      ),
    );
  }
}

class _RingsArtPainter extends _UnitPainter {
  _RingsArtPainter(this.t, this.delta, this.ink, this.night) : super(t);

  final Animation<double> t;
  final double delta;
  final Color ink;
  final bool night;

  @override
  void paintUnit(Canvas c) {
    final e = _iv(t.value, 0, .4);
    const center = Offset(50, 42);

    // Arka katman: kadran işaretleri
    c.save();
    c.translate(delta * 12, 0);
    _group(c, e, () {
      c.drawCircle(center, 43.5 * (.92 + .08 * e), _paint(Colors.white.withValues(alpha: night ? .05 : .34)));
      for (var i = 0; i < 60; i++) {
        final a = i * 2 * math.pi / 60 - math.pi / 2;
        final major = i % 5 == 0;
        final r1 = 38.2, r2 = major ? 41.2 : 39.8;
        c.drawLine(
          center + Offset(math.cos(a), math.sin(a)) * r1,
          center + Offset(math.cos(a), math.sin(a)) * r2,
          Paint()
            ..strokeWidth = major ? .8 : .5
            ..strokeCap = StrokeCap.round
            ..color = ink.withValues(alpha: major ? .34 : .18),
        );
      }
    });
    c.restore();

    // Halkalar
    final rings = [
      (31.0, const Color(0xFF5EEAD4), const Color(0xFF0D9488), .84, 0.0),
      (23.8, const Color(0xFFFCD9A0), const Color(0xFFF0A02E), .68, .1),
      (16.6, const Color(0xFFF9BDAA), const Color(0xFFE8604A), .52, .2),
    ];
    for (final r in rings) {
      final rect = Rect.fromCircle(center: center, radius: r.$1);
      c.drawCircle(center, r.$1, Paint()..style = PaintingStyle.stroke..strokeWidth = 5.8..color = ink.withValues(alpha: night ? .16 : .07));
      final p = _iv(t.value, .06 + r.$5, .7 + r.$5);
      if (p <= 0) continue;
      final sweep = 2 * math.pi * r.$4 * p;
      c.drawArc(
        rect,
        -math.pi / 2,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5.8
          ..strokeCap = StrokeCap.round
          // Kuyruk koyu, uç parlak (Apple halkaları gibi); başlangıç yuvarlağı koyu kalsın diye gradyan başa sarılır.
          ..shader = SweepGradient(
            startAngle: 0,
            endAngle: 2 * math.pi,
            colors: [r.$3, r.$2, r.$2, r.$3, r.$3],
            stops: [0, r.$4 * p, math.min(.95, r.$4 * p + .03), .96, 1],
            transform: const GradientRotation(-math.pi / 2),
          ).createShader(rect),
      );
    }

    // Merkez
    c.save();
    c.translate(-delta * 6, 0);
    final disc = _iv(t.value, .3, .6, Curves.easeOutBack);
    c.drawCircle(center.translate(0, 1.2), 9.6 * disc, _blur(Colors.black.withValues(alpha: night ? .4 : .16), 1.6));
    c.drawCircle(center, 9.6 * disc, _paint(night ? const Color(0xFF16332F) : Colors.white));
    c.restore();
  }
}

// ---------------------------------------------------------------------------------------------
// Arka plan: yaprak gölgeleri
// ---------------------------------------------------------------------------------------------

/// Zemine vuran yumuşak yaprak gölgeleri (rüzgârda hafifçe salınır). Bir kez çizilir, yalnızca döndürülür.
class DappledLeaves extends StatefulWidget {
  const DappledLeaves({super.key});

  @override
  State<DappledLeaves> createState() => _DappledLeavesState();
}

class _DappledLeavesState extends State<DappledLeaves> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 11));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          final v = Curves.easeInOut.transform(_c.value) - .5;
          return Transform.rotate(angle: v * .05, alignment: Alignment.topRight, child: Transform.translate(offset: Offset(v * 8, v * 4), child: child));
        },
        child: RepaintBoundary(child: CustomPaint(painter: _DapplePainter(Brand.dark), size: Size.infinite)),
      ),
    );
  }
}

class _DapplePainter extends CustomPainter {
  _DapplePainter(this.night);

  final bool night;

  @override
  void paint(Canvas canvas, Size size) {
    final color = night ? Colors.white.withValues(alpha: .05) : const Color(0xFF0B3D38).withValues(alpha: .10);
    final w = size.width;
    final h = size.height;
    final blur = _blur(color, 7);

    void spray(Offset from, Offset to, Offset bend, double leaf, int n) {
      final path = Path()
        ..moveTo(from.dx, from.dy)
        ..quadraticBezierTo(bend.dx, bend.dy, to.dx, to.dy);
      final m = path.computeMetrics().first;
      canvas.drawPath(path, Paint()..style = PaintingStyle.stroke..strokeWidth = 2.2..strokeCap = StrokeCap.round..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6)..color = color);
      for (var i = 0; i < n; i++) {
        final t = (i + 1) / (n + .5);
        final tan = m.getTangentForOffset(m.length * t);
        if (tan == null) continue;
        for (final side in const [-1.0, 1.0]) {
          if (i.isOdd && side > 0 && i % 3 == 0) continue;
          canvas.save();
          canvas.translate(tan.position.dx, tan.position.dy);
          canvas.rotate(-tan.angle + side * (.8 + .1 * (i % 3)));
          final size = leaf * (1.05 - .45 * t);
          canvas.drawPath(_leafPath(size, size * .36), blur);
          canvas.restore();
        }
      }
    }

    spray(Offset(w * 1.06, -h * .02), Offset(w * .46, h * .30), Offset(w * .86, h * .02), w * .26, 6);
    spray(Offset(w * 1.04, h * .26), Offset(w * .68, h * .50), Offset(w * .98, h * .42), w * .2, 4);
    spray(Offset(-w * .06, h * .66), Offset(w * .22, h * .38), Offset(w * .02, h * .46), w * .2, 4);
  }

  @override
  bool shouldRepaint(covariant _DapplePainter old) => old.night != night;
}
