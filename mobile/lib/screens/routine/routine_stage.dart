import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/i18n.dart';
import '../../state/theme_controller.dart';
import '../../ui/brand/brand_caps.dart';
import '../../ui/brand/brand_mark.dart';
import '../../ui/brand/motion.dart';
import '../../ui/brand/palette.dart';
import '../../ui/tw.dart';

/// Rutin sayfasının üst sahnesi: seçili temanın derin tonunda (Bugün sahnesiyle aynı dil), krem Fraunces başlık, cilt
/// profili çipleri ve haftanın gün seçici şeridi. Alttaki ilk kart [overlap] kadar sahneye biner (`StageOverlap`).
/// Durum çubuğu simgeleri sahne ekrandayken açıktır.
class RoutineStage extends StatelessWidget {
  const RoutineStage({
    super.key,
    required this.title,
    required this.dateLine,
    required this.theme,
    required this.chips,
    required this.dayLabel,
    required this.strip,
    required this.caption,
    this.trailing,
  });

  /// Kartın sahneye binen yüksekliği (dp); sahnenin alt boşluğu bunu içerir.
  static const overlap = 36.0;

  final String title;
  final String dateLine;
  final RebiTheme theme;

  /// Cilt tipi · şiddet · yaş grubu gibi kısa profil etiketleri (boşsa çip satırı çizilmez).
  final List<String> chips;

  /// Gün seçicinin üstündeki küçük başlık ("Gün gün rutin").
  final String dayLabel;
  final Widget strip;

  /// Seçili günün başlığı ("Çar · Bugün"): gün şeridinin altında, sahnenin içinde.
  final String caption;

  /// Sağ üstteki öğe (ör. "Takibe dön" bağlantısı).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final lang = context.i18n.lang;
    final top = MediaQuery.paddingOf(context).top;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
        child: ColoredBox(
          color: theme.stage,
          child: Stack(
            children: [
              const Positioned(right: -64, top: -18, child: BrandWatermark(size: 250)),
              Padding(
                padding: EdgeInsets.fromLTRB(20, top + 14, 16, 22 + overlap),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Reveal(
                              offset: const Offset(0, 6),
                              child: Text(
                                brandCaps(dateLine, lang),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: tx(11.5, w: 6, c: Brand.cream.withValues(alpha: .72), ls: brandTracking(lang, 1.6)),
                              ),
                            ),
                          ),
                        ),
                        if (trailing != null) ...[const SizedBox(width: 12), trailing!],
                      ],
                    ),
                    const SizedBox(height: 10),
                    Reveal(
                      delay: const Duration(milliseconds: 60),
                      offset: const Offset(0, 12),
                      child: Semantics(header: true, child: Text(title, style: Brand.serif(32, color: Brand.cream, h: 1.1, ls: -.8))),
                    ),
                    if (chips.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Reveal(
                        delay: const Duration(milliseconds: 140),
                        offset: const Offset(0, 8),
                        child: Wrap(spacing: 8, runSpacing: 8, children: [for (final c in chips) _Chip(c)]),
                      ),
                    ],
                    const SizedBox(height: 22),
                    Text(dayLabel, style: tx(13, w: 6, c: Brand.cream.withValues(alpha: .78))),
                    const SizedBox(height: 8),
                    strip,
                    const SizedBox(height: 18),
                    Text(caption, style: Brand.serif(24, color: Brand.cream, h: 1.15, ls: -.4)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Brand.cream.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Brand.cream.withValues(alpha: .24)),
      ),
      child: Text(text, style: tx(12.5, w: 6, c: Brand.cream.withValues(alpha: .92))),
    );
  }
}
