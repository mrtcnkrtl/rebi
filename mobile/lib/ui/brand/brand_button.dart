import 'package:flutter/material.dart';

import '../tw.dart';
import 'motion.dart';
import 'palette.dart';

/// Karşılama ve giriş ekranlarının düz, kendinden emin düğmesi: tam yuvarlak uçlu, gölgesiz.
/// [outlined] true ise ikincil (çerçeveli) görünür.
class BrandButton extends StatelessWidget {
  const BrandButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.trailingIcon,
    this.loading = false,
    this.outlined = false,
    this.onDark = false,
    this.height = 58,
  });

  final VoidCallback? onPressed;
  final String label;
  final IconData? trailingIcon;
  final bool loading;
  final bool outlined;

  /// Koyu orman zemininde (karşılama): dolu düğme krem zeminde orman yazılı, çerçeveli düğme krem çerçeveli ve yazılıdır.
  final bool onDark;
  final double height;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final fg = onDark ? (outlined ? Brand.cream : Brand.forest) : (outlined ? Brand.ink : Brand.buttonFg);
    final content = loading
        ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: fg))
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(child: Text(label, textAlign: TextAlign.center, style: tx(16, w: 6, c: fg, ls: .1))),
              if (trailingIcon != null) ...[const SizedBox(width: 10), Icon(trailingIcon, size: 19, color: fg)],
            ],
          );
    return AnimatedOpacity(
      opacity: enabled || loading ? 1 : .42,
      duration: const Duration(milliseconds: 200),
      child: Pressable(
        onTap: enabled ? onPressed : null,
        scale: .98,
        child: Container(
          constraints: BoxConstraints(minHeight: height),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: outlined ? Colors.transparent : (onDark ? Brand.cream : Brand.buttonBg),
            borderRadius: BorderRadius.circular(height / 2),
            border: outlined ? Border.all(color: (onDark ? Brand.cream : Brand.ink).withValues(alpha: onDark ? .32 : .22), width: 1.4) : null,
          ),
          child: content,
        ),
      ),
    );
  }
}

/// Vurgulu bağlantı metni: altçizgi, harf kuyruklarını (ş, ç, ğ) kapatmasın diye ayrı bir çizgi olarak çizilir.
class BrandLinkText extends StatelessWidget {
  const BrandLinkText(this.text, {super.key, this.size = 14.5});

  final String text;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(bottom: 2),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Brand.teal, width: 2))),
      child: Text(text, style: tx(size, w: 7, c: Brand.ink)),
    );
  }
}
