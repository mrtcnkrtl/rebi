import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../core/i18n.dart';
import '../core/subscription.dart';
import '../state/auth_controller.dart';
import '../state/theme_controller.dart';
import '../ui/brand/palette.dart';
import '../ui/brand/brand_caps.dart';
import '../ui/components/appearance_card.dart';
import '../ui/shell/page_stage.dart';
import '../ui/tw.dart';
import '../ui/widgets/common.dart';
import 'today/today_widgets.dart';

/// Vurgu rengi seçimi + canlı önizleme (web: `pages/Themes.jsx`). Uygulamanın dili tektir; seçilen renk
/// yalnızca düğmelerde, seçimlerde ve vurgularda görünür.
class ThemesScreen extends StatelessWidget {
  const ThemesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final ctrl = context.watch<ThemeController>();
    final theme = ctrl.theme;
    final plus = userHasRebiPlus(context.watch<AuthController>().user);
    // Plus satın alınamıyorsa (v1 mağaza sürümü) premium renkler yalnızca Plus hesaplarda listelenir.
    final themes = [for (final t in rebiThemes.values) if (!t.premium || plus || plusPurchasable) t];

    void pick(RebiTheme t) {
      if (t.premium && !plus) {
        context.go('/dashboard/subscribe');
        return;
      }
      ctrl.setThemeId(t.id);
    }

    return StagePage(
      theme: theme,
      title: i18n.t('themes.title'),
      subtitle: i18n.t('themes.subtitle'),
      backTo: '/dashboard/profile',
      maxWidth: 512,
      children: [
        AppearanceCard(theme: theme),
        const SizedBox(height: 28),
        SectionLabel(brandCaps(i18n.t('mobileThemes.accent'), i18n.lang)),
        for (var i = 0; i < themes.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 10),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final t in themes.skip(i).take(2).toList().asMap().entries) ...[
                  if (t.key > 0) const SizedBox(width: 10),
                  Expanded(
                    child: _SwatchCard(
                      t: t.value,
                      active: ctrl.themeId == t.value.id,
                      locked: t.value.premium && !plus,
                      onTap: () => pick(t.value),
                    ),
                  ),
                ],
                if (themes.length - i == 1) ...[const SizedBox(width: 10), const Expanded(child: SizedBox())],
              ],
            ),
          ),
        ],
        const SizedBox(height: 14),
        if (plusEntryVisible(context.read<AuthController>().user))
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(i18n.t('mobileThemes.plusPrefix'), style: tx(12, c: Tw.gray500)),
              TextLink(i18n.t('mobileThemes.plusLink'),
                  onTap: () => context.go('/dashboard/subscribe'), style: tx(12, w: 6, c: theme.fg)),
              Text('.', style: tx(12, c: Tw.gray500)),
            ],
          ),
        const SizedBox(height: 28),
        SectionLabel(brandCaps(i18n.t('mobileThemes.preview'), i18n.lang)),
        _Preview(theme: theme),
      ],
    );
  }
}

/// Temanın görünen adı (uygulama dilinde); çeviri yoksa kayıtlı ad.
String themeLabel(RebiTheme t) => I18n.instance.t('mobileThemes.names.${t.id}', const {}, t.label);

/// Temanın küçük bir "sahne"si: üstte derin sahne rengi (krem iki satır yazı izi), altta kâğıt zemin ve temanın düğmesi.
/// Düz bir renk dairesi yerine uygulamanın o temada gerçekte nasıl durduğunu gösterir. Seçiliyken sağ üstte onay işareti.
class _SceneTile extends StatelessWidget {
  const _SceneTile({required this.t, required this.active});

  final RebiTheme t;
  final bool active;

  @override
  Widget build(BuildContext context) {
    Widget bar(double w, double h, double alpha) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(color: Brand.cream.withValues(alpha: alpha), borderRadius: BorderRadius.circular(h / 2)),
        );
    return Container(
      width: 54,
      height: 54,
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Tw.gray900.withValues(alpha: .08)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: Tw.background)),
            Positioned(left: 0, right: 0, top: 0, height: 34, child: ColoredBox(color: t.stage)),
            Positioned(left: 9, top: 10, child: bar(22, 4, .92)),
            Positioned(left: 9, top: 18, child: bar(14, 3, .5)),
            Positioned(
              left: 8,
              right: 8,
              bottom: 7,
              height: 11,
              child: DecoratedBox(decoration: BoxDecoration(color: t.primary, borderRadius: BorderRadius.circular(6))),
            ),
            if (active)
              Positioned(
                right: 5,
                top: 5,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  child: Icon(LucideIcons.check, size: 11, color: t.primary),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Renk örneği kartı: mini sahne, ad ve seçili işareti.
class _SwatchCard extends StatelessWidget {
  const _SwatchCard({required this.t, required this.active, required this.locked, required this.onTap});

  final RebiTheme t;
  final bool active;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      label: themeLabel(t),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            decoration: BoxDecoration(
              color: Tw.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: active ? t.primary : Tw.gray100, width: active ? 2 : 1.5),
            ),
            child: Row(
              children: [
                _SceneTile(t: t, active: active),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(themeLabel(t), maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(14, w: 7)),
                      if (t.premium) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            if (locked) ...[Icon(LucideIcons.lock, size: 11, color: Tw.amber700), const SizedBox(width: 3)],
                            Text('PLUS', style: tx(9.5, w: 7, c: Tw.amber700, ls: 1)),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Seçili rengin sabah rutini kartında nasıl göründüğü.
class _Preview extends StatelessWidget {
  const _Preview({required this.theme});

  final RebiTheme theme;

  @override
  Widget build(BuildContext context) {
    Widget step(IconData icon, String label, bool done) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: theme.primaryLight.withValues(alpha: Tw.dark ? .5 : .6), borderRadius: BorderRadius.circular(14)),
          child: Row(
            children: [
              Icon(icon, size: 18, color: theme.primaryDark),
              const SizedBox(width: 10),
              Expanded(child: Text(label, style: tx(13, w: 6, c: theme.primaryDark))),
              Icon(done ? LucideIcons.circleCheck : LucideIcons.circle, size: 18, color: done ? theme.primary : theme.primaryDark.withValues(alpha: .4)),
            ],
          ),
        );

    return RCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(I18n.instance.t('mobileThemes.sample.title'), style: Brand.serif(20, weight: 500))),
              Text('2 / 3', style: tx(12, w: 7, c: theme.fg)),
            ],
          ),
          const SizedBox(height: 4),
          Text(I18n.instance.t('mobileThemes.sample.hint'), style: tx(12, c: Tw.gray600)),
          const SizedBox(height: 14),
          step(LucideIcons.droplets, I18n.instance.t('mobileThemes.sample.cleanser'), true),
          const SizedBox(height: 8),
          step(LucideIcons.sparkles, I18n.instance.t('mobileThemes.sample.serum'), true),
          const SizedBox(height: 8),
          step(LucideIcons.sun, I18n.instance.t('mobileThemes.sample.sunscreen'), false),
          const SizedBox(height: 16),
          PrimaryButton(onPressed: () {}, color: theme.primary, label: I18n.instance.t('mobileThemes.sample.done')),
        ],
      ),
    );
  }
}
