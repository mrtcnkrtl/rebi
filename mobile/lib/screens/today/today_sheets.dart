import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'today_widgets.dart';
import '../../ui/brand/glyphs.dart';
import '../../ui/widgets/app_sheet.dart';

/// "Bugün" ekranındaki seçim ekranlarından birini alt sayfa olarak açar.
/// [products]: "ürün bitti" sayfasında listelenecek bakım ürünleri.
Future<void> showTodaySheet(
  BuildContext context,
  DaySheet sheet, {
  required TodayActions actions,
  required RebiTheme theme,
  List<RoutineItem> products = const [],
}) {
  final i18n = I18n.instance;
  final (title, subtitle, body) = switch (sheet) {
    DaySheet.cleansing => (
        i18n.t('mobileToday.sheets.cleansing.title'),
        i18n.t('mobileToday.sheets.cleansing.subtitle'),
        (BuildContext c) => _CleansingBody(actions: actions, theme: theme),
      ),
    DaySheet.nutrition => (
        i18n.t('mobileToday.sheets.nutrition.title'),
        i18n.t('mobileToday.sheets.nutrition.subtitle'),
        (BuildContext c) => _NutritionBody(actions: actions, theme: theme),
      ),
    DaySheet.water => (
        i18n.t('mobileToday.sheets.water.title'),
        null,
        (BuildContext c) => _WaterBody(actions: actions, theme: theme),
      ),
    DaySheet.products => (
        i18n.t('mobileToday.sheets.products.title'),
        i18n.t('mobileToday.sheets.products.subtitle'),
        (BuildContext c) => _ProductsBody(actions: actions, theme: theme, products: products),
      ),
  };
  return AppSheet.show<void>(context, title: title, subtitle: subtitle, body: body);
}

/// Seçilebilir satır: simge, başlık, açıklama.
class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.icon,
    required this.title,
    required this.color,
    required this.selected,
    required this.onTap,
    this.description,
    this.check = false,
    this.titleMaxLines,
  });

  final IconData icon;
  final String title;

  /// Çok uzun başlıklar (ürün adları) bu kadar satırda kesilir.
  final int? titleMaxLines;
  final String? description;
  final Color color;
  final bool selected;
  final VoidCallback? onTap;

  /// Çoklu seçimde sağda onay kutusu gösterir.
  final bool check;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        button: true,
        selected: selected,
        label: title,
        child: Material(
          color: selected ? color.withValues(alpha: .08) : Tw.gray50,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: selected ? color : Tw.gray100, width: selected ? 2 : 1),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: Tw.surface, borderRadius: BorderRadius.circular(12)),
                    child: Icon(icon, size: 20, color: selected ? color : Tw.gray600),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: titleMaxLines,
                          overflow: titleMaxLines == null ? null : TextOverflow.ellipsis,
                          style: tx(14, w: 7, c: Tw.gray800, h: snug),
                        ),
                        if (description != null) ...[
                          const SizedBox(height: 2),
                          Text(description!, style: tx(12, c: Tw.gray500, h: snug)),
                        ],
                      ],
                    ),
                  ),
                  if (check) ...[
                    const SizedBox(width: 8),
                    Icon(selected ? LucideIcons.circleCheck : LucideIcons.circle, size: 22, color: selected ? color : Tw.gray300),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// --- Makyaj nasıl temizlendi ----------------------------------------------


class _CleansingBody extends StatelessWidget {
  const _CleansingBody({required this.actions, required this.theme});

  final TodayActions actions;
  final RebiTheme theme;

  @override
  Widget build(BuildContext context) {
    final i18n = I18n.instance;
    final current = actions.plan.plan?.progress.removalMethod;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final method in cleansingMethods)
          _OptionTile(
            icon: cleansingGlyph(method),
            title: i18n.t('mobileToday.cleansing.$method.title'),
            description: i18n.t('mobileToday.cleansing.$method.desc'),
            color: theme.primary,
            selected: current == method,
            onTap: () {
              Navigator.of(context).pop();
              actions.record(
                'makeup',
                cleansingPayload(method),
                message: i18n.t(method == 'none' ? 'mobileToday.toast.notCleaned' : 'mobileToday.toast.cleaned'),
              );
            },
          ),
      ],
    );
  }
}

// --- Beslenme ---------------------------------------------------------------

class _NutritionBody extends StatefulWidget {
  const _NutritionBody({required this.actions, required this.theme});

  final TodayActions actions;
  final RebiTheme theme;

  @override
  State<_NutritionBody> createState() => _NutritionBodyState();
}

class _NutritionBodyState extends State<_NutritionBody> {
  late final Set<String> _selected = {
    ...nutritionSelection(widget.actions.plan.plan?.progress.nutrition ?? const {}),
  };

  void _toggle(String choice) => setState(() {
        if (_selected.contains(choice)) {
          _selected.remove(choice);
        } else if (choice == 'balanced') {
          _selected
            ..clear()
            ..add(choice);
        } else {
          _selected
            ..remove('balanced')
            ..add(choice);
        }
      });

  @override
  Widget build(BuildContext context) {
    final i18n = I18n.instance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final choice in nutritionChoices)
          _OptionTile(
            icon: nutritionGlyph(choice),
            title: i18n.t('mobileToday.nutrition.choices.$choice.title'),
            description: i18n.t('mobileToday.nutrition.choices.$choice.desc'),
            color: Tw.green600,
            selected: _selected.contains(choice),
            check: true,
            onTap: () => _toggle(choice),
          ),
        const SizedBox(height: 8),
        PrimaryButton(
          color: widget.theme.primary,
          label: i18n.t('mobileToday.sheets.save'),
          onPressed: _selected.isEmpty
              ? null
              : () {
                  Navigator.of(context).pop();
                  widget.actions.record(
                    'nutrition',
                    nutritionPayload(_selected),
                    message: i18n.t('mobileToday.toast.nutrition'),
                  );
                },
        ),
      ],
    );
  }
}

// --- Su ---------------------------------------------------------------------

class _WaterBody extends StatefulWidget {
  const _WaterBody({required this.actions, required this.theme});

  final TodayActions actions;
  final RebiTheme theme;

  @override
  State<_WaterBody> createState() => _WaterBodyState();
}

class _WaterBodyState extends State<_WaterBody> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _add(int ml, {bool undoable = true}) {
    final i18n = I18n.instance;
    return widget.actions.record(
      'water_intake',
      {'ml': ml},
      message: i18n.t(ml > 0 ? 'mobileToday.toast.water' : 'mobileToday.toast.waterFixed', {'ml': ml.abs()}),
      undoPayload: undoable ? {'ml': -ml} : null,
    );
  }

  Future<void> _addCustom() async {
    final i18n = I18n.instance;
    final ml = int.tryParse(_controller.text.trim());
    if (ml == null || ml < 1 || ml > maxCustomWaterMl) {
      setState(() => _error = i18n.t('mobileToday.sheets.water.invalid', {'max': maxCustomWaterMl}));
      return;
    }
    setState(() => _error = null);
    _controller.clear();
    FocusScope.of(context).unfocus();
    await _add(ml);
  }

  @override
  Widget build(BuildContext context) {
    final i18n = I18n.instance;
    final theme = widget.theme;
    return ListenableBuilder(
      listenable: widget.actions.plan,
      builder: (context, _) {
        final total = widget.actions.plan.plan?.progress.waterMl ?? 0;
        final fraction = (total / waterTargetMl).clamp(0.0, 1.0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              ProgressRing(
                value: fraction,
                size: 72,
                stroke: 8,
                color: total >= waterTargetMl ? Tw.emerald500 : Tw.blue500,
                track: Tw.blue100,
                child: Text('${(fraction * 100).round()}%', style: tx(14, w: 8, c: Tw.gray700)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(i18n.t('mobileToday.waterProgress', {'ml': total, 'target': waterTargetMl}), style: tx(18, w: 8, c: Tw.blueText)),
                    if (total >= waterTargetMl)
                      Text(i18n.t('mobileToday.waterGoalReached'), style: tx(12, w: 5, c: Tw.emerald700)),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 18),
            Text(i18n.t('mobileToday.sheets.water.add'), style: tx(12, w: 7, c: Tw.gray600)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final ml in waterQuickAmounts)
                TodayPill(label: '+$ml ml', color: ml == 250 ? Tw.blue600 : Tw.blueText, filled: ml == 250, onTap: () => _add(ml)),
            ]),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _addCustom(),
                    decoration: inputDecoration(
                      hint: i18n.t('mobileToday.sheets.water.customHint'),
                      suffixText: 'ml',
                      focusColor: Tw.blue500,
                      radius: 14,
                      borderWidth: 1.5,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 48,
                  child: TodayPill(label: i18n.t('mobileToday.sheets.water.addButton'), color: Tw.blue600, filled: true, onTap: _addCustom),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 6),
              Text(_error!, style: tx(12, c: Tw.red600)),
            ],
            const SizedBox(height: 18),
            Text(i18n.t('mobileToday.sheets.water.fix'), style: tx(12, w: 7, c: Tw.gray600)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final ml in const [100, 250, 500])
                TodayPill(
                  label: '−$ml ml',
                  color: Tw.gray600,
                  // Toplamın altına inecek düzeltme, kalan kadar düşürür.
                  onTap: total <= 0 ? null : () => _add(-(ml < total ? ml : total), undoable: false),
                ),
            ]),
            const SizedBox(height: 20),
            PrimaryButton(
              color: theme.primary,
              label: i18n.t('mobileToday.sheets.done'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }
}

// --- Ürün bitti -------------------------------------------------------------

class _ProductsBody extends StatefulWidget {
  const _ProductsBody({required this.actions, required this.theme, required this.products});

  final TodayActions actions;
  final RebiTheme theme;
  final List<RoutineItem> products;

  @override
  State<_ProductsBody> createState() => _ProductsBodyState();
}

class _ProductsBodyState extends State<_ProductsBody> {
  final Set<int> _selected = {};
  bool _saving = false;

  Future<void> _save() async {
    if (_saving || _selected.isEmpty) return;
    final i18n = I18n.instance;
    final actions = widget.actions;
    setState(() => _saving = true);
    var saved = 0;
    for (final index in _selected.toList()..sort()) {
      final item = widget.products[index];
      final name = str(item['action']).trim();
      final outcome = await actions.log('product_finished', {
        'product': name.length > 120 ? name.substring(0, 120) : name,
        'step_order': stepOrder(item).round(),
      });
      if (outcome.saved) saved++;
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    actions.showToast(
      saved == 0 ? i18n.t('mobileToday.toast.failed') : i18n.t('mobileToday.toast.productsFinished', {'n': saved}),
    );
  }

  @override
  Widget build(BuildContext context) {
    final i18n = I18n.instance;
    final localized = i18n.prefersLocalized;
    final finished = {
      for (final name in widget.actions.plan.plan?.progress.finishedProducts ?? const <String>[]) name.toLowerCase(),
    };
    if (widget.products.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(i18n.t('mobileToday.sheets.products.empty'), style: tx(14, c: Tw.gray500)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < widget.products.length; i++)
          Builder(builder: (context) {
            final item = widget.products[i];
            final already = finished.contains(str(item['action']).trim().toLowerCase());
            final time = str(item['time']).toLowerCase();
            final isMorning = time == 'sabah' || time == 'morning';
            return _OptionTile(
              icon: isMorning ? LucideIcons.sun : LucideIcons.moon,
              title: pickAction(item, localized: localized),
              titleMaxLines: 3,
              description: already ? i18n.t('mobileToday.sheets.products.already') : null,
              color: widget.theme.primary,
              selected: already || _selected.contains(i),
              check: true,
              onTap: already || _saving
                  ? null
                  : () => setState(() => _selected.contains(i) ? _selected.remove(i) : _selected.add(i)),
            );
          }),
        const SizedBox(height: 8),
        PrimaryButton(
          color: widget.theme.primary,
          loading: _saving,
          label: _selected.isEmpty
              ? i18n.t('mobileToday.sheets.products.save')
              : i18n.t('mobileToday.sheets.products.saveCount', {'n': _selected.length}),
          onPressed: _selected.isEmpty ? null : _save,
        ),
      ],
    );
  }
}
