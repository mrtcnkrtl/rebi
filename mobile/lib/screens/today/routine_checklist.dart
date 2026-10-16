import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/day_log.dart';
import '../../core/i18n.dart';
import '../../core/routine_logic.dart';
import '../../core/routine_usage.dart';
import '../../core/today_plan.dart';
import '../../state/theme_controller.dart';
import '../../state/today_actions.dart';
import '../../ui/tw.dart';
import '../../ui/widgets/common.dart';
import 'today_clock.dart';
import 'today_widgets.dart';
import '../../ui/brand/glyphs.dart';

/// Günün rutini: sabah / akşam sekmeleri ve adım adım işaretlenen liste. Son adım işaretlenince
/// blok tamamlanır; alttaki "yaptım" düğmesiyle tek dokunuşta da tamamlanabilir.
class RoutineChecklistCard extends StatefulWidget {
  const RoutineChecklistCard({
    super.key,
    required this.actions,
    required this.theme,
    required this.dayLabel,
    required this.localized,
    required this.morning,
    required this.evening,
    this.morningNotes = const [],
    this.eveningNotes = const [],
  });

  final TodayActions actions;
  final RebiTheme theme;

  /// Haftanın günü (ör. "Cumartesi").
  final String dayLabel;
  final bool localized;
  final List<RoutineItem> morning;
  final List<RoutineItem> evening;

  /// Yaşam / beslenme önerileri (işaretlenmez, yalnızca okunur).
  final List<RoutineItem> morningNotes;
  final List<RoutineItem> eveningNotes;

  @override
  State<RoutineChecklistCard> createState() => _RoutineChecklistCardState();
}

class _RoutineChecklistCardState extends State<RoutineChecklistCard> {
  final Set<String> _expanded = {};
  bool _busy = false;

  Future<void> _toggle(String block, int step, List<int> allSteps) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.actions.toggleStep(block: block, step: step, allSteps: allSteps);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.actions, widget.actions.plan, I18n.instance]),
      builder: (context, _) {
        final i18n = I18n.instance;
        final theme = widget.theme;
        final progress = widget.actions.plan.plan?.progress ?? const DayProgress();
        final block = widget.actions.blockAt(todayPanelClock());
        final items = block == 'morning' ? widget.morning : widget.evening;
        final notes = block == 'morning' ? widget.morningNotes : widget.eveningNotes;
        final steps = [for (final it in items) stepOrder(it).round()];
        final blockDone = progress.blockDone(block);
        final checked = steps.where((s) => blockDone || progress.stepsOf(block).contains(s)).length;
        final fraction = items.isEmpty ? (blockDone ? 1.0 : 0.0) : checked / items.length;

        return RCard(
          padding: const EdgeInsets.all(14),
          radius: 20,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                TodayIconBadge(icon: LucideIcons.listChecks, color: theme.primary, size: 32),
                const SizedBox(width: 10),
                Expanded(child: Text(i18n.t('mobileToday.checklist.title'), style: tx(14, w: 7, c: Tw.gray800))),
                Text(widget.dayLabel, style: tx(12, c: Tw.gray500)),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                for (final b in routineBlocks) ...[
                  if (b != routineBlocks.first) const SizedBox(width: 8),
                  Expanded(child: _tab(i18n, b, selected: b == block, progress: progress)),
                ],
              ]),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: fraction,
                  minHeight: 6,
                  backgroundColor: theme.primaryLight,
                  color: theme.primary,
                ),
              ),
              const SizedBox(height: 8),
              if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(i18n.t('dashboard.noPlannedSteps'), style: tx(13, c: Tw.gray500)),
                )
              else
                for (var i = 0; i < items.length; i++)
                  _step(
                    i18n,
                    block: block,
                    item: items[i],
                    index: i,
                    checked: blockDone || progress.stepsOf(block).contains(steps[i]),
                    allSteps: steps,
                  ),
              if (notes.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(i18n.t('mobileToday.checklist.notes'), style: tx(11, w: 6, c: Tw.gray600)),
                const SizedBox(height: 6),
                for (final n in notes) _note(n),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _tab(I18n i18n, String block, {required bool selected, required DayProgress progress}) {
    final theme = widget.theme;
    final items = block == 'morning' ? widget.morning : widget.evening;
    final done = progress.blockDone(block);
    final count = items.where((it) => done || progress.stepsOf(block).contains(stepOrder(it).round())).length;
    final label = i18n.t('mobileToday.checklist.$block');
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: selected ? theme.primary : theme.primary.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => widget.actions.chooseBlock(block),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(block == 'morning' ? LucideIcons.sun : LucideIcons.moon, size: 15, color: selected ? Colors.white : theme.primaryDark),
                  const SizedBox(width: 6),
                  Text(label, style: tx(13, w: 6, c: selected ? Colors.white : theme.primaryDark)),
                  const SizedBox(width: 6),
                  if (done)
                    Icon(LucideIcons.circleCheck, size: 14, color: selected ? Colors.white : Tw.emerald700)
                  else if (items.isNotEmpty)
                    Text('$count/${items.length}', style: tx(11, w: 6, c: selected ? Colors.white70 : Tw.gray500)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _step(
    I18n i18n, {
    required String block,
    required RoutineItem item,
    required int index,
    required bool checked,
    required List<int> allSteps,
  }) {
    final theme = widget.theme;
    final key = '$block-$index';
    final open = _expanded.contains(key);
    final detail = pickDetail(item, localized: widget.localized);
    final usage = routineStepUsage(item, i18n);
    final hasMore = detail.isNotEmpty || usage.isNotEmpty;
    final skincare = isSkincareStep(item);
    final title = pickAction(item, localized: widget.localized);

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Semantics(
        container: true,
        checked: checked,
        label: title,
        child: Material(
          color: checked ? theme.primary.withValues(alpha: .05) : Tw.gray50,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: _busy ? null : () => _toggle(block, allSteps[index], allSteps),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _CheckCircle(checked: checked, color: theme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: tx(14, w: 6, c: checked ? Tw.gray400 : Tw.gray800, h: snug).copyWith(
                            decoration: checked ? TextDecoration.lineThrough : null,
                            decorationColor: Tw.gray400,
                          ),
                        ),
                        StructuredBadges(item: item),
                        if (hasMore) ...[
                          const SizedBox(height: 6),
                          InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => setState(() => open ? _expanded.remove(key) : _expanded.add(key)),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Flexible(
                                  child: Text(
                                    open
                                        ? i18n.t('common.hide')
                                        : skincare
                                            ? i18n.t('dashboard.whySkincareButton')
                                            : i18n.t('common.details'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: tx(12, w: 5, c: theme.primary),
                                  ),
                                ),
                                Icon(open ? LucideIcons.chevronUp : LucideIcons.chevronDown, size: 14, color: theme.primary),
                              ]),
                            ),
                          ),
                        ],
                        if (open) ...[
                          const SizedBox(height: 4),
                          if (detail.isNotEmpty)
                            Text.rich(
                              TextSpan(children: [
                                TextSpan(text: i18n.t('dashboard.shortWhy'), style: const TextStyle(fontWeight: FontWeight.w700)),
                                TextSpan(text: ' $detail'),
                              ]),
                              style: tx(12, c: Tw.gray600, h: relaxed),
                            ),
                          if (usage.isNotEmpty) ...[
                            if (detail.isNotEmpty) const SizedBox(height: 6),
                            Text.rich(
                              TextSpan(children: [
                                TextSpan(
                                  text: skincare ? i18n.t('dashboard.howToApply') : i18n.t('dashboard.howToDo'),
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                                TextSpan(text: ' $usage'),
                              ]),
                              style: tx(12, c: Tw.gray600, h: relaxed),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _note(RoutineItem item) {
    final detail = pickDetail(item, localized: widget.localized);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(glyphForEmoji(str(item['icon']), fallback: LucideIcons.dot), size: 16, color: Tw.gray600),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(pickAction(item, localized: widget.localized), style: tx(12, w: 6, c: Tw.gray700, h: snug)),
                if (detail.isNotEmpty)
                  Text(detail, maxLines: 3, overflow: TextOverflow.ellipsis, style: tx(11, c: Tw.gray500, h: relaxed)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckCircle extends StatelessWidget {
  const _CheckCircle({required this.checked, required this.color});

  final bool checked;
  final Color color;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: checked ? color : Tw.surface,
          border: Border.all(color: checked ? color : Tw.gray300, width: 2),
        ),
        child: checked ? const Icon(LucideIcons.check, size: 15, color: Colors.white) : null,
      );
}
