import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../core/i18n.dart';
import '../ui/brand/brand_caps.dart';
import '../ui/brand/brand_mark.dart';
import '../ui/brand/motion.dart';
import '../ui/brand/palette.dart';
import '../ui/tw.dart';

/// Açılış: yerel açılış ekranıyla aynı yerde, aynı boyutta duran marka karosu yukarı süzülür, altında "Rebi"
/// yazısı soldan sağa açılır, ince bir çizgi çekilir ve slogan belirir; sonra karşılamaya geçilir.
/// Zemin yerel açılışla aynı düz orman yeşilidir (ilk karede dikiş yok) ve yavaşça hafif bir ışık havuzu alır.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));
  bool _left = false;
  bool _reduced = false;

  // Yerleşim (dp): karo, yazı, çizgi ve slogan dikey olarak tek blok oluşturur. Başlangıçta karo ekranın tam
  // ortasındadır (yerel açılışla aynı); blok kurulurken karo yukarı çıkar, blok ekranın ortasında kalır.
  static const _gapTileWord = 26.0;
  static const _wordH = 54.0;
  static const _gapWordRule = 16.0;
  static const _gapRuleTag = 16.0;
  static const _tagH = 14.0;
  static const _blockH = BrandMark.launchSize + _gapTileWord + _wordH + _gapWordRule + 1 + _gapRuleTag + _tagH;
  static const _lift = (_blockH - BrandMark.launchSize) / 2;

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
    final lang = i18n.lang;
    final tagline = brandCaps(i18n.t('landing.heroBadge'), lang);
    const cream = Brand.cream;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Brand.forest,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: Brand.forest,
        resizeToAvoidBottomInset: false,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _leave,
          child: Semantics(
            label: 'Rebi. ${i18n.t('landing.heroBadge')}',
            child: ExcludeSemantics(
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) {
                  final glow = _iv(0, .4, Curves.easeOut);
                  final lift = _iv(.08, .36, Curves.easeInOutCubic);
                  final word = _iv(.15, .45, Curves.easeInOutCubic);
                  final rule = _iv(.38, .54);
                  final tag = _iv(.44, .64);
                  final twinkle = _reduced ? 0.0 : _iv(.48, .68, Curves.easeInOut);
                  final bump = twinkle <= 0 ? 0.0 : (1 - (2 * twinkle - 1).abs());
                  return DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(0, -.1),
                        radius: 1.0,
                        colors: [
                          Color.lerp(Brand.forest, const Color(0xFF0E4943), glow)!,
                          Brand.forest,
                          Color.lerp(Brand.forest, Brand.forestDeep, glow * .75)!,
                        ],
                        stops: const [0, .55, 1],
                      ),
                    ),
                    child: SizedBox.expand(
                      child: Center(
                        child: SizedBox(
                          width: 320,
                          height: _blockH,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Positioned(
                                top: _lift * (1 - lift),
                                left: 0,
                                right: 0,
                                child: Center(
                                  child: BrandMark(size: BrandMark.launchSize, sparkle: 1 + .5 * bump),
                                ),
                              ),
                              Positioned(
                                top: BrandMark.launchSize + _gapTileWord,
                                left: 0,
                                right: 0,
                                height: _wordH,
                                child: Center(
                                  child: _Wordmark(
                                    progress: word,
                                    style: Brand.serif(54, weight: 600, color: cream, ls: -1.6, h: 1),
                                  ),
                                ),
                              ),
                              Positioned(
                                top: BrandMark.launchSize + _gapTileWord + _wordH + _gapWordRule,
                                left: 0,
                                right: 0,
                                height: 1,
                                child: Center(
                                  child: Container(width: 32 * rule, height: 1, color: cream.withValues(alpha: .4)),
                                ),
                              ),
                              Positioned(
                                top: _blockH - _tagH,
                                left: -20,
                                right: -20,
                                height: _tagH,
                                child: Opacity(
                                  opacity: tag,
                                  child: Transform.translate(
                                    offset: Offset(0, (1 - tag) * 6),
                                    child: Text(
                                      tagline,
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      overflow: TextOverflow.visible,
                                      softWrap: false,
                                      style: tx(11.5, w: 6, c: cream.withValues(alpha: .8), ls: brandTracking(lang, 2.4), h: 1.2),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
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

/// "Rebi" yazısı harf harf, soldan sağa süzülerek belirir; [progress] 0→1. Katman filtresi yoktur (her harf kendi
/// saydamlığı ve kaymasıyla çizilir), bitince tek bir yazı gibi durur.
class _Wordmark extends StatelessWidget {
  const _Wordmark({required this.progress, required this.style});

  final double progress;
  final TextStyle style;

  static const _letters = ['R', 'e', 'b', 'i'];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      textBaseline: TextBaseline.alphabetic,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      children: [
        for (var i = 0; i < _letters.length; i++)
          Builder(
            builder: (context) {
              final p = Curves.easeOutCubic.transform(Interval(i * .17, i * .17 + .49).transform(progress));
              return Opacity(
                opacity: p,
                child: Transform.translate(offset: Offset(0, (1 - p) * 14), child: Text(_letters[i], style: style)),
              );
            },
          ),
      ],
    );
  }
}
