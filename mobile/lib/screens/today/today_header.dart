import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n.dart';
import '../../core/routine_logic.dart';
import '../../core/today_plan.dart';
import '../../state/theme_controller.dart';
import '../../ui/brand/brand_caps.dart';
import '../../ui/brand/brand_mark.dart';
import '../../ui/brand/motion.dart';
import '../../ui/brand/palette.dart';
import '../../ui/tw.dart';
import 'today_clock.dart';

/// Bugün'ün üst sahnesi: seçili temanın derin tonunda (Orman'da marka yeşili), tam genişlikte; krem Fraunces selamlama
/// (günün saatine göre, `mobileToday.greet.*`), küçük harfli tarih, hesap kısayolu ve tek satırlık hava özeti.
/// Aşağıdaki kahraman kart [overlap] kadar sahnenin alt kenarına biner (`StageOverlap`).
/// Durum çubuğu simgeleri sahne ekrandayken açık renktir; sahne kaydırılıp çıkınca sayfanın kendi stiline döner.
class TodayHeader extends StatelessWidget {
  const TodayHeader({super.key, required this.name, required this.dateLine, required this.theme, this.trailing, this.plan, this.greeting});

  /// Kartın sahneye binen yüksekliği (dp); sahnenin alt boşluğu bunu içerir.
  static const overlap = 40.0;

  final String name;
  final String dateLine;
  final RebiTheme theme;

  /// Sağ üstteki öğe (hesap kısayolu).
  final Widget? trailing;

  /// Verilirse (ve hava değerleri varsa) selamlamanın altında "18° · UV 6 · nem %38" özeti görünür.
  final TodayPlan? plan;

  /// Verilirse saate göre selamlamanın yerine bu metin yazılır (rutini olmayan kullanıcıda kişisel karşılama).
  final String? greeting;

  static String greetingKey(DateTime now) {
    final h = now.hour;
    if (h >= 5 && h < 12) return 'morning';
    if (h >= 12 && h < 18) return 'afternoon';
    if (h >= 18 && h < 22) return 'evening';
    return 'night';
  }

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final lang = i18n.lang;
    final first = name.trim().split(RegExp(r'\s+')).first;
    final top = MediaQuery.paddingOf(context).top;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
        child: ColoredBox(
          color: theme.stage,
          child: Stack(
            children: [
              // Marka imzası: çok silik, sabit "R" (karşılama ve girişteki monogramın sakin hâli).
              const Positioned(right: -64, top: -18, child: _Watermark(size: 250)),
              Padding(
                // Hava özeti yoksa (rutinsiz karşılama) sahne biraz uzar: selamlama ile kart arasında nefes payı kalsın.
                padding: EdgeInsets.fromLTRB(22, top + 14, 16, 22 + overlap + (plan != null && plan!.weather['temperature'] != null ? 0 : 10)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 14),
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
                      child: Text(
                        greeting ?? i18n.t('mobileToday.greet.${greetingKey(todayPanelClock())}', {'name': first}),
                        style: Brand.serif(34, color: Brand.cream, h: 1.08, ls: -.9),
                      ),
                    ),
                    if (plan != null && plan!.weather['temperature'] != null) ...[
                      const SizedBox(height: 16),
                      Reveal(
                        delay: const Duration(milliseconds: 160),
                        offset: const Offset(0, 8),
                        child: _WeatherPill(plan: plan!),
                      ),
                    ],
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

/// Tek satırlık hava özeti (krem çerçeveli, koyu zeminde); hava gerçek bir kaynaktan değilse "tahmini" etiketi taşır.
class _WeatherPill extends StatelessWidget {
  const _WeatherPill({required this.plan});

  final TodayPlan plan;

  @override
  Widget build(BuildContext context) {
    final i18n = I18n.instance;
    final w = plan.weather;
    final base = i18n.t('mobileToday.weatherPill', {
      'temp': str(w['temperature']),
      'uv': str(w['uv_index']),
      'humidity': str(w['humidity']),
    });
    // Tahmini etiket aynı metinde durur: büyük yazıda hap taşmasın, sığmayan kısım "…" olsun.
    final text = plan.hasRealWeather ? base : '$base · ${i18n.t('mobileToday.weatherPillEstimated')}';
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.fromLTRB(11, 7, 15, 7),
        decoration: BoxDecoration(
          color: Brand.cream.withValues(alpha: .09),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Brand.cream.withValues(alpha: .24)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.cloudSun, size: 16, color: Brand.cream.withValues(alpha: .92)),
            const SizedBox(width: 8),
            Flexible(child: Text(text, style: tx(12.5, w: 6, c: Brand.cream.withValues(alpha: .92)), maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    );
  }
}

/// Süsleme: sabit, çok silik "R"; ekran okuyuculardan gizli, tek katman saydamlık (üst üste binen çizgiler koyulaşmasın).
class _Watermark extends StatelessWidget {
  const _Watermark({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: IgnorePointer(
        child: RepaintBoundary(
          child: Opacity(
            opacity: .055,
            child: CustomPaint(size: Size.square(size), painter: BrandGlyphPainter(1, 1, color: Brand.cream)),
          ),
        ),
      ),
    );
  }
}
