import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/i18n.dart';
import '../core/reminder_text.dart';
import '../core/routine_logic.dart';
import '../core/today_plan.dart';
import '../state/theme_controller.dart';
import '../state/today_plan_controller.dart';
import '../ui/tw.dart';
import '../ui/widgets/common.dart';

/// Hatırlatıcı pencerelerinin karşılaştırıldığı saat. Testlerde sabitlemek için değiştirilir.
@visibleForTesting
DateTime Function() todayPanelClock = DateTime.now;

IconData _reminderIcon(String id) => switch (id) {
      'routine_morning' => LucideIcons.sun,
      'routine_evening' => LucideIcons.moon,
      'water_intake' => LucideIcons.droplet,
      'spf_refresh' => LucideIcons.sun,
      'nutrition_log' => LucideIcons.apple,
      'daily_checkin' => LucideIcons.clipboardCheck,
      'lip_balm' => LucideIcons.heart,
      'makeup_log' || 'makeup_removal' => LucideIcons.sparkles,
      _ => LucideIcons.bell,
    };

/// Panelin "Bugün" kartı: su ilerlemesi, yapılanlar ve saat aralıklı hatırlatıcılar.
class TodayPanel extends StatefulWidget {
  const TodayPanel({
    super.key,
    required this.controller,
    required this.theme,
    required this.onAction,
    required this.onRetryPending,
  });

  final TodayPlanController controller;
  final RebiTheme theme;

  /// Bir hatırlatıcı eylemi seçildi (olay kaydı ya da ekrana gitme).
  final Future<void> Function(ReminderAction action) onAction;

  /// Bekleyen kayıtları şimdi göndermeyi dene.
  final Future<void> Function() onRetryPending;

  @override
  State<TodayPanel> createState() => _TodayPanelState();
}

class _TodayPanelState extends State<TodayPanel> {
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
          if (c.loading) {
            return const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: RingSpinner(size: 28, stroke: 3)));
          }
          if (c.failed) return _failed(i18n, c);
          return const SizedBox.shrink();
        }
        return _content(i18n, plan);
      },
    );
  }

  Widget _failed(I18n i18n, TodayPlanController c) => RCard(
        padding: const EdgeInsets.all(12),
        borderColor: Tw.amber200,
        color: Color.alphaBlend(Tw.amber50.withValues(alpha: .6), Colors.white),
        child: Row(
          children: [
            const Icon(LucideIcons.wifiOff, size: 18, color: Tw.amber600),
            const SizedBox(width: 10),
            Expanded(child: Text(i18n.t('mobileToday.loadFailed'), style: tx(12, c: Tw.amber900))),
            TextLink(i18n.t('mobileToday.retry'), onTap: c.reload, style: tx(12, w: 6, c: widget.theme.primary)),
          ],
        ),
      );

  Widget _content(I18n i18n, TodayPlan plan) {
    final theme = widget.theme;
    final now = todayPanelClock();
    final visible = plan.reminders.where((r) => r.id != 'water_intake').toList();
    final current = [for (final r in visible) if (reminderPhase(r, now) == ReminderPhase.now) r];
    final upcoming = [for (final r in visible) if (reminderPhase(r, now) == ReminderPhase.upcoming) r];
    final p = plan.progress;

    return RCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Icon(LucideIcons.calendarCheck, size: 16, color: theme.primary),
            const SizedBox(width: 8),
            Text(i18n.t('mobileToday.title'), style: tx(12, w: 7, c: Tw.gray800)),
          ]),
          if (widget.controller.pendingCount > 0) ...[
            const SizedBox(height: 8),
            _pendingRow(i18n, widget.controller.pendingCount),
          ],
          const SizedBox(height: 12),
          _water(i18n, p),
          if (_doneChips(i18n, p) case final chips when chips.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 6, runSpacing: 6, children: chips),
          ],
          const SizedBox(height: 12),
          Text(i18n.t('mobileToday.now'), style: tx(11, w: 6, c: Tw.gray600)),
          const SizedBox(height: 6),
          if (current.isEmpty)
            Text(i18n.t('mobileToday.nothingNow'), style: tx(12, c: Tw.gray500))
          else
            for (final r in current) ...[_reminderTile(i18n, plan, r), const SizedBox(height: 8)],
          if (upcoming.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(i18n.t('mobileToday.later'), style: tx(11, w: 6, c: Tw.gray600)),
            const SizedBox(height: 4),
            for (final r in upcoming.take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text('${r.start} · ${reminderTitle(i18n, r)}', style: tx(12, c: Tw.gray500)),
              ),
          ],
        ],
      ),
    );
  }

  Widget _pendingRow(I18n i18n, int count) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Color.alphaBlend(Tw.amber50.withValues(alpha: .8), Colors.white),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Tw.amber200),
        ),
        child: Row(children: [
          const Icon(LucideIcons.cloudOff, size: 14, color: Tw.amber600),
          const SizedBox(width: 8),
          Expanded(child: Text(i18n.t('mobileToday.pending', {'count': count}), style: tx(11, c: Tw.amber900))),
          if (_retrying)
            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Tw.amber600))
          else
            TextLink(i18n.t('mobileToday.pendingRetry'), onTap: _retryPending, style: tx(11, w: 6, c: widget.theme.primary)),
        ]),
      );

  Widget _water(I18n i18n, DayProgress p) {
    final reached = p.waterMl >= waterTargetMl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          const Icon(LucideIcons.droplet, size: 16, color: Tw.blue500),
          const SizedBox(width: 6),
          Text(i18n.t('mobileToday.waterTitle'), style: tx(12, w: 6, c: Tw.gray800)),
          const Spacer(),
          Text(i18n.t('mobileToday.waterProgress', {'ml': p.waterMl, 'target': waterTargetMl}), style: tx(12, w: 6, c: Tw.blue500)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: p.waterFraction,
            minHeight: 8,
            backgroundColor: Tw.blue100,
            color: Tw.blue500,
          ),
        ),
        const SizedBox(height: 8),
        if (reached)
          Text(i18n.t('mobileToday.waterGoalReached'), style: tx(11, w: 5, c: Tw.emerald700))
        else
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final (ml, key) in [(250, 'water250'), (500, 'water500')])
              _pill(
                i18n.t('mobileToday.actions.$key'),
                () => _run(ReminderAction(key, type: 'water_intake', payload: {'ml': ml})),
                border: Tw.blue100,
                bg: Tw.blue50,
                fg: Tw.blue500,
              ),
          ]),
      ],
    );
  }

  List<Widget> _doneChips(I18n i18n, DayProgress p) {
    Widget chip(String text) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: Tw.green100, borderRadius: BorderRadius.circular(999)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(LucideIcons.check, size: 12, color: Tw.green700),
            const SizedBox(width: 4),
            Text(text, style: tx(10, w: 5, c: Tw.green700)),
          ]),
        );
    return [
      if (p.morningDone) chip(i18n.t('mobileToday.morningDone')),
      if (p.eveningDone) chip(i18n.t('mobileToday.eveningDone')),
      if (p.makeupUsed) chip(i18n.t('mobileToday.makeupUsed')),
      if (p.makeupRemoved) chip(i18n.t('mobileToday.makeupRemoved')),
      if (p.spfRefreshes > 0) chip(i18n.t('mobileToday.spfRefreshed', {'n': p.spfRefreshes})),
    ];
  }

  Widget _reminderTile(I18n i18n, TodayPlan plan, Reminder r) {
    final actions = reminderActions(r);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: widget.theme.primary.withValues(alpha: .05),
        borderRadius: BorderRadius.circular(12),
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
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final a in actions)
                _pill(
                  i18n.t('mobileToday.actions.${a.labelKey}'),
                  () => _run(a),
                  border: widget.theme.primaryLight,
                  bg: Colors.white,
                  fg: widget.theme.primary,
                ),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _pill(String label, VoidCallback onTap, {required Color border, required Color bg, required Color fg}) => Opacity(
        opacity: _busy ? .5 : 1,
        child: Material(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _busy ? null : onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: border)),
              child: Text(label, style: tx(11, w: 6, c: fg)),
            ),
          ),
        ),
      );
}

/// Havaya göre bugün kullanılacak ürün önerileri (SPF, nemlendirici, dudak balsamı).
class EnvironmentAdviceCard extends StatelessWidget {
  const EnvironmentAdviceCard({super.key, required this.plan, required this.theme});

  final TodayPlan plan;
  final RebiTheme theme;

  @override
  Widget build(BuildContext context) {
    final i18n = I18n.instance;
    final w = plan.weather;
    String v(String key) => str(w[key]);
    final sourceKey = ['live', 'tracking', 'profile'].contains(plan.weatherSource) ? plan.weatherSource : 'default';

    return RCard(
      padding: const EdgeInsets.all(12),
      borderColor: Tw.blue100,
      gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Tw.blue50, Tw.cyan50]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Icon(LucideIcons.cloudSun, size: 16, color: Tw.blue500),
            const SizedBox(width: 8),
            Expanded(child: Text(i18n.t('mobileToday.advice.title'), style: tx(12, w: 7, c: Tw.gray800))),
          ]),
          const SizedBox(height: 4),
          Text(
            i18n.t('mobileToday.advice.weatherLine', {'temp': v('temperature'), 'uv': v('uv_index'), 'humidity': v('humidity')}),
            style: tx(12, w: 6, c: Tw.gray700),
          ),
          Text(i18n.t('mobileToday.advice.source.$sourceKey'), style: tx(10, c: Tw.gray500)),
          if (plan.environmentAdvice.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final item in plan.environmentAdvice)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: .75), borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      emojiText(truthy(item['icon']) ? str(item['icon']) : '🧴', 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(str(item['action']), style: tx(12, w: 7, c: Tw.gray800)),
                            if (truthy(item['detail'])) ...[
                              const SizedBox(height: 2),
                              Text(str(item['detail']), style: tx(11, c: Tw.gray600, h: relaxed)),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
          if (!plan.hasRealWeather)
            Text(i18n.t('mobileToday.advice.locationHint'), style: tx(10, c: Tw.gray500, h: relaxed)),
        ],
      ),
    );
  }
}
