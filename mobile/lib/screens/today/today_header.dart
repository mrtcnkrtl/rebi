import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n.dart';
import '../../core/today_plan.dart';
import '../../state/theme_controller.dart';
import '../../ui/brand/brand_caps.dart';
import '../../ui/brand/motion.dart';
import '../../ui/brand/palette.dart';
import '../../ui/shell/page_stage.dart';
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
    return StageSurface(
      theme: theme,
      child: Padding(
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
              const SizedBox(height: 20),
              Reveal(
                delay: const Duration(milliseconds: 160),
                offset: const Offset(0, 8),
                child: _WeatherPanel(plan: plan!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Sahnedeki hava paneli: büyük derece + UV ve nem göstergeleri (uygulamanın "hava durumuna göre" vaadinin ilk yüzü).
/// Hava gerçek bir kaynaktan değilse "tahmini" etiketi taşır. Büyük yazıda ya da dar ekranda alt alta dizilir.
class _WeatherPanel extends StatelessWidget {
  const _WeatherPanel({required this.plan});

  final TodayPlan plan;

  static num? _n(Object? v) => v is num ? v : num.tryParse('${v ?? ''}');

  @override
  Widget build(BuildContext context) {
    final i18n = I18n.instance;
    final w = plan.weather;
    final temp = _n(w['temperature']);
    if (temp == null) return const SizedBox.shrink();
    final uv = _n(w['uv_index']);
    final humidity = _n(w['humidity']);

    final uvKey = uv == null ? null : (uv < 3 ? 'low' : (uv < 6 ? 'moderate' : (uv < 8 ? 'high' : 'veryHigh')));
    final humKey = humidity == null ? null : (humidity < 40 ? 'dry' : (humidity > 65 ? 'humid' : 'comfortable'));

    final degree = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${temp.round()}°', style: Brand.serif(54, color: Brand.cream, h: 1, ls: -1.6)),
          const SizedBox(width: 10),
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Icon(LucideIcons.cloudSun, size: 26, color: Brand.cream.withValues(alpha: .9)),
          ),
        ],
      ),
    );

    // Satır sığmazsa (büyük yazı, dar panel) küçülür; taşma ve kesilme olmaz.
    Widget stat(String label, String value, String? word, {Widget? meter}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(label, style: tx(11.5, w: 7, c: Brand.cream.withValues(alpha: .7), ls: .8)),
              const SizedBox(width: 8),
              Text(value, style: tx(20, w: 7, c: Brand.cream)),
              if (word != null) ...[const SizedBox(width: 8), Text(word, style: tx(12.5, w: 6, c: Brand.cream.withValues(alpha: .86)))],
            ],
          ),
        ),
        if (meter != null) ...[const SizedBox(height: 7), meter],
      ],
    );

    final stats = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (uv != null)
          stat(
            'UV',
            '${uv.round()}',
            uvKey == null ? null : i18n.t('mobileToday.weatherPanel.uv.$uvKey'),
            meter: _Meter(fraction: (uv / 11).clamp(0, 1).toDouble(), warm: uv >= 6),
          ),
        if (uv != null && humidity != null) const SizedBox(height: 12),
        if (humidity != null)
          stat(
            i18n.t('mobileToday.weatherPanel.humidity'),
            '%${humidity.round()}',
            humKey == null ? null : i18n.t('mobileToday.weatherPanel.hum.$humKey'),
            meter: _Meter(fraction: (humidity / 100).clamp(0, 1).toDouble(), warm: false),
          ),
      ],
    );

    final estimated = !plan.hasRealWeather;
    return LayoutBuilder(
      builder: (context, box) {
        // Yan yana dizilim ~330 dp panel genişliği ister; dar ekranda ya da büyük yazıda alt alta.
        final stacked = MediaQuery.textScalerOf(context).scale(1) > 1.25 || box.maxWidth < 330;
        return Semantics(
          container: true,
          label: i18n.t('mobileToday.weatherPill', {
            'temp': '${temp.round()}',
            'uv': uv == null ? '–' : '${uv.round()}',
            'humidity': humidity == null ? '–' : '${humidity.round()}',
          }),
          child: ExcludeSemantics(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              decoration: BoxDecoration(
                color: Brand.cream.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Brand.cream.withValues(alpha: .2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(i18n.t('mobileToday.weatherPanel.title'), style: tx(12.5, w: 6, c: Brand.cream.withValues(alpha: .78))),
                      ),
                      if (estimated) Text(i18n.t('mobileToday.weatherPillEstimated'), style: tx(11.5, w: 6, c: Brand.cream.withValues(alpha: .66))),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (stacked) ...[
                    degree,
                    const SizedBox(height: 14),
                    stats,
                  ] else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        degree,
                        Container(width: 1, height: 70, margin: const EdgeInsets.symmetric(horizontal: 18), color: Brand.cream.withValues(alpha: .2)),
                        Expanded(child: stats),
                      ],
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Beş parçalı küçük gösterge (UV ve nem): dolu parçalar krem, sıcak uyarıda bal tonu.
class _Meter extends StatelessWidget {
  const _Meter({required this.fraction, required this.warm});

  final double fraction;
  final bool warm;

  @override
  Widget build(BuildContext context) {
    final filled = (fraction * 5).ceil().clamp(0, 5);
    return SizedBox(
      width: 110,
      child: Row(
        children: [
          for (var i = 0; i < 5; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: Container(
                height: 5,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  color: i < filled ? (warm ? Tw.amber300 : Brand.cream.withValues(alpha: .92)) : Brand.cream.withValues(alpha: .2),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
