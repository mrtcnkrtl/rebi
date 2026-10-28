import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show TextInputFormatter;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../state/theme_controller.dart';
import '../../ui/brand/motion.dart';
import '../../ui/brand/palette.dart';
import '../../ui/tw.dart';
import '../../ui/widgets/common.dart';
import 'analyze_widgets.dart' show RangeSlider1;

/// Analiz sihirbazının yapı taşları: üst çubuk + bölüm ilerlemesi, alt eylem çubuğu, başlık, seçim satırları.
/// Dil: krem kâğıt zemin, Fraunces soru, büyük dokunma alanları, tek odak (bkz. docs/MOBIL-TASARIM-DILI.md).

/// Üst çubuk: geri, bölüm adı, kapat; altında bölüm başına bir ince ilerleme çizgisi.
class FlowTop extends StatelessWidget {
  const FlowTop({
    super.key,
    required this.chapterLabel,
    required this.fractions,
    required this.onBack,
    required this.onClose,
    required this.backLabel,
    required this.closeLabel,
  });

  final String chapterLabel;

  /// Her bölümün doluluk oranı (0–1).
  final List<double> fractions;
  final VoidCallback onBack;
  final VoidCallback onClose;
  final String backLabel;
  final String closeLabel;

  @override
  Widget build(BuildContext context) {
    final fill = context.watch<ThemeController>().theme.fg;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: backLabel,
                onPressed: onBack,
                icon: Icon(LucideIcons.chevronLeft, size: 26, color: Tw.gray700),
              ),
              Expanded(
                child: Text(
                  chapterLabel,
                  textAlign: TextAlign.center,
                  style: tx(13, w: 6, c: Tw.gray500, ls: .3),
                ),
              ),
              IconButton(
                tooltip: closeLabel,
                onPressed: onClose,
                icon: Icon(LucideIcons.x, size: 22, color: Tw.gray500),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
            child: Row(
              children: [
                for (var i = 0; i < fractions.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: SizedBox(
                        height: 4,
                        child: Stack(
                          children: [
                            Positioned.fill(child: ColoredBox(color: Tw.gray100)),
                            Positioned.fill(
                              child: TweenAnimationBuilder<double>(
                                tween: Tween(end: fractions[i].clamp(0.0, 1.0)),
                                duration: const Duration(milliseconds: 320),
                                curve: Curves.easeOutCubic,
                                builder: (context, v, _) => Align(
                                  alignment: Alignment.centerLeft,
                                  child: FractionallySizedBox(
                                    widthFactor: v,
                                    heightFactor: 1,
                                    child: ColoredBox(color: fill),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
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
}

/// Alt eylem çubuğu: tek ana düğme; isteğe bağlı sessiz ikinci eylem (atla / şimdi değil).
class FlowBottom extends StatelessWidget {
  const FlowBottom({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon = LucideIcons.arrowRight,
    this.leadingIcon,
    this.secondaryLabel,
    this.onSecondary,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final IconData? leadingIcon;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>().theme;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 8, 24, 12 + MediaQuery.paddingOf(context).bottom),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PrimaryButton(
                key: const Key('flow-next'),
                onPressed: onPressed,
                color: theme.primary,
                label: label,
                icon: leadingIcon,
                trailingIcon: icon,
                minHeight: 56,
              ),
              if (secondaryLabel != null)
                TextButton(
                  key: const Key('flow-skip'),
                  onPressed: onSecondary,
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48), foregroundColor: Tw.gray600),
                  child: Text(secondaryLabel!, style: tx(14.5, w: 6, c: Tw.gray600)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sorunun başlığı: küçük üst etiket, Fraunces soru, kısa açıklama.
class FlowTitle extends StatelessWidget {
  const FlowTitle({super.key, required this.title, this.subtitle, this.caption});

  final String title;
  final String? subtitle;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final fg = context.watch<ThemeController>().theme.fg;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (caption != null) ...[Text(caption!, style: tx(13, w: 6, c: fg, ls: .2)), const SizedBox(height: 8)],
        Semantics(header: true, child: Text(title, style: heading(30, h: 1.14))),
        if (subtitle != null && subtitle!.isNotEmpty) ...[const SizedBox(height: 10), Text(subtitle!, style: tx(15.5, c: Tw.gray500, h: 1.45))],
      ],
    );
  }
}

/// Tek ya da çoklu seçim satırı: büyük dokunma alanı, soldaki görsel/ikon, başlık + kısa açıklama, sağda işaret.
class ChoiceTile extends StatelessWidget {
  const ChoiceTile({super.key, required this.title, required this.selected, required this.onTap, this.description, this.leading, this.multi = false});

  final String title;
  final String? description;
  final Widget? leading;
  final bool selected;
  final bool multi;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>().theme;
    final mark = multi ? BorderRadius.circular(8) : BorderRadius.circular(99);
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: !multi,
      label: description == null ? title : '$title. $description',
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: selected ? Color.alphaBlend(theme.primary.withValues(alpha: .08), Tw.surface) : Tw.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: selected ? theme.primary : Tw.gray200, width: selected ? 1.8 : 1.4),
            ),
            child: Row(
              children: [
                if (leading != null) ...[leading!, const SizedBox(width: 14)],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: tx(16.5, w: selected ? 6 : 5, c: Tw.gray900, h: 1.25),
                      ),
                      if (description != null) ...[const SizedBox(height: 3), Text(description!, style: tx(13.5, c: Tw.gray500, h: 1.35))],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: selected ? theme.primary : Colors.transparent,
                    borderRadius: mark,
                    border: Border.all(color: selected ? theme.primary : Tw.gray300, width: 1.6),
                  ),
                  child: selected ? const Icon(LucideIcons.check, size: 15, color: Colors.white) : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Seçim satırlarını eşit aralıkla dizer (ilk eleman üstte, her biri tam genişlik).
class ChoiceList extends StatelessWidget {
  const ChoiceList({super.key, required this.children, this.gap = 10});

  final List<Widget> children;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[if (i > 0) SizedBox(height: gap), children[i]],
      ],
    );
  }
}

/// Kısa seçenekler için çip bulutu (bölge, tetikleyici, işaret…).
class ChipCloud extends StatelessWidget {
  const ChipCloud({super.key, required this.items, required this.isSelected, required this.onTap});

  /// (kimlik, etiket)
  final List<(String, String)> items;
  final bool Function(String id) isSelected;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>().theme;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final (id, label) in items)
          Semantics(
            button: true,
            selected: isSelected(id),
            label: label,
            excludeSemantics: true,
            onTap: () => onTap(id),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => onTap(id),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isSelected(id) ? Color.alphaBlend(theme.primary.withValues(alpha: .08), Tw.surface) : Tw.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: isSelected(id) ? theme.primary : Tw.gray200, width: isSelected(id) ? 1.8 : 1.4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isSelected(id)) ...[Icon(LucideIcons.check, size: 16, color: theme.fg), const SizedBox(width: 6)],
                      Flexible(
                        child: Text(
                          label,
                          style: tx(15, w: isSelected(id) ? 6 : 5, c: Tw.gray900, h: 1.25),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Alt soru başlığı (ör. "Kaç yıldır?").
class SubQuestion extends StatelessWidget {
  const SubQuestion(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 28, bottom: 12),
    child: Text(text, style: heading(21, h: 1.2)),
  );
}

/// Kısa bilgi satırı: küçük ikon + sakin metin.
class FlowNote extends StatelessWidget {
  const FlowNote({super.key, required this.text, this.icon = LucideIcons.info});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 16, color: Tw.gray500),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: tx(13.5, c: Tw.gray500, h: 1.4)),
        ),
      ],
    );
  }
}

/// Büyük sayı + kaydırıcı + eksi/artı düğmeleri (su, uyku, döngü uzunluğu).
class BigStepper extends StatelessWidget {
  const BigStepper({
    super.key,
    required this.icon,
    required this.color,
    required this.label,
    required this.valueText,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
    required this.decreaseLabel,
    required this.increaseLabel,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String valueText;
  final double value;
  final double min;
  final double max;
  final double step;
  final ValueChanged<double> onChanged;
  final String decreaseLabel;
  final String increaseLabel;

  @override
  Widget build(BuildContext context) {
    void nudge(double d) => onChanged((value + d).clamp(min, max));
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: Tw.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Tw.gray100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: color.withValues(alpha: .14), shape: BoxShape.circle),
                child: Icon(icon, size: 18, color: Tw.readable(color, bg: Color.alphaBlend(color.withValues(alpha: .14), Tw.surface))),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(label, style: tx(15.5, w: 6, c: Tw.gray800)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Semantics(
            liveRegion: true,
            child: Text(valueText, textAlign: TextAlign.center, style: heading(42, h: 1.2)),
          ),
          Row(
            children: [
              _RoundStep(icon: LucideIcons.minus, label: decreaseLabel, onTap: value > min ? () => nudge(-step) : null),
              Expanded(
                child: Semantics(
                  label: label,
                  child: RangeSlider1(value: value, min: min, max: max, step: step, color: color, onChanged: onChanged),
                ),
              ),
              _RoundStep(icon: LucideIcons.plus, label: increaseLabel, onTap: value < max ? () => nudge(step) : null),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoundStep extends StatelessWidget {
  const _RoundStep({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? .4 : 1,
        child: Pressable(
          onTap: onTap,
          scale: .94,
          child: Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Tw.gray200, width: 1.4),
              ),
              child: Icon(icon, size: 18, color: Tw.gray700),
            ),
          ),
        ),
      ),
    );
  }
}

/// Ad / yaş gibi metin alanı: üstte etiket, altında büyük giriş.
class FlowField extends StatelessWidget {
  const FlowField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
    this.textInputAction,
    this.onSubmitted,
    this.suffixText,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final String? suffixText;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>().theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 2),
          child: Text(label, style: tx(14, w: 6, c: Tw.gray700)),
        ),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          textCapitalization: textCapitalization,
          inputFormatters: inputFormatters,
          textInputAction: textInputAction,
          onSubmitted: onSubmitted,
          cursorColor: theme.primary,
          style: tx(18, w: 5, c: Tw.gray900),
          decoration: inputDecoration(
            hint: hint,
            radius: 18,
            focusColor: theme.primary,
            suffixText: suffixText,
            contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
          ),
        ),
      ],
    );
  }
}
