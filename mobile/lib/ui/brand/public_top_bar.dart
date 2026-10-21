import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n.dart';
import '../components/language_sheet.dart';
import '../tw.dart';
import 'brand_mark.dart';
import 'motion.dart';
import 'palette.dart';

/// Açılış ve giriş ekranlarının üst çubuğu: solda marka yazısı (ya da geri düğmesi), sağda dil seçici.
/// Sayfayla birlikte durur; kabuğun sabit çubuğunun yerini alır.
class PublicTopBar extends StatelessWidget {
  const PublicTopBar({super.key, this.onBack, this.onDark = false});

  /// Verilirse marka yazısı yerine geri düğmesi görünür.
  final VoidCallback? onBack;

  /// Koyu orman zemininde (karşılama sahnesi) krem renkler ve marka karosu kullanılır.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    const cream = Color(0xFFF7F3EC);
    final fg = onDark ? cream : Brand.ink;
    final fgSoft = onDark ? cream.withValues(alpha: .72) : Brand.inkSoft;
    final line = onDark ? cream.withValues(alpha: .26) : Brand.ink.withValues(alpha: .16);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 20, 0),
      child: SizedBox(
        height: 52,
        child: Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: onBack != null
                    ? Semantics(
                        label: i18n.t('mobileNav.back'),
                        child: Pressable(
                          onTap: onBack,
                          scale: .92,
                          child: SizedBox(
                            width: 48,
                            height: 48,
                            child: Center(
                              child: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: line, width: 1.3)),
                                child: Icon(LucideIcons.chevronLeft, size: 22, color: fg),
                              ),
                            ),
                          ),
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (onDark) ...[const BrandMark(size: 28), const SizedBox(width: 10)],
                          Text('Rebi', maxLines: 1, style: Brand.serif(27, weight: 600, color: onDark ? cream : null, ls: -.8)),
                        ],
                      ),
              ),
            ),
            const SizedBox(width: 8),
            Semantics(
              button: true,
              label: i18n.t('lang.label'),
              child: Pressable(
                onTap: () => showLanguageSheet(context),
                scale: .95,
                child: ConstrainedBox(
                  // Görünüm hap boyunda, dokunma alanı 48 dp.
                  constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
                  child: Center(
                    widthFactor: 1,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: line, width: 1.3),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LucideIcons.globe, size: 15, color: fg),
                          const SizedBox(width: 6),
                          Text(i18n.lang.toUpperCase(), style: tx(12.5, w: 7, c: fg, ls: .4)),
                          const SizedBox(width: 3),
                          Icon(LucideIcons.chevronDown, size: 14, color: fgSoft),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
