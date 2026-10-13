import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../core/i18n.dart';
import '../core/subscription.dart';
import '../state/auth_controller.dart';
import '../state/theme_controller.dart';
import '../ui/components/appearance_card.dart';
import '../ui/tw.dart';
import '../ui/widgets/common.dart';
import '../ui/widgets/theme_pattern_overlay.dart';

/// Tema seçimi + canlı önizleme (web: `pages/Themes.jsx`).
class ThemesScreen extends StatelessWidget {
  const ThemesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final ctrl = context.watch<ThemeController>();
    final theme = ctrl.theme;
    final plus = userHasRebiPlus(context.watch<AuthController>().user);

    void pick(RebiTheme t) {
      if (t.premium && !plus) {
        context.go('/dashboard/subscribe');
        return;
      }
      ctrl.setThemeId(t.id);
    }

    return ThemedPage(
      theme: theme,
      children: [
        Row(
          children: [
            Icon(LucideIcons.sparkles, size: 24, color: theme.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(i18n.t('themes.title'), style: tx(24, w: 7))),
          ],
        ),
        const SizedBox(height: 4),
        Text(i18n.t('themes.subtitle'), style: tx(14, c: Tw.gray500)),
        const SizedBox(height: 16),
        AppearanceCard(theme: theme),
        const SizedBox(height: 24),
        // Web: 2 sütunlu ızgara; kart yüksekliği içerikten gelir (önizleme h-28 = 112 px).
        for (var i = 0; i < rebiThemes.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final t in rebiThemes.values.skip(i).take(2).toList().asMap().entries) ...[
                  if (t.key > 0) const SizedBox(width: 12),
                  Expanded(
                    child: _ThemeCard(
                      t: t.value,
                      active: ctrl.themeId == t.value.id,
                      locked: t.value.premium && !plus,
                      onTap: () => pick(t.value),
                    ),
                  ),
                ],
                if (rebiThemes.length - i == 1) ...[const SizedBox(width: 12), const Expanded(child: SizedBox())],
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('Rebi Plus için ', style: tx(12, c: Tw.gray500)),
            TextLink('abonelik sayfası',
                onTap: () => context.go('/dashboard/subscribe'), style: tx(12, w: 6, c: theme.primary)),
            Text('.', style: tx(12, c: Tw.gray500)),
          ],
        ),
        const SizedBox(height: 32),
        Text('Canlı Önizleme', style: tx(14, w: 7, c: Tw.gray700)),
        const SizedBox(height: 12),
        RCard(
          borderColor: theme.primaryLight,
          clip: true,
          padding: EdgeInsets.zero,
          child: Stack(
            children: [
              if (theme.pattern.isNotEmpty)
                Positioned.fill(child: Opacity(opacity: .15, child: ThemePatternPreview(pattern: theme.pattern))),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(color: theme.primary, borderRadius: BorderRadius.circular(16)),
                          child: const Icon(LucideIcons.sparkles, size: 20, color: Colors.white),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Sabah Rutini', style: tx(14, w: 7)),
                              Text('3 adım', style: tx(11, c: Tw.gray500)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _PreviewRow(emoji: '🧴', label: 'Temizleme', theme: theme),
                    const SizedBox(height: 8),
                    _PreviewRow(emoji: '💧', label: 'Nemlendirme', theme: theme),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(color: theme.primary, borderRadius: BorderRadius.circular(12)),
                      child: Text('Rutini Başlat', textAlign: TextAlign.center, style: tx(14, w: 5, c: Colors.white)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.emoji, required this.label, required this.theme});

  final String emoji;
  final String label;
  final RebiTheme theme;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: theme.primaryLight, borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            Text(emoji),
            const SizedBox(width: 8),
            Expanded(child: Text(label, overflow: TextOverflow.ellipsis, style: tx(12, w: 5, c: theme.primaryDark))),
          ],
        ),
      );
}

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({required this.t, required this.active, required this.locked, required this.onTap});

  final RebiTheme t;
  final bool active;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final r = t.shape == 'angular' ? 8.0 : 16.0;
    Widget bar(double h, double? w, Color c) => Container(
          height: h,
          width: w,
          decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(r)),
        );

    return AnimatedScale(
      scale: active ? 1.02 : 1,
      duration: const Duration(milliseconds: 150),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: active ? [BoxShadow(color: t.primary.withValues(alpha: .9), spreadRadius: 2)] : null,
          ),
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Tw.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: active ? t.primary : Tw.gray200, width: 2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 112,
                  child: Container(
                    color: t.primaryLight,
                    child: Stack(
                      children: [
                        Positioned.fill(child: ThemePatternPreview(pattern: t.pattern)),
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              bar(8, 48, t.primary.withValues(alpha: .7)),
                              const SizedBox(height: 6),
                              bar(6, 64, Tw.gray300.withValues(alpha: .5)),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  bar(20, 20, t.primary.withValues(alpha: .5)),
                                  const SizedBox(width: 4),
                                  Expanded(child: bar(20, null, Colors.white.withValues(alpha: .6))),
                                ],
                              ),
                              const SizedBox(height: 6),
                              bar(24, double.infinity, t.primary.withValues(alpha: .3)),
                            ],
                          ),
                        ),
                        if (locked)
                          Positioned.fill(
                            child: ColoredBox(
                              color: Colors.white.withValues(alpha: .35),
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: .9),
                                    borderRadius: BorderRadius.circular(999),
                                    boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 4)],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(LucideIcons.lock, size: 12, color: Tw.gray800),
                                      const SizedBox(width: 4),
                                      Text('Plus', style: tx(10, w: 7, c: Tw.gray800)),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (active && !locked)
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(color: t.primary, shape: BoxShape.circle),
                              child: const Icon(LucideIcons.check, size: 16, color: Colors.white),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      Expanded(child: Text('${t.emoji} ${t.label}', style: tx(12, w: 6))),
                      if (t.premium) Text('PLUS', style: tx(9, w: 7, c: Tw.amber700, ls: .5)),
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
