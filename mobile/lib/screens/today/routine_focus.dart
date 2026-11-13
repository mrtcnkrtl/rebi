import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/haptics.dart';
import '../../core/i18n.dart';
import '../../core/routine_logic.dart';
import '../../core/routine_usage.dart';
import '../../state/today_actions.dart';
import '../../ui/brand/brand_button.dart';
import '../../ui/brand/brand_caps.dart';
import '../../ui/brand/motion.dart';
import '../../ui/brand/palette.dart';
import '../../ui/tw.dart';
import '../../ui/widgets/common.dart';

/// Aktiflerin emilmesi için önerilen bekleme (saniye).
const focusWaitSeconds = 60;

/// Bu adımdan sonra kısa bir bekleme önerilir mi: serum / aktif adımı (sıra 20–29) ve ardından başka bir adım varsa.
bool suggestsWait(RoutineItem item, {required bool last}) {
  if (last) return false;
  final order = stepOrder(item);
  return order >= 20 && order < 30;
}

/// Rutini tam ekranda, tek tek uygulatan odak modu.
///
/// Tasarım dili: krem kâğıt zemin, orman yeşili mürekkep, ekranda bir anda tek ürün. Üstte ince adım çizgileri;
/// ortada adım numarası, kısa ad (Fraunces) ve nasıl uygulanacağı; altta tek ana düğme ("Yaptım") ve "atla".
/// Serum/aktif adımlarından sonra isteğe bağlı 1 dakikalık bekleme sayacı. "Yaptım" adımı bugünün kaydına işler
/// (Bugün ekranındaki işaretle aynı olay); son adım işaretlenince blok kendiliğinden tamamlanır.
class RoutineFocusScreen extends StatefulWidget {
  const RoutineFocusScreen({
    super.key,
    required this.actions,
    required this.block,
    required this.items,
    required this.localized,
  });

  final TodayActions actions;

  /// `morning` | `evening`
  final String block;

  /// Bugünün bu bloktaki uygulanacak adımları (bitmiş ürünler hariç), sırasıyla.
  final List<RoutineItem> items;
  final bool localized;

  static Future<void> open(
    BuildContext context, {
    required TodayActions actions,
    required String block,
    required List<RoutineItem> items,
    required bool localized,
  }) {
    return Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => RoutineFocusScreen(actions: actions, block: block, items: items, localized: localized),
      ),
    );
  }

  @override
  State<RoutineFocusScreen> createState() => _RoutineFocusScreenState();
}

class _RoutineFocusScreenState extends State<RoutineFocusScreen> {
  int _index = 0;
  bool _finished = false;
  bool _busy = false;
  Timer? _timer;
  int? _waitLeft;

  List<int> get _allSteps => [for (final it in widget.items) stepOrder(it).round()];

  @override
  void initState() {
    super.initState();
    // Daha önce işaretlenmiş adımlar atlanır: odak modu ilk yapılmamış adımdan başlar.
    final done = widget.actions.plan.plan?.progress.stepsOf(widget.block) ?? const <int>{};
    final first = widget.items.indexWhere((it) => !done.contains(stepOrder(it).round()));
    _index = first < 0 ? 0 : first;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  bool _isDone(RoutineItem item) {
    final progress = widget.actions.plan.plan?.progress;
    if (progress == null) return false;
    return progress.blockDone(widget.block) || progress.stepsOf(widget.block).contains(stepOrder(item).round());
  }

  Future<void> _markDone() async {
    if (_busy) return;
    final item = widget.items[_index];
    setState(() => _busy = true);
    try {
      // Zaten işaretliyse dokunma (toggleStep işareti kaldırırdı).
      if (!_isDone(item)) {
        await widget.actions.toggleStep(block: widget.block, step: stepOrder(item).round(), allSteps: _allSteps);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    _advance();
  }

  void _advance() {
    _stopWait();
    if (_index >= widget.items.length - 1) {
      Haptics.milestone();
      setState(() => _finished = true);
      return;
    }
    setState(() => _index += 1);
  }

  void _startWait() {
    _timer?.cancel();
    setState(() => _waitLeft = focusWaitSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      final left = (_waitLeft ?? 0) - 1;
      if (left <= 0) {
        t.cancel();
        Haptics.selection();
        setState(() => _waitLeft = null);
      } else {
        setState(() => _waitLeft = left);
      }
    });
  }

  void _stopWait() {
    _timer?.cancel();
    _timer = null;
    _waitLeft = null;
  }

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    return Scaffold(
      backgroundColor: Brand.paper,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 24, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _topBar(i18n),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 380),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: SlideTransition(position: Tween(begin: const Offset(.05, 0), end: Offset.zero).animate(anim), child: child),
                      ),
                      child: KeyedSubtree(
                        key: ValueKey(_finished ? 'done' : _index),
                        child: Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: _finished ? _finish(i18n) : _step(i18n, widget.items[_index]),
                        ),
                      ),
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

  Widget _topBar(I18n i18n) {
    final count = widget.items.length;
    final reached = _finished ? count : _index;
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          IconButton(
            tooltip: i18n.t('mobileFocus.close'),
            onPressed: () => Navigator.of(context).maybePop(),
            icon: Icon(LucideIcons.x, size: 24, color: Brand.ink),
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              children: [
                for (var i = 0; i < count; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 320),
                      height: 3,
                      decoration: BoxDecoration(
                        color: i < reached || (i == reached && !_finished) ? Brand.ink : Brand.inkFaint,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _step(I18n i18n, RoutineItem item) {
    final lang = i18n.lang;
    final full = pickAction(item, localized: widget.localized);
    final parts = stepParts(full);
    final usage = routineStepUsage(item, i18n);
    final detail = pickDetail(item, localized: widget.localized);
    final last = _index == widget.items.length - 1;
    final wait = suggestsWait(item, last: last);
    final already = _isDone(item);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(top: 28, bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  brandCaps(i18n.t('mobileFocus.stepOf', {'n': _index + 1, 'total': widget.items.length}), lang),
                  style: tx(11.5, w: 7, c: Brand.inkSoft, ls: brandTracking(lang, 2.0)),
                ),
                const SizedBox(height: 14),
                Semantics(header: true, child: Text(parts.title, style: Brand.serif(36, h: 1.08))),
                if (parts.subtitle.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(parts.subtitle, style: tx(16, c: Brand.inkSoft, h: 1.4)),
                ],
                StructuredBadges(item: item),
                if (usage.isNotEmpty || detail.isNotEmpty) ...[
                  const SizedBox(height: 26),
                  Divider(height: 1, color: Brand.inkFaint),
                  const SizedBox(height: 22),
                  Text(
                    brandCaps(i18n.t(usage.isNotEmpty ? 'mobileFocus.how' : 'mobileFocus.why'), lang),
                    style: tx(11, w: 7, c: Brand.inkSoft, ls: brandTracking(lang, 1.6)),
                  ),
                  const SizedBox(height: 10),
                  Text(usage.isNotEmpty ? usage : detail, style: tx(17, c: Brand.ink, h: 1.5)),
                ],
                if (already) ...[
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Icon(LucideIcons.circleCheck, size: 18, color: Tw.emerald700),
                      const SizedBox(width: 8),
                      Flexible(child: Text(i18n.t('mobileFocus.alreadyDone'), style: tx(14, w: 6, c: Tw.emerald700))),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        if (wait) ...[_waitRow(i18n), const SizedBox(height: 12)],
        BrandButton(
          onPressed: _busy ? null : _markDone,
          loading: _busy,
          label: i18n.t(last ? 'mobileFocus.doneLast' : 'mobileFocus.done'),
          trailingIcon: last ? LucideIcons.check : LucideIcons.arrowRight,
        ),
        const SizedBox(height: 6),
        TextButton(
          onPressed: _busy ? null : _advance,
          style: TextButton.styleFrom(minimumSize: const Size(48, 52), foregroundColor: Brand.ink),
          child: Text(i18n.t('mobileFocus.skip'), style: tx(15, w: 6, c: Brand.inkSoft)),
        ),
      ],
    );
  }

  /// "Emilmesi için 1 dk bekle": dokununca geri sayım; bitince kısa titreşim. İsteğe bağlıdır, akışı durdurmaz.
  Widget _waitRow(I18n i18n) {
    final left = _waitLeft;
    final running = left != null;
    return Material(
      color: Brand.inkFaint.withValues(alpha: .5),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: running ? () => setState(_stopWait) : _startWait,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  height: 28,
                  child: running
                      ? CircularProgressIndicator(
                          value: left / focusWaitSeconds,
                          strokeWidth: 2.6,
                          color: Brand.ink,
                          backgroundColor: Brand.inkFaint,
                        )
                      : Icon(LucideIcons.timer, size: 22, color: Brand.ink),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    running ? i18n.t('mobileFocus.waiting', {'s': left}) : i18n.t('mobileFocus.wait'),
                    style: tx(14.5, w: 6, c: Brand.ink),
                  ),
                ),
                if (running) Text(i18n.t('mobileFocus.waitStop'), style: tx(13.5, w: 6, c: Brand.inkSoft)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _finish(I18n i18n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Spacer(),
        Center(
          child: Reveal(
            scaleFrom: .4,
            duration: const Duration(milliseconds: 620),
            curve: Curves.easeOutBack,
            offset: Offset.zero,
            child: Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Brand.ink),
              child: Icon(LucideIcons.check, size: 40, color: Brand.paper),
            ),
          ),
        ),
        const SizedBox(height: 28),
        Semantics(
          header: true,
          child: Text(i18n.t('mobileFocus.finishTitle.${widget.block}'), textAlign: TextAlign.center, style: Brand.serif(32, h: 1.1)),
        ),
        const SizedBox(height: 10),
        Text(i18n.t('mobileFocus.finishBody'), textAlign: TextAlign.center, style: tx(15.5, c: Brand.inkSoft, h: 1.5)),
        const Spacer(),
        BrandButton(onPressed: () => Navigator.of(context).maybePop(), label: i18n.t('mobileFocus.close')),
      ],
    );
  }
}
