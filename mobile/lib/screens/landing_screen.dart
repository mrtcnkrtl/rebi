import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../core/i18n.dart';
import '../state/auth_controller.dart';
import '../ui/tw.dart';
import '../ui/widgets/common.dart';

/// Tanıtım / giriş sayfası (web: `pages/Landing.jsx`).
class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final authed = context.watch<AuthController>().user != null;
    const nextAnalyze = '/dashboard/analyze';
    final rebiHref = authed ? '/dashboard/chat' : '/rebi';
    final routineHref = authed ? nextAnalyze : '/auth?next=${Uri.encodeComponent(nextAnalyze)}';
    final wide = MediaQuery.of(context).size.width >= 768;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Tw.warm50, Tw.surface, Tw.teal50.withValues(alpha: .3)],
        ),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Hero(
              wide: wide,
              onRebi: () => context.go(rebiHref),
              onRoutine: () => context.go(routineHref),
            ),
            const SizedBox(height: 32),
            _Differences(wide: wide),
            _PlusBlock(onCta: () => context.go(authed ? '/dashboard/subscribe' : '/auth')),
            _Features(wide: wide),
            _HowItWorks(onCta: () => context.go(authed ? '/dashboard/analyze' : '/auth')),
            _Footer(i18n: i18n),
          ],
        ),
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({required this.size, required this.color, this.radius});

  final double size;
  final Color color;
  final double? radius;

  @override
  Widget build(BuildContext context) => ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color,
            shape: radius == null ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: radius == null ? null : BorderRadius.circular(radius!),
          ),
        ),
      );
}

/// Video kapalıyken gösterilen hareketli renk ağı (web: `HeroBackgroundVideo` + `hero-mesh-shift`).
class _AnimatedMesh extends StatefulWidget {
  const _AnimatedMesh();

  @override
  State<_AnimatedMesh> createState() => _AnimatedMeshState();
}

class _AnimatedMeshState extends State<_AnimatedMesh> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 18))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = reduce ? 0.0 : (1 - math.cos(_c.value * 2 * math.pi)) / 2;
        return Opacity(
          opacity: reduce ? .55 : .55 + .35 * t,
          child: Transform.translate(
            offset: Offset(t * 8, -t * 4),
            child: Transform.scale(scale: 1.1 * (1 + .08 * t), child: child),
          ),
        );
      },
      child: const Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(-.6, -.6),
                radius: .9,
                colors: [Color(0x592DD4BF), Color(0x002DD4BF)],
                stops: [0, .5],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(.7, -.4),
                radius: .8,
                colors: [Color(0x47A78BFA), Color(0x00A78BFA)],
                stops: [0, .45],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, 1),
                radius: 1,
                colors: [Color(0x380EA5E9), Color(0x000EA5E9)],
                stops: [0, .55],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Hero altındaki yavaş dalga (web: SVG `<animate>`).
class _Wave extends StatefulWidget {
  const _Wave();

  @override
  State<_Wave> createState() => _WaveState();
}

class _WaveState extends State<_Wave> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = reduce ? 0.0 : (1 - math.cos(_c.value * 2 * math.pi)) / 2;
        return CustomPaint(painter: _WavePainter(t), size: const Size(double.infinity, 80));
      },
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter(this.t);

  final double t;

  double _l(double a, double b) => a + (b - a) * t;

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 1440;
    final sy = size.height / 120;
    Offset p(double x, double ya, double yb) => Offset(x * sx, _l(ya, yb) * sy);
    final path = Path()..moveTo(0, _l(64, 70) * sy);
    final a = p(80, 58.7, 80);
    path.lineTo(a.dx, a.dy);
    final c1 = [p(160, 53, 90), p(320, 43, 110), p(480, 48, 96)];
    path.cubicTo(c1[0].dx, c1[0].dy, c1[1].dx, c1[1].dy, c1[2].dx, c1[2].dy);
    final c2 = [p(640, 53, 82), p(800, 75, 34), p(960, 80, 26)];
    path.cubicTo(c2[0].dx, c2[0].dy, c2[1].dx, c2[1].dy, c2[2].dx, c2[2].dy);
    final c3 = [p(1120, 85, 18), p(1280, 75, 50), p(1360, 69.3, 66)];
    path.cubicTo(c3[0].dx, c3[0].dy, c3[1].dx, c3[1].dy, c3[2].dx, c3[2].dy);
    final e = p(1440, 64, 82);
    path
      ..lineTo(e.dx, e.dy)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0x1F14B8A6));
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) => old.t != t;
}

class _Hero extends StatelessWidget {
  const _Hero({required this.wide, required this.onRebi, required this.onRoutine});

  final bool wide;
  final VoidCallback onRebi;
  final VoidCallback onRoutine;

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final w = MediaQuery.of(context).size.width;
    final cards = [
      _ChoiceCard(
        onTap: onRebi,
        border: Tw.teal200.withValues(alpha: .9),
        bg: Tw.surface.withValues(alpha: .75),
        glow: Tw.teal300.withValues(alpha: .3),
        glowAtTopRight: true,
        icon: _SolidIcon(icon: LucideIcons.messageCircle, colors: [Tw.teal600, Tw.teal600]),
        title: i18n.t('appName'),
        desc: i18n.t('landing.choiceRebiDesc'),
        arrowColor: Tw.teal700,
      ),
      _ChoiceCard(
        onTap: onRoutine,
        border: Tw.gray200,
        bg: Tw.surface.withValues(alpha: .9),
        glow: const Color(0xFFD8B4FE).withValues(alpha: .2),
        glowAtTopRight: false,
        icon: _SolidIcon(icon: LucideIcons.sparkles, colors: [Tw.teal500, Tw.emerald500]),
        title: i18n.t('landing.choiceRoutineName'),
        desc: i18n.t('landing.choiceRoutineDesc'),
        arrowColor: Tw.gray700,
      ),
    ];

    return Stack(
      clipBehavior: Clip.none,
      children: [
        const Positioned.fill(child: ClipRect(child: _AnimatedMesh())),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Tw.surface.withValues(alpha: .55), Tw.surface.withValues(alpha: .25), Tw.teal50.withValues(alpha: .4)],
              ),
            ),
          ),
        ),
        Positioned(top: 40, right: -w * .05, child: _Blob(size: math.min(w * .9, 520), color: Tw.teal200.withValues(alpha: .25))),
        Positioned(top: -64, left: 32, child: Transform.rotate(angle: .2, child: _Blob(size: 160, color: Tw.fuchsia300.withValues(alpha: .25), radius: 40))),
        Positioned.fill(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Transform.translate(offset: const Offset(0, 40), child: const Opacity(opacity: .7, child: _Wave())),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(16, wide ? 40 : 28, 16, wide ? 40 : 32),
          child: CenteredBox(
            maxWidth: 1152,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Tw.teal50,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Tw.teal100),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.sparkles, size: 16, color: Tw.teal700),
                      const SizedBox(width: 8),
                      Flexible(child: Text(i18n.t('landing.heroBadge'), style: tx(14, w: 5, c: Tw.teal700))),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  i18n.t('landing.choiceTitle'),
                  textAlign: TextAlign.center,
                  style: tx(wide ? 60 : 36, w: 7, h: 1.05, ls: -.8),
                ),
                const SizedBox(height: 20),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 672),
                  child: Text(i18n.t('landing.choiceSubtitle'), textAlign: TextAlign.center, style: tx(wide ? 20 : 18, c: Tw.gray700)),
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 576),
                  child: const AiDisclaimer(textAlign: TextAlign.center),
                ),
                const SizedBox(height: 24),
                if (wide)
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [Expanded(child: cards[0]), const SizedBox(width: 32), Expanded(child: cards[1])],
                    ),
                  )
                else ...[
                  cards[0],
                  const SizedBox(height: 20),
                  cards[1],
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SolidIcon extends StatelessWidget {
  const _SolidIcon({required this.icon, required this.colors});

  final IconData icon;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) => Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
          boxShadow: [BoxShadow(color: colors.last.withValues(alpha: .25), blurRadius: 25, offset: const Offset(0, 12))],
        ),
        child: Icon(icon, size: 28, color: Colors.white),
      );
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.onTap,
    required this.border,
    required this.bg,
    required this.glow,
    required this.glowAtTopRight,
    required this.icon,
    required this.title,
    required this.desc,
    required this.arrowColor,
  });

  final VoidCallback onTap;
  final Color border;
  final Color bg;
  final Color glow;
  final bool glowAtTopRight;
  final Widget icon;
  final String title;
  final String desc;
  final Color arrowColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 178),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: border, width: 2),
        boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 6, offset: Offset(0, 4))],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            children: [
              Positioned(
                top: glowAtTopRight ? -64 : null,
                right: glowAtTopRight ? -64 : null,
                bottom: glowAtTopRight ? null : -64,
                left: glowAtTopRight ? null : -64,
                child: _Blob(size: 224, color: glow),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    icon,
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: tx(20, w: 9)),
                          const SizedBox(height: 8),
                          Text(desc, style: tx(16, c: Tw.gray600, h: relaxed)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Padding(padding: const EdgeInsets.only(top: 4), child: Icon(LucideIcons.arrowRight, size: 28, color: arrowColor)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SchemaRow extends StatelessWidget {
  const _SchemaRow({required this.icon, required this.iconColor, required this.text, this.us = false});

  final IconData icon;
  final Color iconColor;
  final String text;
  final bool us;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: us ? Tw.surface.withValues(alpha: .9) : Tw.gray50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: us ? Tw.teal200.withValues(alpha: .7) : Tw.gray100),
          boxShadow: us ? const [BoxShadow(color: Color(0x0D000000), blurRadius: 2, offset: Offset(0, 1))] : null,
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: iconColor),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: tx(14, c: us ? Tw.gray900 : Tw.gray800))),
          ],
        ),
      );
}

class _Differences extends StatelessWidget {
  const _Differences({required this.wide});

  final bool wide;

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final others = Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Tw.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Tw.gray200),
        boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 2, offset: Offset(0, 1))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(i18n.t('landing.differenceSchemaOthers'), style: tx(14, w: 7, c: Tw.gray700)),
          const SizedBox(height: 16),
          _SchemaRow(icon: LucideIcons.camera, iconColor: Tw.gray600, text: i18n.t('landing.differenceSchemaOthersS1')),
          const SizedBox(height: 10),
          _SchemaRow(icon: LucideIcons.triangleAlert, iconColor: Tw.amber600, text: i18n.t('landing.differenceSchemaOthersS2')),
          const SizedBox(height: 10),
          _SchemaRow(icon: LucideIcons.shield, iconColor: Tw.gray600, text: i18n.t('landing.differenceSchemaOthersS3')),
        ],
      ),
    );
    final us = Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Tw.teal300, width: 2),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Tw.teal50, Tw.emerald50.withValues(alpha: .7), Tw.cyan50],
        ),
      ),
      child: Stack(
        children: [
          Positioned(top: -40, right: -40, child: _Blob(size: 176, color: Tw.teal300.withValues(alpha: .25))),
          Positioned(bottom: -48, left: -48, child: _Blob(size: 224, color: Tw.emerald300.withValues(alpha: .2))),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(i18n.t('landing.differenceSchemaUs'), style: tx(14, w: 7, c: Tw.teal900)),
                const SizedBox(height: 16),
                _SchemaRow(icon: LucideIcons.brain, iconColor: Tw.teal700, text: i18n.t('landing.differenceSchemaUsS1'), us: true),
                const SizedBox(height: 10),
                _SchemaRow(
                    icon: LucideIcons.clipboardCheck, iconColor: Tw.teal700, text: i18n.t('landing.differenceSchemaUsS2'), us: true),
                const SizedBox(height: 10),
                _SchemaRow(icon: LucideIcons.sparkles, iconColor: Tw.teal700, text: i18n.t('landing.differenceSchemaUsS3'), us: true),
              ],
            ),
          ),
        ],
      ),
    );

    final screenW = MediaQuery.of(context).size.width;
    final cardW = math.min(screenW * .86, 360.0);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: CenteredBox(
        maxWidth: 1152,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(i18n.t('landing.differenceTitle'), style: tx(wide ? 24 : 20, w: 9)),
                  const SizedBox(height: 4),
                  Text(i18n.t('landing.differenceSubtitle'), style: tx(14, c: Tw.gray600)),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (wide)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: others),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Center(
                          child: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              gradient: LinearGradient(colors: [Tw.teal600, Tw.emerald500]),
                            ),
                            child: const Icon(LucideIcons.arrowRight, color: Colors.white),
                          ),
                        ),
                      ),
                      Expanded(child: us),
                    ],
                  ),
                ),
              )
            else ...[
              // Web: `snap-x` yatay kaydırma. Yükseklik içerikten gelir (büyük yazı boyutunda taşmaz).
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: _SnapPhysics(itemExtent: cardW + 12),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(width: cardW, child: others),
                      const SizedBox(width: 12),
                      SizedBox(width: cardW, child: us),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Text('Kaydırarak devam et.', style: tx(11, c: Tw.gray500)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PlusBlock extends StatelessWidget {
  const _PlusBlock({required this.onCta});

  final VoidCallback onCta;

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final wide = MediaQuery.of(context).size.width >= 768;
    final items = [
      (LucideIcons.messageCircle, 'landing.plus.unlimitedAiTitle', 'landing.plus.unlimitedAiDesc', [const Color(0xFF8B5CF6), Tw.fuchsia500]),
      (LucideIcons.palette, 'landing.plus.premiumThemesTitle', 'landing.plus.premiumThemesDesc', [Tw.cyan500, const Color(0xFF2563EB)]),
      (LucideIcons.clipboardCheck, 'landing.plus.deepTrackingTitle', 'landing.plus.deepTrackingDesc', [Tw.amber500, Tw.orange600]),
    ];
    final cards = [
      for (final it in items)
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .05),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: .1)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SolidIcon(icon: it.$1, colors: it.$4),
              const SizedBox(height: 20),
              Text(i18n.t(it.$2), style: tx(20, w: 7, c: Colors.white)),
              const SizedBox(height: 8),
              Text(i18n.t(it.$3), style: tx(14, c: Tw.violet100.withValues(alpha: .85), h: relaxed)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(LucideIcons.lock, size: 14, color: Tw.amber200.withValues(alpha: .9)),
                  const SizedBox(width: 6),
                  Expanded(child: Text(i18n.t('landing.plusUnlockHint'), style: tx(12, w: 6, c: Tw.amber200.withValues(alpha: .9)))),
                ],
              ),
            ],
          ),
        ),
    ];
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Tw.fixedSlate900, Tw.fixedViolet950.withValues(alpha: .95), Tw.fixedSlate900],
        ),
      ),
      child: Stack(
        children: [
          const Positioned.fill(
            child: Opacity(
              opacity: .4,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(-.6, -.4),
                    radius: .9,
                    colors: [Color(0x59A78BFA), Color(0x00A78BFA)],
                    stops: [0, .45],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
            child: CenteredBox(
              maxWidth: 1152,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .1),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.white.withValues(alpha: .15)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LucideIcons.crown, size: 16, color: Tw.amber300),
                          const SizedBox(width: 8),
                          Text(i18n.t('landing.plusBadge'), style: tx(14, w: 5, c: Tw.amber200)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(i18n.t('landing.plusTitle'), textAlign: TextAlign.center, style: tx(wide ? 36 : 30, w: 7, c: Colors.white, ls: -.5)),
                  const SizedBox(height: 16),
                  Text(i18n.t('landing.plusDesc'),
                      textAlign: TextAlign.center, style: tx(18, c: Tw.violet200.withValues(alpha: .9), h: relaxed)),
                  const SizedBox(height: 48),
                  if (wide)
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < cards.length; i++) ...[
                            if (i > 0) const SizedBox(width: 24),
                            Expanded(child: cards[i]),
                          ],
                        ],
                      ),
                    )
                  else
                    for (var i = 0; i < cards.length; i++) ...[if (i > 0) const SizedBox(height: 20), cards[i]],
                  const SizedBox(height: 40),
                  Center(
                    child: Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      elevation: 8,
                      shadowColor: Colors.black38,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: onCta,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(LucideIcons.crown, size: 20, color: Tw.amber600),
                              const SizedBox(width: 8),
                              Flexible(child: Text(i18n.t('landing.plusCta'), style: tx(16, w: 7, c: Tw.fixedViolet950))),
                              const SizedBox(width: 8),
                              Icon(LucideIcons.arrowRight, size: 20, color: Tw.fixedViolet950),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Features extends StatelessWidget {
  const _Features({required this.wide});

  final bool wide;

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final features = [
      (LucideIcons.camera, 'landing.features.cameraTitle', 'landing.features.cameraDesc', Tw.pink50, Tw.pink500),
      (LucideIcons.brain, 'landing.features.holisticTitle', 'landing.features.holisticDesc', Tw.purple50, const Color(0xFF8B5CF6)),
      (LucideIcons.cloudSun, 'landing.features.weatherTitle', 'landing.features.weatherDesc', Tw.blue50, Tw.blue500),
    ];
    final cards = [
      for (final f in features)
        RCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(color: f.$4, borderRadius: BorderRadius.circular(16)),
                child: Icon(f.$1, size: 28, color: f.$5),
              ),
              const SizedBox(height: 20),
              Text(i18n.t(f.$2), style: tx(20, w: 7)),
              const SizedBox(height: 8),
              Text(i18n.t(f.$3), style: tx(16, c: Tw.gray500, h: relaxed)),
            ],
          ),
        ),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 48),
      child: CenteredBox(
        maxWidth: 1152,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(i18n.t('landing.featuresTitle'), textAlign: TextAlign.center, style: tx(wide ? 36 : 30, w: 7)),
            const SizedBox(height: 16),
            Text(i18n.t('landing.featuresSubtitle'), textAlign: TextAlign.center, style: tx(18, c: Tw.gray500)),
            const SizedBox(height: 16),
            Text(i18n.t('landing.disclaimer'), textAlign: TextAlign.center, style: tx(14, c: Tw.gray600, h: relaxed)),
            const SizedBox(height: 40),
            if (wide)
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < cards.length; i++) ...[
                      if (i > 0) const SizedBox(width: 32),
                      Expanded(child: cards[i]),
                    ],
                  ],
                ),
              )
            else
              for (var i = 0; i < cards.length; i++) ...[if (i > 0) const SizedBox(height: 24), cards[i]],
          ],
        ),
      ),
    );
  }
}

class _HowItWorks extends StatelessWidget {
  const _HowItWorks({required this.onCta});

  final VoidCallback onCta;

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final steps = [
      ('01', 'landing.steps.s1Title', 'landing.steps.s1Desc'),
      ('02', 'landing.steps.s2Title', 'landing.steps.s2Desc'),
      ('03', 'landing.steps.s3Title', 'landing.steps.s3Desc'),
    ];
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Tw.surface, Tw.teal50.withValues(alpha: .5)],
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 48),
      child: CenteredBox(
        maxWidth: 896,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(i18n.t('landing.howItWorksTitle'), textAlign: TextAlign.center, style: tx(30, w: 7)),
            const SizedBox(height: 40),
            for (final s in steps) ...[
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Tw.surface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Tw.gray100),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Tw.teal500, Tw.teal600],
                        ),
                        boxShadow: [BoxShadow(color: Tw.teal500.withValues(alpha: .2), blurRadius: 15, offset: const Offset(0, 8))],
                      ),
                      child: Text(s.$1, style: tx(18, w: 7, c: Colors.white)),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(i18n.t(s.$2), style: tx(20, w: 7)),
                          const SizedBox(height: 4),
                          Text(i18n.t(s.$3), style: tx(16, c: Tw.gray500)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Padding(padding: EdgeInsets.only(top: 4), child: Icon(LucideIcons.chevronRight, size: 20, color: Tw.gray300)),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
            const SizedBox(height: 16),
            Center(
              child: PrimaryButton(
                onPressed: onCta,
                label: i18n.t('landing.ctaStartNow'),
                trailingIcon: LucideIcons.arrowRight,
                fontSize: 18,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.i18n});

  final I18n i18n;

  @override
  Widget build(BuildContext context) {
    final link = tx(12, c: Tw.gray400).copyWith(decoration: TextDecoration.underline, decorationColor: Tw.gray400);
    return Container(
      decoration: BoxDecoration(border: Border(top: BorderSide(color: Tw.gray100))),
      padding: EdgeInsets.fromLTRB(16, 40, 16, 40 + MediaQuery.of(context).padding.bottom),
      child: Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Tw.teal500, Tw.teal600]),
                ),
                child: const Icon(LucideIcons.leaf, size: 16, color: Colors.white),
              ),
              const SizedBox(width: 8),
              Text('Rebi', style: tx(16, w: 7)),
            ],
          ),
          const SizedBox(height: 16),
          Text(i18n.t('landing.footer'), textAlign: TextAlign.center, style: tx(14, c: Tw.gray400)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            alignment: WrapAlignment.center,
            children: [
              GestureDetector(onTap: () => context.push('/kvkk'), child: Text(i18n.t('legal.kvkkTitle'), style: link)),
              GestureDetector(onTap: () => context.push('/riza'), child: Text(i18n.t('legal.rizaTitle'), style: link)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Kartları tek tek yerine oturtan yatay kaydırma (CSS `scroll-snap`).
class _SnapPhysics extends ScrollPhysics {
  const _SnapPhysics({required this.itemExtent, super.parent});

  final double itemExtent;

  @override
  _SnapPhysics applyTo(ScrollPhysics? ancestor) => _SnapPhysics(itemExtent: itemExtent, parent: buildParent(ancestor));

  @override
  Simulation? createBallisticSimulation(ScrollMetrics position, double velocity) {
    if ((velocity <= 0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }
    final tol = toleranceFor(position);
    var page = position.pixels / itemExtent;
    if (velocity < -tol.velocity) {
      page -= .5;
    } else if (velocity > tol.velocity) {
      page += .5;
    }
    final target = (page.roundToDouble() * itemExtent).clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((target - position.pixels).abs() < tol.distance) return null;
    return ScrollSpringSimulation(spring, position.pixels, target, velocity, tolerance: tol);
  }

  @override
  bool get allowImplicitScrolling => false;
}
