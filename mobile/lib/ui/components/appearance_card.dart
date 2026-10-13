import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/i18n.dart';
import '../../state/theme_controller.dart';
import '../tw.dart';
import '../widgets/common.dart';

/// Görünüm seçici: sistemi izle, açık ya da koyu. Renk temasından (Klasik Teal, Pembe Kalp…) bağımsızdır.
class AppearanceCard extends StatelessWidget {
  const AppearanceCard({super.key, required this.theme});

  final RebiTheme theme;

  static const _modes = [
    (ThemeMode.system, 'system', LucideIcons.smartphone),
    (ThemeMode.light, 'light', LucideIcons.sun),
    (ThemeMode.dark, 'dark', LucideIcons.moon),
  ];

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final ctrl = context.watch<ThemeController>();
    return RCard(
      padding: const EdgeInsets.all(16),
      radius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Icon(Tw.dark ? LucideIcons.moon : LucideIcons.sun, size: 16, color: theme.primary),
            const SizedBox(width: 8),
            Text(i18n.t('mobileAppearance.title'), style: tx(14, w: 7, c: Tw.gray800)),
          ]),
          const SizedBox(height: 4),
          Text(i18n.t('mobileAppearance.hint'), style: tx(12, c: Tw.gray500, h: snug)),
          const SizedBox(height: 12),
          Row(children: [
            for (final (mode, key, icon) in _modes) ...[
              if (mode != _modes.first.$1) const SizedBox(width: 8),
              Expanded(
                child: ChoiceChipBox(
                  label: i18n.t('mobileAppearance.$key'),
                  selected: ctrl.mode == mode,
                  radius: 12,
                  center: true,
                  fontSize: 13,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  activeBorder: theme.primary,
                  activeBg: theme.primaryLight.withValues(alpha: .4),
                  activeText: theme.primaryDark,
                  leading: Icon(icon, size: 14, color: ctrl.mode == mode ? theme.primaryDark : Tw.gray400),
                  onTap: () => ctrl.setMode(mode),
                ),
              ),
            ],
          ]),
        ],
      ),
    );
  }
}
