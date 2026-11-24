import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kDebugMode;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;
import 'package:url_launcher/url_launcher.dart';

import '../config/env.dart';
import '../core/haptics.dart';
import '../core/i18n.dart';
import '../core/sales_consent.dart';
import '../core/subscription.dart';
import '../state/auth_controller.dart';
import '../state/store_controller.dart';
import '../state/theme_controller.dart';
import '../ui/brand/brand_sheet.dart';
import '../ui/brand/motion.dart';
import '../ui/brand/palette.dart';
import '../ui/brand/plus_style.dart';
import '../ui/shell/page_stage.dart';
import '../ui/tw.dart';
import '../ui/widgets/common.dart';

/// Rebi Plus: uygulamanın premium vitrini. Dil "klinik sıcaklık" + tek bir şampanya altını ([PlusPalette]):
///
/// 1. Sahnenin üstüne binen **üyelik kartı** (orman yeşili, altın gravür) — sayfanın tek odak noktası; seçilen paketi
///    ve fiyatını canlı gösterir, abonede paketini ve yenilenme tarihini taşır.
/// 2. **Plus ile gelenler** — dört ayrıcalık, altın madalyonlu geniş satırlar; sohbette "ücretsiz → Plus" farkı.
/// 3. **Paket seçimi** — aylık/yıllık anahtarı (yıllıkta tasarruf rozeti), seçilince koyu yeşile dönen paket kartları.
/// 4. Altta sabit **altın satın alma düğmesi** ve güven satırı; içerik kaydırılsa da görünür kalır.
///
/// Mağaza sürümünde satın alma yolu yoksa yalnızca nötr bir bilgi çıkar; geliştirici notu yalnız debug'da.
class SubscribeScreen extends StatefulWidget {
  const SubscribeScreen({super.key, this.backTo = '/dashboard/profile'});

  /// "Geri"nin gideceği sayfa: Bugün'deki Plus düğmesiyle gelindiyse Bugün'e döner.
  final String backTo;

  @override
  State<SubscribeScreen> createState() => _SubscribeScreenState();
}

class _SubscribeScreenState extends State<SubscribeScreen> {
  static const _appleEula = 'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/';

  bool _yearly = false;
  String? _selected;
  String _notice = '';

  bool get _ios => defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    if (storePurchasesEnabled) {
      final store = context.read<StoreController>();
      if (store.plans.isEmpty) store.loadPlans();
    }
  }

  String _defaultSelection(List<StorePlan> plans, String? current) {
    final higher = plans.where((p) => current == null || storeTiers.indexOf(p.tier) > storeTiers.indexOf(current));
    // Varsayılan: orta paket (yoksa ilk uygun olan).
    return higher.any((p) => p.tier == 'pro') ? 'pro' : (higher.isNotEmpty ? higher.first.tier : plans.first.tier);
  }

  /// Yıllık ödemenin aylığa göre en yüksek tasarrufu (%). Fiyatlar bilinmiyorsa null.
  int? _yearlySaving(List<StorePlan> all) {
    int? best;
    for (final tier in storeTiers) {
      final m = all.where((p) => p.tier == tier && !p.yearly).firstOrNull?.package.storeProduct.price ?? 0;
      final y = all.where((p) => p.tier == tier && p.yearly).firstOrNull?.package.storeProduct.price ?? 0;
      if (m <= 0 || y <= 0) continue;
      final pct = ((1 - y / (m * 12)) * 100).round();
      if (pct > 0 && (best == null || pct > best)) best = pct;
    }
    return best;
  }

  Future<void> _buy(StoreController store, StorePlan plan) async {
    final i18n = I18n.instance;
    setState(() => _notice = '');
    final r = await store.purchase(plan);
    if (!mounted) return;
    // Üyelik açıldı: günün "kilometre taşı" vuruşu; başarısızlıkta hata titreşimi.
    if (r == PurchaseOutcome.success || r == PurchaseOutcome.activating) Haptics.milestone();
    if (r == PurchaseOutcome.failed) Haptics.failure();
    setState(() {
      _notice = switch (r) {
        PurchaseOutcome.success => i18n.t('mobileSubscribe.store.success'),
        PurchaseOutcome.activating => i18n.t('mobileSubscribe.store.activating'),
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
    final theme = context.watch<ThemeController>().theme;
    final user = context.watch<AuthController>().user;
    final store = context.watch<StoreController>();
    final plus = userHasRebiPlus(user);
    final tier = activeStoreTier(user);
    const checkoutUrl = Env.rebiPlusCheckoutUrl;

    // Mağaza paketleri ve seçim (alt çubuk ile içerik aynı seçimi kullanır).
    final all = storePurchasesEnabled ? store.plans : const <StorePlan>[];
    final hasYearly = all.any((p) => p.yearly);
    final yearly = _yearly && hasYearly;
    final plans = all.where((p) => p.yearly == yearly).toList();
    final selectedTier = all.isEmpty ? null : (_selected ?? _defaultSelection(plans.isEmpty ? all : plans, tier));
    final selected = plans.where((p) => p.tier == selectedTier).firstOrNull;
    final isCurrent = selected != null && selected.tier == tier;

    final card = _membershipCard(i18n, user, plus, tier, selected);

    return StagePage(
      theme: theme,
      title: i18n.t('subscribe.title'),
      subtitle: i18n.t('mobileSubscribe.premium.tagline'),
      backTo: widget.backTo,
      maxWidth: 512,
      overlap: 96,
      bottomBar: selected == null
          ? null
          : StageBottomBar(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_notice.isNotEmpty) ...[
                    Text(
                      _notice,
                      textAlign: TextAlign.center,
                      style: tx(13, w: 5, c: Tw.gray700, h: relaxed),
                    ),
                    const SizedBox(height: 8),
                  ],
                  PlusButton(
                    loading: store.busy,
                    onPressed: isCurrent ? null : () => _buy(store, selected),
                    icon: isCurrent ? LucideIcons.circleCheck : LucideIcons.crown,
                    label: isCurrent
                        ? i18n.t('mobileSubscribe.store.current')
                        : i18n.t(tier == null ? 'mobileSubscribe.store.subscribe' : 'mobileSubscribe.store.upgrade', {
                            'tier': i18n.t('mobileSubscribe.store.tiers.${selected.tier}'),
                          }),
                  ),
                  const SizedBox(height: 8),
                  _TrustLine(ios: _ios),
                ],
              ),
            ),
      children: [
        Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: card),
        if (plus) ...[
          const SizedBox(height: 14),
          Text(
            tier == null
                ? i18n.t('mobileSubscribe.activeBody')
                : i18n.t('mobileSubscribe.activeTierBody', {'count': '${storeTierDailyLimits[tier]}'}),
            textAlign: TextAlign.center,
            style: tx(13.5, c: Tw.gray600, h: relaxed),
          ),
        ],
        const SizedBox(height: 28),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Semantics(
            header: true,
            child: Text(i18n.t(plus ? 'mobileSubscribe.included' : 'mobileSubscribe.premium.compareTitle'), style: heading(24, h: 1.15)),
          ),
        ),
        const SizedBox(height: 14),
        const _Benefits(),
        const SizedBox(height: 30),
        if (storePurchasesEnabled)
          _storeSection(i18n, store, all, plans, yearly, hasYearly, selectedTier, tier)
        else if (checkoutUrl.isNotEmpty)
          _CheckoutGate(checkoutUrl: checkoutUrl, userId: user?.id ?? '')
        else
          RCard(
            padding: const EdgeInsets.all(16),
            radius: 20,
            borderColor: PlusPalette.line,
            color: PlusPalette.wash,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(LucideIcons.info, size: 17, color: PlusPalette.text),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        i18n.t('mobileSubscribe.unavailable'),
                        style: tx(13, c: Tw.gray800, h: relaxed),
                      ),
                      // Geliştirici ipucu yalnızca debug derlemesinde görünür.
                      if (kDebugMode) ...[
                        const SizedBox(height: 4),
                        Text('(Dev: REBI_PLUS_CHECKOUT_URL tanımlı değil)', style: tx(11, c: Tw.gray600)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 22),
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

  /// Kart canlıdır: abonede paket + yenilenme tarihi, ücretsizde o an seçili paket ve fiyatı.
  Widget _membershipCard(I18n i18n, User? user, bool plus, String? tier, StorePlan? selected) {
    if (plus) {
      final exp = storeExpiry(user);
      return PlusMembershipCard(
        active: true,
        label: i18n.t('mobileSubscribe.premium.memberLabel'),
        value: tier != null
            ? i18n.t('mobileSubscribe.activeTier', {'tier': i18n.t('mobileSubscribe.store.tiers.$tier')})
            : i18n.t('mobileSubscribe.active'),
        footnote: exp == null
            ? null
            : i18n.t('mobileSubscribe.premium.renews', {'date': DateFormat.yMMMMd(i18n.lang).format(exp.toLocal())}),
      );
    }
    if (selected == null) {
      return PlusMembershipCard(
        label: i18n.t('mobileSubscribe.premium.cardLabel'),
        value: i18n.t('mobileSubscribe.premium.cardValue'),
      );
    }
    final limit = storeTierDailyLimits[selected.tier];
    return PlusMembershipCard(
      label: '${i18n.t('mobileSubscribe.store.tiers.${selected.tier}')} · '
          '${i18n.t(selected.yearly ? 'mobileSubscribe.store.yearly' : 'mobileSubscribe.store.monthly')}',
      value: limit == null
          ? i18n.t('mobileSubscribe.premium.cardValue')
          : i18n.t('mobileSubscribe.premium.cardDaily', {'count': '$limit'}),
      price: selected.priceString,
      priceUnit: i18n.t(selected.yearly ? 'mobileSubscribe.store.perYear' : 'mobileSubscribe.store.perMonth'),
    );
  }

  Widget _storeSection(
    I18n i18n,
    StoreController store,
    List<StorePlan> all,
    List<StorePlan> plans,
    bool yearly,
    bool hasYearly,
    String? selectedTier,
    String? current,
  ) {
    if (all.isEmpty) {
      return RCard(
        padding: const EdgeInsets.all(16),
        radius: 20,
        child: store.loadingPlans
            ? Row(
                children: [
                  SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: PlusPalette.text)),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(i18n.t('mobileSubscribe.store.loading'), style: tx(13, c: Tw.gray600)),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    i18n.t('mobileSubscribe.store.noPlans'),
                    style: tx(13, c: Tw.gray600, h: relaxed),
                  ),
                  const SizedBox(height: 8),
                  TextLink(
                    i18n.t('mobileSubscribe.store.retry'),
                    onTap: store.loadPlans,
                    style: tx(13.5, w: 6, c: PlusPalette.text),
                  ),
                ],
              ),
      );
    }
    final saving = _yearlySaving(all);
    final linkStyle = tx(13, w: 6, c: Tw.gray800);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Semantics(header: true, child: BrandEyebrow(i18n.t('mobileSubscribe.premium.choose'))),
        ),
        const SizedBox(height: 14),
        if (hasYearly) ...[
          _PeriodToggle(yearly: yearly, saving: saving, onChanged: store.busy ? null : (v) => setState(() => _yearly = v)),
          const SizedBox(height: 14),
        ],
        for (final p in plans) ...[
          _TierCard(
            plan: p,
            selected: p.tier == selectedTier,
            current: p.tier == current,
            popular: p.tier == 'pro',
            onTap: store.busy ? null : () => setState(() => _selected = p.tier),
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 10),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 18,
          runSpacing: 4,
          children: [
            TextLink(i18n.t('mobileSubscribe.store.restore'), onTap: store.busy ? () {} : () => _restore(store), style: linkStyle),
            if (current != null)
              TextLink(
                i18n.t('mobileSubscribe.store.manage'),
                onTap: () => launchUrl(Uri.parse(storeManageSubscriptionsUrl), mode: LaunchMode.externalApplication),
                style: linkStyle,
              ),
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
              TextLink(
                i18n.t('mobileSubscribe.store.terms'),
                onTap: () => launchUrl(Uri.parse(_appleEula), mode: LaunchMode.externalApplication),
                style: tx(11.5, w: 6, c: Tw.gray600),
                underline: true,
              ),
            TextLink(
              i18n.t('mobileSubscribe.store.privacy'),
              onTap: () => context.push('/kvkk'),
              style: tx(11.5, w: 6, c: Tw.gray600),
              underline: true,
            ),
          ],
        ),
      ],
    );
  }
}

/// Satın alma düğmesinin altındaki güven satırı: iptal özgürlüğü ve mağaza üzerinden güvenli ödeme.
class _TrustLine extends StatelessWidget {
  const _TrustLine({required this.ios});

  final bool ios;

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final style = tx(11.5, w: 5, c: Tw.gray600);
    Widget item(IconData icon, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(child: Icon(icon, size: 13, color: Tw.gray500)),
        const SizedBox(width: 5),
        Flexible(child: Text(text, style: style)),
      ],
    );
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 16,
      runSpacing: 2,
      children: [
        item(LucideIcons.rotateCcw, i18n.t('mobileSubscribe.premium.trustCancel')),
        item(LucideIcons.shieldCheck, i18n.t(ios ? 'mobileSubscribe.premium.trustIos' : 'mobileSubscribe.premium.trustAndroid')),
      ],
    );
  }
}

/// Yıllık paketin aylık karşılığı (mağazanın para birimiyle); fiyat bilinmiyorsa null.
String? monthlyEquivalent(StorePlan plan, String lang) {
  final product = plan.package.storeProduct;
  if (product.price <= 0 || product.currencyCode.isEmpty) return null;
  try {
    return NumberFormat.simpleCurrency(locale: lang == 'tr' ? 'tr_TR' : 'en_US', name: product.currencyCode)
        .format(product.price / 12);
  } catch (_) {
    return null;
  }
}

/// Plus ile gelenler: tek kartta dört ayrıcalık. Her satırda altın zeminli bir madalyon, serif başlık ve kısa açıklama;
/// sohbet satırında ücretsiz → Plus farkı tek satırda. Eski üç sütunlu tablo dar ekranda metni üç-dört satıra
/// bölüyordu; bu düzen tam genişliği metne verir.
class _Benefits extends StatelessWidget {
  const _Benefits();

  static const _rows = [
    (LucideIcons.messageCircle, 'chat'),
    (LucideIcons.palette, 'themes'),
    (LucideIcons.ban, 'adFree'),
    (LucideIcons.sparkles, 'early'),
  ];

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    return RCard(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 4),
      radius: 22,
      child: Column(
        children: [
          for (var i = 0; i < _rows.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(border: i == 0 ? null : Border(top: BorderSide(color: Tw.gray100))),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExcludeSemantics(
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: PlusPalette.wash,
                        border: Border.all(color: PlusPalette.line),
                      ),
                      child: Icon(_rows[i].$1, size: 18, color: PlusPalette.text),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 1),
                        Text(
                          i18n.t('mobileSubscribe.benefits.${_rows[i].$2}.title'),
                          style: Brand.serif(18, color: Tw.gray900, h: 1.2, ls: -.2),
                        ),
                        const SizedBox(height: 4),
                        Text(i18n.t('mobileSubscribe.benefits.${_rows[i].$2}.body'), style: tx(13, c: Tw.gray600, h: 1.45)),
                        if (i == 0) ...[
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _Tag(text: i18n.t('mobileSubscribe.premium.chatFree'), plus: false),
                              _Tag(text: i18n.t('mobileSubscribe.premium.chatPaid'), plus: true),
                            ],
                          ),
                        ],
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

/// Ücretsiz (gri) / Plus (altın) küçük etiket.
class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.plus});

  final String text;
  final bool plus;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: plus ? PlusPalette.wash : Tw.gray50,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: plus ? PlusPalette.line : Tw.gray200),
      ),
      child: Text(text, style: tx(12, w: plus ? 7 : 5, c: plus ? PlusPalette.text : Tw.gray600)),
    );
  }
}

/// Aylık / yıllık anahtarı: seçili bölüm orman yeşili hap; yıllıkta tasarruf rozeti.
class _PeriodToggle extends StatelessWidget {
  const _PeriodToggle({required this.yearly, required this.saving, required this.onChanged});

  final bool yearly;
  final int? saving;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    Widget seg(String label, bool value, {Widget? extra}) {
      final on = yearly == value;
      return Expanded(
        child: Semantics(
          button: true,
          selected: on,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onChanged == null ? null : () => onChanged!(value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              constraints: const BoxConstraints(minHeight: 44),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: on ? const Color(0xFF0F4A43) : null, borderRadius: BorderRadius.circular(99)),
              child: Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                runSpacing: 2,
                children: [
                  Text(
                    label,
                    style: tx(14, w: on ? 7 : 5, c: on ? Brand.cream : Tw.gray700),
                  ),
                  ?extra,
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Tw.surface,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Brand.inkFaint),
      ),
      child: Row(
        children: [
          seg(i18n.t('mobileSubscribe.store.monthly'), false),
          seg(
            i18n.t('mobileSubscribe.store.yearly'),
            true,
            extra: saving == null ? null : PlusPill(i18n.t('mobileSubscribe.premium.save', {'pct': '$saving'}), onDark: yearly),
          ),
        ],
      ),
    );
  }
}

/// Paket kartı: seçilince orman yeşili zemin + altın çerçeve ve altın onay; fiyat sağda büyük.
/// Büyük yazıda fiyat adın altına iner (dar ekranda yan yana sığmaz).
class _TierCard extends StatelessWidget {
  const _TierCard({required this.plan, required this.selected, required this.current, required this.popular, required this.onTap});

  final StorePlan plan;
  final bool selected;
  final bool current;
  final bool popular;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final limit = storeTierDailyLimits[plan.tier];
    final tag = current ? i18n.t('mobileSubscribe.store.current') : (popular ? i18n.t('mobileSubscribe.store.popular') : null);
    final stacked = MediaQuery.textScalerOf(context).scale(10) > 13.5;
    final ink = selected ? Brand.cream : Tw.gray900;
    final soft = selected ? Brand.cream.withValues(alpha: .7) : Tw.gray600;

    final price = Column(
      crossAxisAlignment: stacked ? CrossAxisAlignment.start : CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(plan.priceString, style: tx(19, w: 7, c: ink, h: 1.15)),
        Text(i18n.t(plan.yearly ? 'mobileSubscribe.store.perYear' : 'mobileSubscribe.store.perMonth'), style: tx(11.5, w: 5, c: soft)),
        if (plan.yearly && monthlyEquivalent(plan, i18n.lang) != null)
          Text(
            i18n.t('mobileSubscribe.premium.monthlyEquivalent', {'price': monthlyEquivalent(plan, i18n.lang)!}),
            style: tx(11.5, w: 6, c: selected ? PlusPalette.goldSoft : PlusPalette.text),
          ),
      ],
    );

    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            Text(i18n.t('mobileSubscribe.store.tiers.${plan.tier}'), style: Brand.serif(21, color: ink, h: 1.1, ls: -.3)),
            if (tag != null) PlusPill(tag, onDark: selected),
          ],
        ),
        if (limit != null) ...[
          const SizedBox(height: 4),
          Text(i18n.t('mobileSubscribe.store.dailyQuestions', {'count': '$limit'}), style: tx(13, c: soft)),
        ],
      ],
    );

    final radio = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? PlusPalette.gold : Colors.transparent,
        border: selected ? null : Border.all(color: Tw.gray300, width: 1.6),
      ),
      child: selected ? const Icon(LucideIcons.check, size: 15, color: PlusPalette.onGold) : null,
    );

    return Semantics(
      selected: selected,
      button: true,
      child: Pressable(
        onTap: onTap,
        scale: .985,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.fromLTRB(16, 16, 18, 16),
          decoration: BoxDecoration(
            color: selected ? null : Tw.surface,
            gradient: selected ? PlusPalette.cardGradient : null,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? PlusPalette.goldSoft.withValues(alpha: .6) : Brand.inkFaint, width: selected ? 1.5 : 1),
            boxShadow: selected
                ? [BoxShadow(color: const Color(0xFF021412).withValues(alpha: .22), blurRadius: 20, offset: const Offset(0, 10))]
                : null,
          ),
          child: Row(
            crossAxisAlignment: stacked ? CrossAxisAlignment.start : CrossAxisAlignment.center,
            children: [
              ExcludeSemantics(child: radio),
              const SizedBox(width: 14),
              Expanded(
                child: stacked
                    ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [info, const SizedBox(height: 8), price])
                    : info,
              ),
              if (!stacked) ...[const SizedBox(width: 12), price],
            ],
          ),
        ),
      ),
    );
  }
}

/// Web ödeme bağlantısı (mağaza dışı): iki yasal onay işaretlenmeden ödeme sayfası açılmaz.
class _CheckoutGate extends StatefulWidget {
  const _CheckoutGate({required this.checkoutUrl, required this.userId});

  final String checkoutUrl;
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

  Widget _check(String linkLabel, String route, String rest, bool value, ValueChanged<bool> onChanged) {
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      value: value,
      activeColor: Brand.forest,
      checkColor: PlusPalette.goldSoft,
      onChanged: _busy ? null : (v) => onChanged(v == true),
      title: Text.rich(
        TextSpan(
          style: tx(13.5, c: Tw.gray800, h: relaxed),
          children: [
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: TextLink(
                linkLabel,
                onTap: () => context.push(route),
                style: tx(13.5, w: 6, c: Tw.teal700),
              ),
            ),
            TextSpan(text: ' — $rest'),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final ready = _preInfo && _distance && widget.userId.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          i18n.t('mobileSubscribe.contractsHint'),
          style: tx(13, c: Tw.gray600, h: relaxed),
        ),
        const SizedBox(height: 8),
        _check(
          i18n.t('legal.preInfoTitle'),
          '/on-bilgilendirme',
          i18n.t('mobileSubscribe.preInfo'),
          _preInfo,
          (v) => setState(() => _preInfo = v),
        ),
        _check(
          i18n.t('legal.distanceTitle'),
          '/mesafeli-satis',
          i18n.t('mobileSubscribe.distance'),
          _distance,
          (v) => setState(() => _distance = v),
        ),
        const SizedBox(height: 12),
        PlusButton(loading: _busy, onPressed: ready ? _open : null, label: i18n.t('mobileSubscribe.open'), icon: LucideIcons.externalLink),
        if (_error.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            _error,
            style: tx(12.5, c: Tw.amber900, h: relaxed),
          ),
        ],
      ],
    );
  }
}
