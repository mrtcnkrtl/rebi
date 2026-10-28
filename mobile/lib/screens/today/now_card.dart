import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n.dart';
import '../../core/reminder_text.dart';
import '../../core/today_plan.dart';
import '../../ui/brand/palette.dart';
import '../../state/theme_controller.dart';
import '../../state/today_plan_controller.dart';
import '../../ui/tw.dart';
import '../../ui/widgets/common.dart';
import '../../ui/widgets/skeleton.dart';
import 'day_flow.dart';
import 'today_clock.dart';
import 'today_widgets.dart';

IconData _reminderIcon(String id) => switch (id) {
      'routine_morning' => LucideIcons.sun,
      'routine_evening' => LucideIcons.moon,
      'water_intake' => LucideIcons.droplet,
      'spf_refresh' => LucideIcons.sunMedium,
      'nutrition_log' => LucideIcons.apple,
      'daily_checkin' => LucideIcons.clipboardCheck,
      'restock_check' => LucideIcons.packageCheck,
      'lip_balm' => LucideIcons.heart,
      'makeup_log' || 'makeup_removal' => LucideIcons.sparkles,
      _ => LucideIcons.bell,
    };

/// "Gün akışı" kartı: uyanmadan uykuya zaman şeridi, altında şu an penceresi açık olan hatırlatıcılar eylem
/// düğmeleriyle ve sıradakiler. Su hatırlatması şeritte noktalarla görünür, kendi kartında kaydedilir.
class NowCard extends StatefulWidget {
  const NowCard({
    super.key,
    required this.controller,
    required this.theme,
    required this.onAction,
    required this.onRetryPending,
    this.onOpenSettings,
  });

  final TodayPlanController controller;
  final RebiTheme theme;

  /// Bir hatırlatıcı eylemi seçildi (olay kaydı, ekrana gitme ya da seçim ekranı).
  final Future<void> Function(ReminderAction action) onAction;

  /// Bekleyen kayıtları şimdi göndermeyi dene.
  final Future<void> Function() onRetryPending;

  /// Hatırlatıcı ayarları ekranını açar; null ise simge gösterilmez.
  final VoidCallback? onOpenSettings;

  @override
  State<NowCard> createState() => _NowCardState();
}

class _NowCardState extends State<NowCard> {
  bool _busy = false;
  bool _retrying = false;

  Future<void> _retryPending() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    try {
      await widget.onRetryPending();
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  Future<void> _run(ReminderAction action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onAction(action);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.controller, I18n.instance]),
      builder: (context, _) {
        final i18n = I18n.instance;
        final c = widget.controller;
        final plan = c.plan;
        if (plan == null) {
          if (c.loading) return const SkeletonCard(lines: 1, withActions: true);
          if (c.failed) return _failed(i18n, c);
          return const SizedBox.shrink();
        }
        return _content(i18n, plan);
      },
    );
  }

  Widget _failed(I18n i18n, TodayPlanController c) => RCard(
        padding: const EdgeInsets.all(12),
        radius: 20,
        borderColor: Tw.amber200,
        color: Color.alphaBlend(Tw.amber50.withValues(alpha: .6), Tw.surface),
        child: Row(
          children: [
            Icon(LucideIcons.wifiOff, size: 18, color: Tw.amber600),
            const SizedBox(width: 10),
            Expanded(child: Text(i18n.t('mobileToday.loadFailed'), style: tx(12, c: Tw.amber900))),
            TextLink(i18n.t('mobileToday.retry'), onTap: c.reload, style: tx(12, w: 6, c: widget.theme.primary)),
          ],
        ),
      );

  Widget _content(I18n i18n, TodayPlan plan) {
    final theme = widget.theme;
    final now = todayPanelClock();
    // Su kendi kartında; sabah/akşam rutini kahraman kartta ve alt çubukta yaşar, "şimdi" listesinde tekrar etmez.
    const handledElsewhere = {'water_intake', 'routine_morning', 'routine_evening'};
    final visible = plan.reminders.where((r) => r.id != 'water_intake').toList();
    final current = [for (final r in visible) if (!handledElsewhere.contains(r.id) && reminderPhase(r, now) == ReminderPhase.now) r];
    final upcoming = [for (final r in visible) if (reminderPhase(r, now) == ReminderPhase.upcoming) r];

    return RCard(
      padding: const EdgeInsets.fromLTRB(20, 16, 14, 18),
      radius: 24,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(child: Text(i18n.t('mobileToday.flow.title'), style: heading(22))),
            if (widget.onOpenSettings != null)
              IconButton(
                tooltip: i18n.t('mobileToday.settings'),
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                padding: EdgeInsets.zero,
                onPressed: widget.onOpenSettings,
                icon: Icon(LucideIcons.settings2, size: 20, color: Tw.gray500),
              ),
          ]),
          if (widget.controller.pendingCount > 0) ...[
            const SizedBox(height: 8),
            _pendingRow(i18n, widget.controller.pendingCount),
          ],
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: DayFlowStrip(plan: plan, theme: theme, now: now.hour * 60 + now.minute),
          ),
          const SizedBox(height: 10),
          Padding(padding: const EdgeInsets.only(right: 6), child: FlowLegend(plan: plan, theme: theme)),
          const SizedBox(height: 14),
          const Hairline(),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(i18n.t('mobileToday.now'), style: tx(11.5, w: 7, c: Tw.gray500, ls: 1.1)),
                const SizedBox(height: 8),
                if (current.isEmpty)
                  Text(i18n.t('mobileToday.nothingNow'), style: tx(13, c: Tw.gray600, h: relaxed))
                else
                  for (final r in current) ...[_reminderTile(i18n, plan, r), const SizedBox(height: 8)],
                if (upcoming.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(i18n.t('mobileToday.later'), style: tx(11.5, w: 7, c: Tw.gray500, ls: 1.1)),
                  const SizedBox(height: 6),
                  for (final r in upcoming.take(3))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('${r.start} · ${reminderTitle(i18n, r)}', style: tx(13, c: Tw.gray600)),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pendingRow(I18n i18n, int count) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Color.alphaBlend(Tw.amber50.withValues(alpha: .8), Tw.surface),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Tw.amber200),
        ),
        child: Row(children: [
          Icon(LucideIcons.cloudOff, size: 14, color: Tw.amber600),
          const SizedBox(width: 8),
          Expanded(child: Text(i18n.t('mobileToday.pending', {'count': count}), style: tx(11, c: Tw.amber900))),
          if (_retrying)
            SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Tw.amber600))
          else
            TextLink(i18n.t('mobileToday.pendingRetry'), onTap: _retryPending, style: tx(11, w: 6, c: widget.theme.primary)),
        ]),
      );

  Widget _reminderTile(I18n i18n, TodayPlan plan, Reminder r) {
    final actions = reminderActions(r);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: widget.theme.primary.withValues(alpha: .05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: widget.theme.primaryLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(_reminderIcon(r.id), size: 16, color: widget.theme.primary),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(reminderTitle(i18n, r), style: tx(13, w: 7, c: Tw.gray800)),
                    const SizedBox(height: 2),
                    Text(reminderBody(i18n, r, plan.weather), style: tx(11, c: Tw.gray600, h: relaxed)),
                  ],
                ),
              ),
            ],
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final a in actions)
                TodayPill(
                  label: i18n.t('mobileToday.actions.${a.labelKey}'),
                  color: widget.theme.primary,
                  onTap: _busy ? null : () => _run(a),
                ),
            ]),
          ],
        ],
      ),
    );
  }
}
