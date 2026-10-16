import 'package:flutter/material.dart';

import '../../ui/tw.dart';
import '../../ui/widgets/common.dart';
import '../../ui/brand/palette.dart';

class ChipOption<T> {
  const ChipOption(this.id, this.label);

  final T id;
  final String label;
}

/// Web `ChipSelect`: eşit sütunlu ızgara, tek seçim.
class ChipSelect<T> extends StatelessWidget {
  const ChipSelect({super.key, required this.options, required this.value, required this.onChanged, this.cols = 2});

  final List<ChipOption<T>> options;
  final T value;
  final ValueChanged<T> onChanged;
  final int cols;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < options.length; i += cols) {
      final slice = options.sublist(i, (i + cols).clamp(0, options.length));
      rows.add(IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var j = 0; j < cols; j++) ...[
              if (j > 0) const SizedBox(width: 4),
              Expanded(
                child: j < slice.length ? _chip(slice[j]) : const SizedBox.shrink(),
              ),
            ],
          ],
        ),
      ));
      if (i + cols < options.length) rows.add(const SizedBox(height: 4));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }

  Widget _chip(ChipOption<T> o) {
    final active = value == o.id;
    return Material(
      color: active ? Tw.teal50 : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => onChanged(o.id),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: active ? Tw.teal500 : Tw.gray200, width: 2),
          ),
          child: Text(
            o.label,
            textAlign: TextAlign.center,
            style: tx(10, w: active ? 5 : 4, c: active ? Tw.teal800 : Tw.gray500, h: tight),
          ),
        ),
      ),
    );
  }
}

/// Webdeki `input type=range` karşılığı.
class RangeSlider1 extends StatelessWidget {
  const RangeSlider1({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.color,
    required this.onChanged,
  });

  final double value;
  final double min;
  final double max;
  final double step;
  final Color color;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 6,
        activeTrackColor: color,
        inactiveTrackColor: Tw.gray200,
        thumbColor: color,
        overlayColor: color.withValues(alpha: .12),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
        tickMarkShape: SliderTickMarkShape.noTickMark,
        showValueIndicator: ShowValueIndicator.never,
      ),
      child: SizedBox(
        height: 28,
        child: Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: ((max - min) / step).round(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

/// İki düğmeli alt satır: Geri / Devam.
class BackNextRow extends StatelessWidget {
  const BackNextRow({
    super.key,
    required this.backLabel,
    required this.onBack,
    required this.nextLabel,
    required this.onNext,
    this.nextIcon,
    this.nextLeadingIcon,
  });

  final String backLabel;
  final VoidCallback onBack;
  final String nextLabel;
  final VoidCallback? onNext;
  final IconData? nextIcon;
  final IconData? nextLeadingIcon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SecondaryButton(
            onPressed: onBack,
            icon: Icons.arrow_back_rounded,
            label: backLabel,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: PrimaryButton(
            onPressed: onNext,
            icon: nextLeadingIcon,
            label: nextLabel,
            trailingIcon: nextIcon,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
        ),
      ],
    );
  }
}

/// Bölüm başlığı (h2 + açıklama).
class StepHeader extends StatelessWidget {
  const StepHeader({super.key, required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: heading(26)),
          const SizedBox(height: 4),
          Text(subtitle, style: tx(14, c: Tw.gray500)),
        ],
      );
}

/// Kart başlığı: ikon + kalın küçük metin.
class CardTitle extends StatelessWidget {
  const CardTitle({super.key, required this.icon, required this.color, required this.text, this.size = 12});

  final IconData icon;
  final Color color;
  final String text;
  final double size;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: tx(size, w: 7))),
        ],
      );
}
