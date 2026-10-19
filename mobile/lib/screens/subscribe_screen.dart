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
import '../ui/brand/palette.dart';
import '../ui/tw.dart';
import '../ui/widgets/common.dart';
import 'today/today_widgets.dart';

/// Rebi Plus tanıtımı ve (varsa) ödeme bağlantısı. Uygulamanın geri kalanıyla aynı dil: krem zemin, mürekkep yazı,
/// düz kartlar. Mağaza sürümünde satın alma yolu yoksa yalnızca nötr bir bilgi çıkar; geliştirici notu yalnız debug'da.
class SubscribeScreen extends StatelessWidget {
  const SubscribeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final theme = context.watch<ThemeController>().theme;
    final plus = userHasRebiPlus(context.watch<AuthController>().user);
    const checkoutUrl = Env.rebiPlusCheckoutUrl;

    final benefits = [
      (LucideIcons.messageCircle, 'chat'),
      (LucideIcons.palette, 'themes'),
      (LucideIcons.sparkles, 'early'),
      (LucideIcons.shield, 'tracking'),
    ];

    return ThemedPage(
      theme: theme,
      maxWidth: 512,
      padding: const EdgeInsets.fromLTRB(16, 32, 16, 40),
      children: [
        Center(
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(color: theme.primary.withValues(alpha: .12), borderRadius: BorderRadius.circular(20)),
            child: Icon(LucideIcons.crown, size: 28, color: theme.fg),
          ),
        ),
        const SizedBox(height: 16),
        Text(i18n.t('subscribe.title'), textAlign: TextAlign.center, style: heading(32, h: 1.1)),
        const SizedBox(height: 8),
        Text(i18n.t('subscribe.subtitle'), textAlign: TextAlign.center, style: tx(14.5, c: Tw.gray600, h: relaxed)),
        const SizedBox(height: 24),
        if (plus) ...[
          RCard(
            padding: const EdgeInsets.all(16),
            radius: 20,
            borderColor: Tw.emerald200,
            color: Color.alphaBlend(Tw.emerald50.withValues(alpha: .7), Tw.surface),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(padding: const EdgeInsets.only(top: 1), child: Icon(LucideIcons.circleCheck, size: 18, color: Tw.emerald700)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(i18n.t('mobileSubscribe.active'), style: tx(14.5, w: 7, c: Tw.emerald900)),
                      const SizedBox(height: 2),
                      Text(i18n.t('mobileSubscribe.activeBody'), style: tx(13, c: Tw.emerald800, h: relaxed)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        RCard(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          radius: 24,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(i18n.t('mobileSubscribe.included'), style: heading(22, h: 1.2)),
              const SizedBox(height: 8),
              for (var i = 0; i < benefits.length; i++) ...[
                if (i > 0) const Hairline(indent: 56),
                _Benefit(
                  icon: benefits[i].$1,
                  title: i18n.t('mobileSubscribe.benefits.${benefits[i].$2}.title'),
                  body: i18n.t('mobileSubscribe.benefits.${benefits[i].$2}.body'),
                  theme: theme,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (checkoutUrl.isNotEmpty)
          PrimaryButton(
            color: theme.primary,
            onPressed: () => launchUrl(Uri.parse(checkoutUrl), mode: LaunchMode.externalApplication),
            label: i18n.t('mobileSubscribe.open'),
            trailingIcon: LucideIcons.externalLink,
          )
        else
          RCard(
            padding: const EdgeInsets.all(16),
            radius: 20,
            borderColor: Tw.amber200,
            color: Color.alphaBlend(Tw.amber50.withValues(alpha: .6), Tw.surface),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(padding: const EdgeInsets.only(top: 1), child: Icon(LucideIcons.info, size: 17, color: Tw.amber600)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(i18n.t('mobileSubscribe.unavailable'), style: tx(13, c: Tw.amber900, h: relaxed)),
                      // Geliştirici ipucu yalnızca debug derlemesinde görünür.
                      if (kDebugMode) ...[
                        const SizedBox(height: 4),
                        Text('(Dev: REBI_PLUS_CHECKOUT_URL tanımlı değil)', style: tx(11, c: Tw.amber900.withValues(alpha: .7))),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 20),
        Center(
          child: TextLink(
            i18n.t('mobileSubscribe.backToChat'),
            onTap: () => context.go('/dashboard/chat'),
            style: tx(14, w: 6, c: theme.fg),
          ),
        ),
      ],
    );
  }
}

class _Benefit extends StatelessWidget {
  const _Benefit({required this.icon, required this.title, required this.body, required this.theme});

  final IconData icon;
  final String title;
  final String body;
  final RebiTheme theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: theme.primary.withValues(alpha: .1), borderRadius: BorderRadius.circular(13)),
            child: Icon(icon, size: 20, color: theme.fg),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: tx(15, w: 7, c: Tw.gray900)),
                const SizedBox(height: 2),
                Text(body, style: tx(13, c: Tw.gray600, h: relaxed)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
