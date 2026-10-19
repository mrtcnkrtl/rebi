import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../core/i18n.dart';
import '../state/auth_controller.dart';
import '../ui/brand/brand_button.dart';
import '../ui/brand/motion.dart';
import '../ui/brand/palette.dart';
import '../ui/brand/public_top_bar.dart';
import '../ui/brand/welcome_art.dart';
import '../ui/tw.dart';

const _slideCount = 3;

/// Karşılama (web: `pages/Landing.jsx`): tam ekran, yana kaydırılan üç sahne ve altta tek net eylem.
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

  static Color _tint(double page) {
    final i = page.floor().clamp(0, _slideCount - 1);
    final next = math.min(i + 1, _slideCount - 1);
    return Color.lerp(
      Brand.tint(i),
      Brand.tint(next),
      (page - i).clamp(0.0, 1.0),
    )!;
  }

  @override
  Widget build(BuildContext context) {
    final authed = context.watch<AuthController>().user != null;
    final chatHref = authed ? '/dashboard/chat' : '/rebi';
    final overlay =
        (Brand.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
            .copyWith(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: Brand.paper,
              systemNavigationBarIconBrightness: Brand.dark
                  ? Brightness.light
                  : Brightness.dark,
            );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: Stack(
        children: [
          Positioned.fill(
            child: ValueListenableBuilder<double>(
              valueListenable: _page,
              builder: (context, page, _) => ColoredBox(color: _tint(page)),
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
                    const Reveal(offset: Offset.zero, child: PublicTopBar()),
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

/// Altta duran krem panel: sahne metni, noktalar ve eylemler.
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

    return Reveal(
      delay: const Duration(milliseconds: 150),
      duration: const Duration(milliseconds: 750),
      offset: const Offset(0, 70),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(26, 28, 26, 10 + bottom),
        decoration: BoxDecoration(
          color: Brand.paper,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(38)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: Brand.dark ? .25 : .035),
              blurRadius: 18,
              offset: const Offset(0, -3),
            ),
          ],
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
                _Dots(page: page),
                const SizedBox(height: 24),
                BrandButton(
                  onPressed: onPrimary,
                  label: authed
                      ? i18n.t('mobileLanding.openApp')
                      : i18n.t('landing.ctaBuildRoutine'),
                  trailingIcon: LucideIcons.arrowRight,
                ),
                const SizedBox(height: 6),
                if (!authed)
                  Center(
                    child: tap(
                      Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        children: [
                          Text(
                            i18n.t('auth.haveAccount'),
                            style: tx(14.5, c: Brand.inkSoft),
                          ),
                          BrandLinkText(i18n.t('auth.login')),
                        ],
                      ),
                      onLogin,
                    ),
                  ),
                Center(
                  child: tap(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          LucideIcons.messageCircle,
                          size: 16,
                          color: Brand.inkSoft,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            i18n.t('landing.ctaChat'),
                            style: tx(14, w: 6, c: Brand.inkSoft),
                          ),
                        ),
                      ],
                    ),
                    onChat,
                  ),
                ),
                const SizedBox(height: 2),
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 14,
                  children: [
                    tap(
                      Text(i18n.t('legal.kvkkTitle'), style: legal),
                      () => context.push('/kvkk'),
                    ),
                    tap(
                      Text(i18n.t('legal.rizaTitle'), style: legal),
                      () => context.push('/riza'),
                    ),
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

/// Üç sahnenin başlık ve açıklaması; kaydırırken çapraz solar, hafifçe yana kayar.
class _SlideTexts extends StatelessWidget {
  const _SlideTexts({required this.page});

  final ValueNotifier<double> page;

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final texts = [
      (i18n.t('mobileLanding.s1Title'), i18n.t('mobileLanding.s1Sub')),
      (i18n.t('mobileLanding.s2Title'), i18n.t('mobileLanding.s2Sub')),
      (i18n.t('mobileLanding.s3Title'), i18n.t('mobileLanding.s3Sub')),
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
                          Text(
                            texts[i].$1,
                            style: Brand.serif(titleSize, ls: -1.1, h: 1.08),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            texts[i].$2,
                            style: tx(16, c: Brand.inkSoft, h: 1.5),
                          ),
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

class _Dots extends StatelessWidget {
  const _Dots({required this.page});

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
                  margin: const EdgeInsets.only(right: 6),
                  width: 7 + 21 * a,
                  height: 7,
                  decoration: BoxDecoration(
                    color: Color.lerp(
                      Brand.ink.withValues(alpha: .18),
                      Brand.ink,
                      a,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
