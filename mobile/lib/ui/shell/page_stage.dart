import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n.dart';
import '../../state/theme_controller.dart';
import '../brand/brand_caps.dart';
import '../brand/brand_mark.dart';
import '../brand/motion.dart';
import '../brand/palette.dart';
import '../tw.dart';
import '../widgets/common.dart';
import '../widgets/stage_overlap.dart';

/// Bir alt sayfadan çıkış: geçmişte bir sayfa varsa ona, yoksa [fallback] (ilgili sekmenin kökü) yoluna döner.
void popOrGo(BuildContext context, String fallback) => context.canPop() ? context.pop() : context.go(fallback);

/// Ana sekmelerin dışındaki ekranların (Ben, Geçmiş, Rafım, Hatırlatıcılar, Görünüm, Abonelik, Hesap, Check-in) ortak üst sahnesi.
/// Bugün, Rutin ve Sohbet sahneleriyle aynı dil: seçili temanın derin tonu, krem Fraunces başlık, çok silik "R" imzası.
/// Alt köşeleri yuvarlaktır; ilk kart [overlap] kadar sahneye biner ([StagePage]). Durum çubuğu simgeleri sahne ekrandayken açıktır.
///
/// Soldan sağa/yukarıdan aşağı: (varsa) geri düğmesi ve sağ üst öğe → küçük harfli üst etiket → başlık → açıklama → [footer]
/// (ör. aralık seçici). Sahne içeriğin yeridir, bu yüzden sistem yazısı en çok %130 büyür; başlık satır kırar, taşmaz.
class PageStage extends StatelessWidget {
  const PageStage({
    super.key,
    required this.theme,
    required this.title,
    this.eyebrow,
    this.badge,
    this.subtitle,
    this.onBack,
    this.trailing,
    this.leading,
    this.footer,
    this.overlap = defaultOverlap,
  });

  /// Kartın sahneye binen yüksekliği (dp); sahnenin alt boşluğu bunu içerir.
  static const defaultOverlap = 30.0;

  final RebiTheme theme;
  final String title;

  /// Başlığın üstündeki küçük harfli etiket (ör. e-posta, tarih).
  final String? eyebrow;

  /// Başlığın üstünde küçük bir hap (ör. "Plus"); [eyebrow] yerine geçer, büyük harfe çevrilmez.
  final Widget? badge;
  final String? subtitle;

  /// Verilirse sol üstte "Geri" düğmesi çizilir (alt sayfalar). Sekme köklerinde null.
  final VoidCallback? onBack;

  /// Sağ üstteki öğe (ör. durum hapı).
  final Widget? trailing;

  /// Başlık bloğunun solundaki öğe (ör. hesap avatarı).
  final Widget? leading;

  /// Açıklamanın altındaki öğe (ör. aralık seçici); sahnenin içinde, krem üstünde.
  final Widget? footer;
  final double overlap;

  @override
  Widget build(BuildContext context) {
    final lang = I18n.instance.lang;
    final top = MediaQuery.paddingOf(context).top;
    final hasBar = onBack != null || trailing != null;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
        child: ColoredBox(
          color: theme.stage,
          child: Stack(
            children: [
              const Positioned(right: -64, top: -18, child: BrandWatermark(size: 240)),
              Padding(
                padding: EdgeInsets.fromLTRB(20, top + (hasBar ? 4 : 24), 16, 20 + overlap),
                child: MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1.3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (hasBar)
                        SizedBox(
                          height: 52,
                          child: Row(
                            children: [
                              if (onBack != null) _BackLink(onTap: onBack!),
                              const Spacer(),
                              ?trailing,
                            ],
                          ),
                        ),
                      if (hasBar) const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          if (leading != null) ...[leading!, const SizedBox(width: 16)],
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (eyebrow != null && eyebrow!.isNotEmpty)
                                  Reveal(
                                    offset: const Offset(0, 6),
                                    child: Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Text(
                                        brandCaps(eyebrow!, lang),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: tx(11.5, w: 6, c: Brand.cream.withValues(alpha: .72), ls: brandTracking(lang, 1.6)),
                                      ),
                                    ),
                                  ),
                                if (badge != null && (eyebrow == null || eyebrow!.isEmpty))
                                  Padding(padding: const EdgeInsets.only(bottom: 8), child: Align(alignment: Alignment.centerLeft, child: badge!)),
                                Reveal(
                                  delay: const Duration(milliseconds: 60),
                                  offset: const Offset(0, 12),
                                  child: Semantics(
                                    header: true,
                                    child: Text(title, style: Brand.serif(33, color: Brand.cream, h: 1.1, ls: -.8)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (subtitle != null && subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Reveal(
                          delay: const Duration(milliseconds: 120),
                          offset: const Offset(0, 8),
                          child: Text(subtitle!, style: tx(14, c: Brand.cream.withValues(alpha: .8), h: 1.45)),
                        ),
                      ],
                      if (footer != null) ...[
                        const SizedBox(height: 18),
                        Reveal(delay: const Duration(milliseconds: 180), offset: const Offset(0, 8), child: footer!),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sahne içi segment seçici (ör. 7 · 30 · 90 gün): seçili segment krem dolu ve derin tonda yazılı, diğerleri krem çerçeveli.
/// Segmentler eşit genişlikte ve en az 48 dp yüksekliktedir; seçili olan ekran okuyucuya "seçili" olarak bildirilir.
class StageSegments<T> extends StatelessWidget {
  const StageSegments({super.key, required this.theme, required this.options, required this.value, required this.onChanged});

  final RebiTheme theme;
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < options.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: _Segment(label: options[i].$2, selected: options[i].$1 == value, stage: theme.stage, onTap: () => onChanged(options[i].$1))),
        ],
      ],
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({required this.label, required this.selected, required this.stage, required this.onTap});

  final String label;
  final bool selected;
  final Color stage;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Pressable(
        onTap: selected ? null : onTap,
        scale: .96,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          constraints: const BoxConstraints(minHeight: 48),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? Brand.cream : Brand.cream.withValues(alpha: .06),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: selected ? Brand.cream : Brand.cream.withValues(alpha: .28), width: 1.3),
          ),
          child: Text(label, textAlign: TextAlign.center, style: tx(13.5, w: selected ? 7 : 6, c: selected ? stage : Brand.cream.withValues(alpha: .92))),
        ),
      ),
    );
  }
}

/// Sahnenin "Geri" bağlantısı: krem, çizgi ok + yazı; dokunma alanı en az 48 dp.
class _BackLink extends StatelessWidget {
  const _BackLink({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = I18n.instance.t('mobileNav.back');
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        scale: .95,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.chevronLeft, size: 22, color: Brand.cream),
                const SizedBox(width: 2),
                Text(label, style: tx(14.5, w: 6, c: Brand.cream.withValues(alpha: .92))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Sahneli sayfa iskeleti: kaydırılabilir gövde = tam genişlikte [PageStage] + ortalanmış içerik. [children]'ın ilki
/// sahneye biner, bu yüzden bir kart (ya da kart gibi bir yüzey) olmalıdır. Sahne durum çubuğunun altına uzanır;
/// kabuk bu yollarda üst güvenli alanı uygulamaz (`hasStage`).
class StagePage extends StatelessWidget {
  const StagePage({
    super.key,
    required this.theme,
    required this.title,
    required this.children,
    this.eyebrow,
    this.badge,
    this.subtitle,
    this.backTo,
    this.trailing,
    this.leading,
    this.footer,
    this.maxWidth = 672,
    this.controller,
    this.bottomPadding = 40,
    this.overlap = PageStage.defaultOverlap,
    this.onRefresh,
  });

  final RebiTheme theme;
  final String title;
  final String? eyebrow;
  final Widget? badge;
  final String? subtitle;

  /// Verilirse sahnede "Geri" çıkar: geçmişte sayfa varsa ona, yoksa bu yola döner (alt sayfalar).
  final String? backTo;
  final Widget? trailing;
  final Widget? leading;
  final Widget? footer;
  final List<Widget> children;
  final double maxWidth;
  final ScrollController? controller;
  final double bottomPadding;
  final double overlap;

  /// Verilirse sayfa aşağı çekilerek yenilenir.
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final back = backTo;
    final scroll = SingleChildScrollView(
        controller: controller,
        physics: onRefresh == null ? null : const AlwaysScrollableScrollPhysics(),
        child: StageOverlap(
          overlap: overlap,
          stage: PageStage(
            theme: theme,
            title: title,
            eyebrow: eyebrow,
            badge: badge,
            subtitle: subtitle,
            onBack: back == null ? null : () => popOrGo(context, back),
            trailing: trailing,
            leading: leading,
            footer: footer,
            overlap: overlap,
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPadding),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
              ),
            ),
          ),
        ),
      );
    return ThemedBackground(
      theme: theme,
      child: onRefresh == null ? scroll : PullToRefresh(color: theme.primary, onRefresh: onRefresh!, child: scroll),
    );
  }
}
