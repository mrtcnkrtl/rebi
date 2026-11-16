import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kDebugMode;
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
import '../state/store_controller.dart';
import '../state/theme_controller.dart';
import '../ui/brand/palette.dart';
import '../ui/shell/page_stage.dart';
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

    final tier = activeStoreTier(user);
    final benefits = [
      (LucideIcons.messageCircle, 'chat'),
      (LucideIcons.palette, 'themes'),
      (LucideIcons.ban, 'adFree'),
      (LucideIcons.sparkles, 'early'),
    ];

    return StagePage(
      theme: theme,
      title: i18n.t('subscribe.title'),
      subtitle: i18n.t('mobileSubscribe.subtitle'),
      backTo: '/dashboard/profile',
      maxWidth: 512,
      leading: ExcludeSemantics(
        child: Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: Brand.cream.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Brand.cream.withValues(alpha: .34), width: 1.3),
          ),
          child: Icon(LucideIcons.crown, size: 28, color: Brand.cream),
        ),
      ),
      children: [
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
                      Text(
                        tier == null
                            ? i18n.t('mobileSubscribe.active')
                            : i18n.t('mobileSubscribe.activeTier', {'tier': i18n.t('mobileSubscribe.store.tiers.$tier')}),
                        style: tx(14.5, w: 7, c: Tw.emerald900),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        tier == null
                            ? i18n.t('mobileSubscribe.activeBody')
                            : i18n.t('mobileSubscribe.activeTierBody', {'count': '${storeTierDailyLimits[tier]}'}),
                        style: tx(13, c: Tw.emerald800, h: relaxed),
                      ),
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
        if (storePurchasesEnabled)
          _StorePaywall(theme: theme, currentTier: tier)
        else if (checkoutUrl.isNotEmpty)
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

/// Uygulama içi abonelik (App Store / Google Play, RevenueCat). Apple'ın istediği öğeler burada: fiyat ve dönem,
/// otomatik yenileme açıklaması, geri yükleme, kullanım koşulları ve gizlilik bağlantıları.
class _StorePaywall extends StatefulWidget {
  const _StorePaywall({required this.theme, required this.currentTier});

  final RebiTheme theme;
  final String? currentTier;

  @override
  State<_StorePaywall> createState() => _StorePaywallState();
}

class _StorePaywallState extends State<_StorePaywall> {
  static const _appleEula = 'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/';
  static const _manageIos = 'https://apps.apple.com/account/subscriptions';
  static const _manageAndroid = 'https://play.google.com/store/account/subscriptions';

  bool _yearly = false;
  String? _selected;
  String _notice = '';

  bool get _ios => defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    final store = context.read<StoreController>();
    if (store.plans.isEmpty) store.loadPlans();
  }

  String _defaultSelection(List<StorePlan> plans) {
    final current = widget.currentTier;
    final higher = plans.where((p) => current == null || storeTiers.indexOf(p.tier) > storeTiers.indexOf(current));
    // Varsayılan: orta paket (yoksa ilk uygun olan).
    return higher.any((p) => p.tier == 'pro') ? 'pro' : (higher.isNotEmpty ? higher.first.tier : plans.first.tier);
  }

  Future<void> _buy(StoreController store, StorePlan plan) async {
    final i18n = I18n.instance;
    setState(() => _notice = '');
    final r = await store.purchase(plan);
    if (!mounted) return;
    setState(() {
      _notice = switch (r) {
        PurchaseOutcome.success => i18n.t('mobileSubscribe.store.success'),
        PurchaseOutcome.pending => i18n.t('mobileSubscribe.store.pending'),
        PurchaseOutcome.failed => i18n.t('mobileSubscribe.store.failed'),
        PurchaseOutcome.cancelled => '',
      };
    });
  }

  Future<void> _restore(StoreController store) async {
    final i18n = I18n.instance;
    setState(() => _notice = '');
    final found = await store.restore();
    if (!mounted) return;
    setState(() => _notice = i18n.t(found ? 'mobileSubscribe.store.restored' : 'mobileSubscribe.store.nothingToRestore'));
  }

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final store = context.watch<StoreController>();
    final theme = widget.theme;
    final all = store.plans;

    if (all.isEmpty) {
      return RCard(
        padding: const EdgeInsets.all(16),
        radius: 20,
        child: store.loadingPlans
            ? Row(children: [
                SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: theme.primary)),
                const SizedBox(width: 12),
                Text(i18n.t('mobileSubscribe.store.loading'), style: tx(13, c: Tw.gray600)),
              ])
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(i18n.t('mobileSubscribe.store.noPlans'), style: tx(13, c: Tw.gray600, h: relaxed)),
                const SizedBox(height: 8),
                TextLink(i18n.t('mobileSubscribe.store.retry'), onTap: store.loadPlans, style: tx(13.5, w: 6, c: theme.fg)),
              ]),
      );
    }

    final hasYearly = all.any((p) => p.yearly);
    final yearly = _yearly && hasYearly;
    final plans = all.where((p) => p.yearly == yearly).toList();
    final selectedTier = _selected ?? _defaultSelection(plans.isEmpty ? all : plans);
    final selected = plans.where((p) => p.tier == selectedTier).firstOrNull;
    final current = widget.currentTier;
    final isCurrent = selected != null && selected.tier == current;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasYearly) ...[
          _PeriodToggle(
            yearly: yearly,
            theme: theme,
            onChanged: store.busy ? null : (v) => setState(() => _yearly = v),
          ),
          const SizedBox(height: 12),
        ],
        for (final p in plans) ...[
          _TierCard(
            plan: p,
            theme: theme,
            selected: p.tier == selectedTier,
            current: p.tier == current,
            popular: p.tier == 'pro',
            onTap: store.busy ? null : () => setState(() => _selected = p.tier),
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 6),
        PrimaryButton(
          color: theme.primary,
          loading: store.busy,
          onPressed: selected == null || isCurrent ? null : () => _buy(store, selected),
          label: selected == null
              ? i18n.t('mobileSubscribe.store.loading')
              : isCurrent
                  ? i18n.t('mobileSubscribe.store.current')
                  : i18n.t(current == null ? 'mobileSubscribe.store.subscribe' : 'mobileSubscribe.store.upgrade',
                      {'tier': i18n.t('mobileSubscribe.store.tiers.${selected.tier}')}),
        ),
        if (_notice.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(_notice, textAlign: TextAlign.center, style: tx(13, c: Tw.gray700, h: relaxed)),
        ],
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 16,
          runSpacing: 6,
          children: [
            TextLink(i18n.t('mobileSubscribe.store.restore'),
                onTap: store.busy ? () {} : () => _restore(store), style: tx(13, w: 6, c: theme.fg)),
            if (current != null)
              TextLink(i18n.t('mobileSubscribe.store.manage'),
                  onTap: () => launchUrl(Uri.parse(_ios ? _manageIos : _manageAndroid), mode: LaunchMode.externalApplication),
                  style: tx(13, w: 6, c: theme.fg)),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          i18n.t(_ios ? 'mobileSubscribe.store.renewNoteIos' : 'mobileSubscribe.store.renewNoteAndroid'),
          style: tx(11.5, c: Tw.gray500, h: relaxed),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            if (_ios)
              TextLink(i18n.t('mobileSubscribe.store.terms'),
                  onTap: () => launchUrl(Uri.parse(_appleEula), mode: LaunchMode.externalApplication),
                  style: tx(11.5, w: 6, c: Tw.gray600), underline: true),
            TextLink(i18n.t('mobileSubscribe.store.privacy'),
                onTap: () => context.push('/kvkk'), style: tx(11.5, w: 6, c: Tw.gray600), underline: true),
          ],
        ),
      ],
    );
  }
}

class _PeriodToggle extends StatelessWidget {
  const _PeriodToggle({required this.yearly, required this.theme, required this.onChanged});

  final bool yearly;
  final RebiTheme theme;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    Widget seg(String label, bool value) {
      final on = yearly == value;
      return Expanded(
        child: Semantics(
          button: true,
          selected: on,
          child: GestureDetector(
            onTap: onChanged == null ? null : () => onChanged!(value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(vertical: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? Tw.surface : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: on ? theme.primaryLight : Colors.transparent),
              ),
              child: Text(label, style: tx(13.5, w: on ? 7 : 5, c: on ? theme.fg : Tw.gray600)),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: Tw.gray100, borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        seg(i18n.t('mobileSubscribe.store.monthly'), false),
        seg(i18n.t('mobileSubscribe.store.yearly'), true),
      ]),
    );
  }
}

class _TierCard extends StatelessWidget {
  const _TierCard({
    required this.plan,
    required this.theme,
    required this.selected,
    required this.current,
    required this.popular,
    required this.onTap,
  });

  final StorePlan plan;
  final RebiTheme theme;
  final bool selected;
  final bool current;
  final bool popular;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final limit = storeTierDailyLimits[plan.tier];
    final tag = current ? i18n.t('mobileSubscribe.store.current') : (popular ? i18n.t('mobileSubscribe.store.popular') : null);
    return Semantics(
      selected: selected,
      button: true,
      child: RCard(
        onTap: onTap,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        radius: 18,
        borderWidth: selected ? 2 : 1,
        borderColor: selected ? theme.primary : Tw.gray200,
        child: Row(
          children: [
            Icon(selected ? LucideIcons.circleCheck : LucideIcons.circle,
                size: 20, color: selected ? theme.primary : Tw.gray400),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(i18n.t('mobileSubscribe.store.tiers.${plan.tier}'), style: tx(15.5, w: 7, c: Tw.gray900)),
                    if (tag != null) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: theme.primary.withValues(alpha: .12),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(tag, overflow: TextOverflow.ellipsis, style: tx(10.5, w: 7, c: theme.fg)),
                        ),
                      ),
                    ],
                  ]),
                  if (limit != null) ...[
                    const SizedBox(height: 2),
                    Text(i18n.t('mobileSubscribe.store.dailyQuestions', {'count': '$limit'}),
                        style: tx(13, c: Tw.gray600)),
                  ],
                  const SizedBox(height: 4),
                  // Fiyat ayrı satırda: dar ekranda / büyük yazıda adın yanına sığmaz.
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(text: plan.priceString, style: tx(15, w: 7, c: Tw.gray900)),
                      TextSpan(
                        text: i18n.t(plan.yearly ? 'mobileSubscribe.store.perYear' : 'mobileSubscribe.store.perMonth'),
                        style: tx(12, c: Tw.gray500),
                      ),
                    ]),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
