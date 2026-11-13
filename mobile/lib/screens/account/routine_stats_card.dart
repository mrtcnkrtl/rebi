
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/checkin_stats.dart';
import '../../core/i18n.dart';
import '../../state/theme_controller.dart';
import '../../ui/tw.dart';
import '../../ui/widgets/common.dart';
import 'account_parts.dart';

/// Rutin ve check-in özeti: seri, toplam check-in, rutine uyum, hedef seri ilerlemesi ve kabul tarihinden bu yana geçen gün.
class AccountRoutineStatsCard extends StatelessWidget {
  const AccountRoutineStatsCard({super.key, required this.theme, required this.stats});

  final RebiTheme theme;
  final ProfileRoutineStats stats;

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final s = stats;

    Widget tile(String value, String label, Color color) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Tw.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Tw.gray100),
            ),
            child: Column(
              children: [
                Text(value, style: tx(26, w: 7, c: color).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                const SizedBox(height: 2),
                Text(label, textAlign: TextAlign.center, style: tx(12, w: 5, c: Tw.gray600, h: snug)),
              ],
            ),
          ),
        );

    Widget smallLink(String label, VoidCallback onTap, Color border, Color color) => Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: border)),
              child: Text(label, style: tx(13, w: 6, c: color)),
            ),
          ),
        );

    return RCard(
      padding: const EdgeInsets.all(18),
      radius: 24,
      borderColor: theme.primaryLight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccountSectionTitle(icon: LucideIcons.target, color: theme.fg, text: i18n.t('profile.routineSummaryTitle')),
          const SizedBox(height: 10),
          Text(i18n.t('mobileAccount.stats.intro', {'n': routineStreakGoalDays}), style: tx(12.5, c: Tw.gray600, h: relaxed)),
          const SizedBox(height: 14),
          Row(
            children: [
              tile('${s.streak}', i18n.t('profile.streak'), theme.fg),
              const SizedBox(width: 8),
              tile('${s.totalCheckIns}', i18n.t('profile.totalCheckins'), Tw.gray800),
            ],
          ),
          if (s.appliedRatePercent != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: Tw.gray50, borderRadius: BorderRadius.circular(14), border: Border.all(color: Tw.gray100)),
              child: Row(
                children: [
                  Icon(LucideIcons.clipboardCheck, size: 16, color: Tw.gray500),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(i18n.t('profile.adherence'), style: tx(13, w: 6, c: Tw.gray800)),
                        Text.rich(
                          TextSpan(children: [
                            TextSpan(text: i18n.t('mobileAccount.stats.applied')),
                            TextSpan(text: '${s.appliedRatePercent}%', style: tx(12, w: 7, c: Tw.gray800)),
                          ]),
                          style: tx(12, c: Tw.gray600, h: snug),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(i18n.t('mobileAccount.stats.goal', {'n': routineStreakGoalDays}), style: tx(12, c: Tw.gray600)),
              Text('${s.goalProgress}%', style: tx(12, c: Tw.gray600)),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: Container(
              height: 8,
              color: Tw.gray100,
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: s.goalProgress / 100,
                child: Container(decoration: BoxDecoration(color: theme.primary, borderRadius: BorderRadius.circular(999))),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (s.daysSinceAccept != null)
            Text.rich(
              TextSpan(children: [
                TextSpan(text: i18n.t('mobileAccount.stats.journey')),
                TextSpan(text: i18n.t('mobileAccount.stats.days', {'n': s.daysSinceAccept}), style: tx(12, w: 7, c: Tw.gray800)),
                TextSpan(text: i18n.t('mobileAccount.stats.sinceAccept')),
              ]),
              textAlign: TextAlign.center,
              style: tx(12, c: Tw.gray600),
            )
          else
            Text(i18n.t('mobileAccount.stats.noAcceptDate'), textAlign: TextAlign.center, style: tx(12, c: Tw.gray500)),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              smallLink(i18n.t('mobileAccount.stats.checkin'), () => context.go('/dashboard/checkin'), theme.primaryLight, theme.fg),
              smallLink(i18n.t('mobileAccount.stats.addPhoto'), () => context.push('/dashboard/analyze?photo=1'), Tw.gray200, Tw.gray700),
            ],
          ),
        ],
      ),
    );
  }
}
