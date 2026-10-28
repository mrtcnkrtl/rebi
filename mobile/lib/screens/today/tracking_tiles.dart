import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/day_log.dart';
import '../../core/i18n.dart';
import '../../core/today_plan.dart';
import '../../state/theme_controller.dart';
import '../../state/today_actions.dart';
import '../../ui/tw.dart';
import '../../ui/widgets/common.dart';
import '../../ui/widgets/progress_ring.dart';
import '../../ui/widgets/skeleton.dart';
import 'today_clock.dart';
import 'today_widgets.dart';

// Kategori renkleri paletten gelir (pudra = makyaj, adaçayı = beslenme, su = su); moda göre değişir, bu yüzden alıcıdır.
Color get _makeupColor => Tw.pink600;
Color get _nutritionColor => Tw.green600;

/// Gün içi kayıtlar: su (tam genişlik, halka + hızlı miktarlar), makyaj ve beslenme (yan yana iki kart).
/// Her kart tek dokunuşla kayıt alır; ayrıntı gereken kayıtlar (temizleme yöntemi, yenilen şeyler, su miktarı) alt sayfa açar.
/// Güneş kremi kaydı "havaya göre" kartının içindedir.
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
        if (plan == null) {
          // Plan yüklenirken kartların yeri belli olsun; yüklenemediyse "Gün akışı" kartı uyarı gösterir.
          if (!widget.actions.plan.loading) return const SizedBox.shrink();
          return const Column(children: [
            SkeletonCard(lines: 1, withActions: true),
            SizedBox(height: 10),
            Row(children: [
              Expanded(child: SkeletonCard(lines: 2)),
              SizedBox(width: 10),
              Expanded(child: SkeletonCard(lines: 2)),
            ]),
          ]);
        }
        final i18n = I18n.instance;
        final p = plan.progress;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _water(i18n, plan, p),
            const SizedBox(height: 10),
            LayoutBuilder(builder: (context, c) {
              // Dar ekranda ya da büyük yazıda iki kart yan yana sığmaz: alt alta dizilir.
              final stacked = c.maxWidth < 340 || MediaQuery.textScalerOf(context).scale(10) > 12.5;
              final makeup = _makeup(i18n, p, pin: !stacked);
              final nutrition = _nutrition(i18n, p, pin: !stacked);
              if (stacked) return Column(children: [makeup, const SizedBox(height: 10), nutrition]);
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [Expanded(child: makeup), const SizedBox(width: 10), Expanded(child: nutrition)],
                ),
              );
            }),
          ],
        );
      },
    );
  }

  /// Yan yana kartların ortak iskeleti: simge + başlık, durum metni, altta eylemler.
  Widget _mini({
    required IconData icon,
    required Color color,
    required String title,
    required Widget status,
    bool complete = false,
    bool pin = false,
    List<Widget> actions = const [],
  }) =>
      RCard(
        padding: const EdgeInsets.all(16),
        radius: 22,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                TodayIconBadge(icon: icon, color: color, size: 36),
                const SizedBox(width: 10),
                Expanded(child: Text(title, style: tx(15, w: 7, c: Tw.gray900))),
                if (complete) Icon(LucideIcons.circleCheck, size: 20, color: Tw.emerald500),
              ],
            ),
            const SizedBox(height: 10),
            status,
            if (actions.isNotEmpty) ...[
              // Yan yana dizilince iki kartın düğmeleri aynı hizada, kartın altında durur.
              if (pin) const Spacer() else const SizedBox(height: 12),
              if (pin) const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: actions),
            ],
          ],
        ),
      );

  Text _sub(String text, {Color? color, int w = 4}) => Text(text, style: tx(12.5, c: color ?? Tw.gray600, w: w, h: relaxed));

  // --- Su ---------------------------------------------------------------

  Widget _water(I18n i18n, TodayPlan plan, DayProgress p) {
    final target = plan.waterTarget;
    final reached = p.waterMl >= target;
    final reminder = plan.reminders.where((r) => r.id == 'water_intake').firstOrNull;
    final next = reminder == null ? null : nextReminderSlot(reminder, todayPanelClock());

    Future<void> add(int ml) => _run(() => widget.actions.record(
          'water_intake',
          {'ml': ml},
          message: i18n.t('mobileToday.toast.water', {'ml': ml}),
          undoPayload: {'ml': -ml},
        ));

    return RCard(
      padding: const EdgeInsets.all(18),
      radius: 24,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ProgressRing(
                value: p.waterFractionFor(target),
                size: 68,
                stroke: 7,
                color: reached ? Tw.emerald500 : Tw.blue500,
                track: Tw.blue100,
                child: Icon(reached ? LucideIcons.check : LucideIcons.droplet, size: 22, color: reached ? Tw.emerald700 : Tw.blue500),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(i18n.t('mobileToday.waterTitle'), style: tx(13, w: 6, c: Tw.gray500)),
                    const SizedBox(height: 2),
                    Text(
                      i18n.t('mobileToday.waterProgress', {'ml': p.waterMl, 'target': target}),
                      style: tx(21, w: 8, c: Tw.blueText, h: 1.15),
                    ),
                    const SizedBox(height: 4),
                    if (reached)
                      _sub(i18n.t('mobileToday.waterGoalReached'), color: Tw.emerald700, w: 6)
                    else if (next != null)
                      _sub(i18n.t('mobileToday.water.next', {'time': next}), color: Tw.gray500),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (!reached)
                for (final (ml, key) in [(250, 'water250'), (500, 'water500')])
                  TodayPill(
                    label: i18n.t('mobileToday.actions.$key'),
                    color: ml == 250 ? Tw.blue600 : Tw.blueText,
                    filled: ml == 250,
                    onTap: _busy ? null : () => add(ml),
                  ),
              TodayPill(
                label: i18n.t('mobileToday.actions.waterMore'),
                color: Tw.blueText,
                onTap: () => widget.onOpenSheet(DaySheet.water),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- Makyaj -----------------------------------------------------------

  Widget _makeup(I18n i18n, DayProgress p, {required bool pin}) {
    final color = _makeupColor;
    final title = i18n.t('mobileToday.makeup.title');
    Future<void> set(bool used) => _run(() => widget.actions.record(
          'makeup',
          {'used': used},
          message: i18n.t(used ? 'mobileToday.toast.makeupUsed' : 'mobileToday.toast.makeupNone'),
        ));
    void openCleansing() => widget.onOpenSheet(DaySheet.cleansing);

    if (!p.makeupLogged) {
      return _mini(
        pin: pin,
        icon: LucideIcons.sparkles,
        color: color,
        title: title,
        status: _sub(i18n.t('mobileToday.makeup.ask')),
        actions: [
          TodayPill(label: i18n.t('mobileToday.actions.yes'), color: color, filled: true, onTap: _busy ? null : () => set(true)),
          TodayPill(label: i18n.t('mobileToday.actions.no'), color: color, onTap: _busy ? null : () => set(false)),
        ],
      );
    }
    if (p.makeupUsed && p.makeupRemoved) {
      final method = p.removalMethod;
      return _mini(
        pin: pin,
        icon: LucideIcons.sparkles,
        color: color,
        title: title,
        complete: true,
        status: _sub(
          method == null
              ? i18n.t('mobileToday.makeup.cleaned')
              : i18n.t('mobileToday.makeup.cleanedWith', {'method': i18n.t('mobileToday.cleansing.$method.title')}),
          color: Tw.emerald700,
          w: 6,
        ),
        actions: [TodayPill(label: i18n.t('mobileToday.actions.change'), color: color, onTap: openCleansing)],
      );
    }
    if (p.makeupUsed) {
      return _mini(
        pin: pin,
        icon: LucideIcons.sparkles,
        color: color,
        title: title,
        status: _sub(
          i18n.t(p.removalMethod == 'none' ? 'mobileToday.makeup.notCleaned' : 'mobileToday.makeup.usedPending'),
          color: Tw.amber700,
          w: 6,
        ),
        actions: [TodayPill(label: i18n.t('mobileToday.actions.removed'), color: color, filled: true, onTap: openCleansing)],
      );
    }
    return _mini(
      pin: pin,
      icon: LucideIcons.sparkles,
      color: color,
      title: title,
      status: _sub(i18n.t('mobileToday.makeup.none')),
      actions: [TodayPill(label: i18n.t('mobileToday.makeup.changeToUsed'), color: color, onTap: _busy ? null : () => set(true))],
    );
  }

  // --- Beslenme ---------------------------------------------------------

  Widget _nutrition(I18n i18n, DayProgress p, {required bool pin}) {
    final title = i18n.t('mobileToday.nutrition.title');
    if (!p.nutritionLogged) {
      return _mini(
        pin: pin,
        icon: LucideIcons.apple,
        color: _nutritionColor,
        title: title,
        status: _sub(i18n.t('mobileToday.nutrition.ask')),
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
    return _mini(
      pin: pin,
      icon: LucideIcons.apple,
      color: _nutritionColor,
      title: title,
      complete: clean,
      status: _sub(
        clean
            ? i18n.t(p.nutrition['balanced'] == true ? 'mobileToday.nutrition.balanced' : 'mobileToday.nutrition.clean')
            : picked.map((c) => i18n.t('mobileToday.nutrition.choices.$c.title')).join(', '),
        color: clean ? Tw.emerald700 : Tw.amber700,
        w: 6,
      ),
      actions: [
        TodayPill(
          label: i18n.t('mobileToday.actions.edit'),
          color: _nutritionColor,
          onTap: () => widget.onOpenSheet(DaySheet.nutrition),
        ),
      ],
    );
  }
}
