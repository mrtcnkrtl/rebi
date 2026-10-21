import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'motion.dart';

// Karşılamanın kahraman illüstrasyonu: podyum üstünde ürünler. 100×100'lük birim tuvalde çizilir, sol üstten gelen tek bir
// ışık yönü ve sınırlı bir palet kullanır. Girişte ürünler yerine süzülür; sonra çok yavaş, neredeyse fark edilmez bir
// nefes alma hareketi vardır (güneş diski salınır, zeytin dalı sallanır). Etiket, kart ya da yazı yoktur.
//
// Zemin açık ve koyu temada da derin orman yeşilidir (açılış ekranıyla aynı), bu yüzden çizim her zaman bu zemine göre
// ("gece" paleti: şeffaf beyaz hale, koyu gölge) çizilir.

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
// Sahne 2 — podyum üstünde ürünler
// ---------------------------------------------------------------------------------------------

class HeroArt extends StatefulWidget {
  const HeroArt({super.key});

  @override
  State<HeroArt> createState() => _HeroArtState();
}

class _HeroArtState extends State<HeroArt> with SingleTickerProviderStateMixin {
  late final AnimationController _idle = AnimationController(vsync: this, duration: const Duration(seconds: 8));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _idle.stop();
    } else if (!_idle.isAnimating) {
      _idle.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _idle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Süsleme: ekran okuyuculardan gizli.
    return ExcludeSemantics(
      child: ArtFrame(
        active: true,
        duration: const Duration(milliseconds: 2400),
        builder: (context, t, s) => CustomPaint(painter: _PodiumPainter(t, _idle)),
      ),
    );
  }
}

class _PodiumPainter extends _UnitPainter {
  _PodiumPainter(this.t, this.idle) : super(Listenable.merge([t, idle]));

  final Animation<double> t;

  /// 0→1→0 yavaş salınım (8 sn): güneş diski ve zeytin dalı.
  final Animation<double> idle;

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
    // -1..1 yumuşak salınım (easeInOut): yalnızca giriş bittikten sonra belirginleşir.
    final sway = (Curves.easeInOut.transform(idle.value) * 2 - 1) * _iv(t.value, .7, 1);

    // Arka katman: güneş ve kemerler
    c.save();
    _group(c, e, () {
      final sunC = Offset(69, 32 + (1 - e) * 5 + sway * 1.3);
      c.drawCircle(sunC, 9.4, _grad(Rect.fromCircle(center: sunC, radius: 9.4), const [Color(0xFFFAD0AE), Color(0xFFF2A07C)], begin: Alignment.topLeft, end: Alignment.bottomRight));
      final arch = _archPath(20, 80, 14, 82);
      c.drawPath(arch, _grad(const Rect.fromLTRB(20, 14, 80, 82), [Colors.white.withValues(alpha: .09), Colors.white.withValues(alpha: .02)]));
      final inner = _archPath(28, 72, 21, 82);
      c.drawPath(inner, _grad(const Rect.fromLTRB(28, 21, 72, 82), [Colors.white.withValues(alpha: .06), Colors.white.withValues(alpha: 0)]));
    });
    c.restore();

    // Orta katman: podyum
    c.drawOval(Rect.fromCenter(center: const Offset(52, 91.5), width: 88, height: 9), _blur(Colors.black.withValues(alpha: .45), 3));
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

    // Zeytin dalı (podyumun arkasında): tabanından hafifçe sallanır
    c.save();
    c.translate(75, 73.5);
    c.rotate(sway * .018);
    c.translate(-75, -73.5);
    _group(c, rise, () {
      _sprig(c, from: const Offset(75, 73.5), to: const Offset(88, 45), bend: const Offset(90, 64), leaves: 7, leaf: 8.2, colors: const [Color(0xFF8CC1B2), Color(0xFF4E8C7E)]);
    });
    c.restore();

    // Ürünler (önce arkadakiler); yükselerek yerine otururlar
    c.save();
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

