import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/day_log.dart';
import '../../core/i18n.dart';
import '../../core/routine_logic.dart';
import '../../core/today_plan.dart';
import '../../state/theme_controller.dart';
import '../../state/today_actions.dart';
import '../../ui/brand/palette.dart';
import '../../ui/tw.dart';
import '../../ui/widgets/common.dart';
import 'today_widgets.dart';
import '../../ui/brand/glyphs.dart';
import '../../core/shelf.dart';
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
    this.trailing,
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

  /// Sağda onay kutusu yerine gösterilecek öğe (ör. "Aldım" düğmesi).
  final Widget? trailing;

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
                  if (trailing != null) ...[const SizedBox(width: 8), trailing!]
                  else if (check) ...[
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

/// Su kaydı: üstte dolan bardak ve büyük rakam; altta iki büyük düğme (bardak / şişe). Başka miktar ve düzeltme,
/// sayfayı kalabalıklaştırmasın diye yalnızca istenince açılır.
class _WaterBodyState extends State<_WaterBody> {
  final _controller = TextEditingController();
  String? _error;
  bool _customOpen = false;
  bool _fixOpen = false;

  /// Bir bardak (ml): "yaklaşık N bardak" hesabı ve ana düğme.
  static const _glassMl = 250;
  static const _bottleMl = 500;

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
    final nf = NumberFormat.decimalPattern(i18n.lang);
    return ListenableBuilder(
      listenable: widget.actions.plan,
      builder: (context, _) {
        final total = widget.actions.plan.plan?.progress.waterMl ?? 0;
        final target = widget.actions.plan.plan?.waterTarget ?? waterTargetMl;
        final fraction = (total / target).clamp(0.0, 1.0);
        final reached = total >= target;
        final remaining = (target - total).clamp(0, target);
        final glasses = (remaining / _glassMl).ceil();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              container: true,
              label: i18n.t('mobileToday.waterProgress', {'ml': total, 'target': target}),
              excludeSemantics: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(end: fraction),
                    duration: const Duration(milliseconds: 650),
                    curve: Curves.easeOutCubic,
                    builder: (context, level, _) => CustomPaint(
                      size: const Size(64, 88),
                      painter: _GlassPainter(level: level, water: reached ? Tw.emerald500 : Tw.blue500, outline: Tw.gray300),
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(text: nf.format(total), style: Brand.serif(40, color: Tw.gray900, h: 1)),
                              TextSpan(text: '  / ${nf.format(target)} ml', style: tx(15, w: 5, c: Tw.gray500)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          reached
                              ? i18n.t('mobileToday.waterGoalReached')
                              : i18n.t('mobileToday.sheets.water.remaining', {'ml': nf.format(remaining), 'n': glasses}),
                          style: tx(13.5, w: 5, c: reached ? Tw.emerald700 : Tw.gray600, h: 1.35),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: _WaterButton(
                    ml: _glassMl,
                    caption: i18n.t('mobileToday.sheets.water.glass'),
                    primary: true,
                    onTap: () => _add(_glassMl),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _WaterButton(
                    ml: _bottleMl,
                    caption: i18n.t('mobileToday.sheets.water.bottle'),
                    onTap: () => _add(_bottleMl),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              children: [
                TextButton(
                  onPressed: () => setState(() => _customOpen = !_customOpen),
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48), foregroundColor: Tw.blueText),
                  child: Text(i18n.t('mobileToday.sheets.water.other'), style: tx(14, w: 6, c: Tw.blueText)),
                ),
                if (total > 0)
                  TextButton(
                    onPressed: () => setState(() => _fixOpen = !_fixOpen),
                    style: TextButton.styleFrom(minimumSize: const Size(48, 48), foregroundColor: Tw.gray600),
                    child: Text(i18n.t('mobileToday.sheets.water.fixToggle'), style: tx(14, w: 6, c: Tw.gray600)),
                  ),
              ],
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: _customOpen
                  ? Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _controller,
                                  autofocus: true,
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
                                child: TodayPill(
                                  label: i18n.t('mobileToday.sheets.water.addButton'),
                                  color: Tw.blue600,
                                  filled: true,
                                  onTap: _addCustom,
                                ),
                              ),
                            ],
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 6),
                            Text(_error!, style: tx(12, c: Tw.red600)),
                          ],
                        ],
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: _fixOpen && total > 0
                  ? Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 8),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final ml in const [100, 250, 500])
                            TodayPill(
                              label: '−$ml ml',
                              color: Tw.gray600,
                              // Toplamın altına inecek düzeltme, kalan kadar düşürür.
                              onTap: () => _add(-(ml < total ? ml : total), undoable: false),
                            ),
                        ],
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
            const SizedBox(height: 14),
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

/// Büyük su düğmesi: miktar (büyük) ve ne olduğu (bardak / şişe).
class _WaterButton extends StatelessWidget {
  const _WaterButton({required this.ml, required this.caption, required this.onTap, this.primary = false});

  final int ml;
  final String caption;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final fg = primary ? Colors.white : Tw.blueText;
    return Semantics(
      button: true,
      label: '+$ml ml, $caption',
      excludeSemantics: true,
      child: Material(
        color: primary ? Tw.blue600 : Tw.blue50,
        // İkincil düğmenin zemini koyu temada sayfaya çok yakın; ince kenar onu seçilir kılar.
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: primary ? BorderSide.none : BorderSide(color: Tw.dark ? Tw.blue500.withValues(alpha: .6) : Tw.blue100, width: 1.4),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          // Kayıt başarılı olunca `record` zaten hafif titreşim verir.
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
            child: Column(
              children: [
                Text('+$ml ml', style: tx(18, w: 7, c: fg)),
                const SizedBox(height: 2),
                Text(caption, style: tx(12.5, w: 5, c: primary ? Colors.white70 : Tw.gray500)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Hafifçe daralan bir bardak: ince dış çizgi, alttan `level` oranında dolan su ve suyun üstünde yumuşak bir kıvrım.
class _GlassPainter extends CustomPainter {
  _GlassPainter({required this.level, required this.water, required this.outline});

  final double level;
  final Color water;
  final Color outline;

  Path _glass(Size size) {
    final w = size.width;
    final h = size.height;
    final inset = w * .11;
    const r = 10.0;
    return Path()
      ..moveTo(0, 0)
      ..lineTo(w, 0)
      ..lineTo(w - inset, h - r)
      ..quadraticBezierTo(w - inset - 1, h, w - inset - r, h)
      ..lineTo(inset + r, h)
      ..quadraticBezierTo(inset + 1, h, inset, h - r)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final glass = _glass(size);
    canvas.save();
    canvas.clipPath(glass);
    canvas.drawRect(Offset.zero & size, Paint()..color = water.withValues(alpha: .08));
    if (level > 0) {
      final top = size.height * (1 - level.clamp(0.0, 1.0));
      final wave = Path()
        ..moveTo(0, top)
        ..cubicTo(size.width * .3, top - 4, size.width * .6, top + 4, size.width, top - 1)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      canvas.drawPath(wave, Paint()..color = water.withValues(alpha: .85));
    }
    canvas.restore();
    canvas.drawPath(
      glass,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = outline,
    );
  }

  @override
  bool shouldRepaint(_GlassPainter old) => old.level != level || old.water != water || old.outline != outline;
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
      final outcome = await actions.log(shelfFinishedEvent, {
        'product': shelfName(name),
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
    final plan = widget.actions.plan.plan;
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
            final name = str(item['action']).trim();
            final already = plan?.isOut(name) ?? false;
            final time = str(item['time']).toLowerCase();
            final isMorning = time == 'sabah' || time == 'morning';
            return _OptionTile(
              icon: already ? LucideIcons.packageX : (isMorning ? LucideIcons.sun : LucideIcons.moon),
              title: pickAction(item, localized: localized),
              titleMaxLines: 3,
              description: already ? i18n.t('mobileToday.sheets.products.already') : null,
              color: already ? Tw.amber700 : widget.theme.primary,
              selected: !already && _selected.contains(i),
              check: !already,
              // Biten ürün tek dokunuşla rafa geri döner ("aldım"); kaydetme düğmesini beklemez.
              trailing: already
                  ? TodayPill(
                      label: i18n.t('mobileToday.sheets.products.restock'),
                      color: Tw.amber700,
                      onTap: _saving
                          ? null
                          : () async {
                              Navigator.of(context).pop();
                              await widget.actions.record(
                                shelfRestockedEvent,
                                {'product': shelfName(name), 'step_order': stepOrder(item).round()},
                                message: i18n.t('mobileToday.toast.restocked', {'product': name}),
                                undoPayload: {'product': shelfName(name), 'step_order': stepOrder(item).round()},
                                undoType: shelfFinishedEvent,
                              );
                            },
                    )
                  : null,
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
        const SizedBox(height: 4),
        Center(
          child: TextLink(
            i18n.t('mobileToday.sheets.products.shelfLink'),
            onTap: () {
              // Sayfa kapanınca bağlam geçersiz olur: yönlendirici önce alınır.
              final router = GoRouter.of(context);
              Navigator.of(context).pop();
              router.go('/dashboard/shelf');
            },
            style: tx(13, w: 6, c: widget.theme.fg),
          ),
        ),
      ],
    );
  }
}
