import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/day_log.dart';
import '../../core/i18n.dart';
import '../../core/routine_logic.dart';
import '../../core/today_plan.dart';
import '../../state/theme_controller.dart';
import '../../state/today_actions.dart';
import '../../ui/tw.dart';
import '../../ui/widgets/common.dart';
import '../../ui/widgets/progress_ring.dart';
import 'today_clock.dart';
import 'today_widgets.dart';

const _makeupColor = Color(0xFFDB2777);
const _nutritionColor = Color(0xFF16A34A);

/// Gün içi takip kartları: su, makyaj, beslenme ve güneş kremi. Her kart tek dokunuşla kayıt
/// alır; ayrıntı gereken kayıtlar (temizleme yöntemi, yenilen şeyler, su miktarı) alt sayfa açar.
class TrackingTiles extends StatefulWidget {
  const TrackingTiles({super.key, required this.actions, required this.theme, required this.onOpenSheet});

  final TodayActions actions;
  final RebiTheme theme;
  final void Function(DaySheet sheet) onOpenSheet;

  @override
  State<TrackingTiles> createState() => _TrackingTilesState();
}

class _TrackingTilesState extends State<TrackingTiles> {
  bool _busy = false;

  /// Peş peşe dokunuşlar aynı kaydı iki kez göndermesin.
  Future<void> _run(Future<Object?> Function() job) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await job();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.actions.plan, I18n.instance]),
      builder: (context, _) {
        final plan = widget.actions.plan.plan;
        if (plan == null) return const SizedBox.shrink();
        final i18n = I18n.instance;
        final p = plan.progress;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _water(i18n, plan, p),
            const SizedBox(height: 10),
            _makeup(i18n, p),
            const SizedBox(height: 10),
            _nutrition(i18n, p),
            const SizedBox(height: 10),
            _spf(i18n, plan, p),
          ],
        );
      },
    );
  }

  Widget _tile({
    required IconData icon,
    required Color color,
    required String title,
    required Widget subtitle,
    Widget? trailing,
    List<Widget> actions = const [],
    Widget? footer,
  }) =>
      RCard(
        padding: const EdgeInsets.all(14),
        radius: 20,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                TodayIconBadge(icon: icon, color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: tx(14, w: 7, c: Tw.gray800)),
                      const SizedBox(height: 2),
                      subtitle,
                    ],
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 8), trailing],
              ],
            ),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: actions),
            ],
            if (footer != null) ...[const SizedBox(height: 8), footer],
          ],
        ),
      );

  Text _sub(String text, {Color? color, int w = 4}) => Text(text, style: tx(12, c: color ?? Tw.gray600, w: w, h: snug));

  // --- Su ---------------------------------------------------------------

  Widget _water(I18n i18n, TodayPlan plan, DayProgress p) {
    final reached = p.waterMl >= waterTargetMl;
    final reminder = plan.reminders.where((r) => r.id == 'water_intake').firstOrNull;
    final next = reminder == null ? null : nextReminderSlot(reminder, todayPanelClock());

    Future<void> add(int ml) => _run(() => widget.actions.record(
          'water_intake',
          {'ml': ml},
          message: i18n.t('mobileToday.toast.water', {'ml': ml}),
          undoPayload: {'ml': -ml},
        ));

    return _tile(
      icon: LucideIcons.droplet,
      color: Tw.blue500,
      title: i18n.t('mobileToday.waterTitle'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sub(i18n.t('mobileToday.waterProgress', {'ml': p.waterMl, 'target': waterTargetMl}), color: Tw.blueText, w: 6),
          if (reached)
            _sub(i18n.t('mobileToday.waterGoalReached'), color: Tw.emerald700, w: 5)
          else if (next != null)
            _sub(i18n.t('mobileToday.water.next', {'time': next}), color: Tw.gray500),
        ],
      ),
      trailing: ProgressRing(
        value: p.waterFraction,
        size: 52,
        stroke: 6,
        color: reached ? Tw.emerald500 : Tw.blue500,
        track: Tw.blue100,
        child: Text('${(p.waterFraction * 100).round()}%', style: tx(11, w: 7, c: Tw.gray700)),
      ),
      actions: [
        if (!reached) ...[
          for (final (ml, key) in [(250, 'water250'), (500, 'water500')])
            TodayPill(
              label: i18n.t('mobileToday.actions.$key'),
              color: ml == 250 ? Tw.blue600 : Tw.blueText,
              filled: ml == 250,
              onTap: _busy ? null : () => add(ml),
            ),
        ],
        TodayPill(
          label: i18n.t('mobileToday.actions.waterMore'),
          color: Tw.blueText,
          onTap: () => widget.onOpenSheet(DaySheet.water),
        ),
      ],
    );
  }

  // --- Makyaj -----------------------------------------------------------

  Widget _makeup(I18n i18n, DayProgress p) {
    final color = _makeupColor;
    final title = i18n.t('mobileToday.makeup.title');
    Future<void> set(bool used) => _run(() => widget.actions.record(
          'makeup',
          {'used': used},
          message: i18n.t(used ? 'mobileToday.toast.makeupUsed' : 'mobileToday.toast.makeupNone'),
        ));
    void openCleansing() => widget.onOpenSheet(DaySheet.cleansing);

    if (!p.makeupLogged) {
      return _tile(
        icon: LucideIcons.sparkles,
        color: color,
        title: title,
        subtitle: _sub(i18n.t('mobileToday.makeup.ask')),
        actions: [
          TodayPill(label: i18n.t('mobileToday.actions.yes'), color: color, filled: true, onTap: _busy ? null : () => set(true)),
          TodayPill(label: i18n.t('mobileToday.actions.no'), color: color, onTap: _busy ? null : () => set(false)),
        ],
      );
    }
    if (p.makeupUsed && p.makeupRemoved) {
      final method = p.removalMethod;
      return _tile(
        icon: LucideIcons.sparkles,
        color: color,
        title: title,
        subtitle: _sub(
          method == null
              ? i18n.t('mobileToday.makeup.cleaned')
              : i18n.t('mobileToday.makeup.cleanedWith', {'method': i18n.t('mobileToday.cleansing.$method.title')}),
          color: Tw.emerald700,
          w: 5,
        ),
        trailing: Icon(LucideIcons.circleCheck, size: 22, color: Tw.emerald500),
        actions: [TodayPill(label: i18n.t('mobileToday.actions.change'), color: color, onTap: openCleansing)],
      );
    }
    if (p.makeupUsed) {
      return _tile(
        icon: LucideIcons.sparkles,
        color: color,
        title: title,
        subtitle: _sub(
          i18n.t(p.removalMethod == 'none' ? 'mobileToday.makeup.notCleaned' : 'mobileToday.makeup.usedPending'),
          color: Tw.amber700,
          w: 5,
        ),
        actions: [TodayPill(label: i18n.t('mobileToday.actions.removed'), color: color, filled: true, onTap: openCleansing)],
      );
    }
    return _tile(
      icon: LucideIcons.sparkles,
      color: color,
      title: title,
      subtitle: _sub(i18n.t('mobileToday.makeup.none')),
      actions: [TodayPill(label: i18n.t('mobileToday.makeup.changeToUsed'), color: color, onTap: _busy ? null : () => set(true))],
    );
  }

  // --- Beslenme ---------------------------------------------------------

  Widget _nutrition(I18n i18n, DayProgress p) {
    final title = i18n.t('mobileToday.nutrition.title');
    if (!p.nutritionLogged) {
      return _tile(
        icon: LucideIcons.apple,
        color: _nutritionColor,
        title: title,
        subtitle: _sub(i18n.t('mobileToday.nutrition.ask')),
        actions: [
          TodayPill(
            label: i18n.t('mobileToday.actions.junkYes'),
            color: _nutritionColor,
            filled: true,
            onTap: () => widget.onOpenSheet(DaySheet.nutrition),
          ),
          TodayPill(
            label: i18n.t('mobileToday.actions.junkNo'),
            color: _nutritionColor,
            onTap: _busy
                ? null
                : () => _run(() => widget.actions.record(
                      'nutrition',
                      {'junk_food': false},
                      message: i18n.t('mobileToday.toast.nutritionClean'),
                    )),
          ),
        ],
      );
    }
    final picked = nutritionSelection(p.nutrition).where((c) => c != 'balanced').toList();
    final clean = picked.isEmpty && p.nutrition['junk_food'] != true;
    return _tile(
      icon: LucideIcons.apple,
      color: _nutritionColor,
      title: title,
      subtitle: _sub(
        clean
            ? i18n.t(p.nutrition['balanced'] == true ? 'mobileToday.nutrition.balanced' : 'mobileToday.nutrition.clean')
            : picked.map((c) => i18n.t('mobileToday.nutrition.choices.$c.title')).join(', '),
        color: clean ? Tw.emerald700 : Tw.amber700,
        w: 5,
      ),
      trailing: clean ? Icon(LucideIcons.circleCheck, size: 22, color: Tw.emerald500) : null,
      actions: [
        TodayPill(
          label: i18n.t('mobileToday.actions.edit'),
          color: _nutritionColor,
          onTap: () => widget.onOpenSheet(DaySheet.nutrition),
        ),
      ],
    );
  }

  // --- Güneş kremi ------------------------------------------------------

  Widget _spf(I18n i18n, TodayPlan plan, DayProgress p) {
    final uv = plan.weather['uv_index'];
    final high = uv is num && uv >= 5;
    return _tile(
      icon: LucideIcons.sunMedium,
      color: Tw.amber600,
      title: i18n.t('mobileToday.spf.title'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sub(
            p.spfRefreshes > 0
                ? i18n.t('mobileToday.spfRefreshed', {'n': p.spfRefreshes})
                : i18n.t(high ? 'mobileToday.spf.hintHigh' : 'mobileToday.spf.hint'),
            color: p.spfRefreshes > 0 ? Tw.emerald700 : Tw.gray600,
            w: p.spfRefreshes > 0 ? 5 : 4,
          ),
          if (uv != null) _sub('UV ${str(uv)}', color: Tw.gray500),
        ],
      ),
      actions: [
        TodayPill(
          label: i18n.t('mobileToday.spf.done'),
          color: Tw.amber600,
          filled: high,
          onTap: _busy
              ? null
              : () => _run(() => widget.actions.record('spf_refresh', const {}, message: i18n.t('mobileToday.toast.spf'))),
        ),
      ],
    );
  }
}
