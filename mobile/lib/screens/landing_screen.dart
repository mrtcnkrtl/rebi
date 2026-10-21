import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../core/i18n.dart';
import '../state/auth_controller.dart';
import '../ui/brand/brand_button.dart';
import '../ui/brand/brand_caps.dart';
import '../ui/brand/motion.dart';
import '../ui/brand/palette.dart';
import '../ui/brand/public_top_bar.dart';
import '../ui/brand/welcome_art.dart';
import '../ui/tw.dart';

const _slideCount = 3;

/// Sahne ışığı: orman zemininin üstünde, sahnenin renginde yumuşak bir ışık havuzu (nane, pudra, kum).
const _glow = [Color(0xFF2FB9A4), Color(0xFFDD8F76), Color(0xFFC9A862)];

/// Karşılama (web: `pages/Landing.jsx`): yukarıda derin orman yeşili sahne (açılış ekranıyla aynı zemin, iki temada da),
/// altında krem "kâğıt" panel: yana kaydırılan üç sahne ve tek net eylem.
class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  final _controller = PageController();
  final _page = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      if (_controller.hasClients && _controller.position.haveDimensions) {
        _page.value = _controller.page ?? 0;
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _page.dispose();
    super.dispose();
  }

  static Color _light(double page) {
    final i = page.floor().clamp(0, _slideCount - 1);
    final next = math.min(i + 1, _slideCount - 1);
    return Color.lerp(_glow[i], _glow[next], (page - i).clamp(0.0, 1.0))!;
  }

  @override
  Widget build(BuildContext context) {
    final authed = context.watch<AuthController>().user != null;
    final chatHref = authed ? '/dashboard/chat' : '/rebi';
    // Üst sahne her iki temada koyu: durum çubuğu simgeleri açık. Alt çubuk panelin (kâğıt) rengindedir.
    final overlay = SystemUiOverlayStyle.light.copyWith(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Brand.paper,
      systemNavigationBarIconBrightness: Brand.dark ? Brightness.light : Brightness.dark,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: Stack(
        children: [
          Positioned.fill(
            child: ValueListenableBuilder<double>(
              valueListenable: _page,
              builder: (context, page, _) => ColoredBox(
                color: Brand.forest,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, -.42),
                      radius: .95,
                      colors: [_light(page).withValues(alpha: .34), _light(page).withValues(alpha: .08), Colors.transparent],
                      stops: const [0, .55, 1],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const Positioned.fill(child: DappledLeaves()),
          LayoutBuilder(
            builder: (context, box) => SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: SizedBox(
                height: math.max(box.maxHeight, 700),
                child: Column(
                  children: [
                    SizedBox(height: MediaQuery.paddingOf(context).top),
                    const Reveal(offset: Offset.zero, child: PublicTopBar(onDark: true)),
                    Expanded(
                      child: _ArtPager(controller: _controller, page: _page),
                    ),
                    _Sheet(
                      page: _page,
                      authed: authed,
                      onPrimary: () => context.go(
                        authed
                            ? '/dashboard'
                            : '/auth?next=${Uri.encodeComponent('/dashboard/analyze')}&mode=signup',
                      ),
                      onLogin: () => context.go('/auth'),
                      onChat: () => context.go(chatHref),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ArtPager extends StatelessWidget {
  const _ArtPager({required this.controller, required this.page});

  final PageController controller;
  final ValueNotifier<double> page;

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      controller: controller,
      itemCount: _slideCount,
      physics: const BouncingScrollPhysics(),
      itemBuilder: (context, i) => ValueListenableBuilder<double>(
        valueListenable: page,
        builder: (context, p, _) {
          final delta = p - i;
          final active = delta.abs() < 1;
          return Padding(
            padding: const EdgeInsets.fromLTRB(26, 6, 26, 14),
            child: switch (i) {
              0 => MirrorArt(active: active, delta: delta),
              1 => PodiumArt(active: active, delta: delta),
              _ => RingsArt(active: active, delta: delta),
            },
          );
        },
      ),
    );
  }
}

/// Altta duran krem "kâğıt" panel: etiket, başlık, açıklama, ilerleme çizgisi ve eylemler.
/// Hiyerarşi: tek ana düğme; altında tek satır ikincil eylem; en altta tek satır yasal metin.
class _Sheet extends StatelessWidget {
  const _Sheet({
    required this.page,
    required this.authed,
    required this.onPrimary,
    required this.onLogin,
    required this.onChat,
  });

  final ValueNotifier<double> page;
  final bool authed;
  final VoidCallback onPrimary;
  final VoidCallback onLogin;
  final VoidCallback onChat;

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final legal = tx(11.5, w: 5, c: Brand.inkSoft);
    final action = tx(14.5, w: 6, c: Brand.ink);

    Widget tap(Widget child, VoidCallback onTap) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ConstrainedBox(
        // Dokunma alanı en az 48 dp; görünüm metin kadar.
        constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
        child: Center(
          widthFactor: 1,
          heightFactor: 1,
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: child),
        ),
      ),
    );

    final chat = tap(
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.messageCircle, size: 17, color: Brand.ink),
          const SizedBox(width: 8),
          Flexible(child: Text(i18n.t('landing.ctaChat'), style: action)),
        ],
      ),
      onChat,
    );

    return Reveal(
      delay: const Duration(milliseconds: 150),
      duration: const Duration(milliseconds: 750),
      offset: const Offset(0, 70),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(26, 26, 26, 6 + bottom),
        decoration: BoxDecoration(
          color: Brand.paper,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SlideTexts(page: page),
                const SizedBox(height: 20),
                _Progress(page: page),
                const SizedBox(height: 22),
                BrandButton(
                  onPressed: onPrimary,
                  label: authed ? i18n.t('mobileLanding.openApp') : i18n.t('landing.ctaBuildRoutine'),
                  trailingIcon: LucideIcons.arrowRight,
                ),
                const SizedBox(height: 6),
                if (authed)
                  Center(child: chat)
                else
                  Row(
                    children: [
                      Expanded(
                        child: Center(child: tap(Text(i18n.t('auth.login'), style: action), onLogin)),
                      ),
                      Container(width: 1, height: 20, color: Brand.inkFaint),
                      Expanded(child: Center(child: chat)),
                    ],
                  ),
                const SizedBox(height: 2),
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 4,
                  children: [
                    tap(Text(i18n.t('legal.kvkkTitle'), style: legal), () => context.push('/kvkk')),
                    Text('·', style: legal),
                    tap(Text(i18n.t('legal.rizaTitle'), style: legal), () => context.push('/riza')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Üç sahnenin etiketi, başlığı ve açıklaması; kaydırırken çapraz solar, hafifçe yana kayar.
class _SlideTexts extends StatelessWidget {
  const _SlideTexts({required this.page});

  final ValueNotifier<double> page;

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final lang = i18n.lang;
    final texts = [
      (i18n.t('mobileLanding.eyebrow1'), i18n.t('mobileLanding.s1Title'), i18n.t('mobileLanding.s1Sub')),
      (i18n.t('mobileLanding.eyebrow2'), i18n.t('mobileLanding.s2Title'), i18n.t('mobileLanding.s2Sub')),
      (i18n.t('mobileLanding.eyebrow3'), i18n.t('mobileLanding.s3Title'), i18n.t('mobileLanding.s3Sub')),
    ];
    final titleSize = MediaQuery.sizeOf(context).width < 360 ? 30.0 : 35.0;
    return ValueListenableBuilder<double>(
      valueListenable: page,
      builder: (context, p, _) => Stack(
        children: [
          for (var i = 0; i < texts.length; i++)
            Builder(
              builder: (context) {
                final d = p - i;
                final o = (1 - d.abs() * 1.8).clamp(0.0, 1.0);
                return ExcludeSemantics(
                  excluding: o < .5,
                  child: Opacity(
                    opacity: o,
                    child: Transform.translate(
                      offset: Offset(-d * 44, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(width: 22, height: 1.5, color: Brand.teal),
                              const SizedBox(width: 10),
                              Flexible(
                                child: Text(
                                  brandCaps(texts[i].$1, lang),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: tx(11, w: 7, c: Brand.inkSoft, ls: brandTracking(lang, 2.0)),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Text(texts[i].$2, style: Brand.serif(titleSize, ls: -1.1, h: 1.08)),
                          const SizedBox(height: 10),
                          Text(texts[i].$3, style: tx(16, c: Brand.inkSoft, h: 1.5)),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

/// Üç ince çizgi: sahne değiştikçe ilgili çizgi dolar.
class _Progress extends StatelessWidget {
  const _Progress({required this.page});

  final ValueNotifier<double> page;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: page,
      builder: (context, p, _) => Row(
        children: [
          for (var i = 0; i < _slideCount; i++)
            Builder(
              builder: (context) {
                final a = (1 - (p - i).abs()).clamp(0.0, 1.0);
                return Container(
                  margin: const EdgeInsetsDirectional.only(end: 6),
                  width: 28,
                  height: 3,
                  decoration: BoxDecoration(
                    color: Color.lerp(Brand.ink.withValues(alpha: .14), Brand.ink, a),
                    borderRadius: BorderRadius.circular(2),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
