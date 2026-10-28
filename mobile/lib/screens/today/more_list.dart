import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n.dart';
import '../../state/theme_controller.dart';
import '../../ui/tw.dart';
import 'today_widgets.dart';

/// "Daha fazlası": Bugün'ün altındaki karolar. Eskiden altı satırlık uzun bir listeydi; şimdi iki sütunlu, her biri tek
/// dokunuşla bir yere götüren sakin karolar (check-in, rafım, hızlı fotoğraf, yeni analiz, haftanın tamamı, geçmiş).
class TodayMoreList extends StatelessWidget {
  const TodayMoreList({super.key, required this.theme, required this.checkinDone, this.shelfCount = 0});

  final RebiTheme theme;
  final bool checkinDone;

  /// Rafta bitmiş ürün sayısı (karonun alt metni).
  final int shelfCount;

  @override
  Widget build(BuildContext context) {
    final i18n = I18n.instance;
    final tiles = <_MoreTile>[
      _MoreTile(
        icon: checkinDone ? LucideIcons.circleCheck : LucideIcons.clipboardCheck,
        color: checkinDone ? Tw.emerald700 : theme.primary,
        title: i18n.t('dashboard.dailyCheckinTitle'),
        subtitle: i18n.t(checkinDone ? 'mobileToday.checkinDoneToday' : 'dashboard.dailyCheckinSubtitle'),
        onTap: () => context.go('/dashboard/checkin'),
      ),
      _MoreTile(
        icon: LucideIcons.packageCheck,
        color: shelfCount > 0 ? Tw.amber700 : theme.primary,
        title: i18n.t('mobileShelf.title'),
        subtitle: i18n.t(shelfCount > 0 ? 'mobileShelf.countHint' : 'mobileShelf.emptyHint', {'n': shelfCount}),
        onTap: () => context.go('/dashboard/shelf'),
      ),
      _MoreTile(
        icon: LucideIcons.camera,
        color: Tw.purple600,
        title: i18n.t('mobileToday.quickPhoto'),
        onTap: () => context.push('/dashboard/analyze?photo=1'),
      ),
      _MoreTile(
        icon: LucideIcons.scanFace,
        color: Tw.blue600,
        title: i18n.t('mobileToday.newAnalysis'),
        onTap: () => context.go('/dashboard/analyze'),
      ),
      _MoreTile(
        icon: LucideIcons.calendarRange,
        color: Tw.amber700,
        title: i18n.t('mobileToday.showFullPlan'),
        onTap: () => context.go('/dashboard/routine'),
      ),
      _MoreTile(
        icon: LucideIcons.calendarDays,
        color: Tw.green700,
        title: i18n.t('mobileHistory.open'),
        onTap: () => context.go('/dashboard/history'),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(i18n.t('mobileToday.more.title')),
        for (var i = 0; i < tiles.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: tiles[i]),
                const SizedBox(width: 12),
                Expanded(child: i + 1 < tiles.length ? tiles[i + 1] : const SizedBox.shrink()),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _MoreTile extends StatelessWidget {
  const _MoreTile({required this.icon, required this.color, required this.title, required this.onTap, this.subtitle});

  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tint = Color.alphaBlend(color.withValues(alpha: .07), Tw.surface);
    return Semantics(
      button: true,
      label: subtitle == null ? title : '$title. $subtitle',
      excludeSemantics: true,
      child: Material(
        color: tint,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 116),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), border: Border.all(color: Tw.gray100)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: color.withValues(alpha: .15), shape: BoxShape.circle),
                  child: Icon(icon, size: 20, color: Tw.readable(color, bg: Color.alphaBlend(color.withValues(alpha: .15), tint))),
                ),
                const Spacer(),
                const SizedBox(height: 10),
                Text(title, style: tx(14.5, w: 6, c: Tw.gray900, h: 1.25)),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(subtitle!, style: tx(12, c: Tw.gray500, h: snug), maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
