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

/// Sahne ışığı: orman zemininin üstünde, kahramanın arkasında tek bir yumuşak ışık havuzu.
const _glow = Color(0xFF2FB9A4);

/// Sayfanın en az olacağı yükseklik: normalde 680; dar ekranda (<360) +80, yazı büyütülünce yazı oranında artar.
double _minHeight(BuildContext context, double width) {
  final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
  return 680 + (width < 360 ? 80 : 0) + (scale > 1 ? (scale - 1) * 340 : 0);
}

/// Karşılama (web: `pages/Landing.jsx`): giriş yapmadan önce açılan sayfa. Tek odak, sıfır etiket: derin orman yeşili
/// zeminde tek bir kahraman görsel (podyum üstünde ürünler), altında iki satırlık başlık, kısa açıklama ve tek ana düğme.
/// Kaydırmalı sahne, yüzen kart, ilerleme göstergesi ya da süs yoktur; göz tek yerde durur, düğme tek eylemdir.
class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authed = context.watch<AuthController>().user != null;
    final chatHref = authed ? '/dashboard/chat' : '/rebi';
    final overlay = SystemUiOverlayStyle.light.copyWith(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Brand.forest,
      systemNavigationBarIconBrightness: Brightness.light,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: ColoredBox(
        color: Brand.forest,
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: SizedBox(
              // Asgari yükseklik: dar ekranda ve büyük sistem yazısında metin satırları çoğalır; sayfa o zaman kaydırılır.
              height: math.max(box.maxHeight, _minHeight(context, box.maxWidth)),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: const Alignment(0, -.32),
                          radius: .85,
                          colors: [_glow.withValues(alpha: .32), _glow.withValues(alpha: .07), Colors.transparent],
                          stops: const [0, .55, 1],
                        ),
                      ),
                    ),
                  ),
                  Column(
                    children: [
                      SizedBox(height: MediaQuery.paddingOf(context).top),
                      const Reveal(offset: Offset.zero, child: PublicTopBar(onDark: true)),
                      const Expanded(
                        child: Padding(padding: EdgeInsets.fromLTRB(20, 4, 20, 8), child: HeroArt()),
                      ),
                      _Bottom(
                        authed: authed,
                        onPrimary: () => context.go(
                          authed ? '/dashboard' : '/auth?next=${Uri.encodeComponent('/dashboard/analyze')}&mode=signup',
                        ),
                        onLogin: () => context.go('/auth'),
                        onChat: () => context.go(chatHref),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Başlık, açıklama, ana düğme, tek satırlık ikincil eylem ve yasal metin; sırayla, sakin bir şekilde belirir.
class _Bottom extends StatelessWidget {
  const _Bottom({required this.authed, required this.onPrimary, required this.onLogin, required this.onChat});

  final bool authed;
  final VoidCallback onPrimary;
  final VoidCallback onLogin;
  final VoidCallback onChat;

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final small = MediaQuery.sizeOf(context).width < 360;
    final action = tx(14.5, w: 6, c: Brand.cream.withValues(alpha: .9));
    final legal = tx(11.5, w: 5, c: Brand.cream.withValues(alpha: .62));

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

    Widget reveal(int ms, Widget child, {double dy = 14}) => Reveal(
      delay: Duration(milliseconds: ms),
      duration: const Duration(milliseconds: 650),
      offset: Offset(0, dy),
      child: child,
    );

    final chat = tap(
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.messageCircle, size: 17, color: Brand.cream.withValues(alpha: .9)),
          const SizedBox(width: 8),
          Flexible(child: Text(i18n.t('landing.ctaChat'), style: action)),
        ],
      ),
      onChat,
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(26, 8, 26, 6 + bottom),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              reveal(
                500,
                Semantics(
                  header: true,
                  child: Text(
                    i18n.t('mobileLanding.heroTitle'),
                    textAlign: TextAlign.center,
                    style: Brand.serif(small ? 32 : 38, color: Brand.cream, ls: -1.1, h: 1.08),
                  ),
                ),
                dy: 18,
              ),
              const SizedBox(height: 12),
              reveal(
                660,
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    i18n.t('mobileLanding.heroSub'),
                    textAlign: TextAlign.center,
                    style: tx(small ? 15 : 16, c: Brand.cream.withValues(alpha: .76), h: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              reveal(
                820,
                BrandButton(
                  onDark: true,
                  onPressed: onPrimary,
                  label: authed ? i18n.t('mobileLanding.openApp') : i18n.t('landing.ctaBuildRoutine'),
                  trailingIcon: LucideIcons.arrowRight,
                ),
              ),
              const SizedBox(height: 4),
              reveal(
                940,
                authed
                    ? Center(child: chat)
                    : Row(
                        children: [
                          Expanded(child: Center(child: tap(Text(i18n.t('auth.login'), style: action), onLogin))),
                          Container(width: 1, height: 20, color: Brand.cream.withValues(alpha: .22)),
                          Expanded(child: Center(child: chat)),
                        ],
                      ),
                dy: 8,
              ),
              reveal(
                1040,
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
                dy: 6,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
