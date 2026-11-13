import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/env.dart';
import '../core/i18n.dart';
import '../core/sales_consent.dart';
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
    final user = context.watch<AuthController>().user;
    final plus = userHasRebiPlus(user);
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
          _CheckoutGate(checkoutUrl: checkoutUrl, theme: theme, userId: user?.id ?? '')
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
                        Text('(Dev: REBI_PLUS_CHECKOUT_URL tanımlı değil)', style: tx(11, c: Tw.amber900)),
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

class _CheckoutGate extends StatefulWidget {
  const _CheckoutGate({required this.checkoutUrl, required this.theme, required this.userId});

  final String checkoutUrl;
  final RebiTheme theme;
  final String userId;

  @override
  State<_CheckoutGate> createState() => _CheckoutGateState();
}

class _CheckoutGateState extends State<_CheckoutGate> {
  bool _preInfo = false;
  bool _distance = false;
  bool _busy = false;
  String _error = '';

  Future<void> _open() async {
    if (!_preInfo || !_distance || _busy) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    final i18n = I18n.instance;
    try {
      await recordSalesConsent(widget.userId);
      final opened = await launchUrl(Uri.parse(widget.checkoutUrl), mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        setState(() => _error = i18n.t('mobileSubscribe.payError'));
      }
    } catch (_) {
      if (mounted) setState(() => _error = i18n.t('mobileSubscribe.payError'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final ready = _preInfo && _distance && widget.userId.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(i18n.t('mobileSubscribe.contractsHint'), style: tx(13, c: Tw.gray600, h: relaxed)),
        const SizedBox(height: 8),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _preInfo,
          activeColor: widget.theme.primary,
          onChanged: _busy ? null : (v) => setState(() => _preInfo = v == true),
          title: Text.rich(
            TextSpan(
              style: tx(13.5, c: Tw.gray800, h: relaxed),
              children: [
                WidgetSpan(
                  alignment: PlaceholderAlignment.baseline,
                  baseline: TextBaseline.alphabetic,
                  child: TextLink(
                    i18n.t('legal.preInfoTitle'),
                    onTap: () => context.push('/on-bilgilendirme'),
                    style: tx(13.5, w: 6, c: Tw.teal700),
                  ),
                ),
                TextSpan(text: ' — ${i18n.t('mobileSubscribe.preInfo')}'),
              ],
            ),
          ),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _distance,
          activeColor: widget.theme.primary,
          onChanged: _busy ? null : (v) => setState(() => _distance = v == true),
          title: Text.rich(
            TextSpan(
              style: tx(13.5, c: Tw.gray800, h: relaxed),
              children: [
                WidgetSpan(
                  alignment: PlaceholderAlignment.baseline,
                  baseline: TextBaseline.alphabetic,
                  child: TextLink(
                    i18n.t('legal.distanceTitle'),
                    onTap: () => context.push('/mesafeli-satis'),
                    style: tx(13.5, w: 6, c: Tw.teal700),
                  ),
                ),
                TextSpan(text: ' — ${i18n.t('mobileSubscribe.distance')}'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        PrimaryButton(
          color: widget.theme.primary,
          loading: _busy,
          onPressed: ready ? _open : null,
          label: i18n.t('mobileSubscribe.open'),
          trailingIcon: LucideIcons.externalLink,
        ),
        if (_error.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(_error, style: tx(12.5, c: Tw.amber900, h: relaxed)),
        ],
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
