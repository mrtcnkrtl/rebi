import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/env.dart';
import '../core/i18n.dart';
import '../core/subscription.dart';
import '../state/auth_controller.dart';
import '../state/theme_controller.dart';
import '../ui/tw.dart';
import '../ui/widgets/common.dart';

/// Rebi Plus tanıtım + ödeme bağlantısı (web: `pages/Subscribe.jsx`).
class SubscribeScreen extends StatelessWidget {
  const SubscribeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final theme = context.watch<ThemeController>().theme;
    final plus = userHasRebiPlus(context.watch<AuthController>().user);
    const checkoutUrl = Env.rebiPlusCheckoutUrl;

    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Colors.white),
        Opacity(
          opacity: .9,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Tw.fixedSlate950, Tw.fixedViolet950.withValues(alpha: .95), Tw.fixedSlate900],
              ),
            ),
          ),
        ),
        const _Glow(),
        SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 40, 16, 40),
          child: CenteredBox(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: GradientIconBox(
                    icon: LucideIcons.crown,
                    from: theme.accent,
                    to: theme.primary,
                    size: 64,
                    iconSize: 32,
                    radius: 24,
                  ),
                ),
                const SizedBox(height: 16),
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
                        Icon(LucideIcons.sparkles, size: 16, color: Tw.amber300),
                        const SizedBox(width: 8),
                        Text('Rebi Plus', style: tx(14, w: 6, c: Tw.amber200)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(i18n.t('subscribe.title'), textAlign: TextAlign.center, style: tx(30, w: 9, c: Colors.white, ls: -.5)),
                const SizedBox(height: 8),
                Text(i18n.t('subscribe.subtitle'),
                    textAlign: TextAlign.center,
                    style: tx(14, c: Tw.violet100.withValues(alpha: .8), h: relaxed)),
                const SizedBox(height: 28),
                if (plus) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    decoration: BoxDecoration(
                      color: Tw.emerald500.withValues(alpha: .1),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Tw.emerald300.withValues(alpha: .25)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Icon(LucideIcons.check, size: 16, color: Tw.emerald300),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Plus aktif', style: tx(14, w: 7, c: Tw.emerald100)),
                              const SizedBox(height: 2),
                              Text('Hesabında Rebi Plus görünüyor. Teşekkürler.',
                                  style: tx(14, c: Tw.emerald100.withValues(alpha: .8))),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
                _GlassPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Neler dahil?', style: tx(20, w: 9, c: Colors.white, ls: -.3)),
                      const SizedBox(height: 20),
                      _Benefit(
                        icon: LucideIcons.messageCircle,
                        iconColor: Tw.amber200,
                        glow: Tw.amber400,
                        glowAlign: Alignment.topRight,
                        title: 'Sınırsız Rebi AI',
                        body: 'Günlük ücretsiz mesaj limiti kalkar; sohbet kesilmez.',
                      ),
                      const SizedBox(height: 16),
                      _Benefit(
                        icon: LucideIcons.palette,
                        iconColor: Tw.cyan200,
                        glow: Color(0xFF22D3EE),
                        glowAlign: Alignment.bottomLeft,
                        title: 'Premium temalar',
                        body: 'Ayırt edici renkler, desenler ve daha “premium” his.',
                      ),
                      const SizedBox(height: 16),
                      _Benefit(
                        icon: LucideIcons.sparkles,
                        iconColor: Tw.fuchsia200,
                        glow: Tw.fuchsia400,
                        glowAlign: Alignment.topLeft,
                        title: 'Öncelikli yenilikler',
                        body: 'Yeni özellikler önce Plus’a gelir; ilk sen denersin.',
                      ),
                      const SizedBox(height: 16),
                      _Benefit(
                        icon: LucideIcons.shield,
                        iconColor: Tw.emerald200,
                        glow: Color(0xFF34D399),
                        glowAlign: Alignment.bottomRight,
                        title: 'Daha derin takip',
                        body: 'Check-in akışı daha güçlü çalışır; rutinin daha iyi uyarlanır.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _GlassPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (checkoutUrl.isNotEmpty)
                        Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => launchUrl(Uri.parse(checkoutUrl), mode: LaunchMode.externalApplication),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Flexible(child: Text('Plus’ı aç', style: tx(16, w: 8, c: Tw.fixedViolet950))),
                                  const SizedBox(width: 8),
                                  Icon(LucideIcons.externalLink, size: 16, color: Tw.fixedViolet950),
                                ],
                              ),
                            ),
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: Tw.amber500.withValues(alpha: .1),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Tw.amber300.withValues(alpha: .2)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(i18n.t('mobileSubscribe.unavailable'), style: tx(12, c: Tw.amber100.withValues(alpha: .9), h: relaxed)),
                              // Geliştirici ipucu yalnızca debug derlemesinde görünür.
                              if (kDebugMode) ...[
                                const SizedBox(height: 4),
                                Text('(Dev: REBI_PLUS_CHECKOUT_URL tanımlı değil)', style: tx(11, c: Tw.amber100.withValues(alpha: .7))),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                Center(
                  child: TextLink(
                    'Sohbete dön',
                    onTap: () => context.go('/dashboard/chat'),
                    style: tx(14, w: 6, c: Colors.white.withValues(alpha: .8)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow();

  @override
  Widget build(BuildContext context) {
    return const Opacity(
      opacity: .55,
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(-.64, -.5),
                radius: .9,
                colors: [Color(0x73A78BFA), Color(0x00A78BFA)],
                stops: [0, .44],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(.64, .4),
                radius: .9,
                colors: [Color(0x47F472B6), Color(0x00F472B6)],
                stops: [0, .40],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(-.2, 1.2),
                radius: .9,
                colors: [Color(0x2E22D3EE), Color(0x0022D3EE)],
                stops: [0, .45],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassPanel extends StatelessWidget {
  const _GlassPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .05),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: Colors.white.withValues(alpha: .1)),
          boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 50, offset: Offset(0, 25))],
        ),
        child: child,
      );
}

class _Benefit extends StatelessWidget {
  const _Benefit({
    required this.icon,
    required this.iconColor,
    required this.glow,
    required this.glowAlign,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final Color iconColor;
  final Color glow;
  final Alignment glowAlign;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: .1)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white.withValues(alpha: .1), Colors.white.withValues(alpha: .05)],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: glowAlign,
                  radius: .8,
                  colors: [glow.withValues(alpha: .15), glow.withValues(alpha: 0)],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withValues(alpha: .1)),
                  ),
                  child: Icon(icon, size: 24, color: iconColor),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: tx(18, w: 8, c: Colors.white)),
                      const SizedBox(height: 4),
                      Text(body, style: tx(14, c: Colors.white.withValues(alpha: .75), h: relaxed)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
