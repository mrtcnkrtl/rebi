import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/day_log.dart';
import '../../core/i18n.dart';
import '../../core/routine_logic.dart';
import '../../core/routine_usage.dart';
import '../../core/shelf.dart';
import '../../core/today_plan.dart';
import '../../state/theme_controller.dart';
import '../../state/today_actions.dart';
import '../../ui/brand/glyphs.dart';
import '../../ui/brand/palette.dart';
import '../../ui/tw.dart';
import '../../ui/widgets/common.dart';
import '../../ui/widgets/progress_ring.dart';
import 'today_clock.dart';
import '../routine/routine_parts.dart';
import 'today_widgets.dart';

/// Bugün'ün kahramanı: günün rutini. Başlık, ilerleme halkası, sabah/akşam seçici ve adım adım işaretlenen liste.
/// Son adım işaretlenince blok tamamlanır ve kart sakin bir "tamam" durumuna geçer (adımlar istenirse açılır,
/// "yeniden aç" ile geri alınır). Alttaki sabit "yaptım" düğmesi aynı işi tek dokunuşla yapar.
class RoutineHero extends StatefulWidget {
  const RoutineHero({
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
  State<RoutineHero> createState() => _RoutineHeroState();
}

class _RoutineHeroState extends State<RoutineHero> {
  final Set<String> _expanded = {};
  final Set<String> _stepsShownWhenDone = {};
  bool _notesOpen = false;
  bool _busy = false;

  Future<void> _guard(Future<void> Function() job) async {
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
      listenable: Listenable.merge([widget.actions, widget.actions.plan, I18n.instance]),
      builder: (context, _) {
        final i18n = I18n.instance;
        final plan = widget.actions.plan.plan;
        final progress = plan?.progress ?? const DayProgress();
        final block = widget.actions.blockAt(todayPanelClock());
        final items = block == 'morning' ? widget.morning : widget.evening;
        final notes = block == 'morning' ? widget.morningNotes : widget.eveningNotes;
        // Biten (Rafım) ürünlerin adımı rutinin ilerlemesine ve tamamlanmasına sayılmaz.
        final live = [
          for (final it in items)
            if (!_isOut(plan, it)) it,
        ];
        final steps = [for (final it in live) stepOrder(it).round()];
        final blockDone = progress.blockDone(block);
        final checked = steps.where((s) => blockDone || progress.stepsOf(block).contains(s)).length;
        final fraction = live.isEmpty ? (blockDone ? 1.0 : 0.0) : checked / live.length;
        final showSteps = !blockDone || _stepsShownWhenDone.contains(block);

        return Semantics(
          container: true,
          label: '${i18n.t('mobileToday.hero.title.$block')}, ${i18n.t('mobileToday.hero.progress', {'done': checked, 'total': live.length})}',
          child: RCard(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            radius: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(i18n, block, fraction, checked, live.length, blockDone),
                const SizedBox(height: 16),
                _segments(i18n, progress, plan),
                const SizedBox(height: 6),
                if (blockDone) _doneSummary(i18n, block, steps),
                if (showSteps) ...[
                  if (items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(i18n.t('dashboard.noPlannedSteps'), style: tx(13, c: Tw.gray500)),
                    )
                  else
                    for (var i = 0; i < items.length; i++)
                      if (_isOut(plan, items[i]))
                        _outStep(i18n, items[i], last: i == items.length - 1)
                      else
                        _step(
                          i18n,
                          block: block,
                          item: items[i],
                          index: i,
                          step: stepOrder(items[i]).round(),
                          checked: blockDone || progress.stepsOf(block).contains(stepOrder(items[i]).round()),
                          allSteps: steps,
                          last: i == items.length - 1,
                        ),
                ],
                if (notes.isNotEmpty) _notes(i18n, notes),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _header(I18n i18n, String block, double fraction, int checked, int total, bool done) {
    final theme = widget.theme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${i18n.t('mobileToday.checklist.title')} · ${widget.dayLabel}', style: tx(11.5, w: 7, c: Tw.gray500, ls: .8)),
              const SizedBox(height: 4),
              Text(i18n.t('mobileToday.hero.title.$block'), style: heading(28, h: 1.1)),
            ],
          ),
        ),
        const SizedBox(width: 12),
        ProgressRing(
          value: fraction,
          size: 56,
          stroke: 6,
          color: done ? Tw.emerald500 : theme.primary,
          track: theme.primaryLight,
          child: done
              ? Icon(LucideIcons.check, size: 22, color: Tw.emerald700)
              : Text(total == 0 ? '–' : '$checked/$total', style: tx(13, w: 7, c: Tw.gray700)),
        ),
      ],
    );
  }

  /// Sabah / akşam seçici: seçili olan dolu, öbürü yalnızca metin.
  Widget _segments(I18n i18n, DayProgress progress, TodayPlan? plan) {
    final theme = widget.theme;
    final current = widget.actions.blockAt(todayPanelClock());
    Widget segment(String b) {
      final items = [
        for (final it in (b == 'morning' ? widget.morning : widget.evening))
          if (!_isOut(plan, it)) it,
      ];
      final done = progress.blockDone(b);
      final count = items.where((it) => done || progress.stepsOf(b).contains(stepOrder(it).round())).length;
      final selected = b == current;
      final label = i18n.t('mobileToday.checklist.$b');
      final fg = selected ? Colors.white : theme.primaryDark;
      return Expanded(
        child: Semantics(
          button: true,
          selected: selected,
          label: label,
          child: Material(
            color: selected ? theme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => widget.actions.chooseBlock(b),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(b == 'morning' ? LucideIcons.sun : LucideIcons.moon, size: 15, color: fg),
                          const SizedBox(width: 6),
                          Text(label, style: tx(13, w: 6, c: fg)),
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
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.primaryLight.withValues(alpha: Tw.dark ? .35 : .55),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(children: [for (final b in routineBlocks) segment(b)]),
    );
  }

  /// Blok tamamlandığında adımların yerine sakin bir bitiş durumu gösterilir.
  Widget _doneSummary(I18n i18n, String block, List<int> steps) {
    final shown = _stepsShownWhenDone.contains(block);
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Tw.emerald50.withValues(alpha: Tw.dark ? .6 : 1),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: .6, end: 1),
                  duration: const Duration(milliseconds: 420),
                  curve: Curves.easeOutBack,
                  builder: (context, v, child) => Transform.scale(scale: v, child: child),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: Tw.emerald500),
                    child: const Icon(LucideIcons.check, size: 22, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(i18n.t('mobileToday.hero.doneTitle.$block'), style: heading(20, c: Tw.emerald800)),
                      const SizedBox(height: 2),
                      Text(
                        i18n.t('mobileToday.hero.doneBody'),
                        style: tx(12.5, c: Tw.emerald800, h: relaxed),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 18,
              children: [
                TextLink(
                  i18n.t(shown ? 'mobileToday.hero.hideSteps' : 'mobileToday.hero.showSteps'),
                  onTap: () => setState(() => shown ? _stepsShownWhenDone.remove(block) : _stepsShownWhenDone.add(block)),
                  style: tx(13, w: 6, c: Tw.emerald800),
                ),
                TextLink(
                  i18n.t('mobileToday.hero.reopen'),
                  onTap: _busy ? () {} : () => _guard(() => widget.actions.reopenBlock(block: block, allSteps: steps)),
                  style: tx(13, w: 6, c: Tw.emerald800),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _step(
    I18n i18n, {
    required String block,
    required RoutineItem item,
    required int index,
    required int step,
    required bool checked,
    required List<int> allSteps,
    required bool last,
  }) {
    final theme = widget.theme;
    final key = '$block-$index';
    final open = _expanded.contains(key);
    final detail = pickDetail(item, localized: widget.localized);
    final usage = routineStepUsage(item, i18n);
    final hasMore = detail.isNotEmpty || usage.isNotEmpty;
    final skincare = isSkincareStep(item);
    final title = pickAction(item, localized: widget.localized);

    return Semantics(
      container: true,
      checked: checked,
      label: title,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _busy ? null : () => _guard(() => widget.actions.toggleStep(block: block, step: step, allSteps: allSteps)),
        child: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: _rail(
            node: _CheckCircle(checked: checked, color: theme.primary),
            last: last,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  // Yapılan adım soluklaşır ama okunur kalır (üstü çizilmez): sakin bir "tamam" hissi.
                  child: Text(title, style: tx(16, w: 6, c: checked ? Tw.gray500 : Tw.gray900, h: 1.3)),
                ),
                StructuredBadges(item: item),
                if (hasMore) ...[
                  const SizedBox(height: 4),
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => setState(() => open ? _expanded.remove(key) : _expanded.add(key)),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 48),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        widthFactor: 1,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                open
                                    ? i18n.t('common.hide')
                                    : skincare
                                    ? i18n.t('dashboard.whySkincareButton')
                                    : i18n.t('common.details'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: tx(12, w: 5, c: theme.fg),
                              ),
                            ),
                            Icon(open ? LucideIcons.chevronUp : LucideIcons.chevronDown, size: 14, color: theme.fg),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
                if (open) ...[
                  const SizedBox(height: 4),
                  if (detail.isNotEmpty)
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: i18n.t('dashboard.shortWhy'),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          TextSpan(text: ' $detail'),
                        ],
                      ),
                      style: tx(12, c: Tw.gray600, h: relaxed),
                    ),
                  if (usage.isNotEmpty) ...[
                    if (detail.isNotEmpty) const SizedBox(height: 6),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: skincare ? i18n.t('dashboard.howToApply') : i18n.t('dashboard.howToDo'),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          TextSpan(text: ' $usage'),
                        ],
                      ),
                      style: tx(12, c: Tw.gray600, h: relaxed),
                    ),
                  ],
                  const SizedBox(height: 2),
                  TextLink(
                    i18n.t('mobileRoutine.askRebi'),
                    onTap: () =>
                        askRebiAboutStep(context, item, RoutineCtx(i18n: i18n, theme: theme, localized: widget.localized, weekDays: const [])),
                    style: tx(12, w: 7, c: theme.fg),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Zaman çizelgesi satırı: solda düğüm ve bir sonraki adıma inen ince çizgi, sağda içerik.
  Widget _rail({required Widget node, required Widget child, required bool last}) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                node,
                if (!last)
                  Expanded(
                    child: Center(
                      child: Container(
                        width: 2,
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        decoration: BoxDecoration(color: widget.theme.primary.withValues(alpha: .18), borderRadius: BorderRadius.circular(1)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 6 : 12),
              child: child,
            ),
          ),
        ],
      ),
    );
  }

  bool _isOut(TodayPlan? plan, RoutineItem item) => plan?.isOut(str(item['action'])) ?? false;

  /// Bitti işaretli ürünün adımı: soluk, "Bitti" rozeti ve "Aldım"; rutinin ilerlemesine sayılmaz.
  Widget _outStep(I18n i18n, RoutineItem item, {required bool last}) {
    final name = str(item['action']).trim();
    final step = stepOrder(item).round();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: _rail(
        node: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(shape: BoxShape.circle, color: Tw.amber100),
          child: Icon(LucideIcons.packageX, size: 15, color: Tw.amber800),
        ),
        last: last,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                pickAction(item, localized: widget.localized),
                style: tx(16, w: 6, c: Tw.gray500, h: 1.3),
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: Tw.amber100, borderRadius: BorderRadius.circular(999)),
                  child: Text(i18n.t('mobileToday.hero.outBadge'), style: tx(11, w: 7, c: Tw.amber800)),
                ),
                Text(i18n.t('mobileToday.hero.outHint'), style: tx(11.5, c: Tw.gray500)),
                TextLink(
                  i18n.t('mobileToday.hero.restock'),
                  onTap: _busy
                      ? () {}
                      : () => _guard(() async {
                          await widget.actions.record(
                            shelfRestockedEvent,
                            {'product': shelfName(name), 'step_order': step},
                            message: i18n.t('mobileToday.toast.restocked', {'product': name}),
                            undoPayload: {'product': shelfName(name), 'step_order': step},
                            undoType: shelfFinishedEvent,
                          );
                        }),
                  style: tx(12.5, w: 7, c: widget.theme.fg),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _notes(I18n i18n, List<RoutineItem> notes) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Hairline(),
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _notesOpen = !_notesOpen),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Row(
              children: [
                Icon(LucideIcons.leaf, size: 16, color: Tw.gray600),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('${i18n.t('mobileToday.checklist.notes')} (${notes.length})', style: tx(13, w: 6, c: Tw.gray700)),
                ),
                Icon(_notesOpen ? LucideIcons.chevronUp : LucideIcons.chevronDown, size: 16, color: Tw.gray500),
              ],
            ),
          ),
        ),
        if (_notesOpen)
          for (final n in notes) _note(n),
      ],
    );
  }

  Widget _note(RoutineItem item) {
    final detail = pickDetail(item, localized: widget.localized);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(glyphForEmoji(str(item['icon']), fallback: LucideIcons.dot), size: 16, color: Tw.gray600),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pickAction(item, localized: widget.localized),
                  style: tx(12.5, w: 6, c: Tw.gray700, h: snug),
                ),
                if (detail.isNotEmpty)
                  Text(
                    detail,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: tx(11.5, c: Tw.gray500, h: relaxed),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// İşaret dairesi: işaretlenince hafifçe büyüyüp yerine oturur, tik belirir.
class _CheckCircle extends StatelessWidget {
  const _CheckCircle({required this.checked, required this.color});

  final bool checked;
  final Color color;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 200),
    curve: Curves.easeOut,
    width: 28,
    height: 28,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: checked ? color : Colors.transparent,
      border: Border.all(color: checked ? color : Tw.gray300, width: 2),
    ),
    child: AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      transitionBuilder: (child, anim) => ScaleTransition(
        scale: CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
        child: child,
      ),
      child: checked ? const Icon(LucideIcons.check, key: ValueKey('on'), size: 16, color: Colors.white) : const SizedBox(key: ValueKey('off')),
    ),
  );
}
