import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n.dart';
import '../../state/theme_controller.dart';
import '../../ui/tw.dart';
import '../../ui/widgets/common.dart';
import 'today_widgets.dart';

/// "Daha fazlası": Bugün'ün altındaki tek liste. Eskiden üst üste dört ince düğmeydi; artık check-in, fotoğraf,
/// yeni analiz, haftanın tamamı ve geçmiş sakin satırlar hâlinde durur.
class TodayMoreList extends StatelessWidget {
  const TodayMoreList({super.key, required this.theme, required this.checkinDone, this.shelfCount = 0});

  final RebiTheme theme;
  final bool checkinDone;

  /// Rafta bitmiş ürün sayısı (satırın alt metni).
  final int shelfCount;

  @override
  Widget build(BuildContext context) {
    final i18n = I18n.instance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(i18n.t('mobileToday.more.title')),
        RCard(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          radius: 24,
          child: Column(
            children: [
              _MoreRow(
                icon: checkinDone ? LucideIcons.circleCheck : LucideIcons.clipboardCheck,
                color: checkinDone ? Tw.emerald700 : theme.primary,
                title: i18n.t('dashboard.dailyCheckinTitle'),
                subtitle: i18n.t(checkinDone ? 'mobileToday.checkinDoneToday' : 'dashboard.dailyCheckinSubtitle'),
                onTap: () => context.go('/dashboard/checkin'),
              ),
              const Hairline(indent: 64),
              _MoreRow(
                icon: LucideIcons.packageCheck,
                color: shelfCount > 0 ? Tw.amber700 : theme.primary,
                title: i18n.t('mobileShelf.title'),
                subtitle: i18n.t(shelfCount > 0 ? 'mobileShelf.countHint' : 'mobileShelf.emptyHint', {'n': shelfCount}),
                onTap: () => context.go('/dashboard/shelf'),
              ),
              const Hairline(indent: 64),
              _MoreRow(
                icon: LucideIcons.camera,
                color: Tw.purple600,
                title: i18n.t('mobileToday.quickPhoto'),
                onTap: () => context.push('/dashboard/analyze?photo=1'),
              ),
              const Hairline(indent: 64),
              _MoreRow(
                icon: LucideIcons.scanFace,
                color: Tw.blue600,
                title: i18n.t('mobileToday.newAnalysis'),
                onTap: () => context.go('/dashboard/analyze'),
              ),
              const Hairline(indent: 64),
              _MoreRow(
                icon: LucideIcons.calendarRange,
                color: Tw.amber700,
                title: i18n.t('mobileToday.showFullPlan'),
                onTap: () => context.go('/dashboard/routine'),
              ),
              const Hairline(indent: 64),
              _MoreRow(
                icon: LucideIcons.calendarDays,
                color: Tw.green700,
                title: i18n.t('mobileHistory.open'),
                onTap: () => context.go('/dashboard/history'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MoreRow extends StatelessWidget {
  const _MoreRow({required this.icon, required this.color, required this.title, required this.onTap, this.subtitle});

  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: title,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            child: Row(
              children: [
                TodayIconBadge(icon: icon, color: color, size: 40),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: tx(14.5, w: 6, c: Tw.gray900, h: snug)),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(subtitle!, style: tx(12, c: Tw.gray500, h: snug)),
                      ],
                    ],
                  ),
                ),
                Icon(LucideIcons.chevronRight, size: 18, color: Tw.gray400),
              ],
            ),
          ),
        ),
      );
}
