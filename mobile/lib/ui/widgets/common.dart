import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n.dart';
import '../../core/routine_logic.dart';
import '../../state/theme_controller.dart';
import '../tw.dart';
import 'theme_pattern_overlay.dart';

/// `.card` — beyaz, rounded-3xl, ince kenarlık, hafif gölge, p-6.
class RCard extends StatelessWidget {
  const RCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.color,
    this.gradient,
    this.borderColor,
    this.borderWidth = 1,
    this.leftBorderColor,
    this.radius = 24,
    this.margin,
    this.onTap,
    this.dashed = false,
    this.clip = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// Verilmezse yüzey rengi (açık modda beyaz, koyu modda koyu yüzey).
  final Color? color;
  final Gradient? gradient;

  /// Verilmezse ince gri kenarlık.
  final Color? borderColor;
  final double borderWidth;

  /// `border-l-4` vurgu çizgisi.
  final Color? leftBorderColor;
  final double radius;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final bool dashed;
  final bool clip;

  @override
  Widget build(BuildContext context) {
    final borderColor = this.borderColor ?? Tw.gray100;
    final border = leftBorderColor != null
        ? Border(
            left: BorderSide(color: leftBorderColor!, width: 4),
            top: BorderSide(color: borderColor, width: borderWidth),
            right: BorderSide(color: borderColor, width: borderWidth),
            bottom: BorderSide(color: borderColor, width: borderWidth),
          )
        : Border.all(color: borderColor, width: borderWidth);
    final radiusGeo = BorderRadius.circular(radius);
    Widget content = Padding(padding: padding, child: child);
    if (clip) content = ClipRRect(borderRadius: radiusGeo, child: content);
    Widget box = Container(
      margin: margin,
      decoration: BoxDecoration(
        color: gradient == null ? (color ?? Tw.surface) : null,
        gradient: gradient,
        borderRadius: leftBorderColor != null ? null : radiusGeo,
        border: dashed ? null : border,
        boxShadow: Tw.dark ? null : const [BoxShadow(color: Color(0x0D000000), blurRadius: 2, offset: Offset(0, 1))],
      ),
      child: dashed
          ? CustomPaint(painter: _DashedBorderPainter(borderColor, borderWidth, radius), child: content)
          : leftBorderColor != null
              ? ClipRRect(borderRadius: radiusGeo, child: content)
              : content,
    );
    if (leftBorderColor != null) {
      box = ClipRRect(borderRadius: radiusGeo, child: box);
    }
    if (onTap == null) return box;
    return Padding(
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: InkWell(borderRadius: radiusGeo, onTap: onTap, child: box),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter(this.color, this.width, this.radius);

  final Color color;
  final double width;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..style = PaintingStyle.stroke;
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));
    final path = Path()..addRRect(rrect.deflate(width / 2));
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 6), paint);
        d += 10;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter old) => old.color != color || old.width != width;
}

/// `.btn-primary`
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.onPressed,
    this.label,
    this.icon,
    this.trailingIcon,
    this.child,
    this.color,
    this.loading = false,
    this.minHeight = 48,
    this.fontSize = 16,
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
    this.radius = 16,
  });

  final VoidCallback? onPressed;
  final String? label;
  final IconData? icon;
  final IconData? trailingIcon;
  final Widget? child;

  /// Verilmezse marka rengi (teal).
  final Color? color;
  final bool loading;
  final double minHeight;
  final double fontSize;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? Tw.teal600;
    final enabled = onPressed != null && !loading;
    final content = loading
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
          )
        : child ??
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[Icon(icon, size: 20, color: Colors.white), const SizedBox(width: 8)],
                if (label != null)
                  Flexible(
                    child: Text(label!, textAlign: TextAlign.center, style: tx(fontSize, w: 6, c: Colors.white)),
                  ),
                if (trailingIcon != null) ...[const SizedBox(width: 8), Icon(trailingIcon, size: 20, color: Colors.white)],
              ],
            );
    return Opacity(
      opacity: enabled || loading ? 1 : 0.5,
      child: Container(
        constraints: BoxConstraints(minHeight: minHeight),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [BoxShadow(color: color.withValues(alpha: .25), blurRadius: 15, offset: const Offset(0, 8))],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(radius),
            onTap: enabled ? onPressed : null,
            child: Padding(padding: padding, child: Center(widthFactor: 1, child: content)),
          ),
        ),
      ),
    );
  }
}

/// `.btn-secondary`
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.onPressed,
    this.label,
    this.icon,
    this.trailingIcon,
    this.child,
    this.borderColor,
    this.textColor,
    this.loading = false,
    this.fontSize = 16,
    this.minHeight = 48,
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
  });

  final VoidCallback? onPressed;
  final String? label;
  final IconData? icon;
  final IconData? trailingIcon;
  final Widget? child;

  /// Verilmezse açık teal kenarlık.
  final Color? borderColor;

  /// Verilmezse koyu teal metin.
  final Color? textColor;
  final bool loading;
  final double fontSize;
  final double minHeight;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final borderColor = this.borderColor ?? Tw.teal200;
    final textColor = this.textColor ?? Tw.teal700;
    final enabled = onPressed != null && !loading;
    final content = loading
        ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: textColor))
        : child ??
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[Icon(icon, size: 20, color: textColor), const SizedBox(width: 8)],
                if (label != null)
                  Flexible(
                    child: Text(label!, textAlign: TextAlign.center, style: tx(fontSize, w: 6, c: textColor)),
                  ),
                if (trailingIcon != null) ...[const SizedBox(width: 8), Icon(trailingIcon, size: 20, color: textColor)],
              ],
            );
    return Opacity(
      opacity: enabled || loading ? 1 : 0.5,
      child: Container(
        constraints: BoxConstraints(minHeight: minHeight),
        decoration: BoxDecoration(
          color: Tw.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: 2),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: enabled ? onPressed : null,
            child: Padding(padding: padding, child: Center(widthFactor: 1, child: content)),
          ),
        ),
      ),
    );
  }
}

/// `.input-field` dekorasyonu.
InputDecoration inputDecoration({
  String? hint,
  IconData? prefixIcon,
  Widget? suffix,
  String? suffixText,
  Color? focusColor,
  double radius = 16,
  double borderWidth = 2,
  Color? borderColor,
  EdgeInsetsGeometry contentPadding = const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
}) {
  focusColor ??= Tw.teal400;
  borderColor ??= Tw.gray200;
  OutlineInputBorder b(Color c) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: BorderSide(color: c, width: borderWidth),
      );
  return InputDecoration(
    hintText: hint,
    hintStyle: tx(16, c: Tw.gray400),
    isDense: true,
    filled: true,
    fillColor: Tw.surface,
    contentPadding: contentPadding,
    prefixIcon: prefixIcon == null ? null : Icon(prefixIcon, size: 20, color: Tw.gray400),
    suffixIcon: suffix,
    suffixText: suffixText,
    suffixStyle: tx(12, w: 6, c: Tw.gray400),
    enabledBorder: b(borderColor),
    disabledBorder: b(borderColor),
    focusedBorder: b(focusColor),
    border: b(borderColor),
  );
}

/// Beyaz zemin + tema gradyanı + desen; içerik kaydırılabilir ve `max-w-*` ile ortalanır.
class ThemedPage extends StatelessWidget {
  const ThemedPage({
    super.key,
    required this.theme,
    required this.children,
    this.maxWidth = 512,
    this.padding = const EdgeInsets.fromLTRB(16, 32, 16, 32),
    this.controller,
    this.crossAxisAlignment = CrossAxisAlignment.stretch,
    this.background,
  });

  final RebiTheme theme;
  final List<Widget> children;
  final double maxWidth;
  final EdgeInsetsGeometry padding;
  final ScrollController? controller;
  final CrossAxisAlignment crossAxisAlignment;
  final Widget? background;

  @override
  Widget build(BuildContext context) {
    return ThemedBackground(
      theme: theme,
      extra: background,
      child: SingleChildScrollView(
        controller: controller,
        padding: padding,
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Column(crossAxisAlignment: crossAxisAlignment, children: children),
          ),
        ),
      ),
    );
  }
}

class ThemedBackground extends StatelessWidget {
  const ThemedBackground({super.key, required this.theme, required this.child, this.extra});

  final RebiTheme theme;
  final Widget child;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: Tw.background),
        DecoratedBox(decoration: BoxDecoration(gradient: theme.bg)),
        ThemePatternOverlay(pattern: theme.pattern),
        ?extra,
        child,
      ],
    );
  }
}

/// Ortalanmış, sabit genişlikli içerik (kaydırma olmadan).
class CenteredBox extends StatelessWidget {
  const CenteredBox({super.key, required this.child, this.maxWidth = 512});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) =>
      Center(child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child));
}

/// accent → primary gradyanlı ikon kutusu.
class GradientIconBox extends StatelessWidget {
  const GradientIconBox({
    super.key,
    required this.icon,
    required this.from,
    required this.to,
    this.size = 56,
    this.iconSize = 28,
    this.radius = 16,
    this.shadow = true,
  });

  final IconData icon;
  final Color from;
  final Color to;
  final double size;
  final double iconSize;
  final double radius;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [from, to]),
        boxShadow: shadow
            ? [BoxShadow(color: to.withValues(alpha: .25), blurRadius: 15, offset: const Offset(0, 8))]
            : null,
      ),
      child: Icon(icon, size: iconSize, color: Colors.white),
    );
  }
}

/// Kalıcı, kutusuz beyan: Rebi bir yapay zekâdır ve hata payı vardır.
class AiDisclaimer extends StatelessWidget {
  const AiDisclaimer({super.key, this.textAlign = TextAlign.start, this.padding = EdgeInsets.zero, this.color});

  final TextAlign textAlign;
  final EdgeInsetsGeometry padding;

  /// Verilmezse soluk gri; koyu zeminlerde açık renk verilir.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    return Padding(
      padding: padding,
      child: Text(i18n.t('common.aiDisclaimer'), textAlign: textAlign, style: tx(11, c: color ?? Tw.gray500, h: relaxed)),
    );
  }
}

/// `border-2 rounded-* px-3 py-1.5` seçim düğmesi (teal aktif).
class ChoiceChipBox extends StatelessWidget {
  const ChoiceChipBox({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.radius = 999,
    this.fontSize = 12,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    this.activeBorder,
    this.activeBg,
    this.activeText,
    this.inactiveText,
    this.inactiveBg = Colors.transparent,
    this.boldWhenActive = false,
    this.center = false,
    this.leading,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final double radius;
  final double fontSize;
  final EdgeInsetsGeometry padding;
  final Color? activeBorder;
  final Color? activeBg;
  final Color? activeText;
  final Color? inactiveText;
  final Color inactiveBg;
  final bool boldWhenActive;
  final bool center;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final activeBorder = this.activeBorder ?? Tw.teal500;
    final activeBg = this.activeBg ?? Tw.teal50;
    final activeText = this.activeText ?? Tw.teal700;
    final inactiveText = this.inactiveText ?? Tw.gray500;
    final text = Text(
      label,
      textAlign: center ? TextAlign.center : TextAlign.start,
      style: tx(fontSize, w: selected && boldWhenActive ? 5 : 5, c: selected ? activeText : inactiveText, h: tight),
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: padding,
          decoration: BoxDecoration(
            color: selected ? activeBg : inactiveBg,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: selected ? activeBorder : Tw.gray200, width: 2),
          ),
          child: leading == null
              ? (center ? Center(child: text) : text)
              : Row(mainAxisSize: MainAxisSize.min, children: [leading!, const SizedBox(width: 6), Flexible(child: text)]),
        ),
      ),
    );
  }
}

/// Bilgi / hata kutusu.
class NoticeBox extends StatelessWidget {
  const NoticeBox({
    super.key,
    required this.text,
    required this.bg,
    required this.border,
    required this.fg,
    this.icon,
    this.fontSize = 14,
    this.padding = const EdgeInsets.all(12),
    this.radius = 12,
  });

  final String text;
  final Color bg;
  final Color border;
  final Color fg;
  final IconData? icon;
  final double fontSize;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, size: 16, color: fg)),
            const SizedBox(width: 8),
          ],
          Expanded(child: Text(text, style: tx(fontSize, c: fg, h: snug))),
        ],
      ),
    );
  }
}

/// `StructuredRoutineBadges` — rutin satırı rozetleri.
class StructuredBadges extends StatelessWidget {
  const StructuredBadges({super.key, required this.item});

  final RoutineItem item;

  @override
  Widget build(BuildContext context) {
    final chips = structuredRoutineBadges(item);
    if (chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final c in chips)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Tw.surface.withValues(alpha: .9),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Tw.gray200.withValues(alpha: .9)),
              ),
              child: Text(c, style: tx(9, w: 5, c: Tw.gray600)),
            ),
        ],
      ),
    );
  }
}

/// Teal dönen halka (webdeki `animate-spin` yükleyici).
class RingSpinner extends StatelessWidget {
  const RingSpinner({super.key, this.color, this.track, this.size = 40, this.stroke = 4});

  final Color? color;
  final Color? track;
  final double size;
  final double stroke;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CircularProgressIndicator(
          strokeWidth: stroke,
          color: color ?? Tw.teal600,
          backgroundColor: track ?? Tw.teal200,
        ),
      );
}

/// Dokunulabilir altı çizili metin bağlantısı.
class TextLink extends StatelessWidget {
  const TextLink(this.text, {super.key, required this.onTap, this.style, this.underline = false});

  final String text;
  final VoidCallback onTap;
  final TextStyle? style;
  final bool underline;

  @override
  Widget build(BuildContext context) {
    final s = (style ?? tx(14, w: 6, c: Tw.teal700))
        .copyWith(decoration: underline ? TextDecoration.underline : null, decorationColor: style?.color);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text(text, style: s)),
    );
  }
}

/// Mesaj (başarı / hata) satırı — profil formlarındaki `CheckCircle` / `AlertCircle` ile.
class StatusLine extends StatelessWidget {
  const StatusLine({super.key, required this.ok, required this.text, this.errorColor});

  final bool ok;
  final String text;
  final Color? errorColor;

  @override
  Widget build(BuildContext context) {
    final c = ok ? Tw.emerald700 : (errorColor ?? Tw.red600);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(ok ? LucideIcons.circleCheck : LucideIcons.circleAlert, size: 14, color: c),
        ),
        const SizedBox(width: 4),
        Expanded(child: Text(text, style: tx(12, c: c))),
      ],
    );
  }
}
