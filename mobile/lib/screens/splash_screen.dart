import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../core/i18n.dart';
import '../ui/brand/brand_mark.dart';
import '../ui/brand/motion.dart';
import '../ui/brand/palette.dart';
import '../ui/tw.dart';

/// Açılış animasyonu: koyu yeşil zeminde "R" harfi çizilir, ardından marka adı ve slogan belirir,
/// sonra karşılamaya geçilir. Android/iOS'un yerel açılış ekranı da aynı renktedir (beyaz parlama olmaz).
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );
  bool _left = false;
  bool _reduced = false;

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) _leave();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.isAnimating || _c.isCompleted) return;
    _reduced = reduceMotion(context);
    if (_reduced) _c.duration = const Duration(milliseconds: 700);
    _c.forward();
  }

  void _leave() {
    if (_left || !mounted) return;
    _left = true;
    context.go('/');
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  double _iv(double a, double b, [Curve curve = Curves.easeOutCubic]) =>
      _reduced ? 1 : curve.transform(Interval(a, b).transform(_c.value));

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Brand.forestDeep,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: Brand.forestDeep,
        resizeToAvoidBottomInset: false,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _leave,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -.25),
                radius: 1.05,
                colors: [Color(0xFF0E4943), Brand.forest, Color(0xFF083430)],
                stops: [0, .55, 1],
              ),
            ),
            child: SizedBox.expand(
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) {
                  final tile = _iv(0, .24);
                  final draw = _iv(.1, .52, Curves.easeInOutCubic);
                  final spark = _iv(.5, .66, Curves.easeOutBack);
                  final word = _iv(.44, .72);
                  final tag = _iv(.62, .86);
                  final pulse = _reduced ? 0.0 : _iv(.46, .95, Curves.easeOut);
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      Align(
                        alignment: const Alignment(0, -.1),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Stack(
                              alignment: Alignment.center,
                              clipBehavior: Clip.none,
                              children: [
                                // Harf tamamlandığında dışa yayılan ince halka
                                CustomPaint(
                                  size: const Size(104, 104),
                                  painter: _PulsePainter(pulse),
                                ),
                                Opacity(
                                  opacity: tile,
                                  child: Transform.scale(
                                    scale: .82 + .18 * tile,
                                    child: BrandMark(
                                      size: 104,
                                      progress: draw,
                                      sparkle: spark,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 30),
                            Opacity(
                              opacity: word,
                              child: Transform.translate(
                                offset: Offset(0, (1 - word) * 14),
                                child: Text(
                                  'Rebi',
                                  style: Brand.serif(
                                    54,
                                    weight: 600,
                                    color: const Color(0xFFF7F3EC),
                                    ls: -1.6 + (1 - word) * 6,
                                    h: 1,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Opacity(
                              opacity: tag,
                              child: Transform.translate(
                                offset: Offset(0, (1 - tag) * 8),
                                child: Text(
                                  i18n.t('landing.heroBadge'),
                                  style: tx(
                                    14,
                                    w: 5,
                                    c: const Color(0xFFF7F3EC)
                                        .withValues(alpha: .66),
                                    ls: .3,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PulsePainter extends CustomPainter {
  _PulsePainter(this.p);

  final double p;

  @override
  void paint(Canvas canvas, Size size) {
    if (p <= 0 || p >= 1) return;
    final c = size.center(Offset.zero);
    canvas.drawCircle(
      c,
      52 + math.min(1.0, p) * 96,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = Brand.teal.withValues(alpha: .38 * (1 - p)),
    );
  }

  @override
  bool shouldRepaint(covariant _PulsePainter old) => old.p != p;
}
