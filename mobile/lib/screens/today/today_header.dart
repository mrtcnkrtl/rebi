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
  const TodayHeader({
    super.key,
    required this.name,
    required this.dateLine,
    required this.theme,
    this.trailing,
    this.plan,
    this.greeting,
    this.placeKnown = false,
    this.placeName,
    this.onWeatherPlace,
    this.onWeatherRetry,
  });

  /// Kartın sahneye binen yüksekliği (dp); sahnenin alt boşluğu bunu içerir.
  static const overlap = 40.0;

  final String name;
  final String dateLine;
  final RebiTheme theme;

  /// Sağ üstteki öğe (hesap kısayolu).
  final Widget? trailing;

  /// Verilirse selamlamanın altında hava paneli görünür: gerçek hava varsa derece, UV ve nem; yoksa uydurma sayı yerine
  /// "yer seç" (ya da hava servisi yanıt vermiyorsa "yeniden dene") durumu.
  final TodayPlan? plan;

  /// Hava için bir yer belli mi (telefon konumu bulundu / şehir seçildi): hava yine de yoksa sorun servis ya da bağlantıdır.
  final bool placeKnown;

  /// Kullanıcının seçtiği şehir (yoksa telefonun konumu kullanılıyordur).
  final String? placeName;

  /// Yer seçme sayfasını açar; verilmezse yer seçimi sunulmaz (demo).
  final VoidCallback? onWeatherPlace;

  /// Hava yeniden okunur.
  final VoidCallback? onWeatherRetry;

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
        padding: EdgeInsets.fromLTRB(22, top + 14, 16, 22 + overlap + (plan != null ? 0 : 10)),
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
            if (plan != null) ...[
              const SizedBox(height: 20),
              Reveal(
                delay: const Duration(milliseconds: 160),
                offset: const Offset(0, 8),
                child: plan!.hasRealWeather
                    ? _WeatherPanel(plan: plan!, placeName: placeName, onPlace: onWeatherPlace)
                    : _WeatherMissing(placeKnown: placeKnown, onPlace: onWeatherPlace, onRetry: onWeatherRetry),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Sahnedeki hava paneli: büyük derece + UV ve nem göstergeleri (uygulamanın "hava durumuna göre" vaadinin ilk yüzü).
/// Yalnızca gerçek hava (canlı, bugünkü kayıt ya da profildeki yer) gösterilir; sağ üstteki yer düğmesi yeri değiştirir.
/// Büyük yazıda ya da dar ekranda alt alta dizilir.
class _WeatherPanel extends StatelessWidget {
  const _WeatherPanel({required this.plan, this.placeName, this.onPlace});

  final TodayPlan plan;
  final String? placeName;
  final VoidCallback? onPlace;

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
            // Türkçede yüzde işareti öne ("%38"), İngilizcede sona ("38%") yazılır.
            i18n.lang == 'tr' ? '%${humidity.round()}' : '${humidity.round()}%',
            humKey == null ? null : i18n.t('mobileToday.weatherPanel.hum.$humKey'),
            meter: _Meter(fraction: (humidity / 100).clamp(0, 1).toDouble(), warm: false),
          ),
      ],
    );

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
                      child: ExcludeSemantics(
                        child: Text(i18n.t('mobileToday.weatherPanel.title'), style: tx(12.5, w: 6, c: Brand.cream.withValues(alpha: .78))),
                      ),
                    ),
                    if (onPlace != null) _PlaceChip(name: placeName, onTap: onPlace!),
                  ],
                ),
                const SizedBox(height: 8),
                ExcludeSemantics(
                  child: stacked
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [degree, const SizedBox(height: 14), stats],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            degree,
                            Container(width: 1, height: 70, margin: const EdgeInsets.symmetric(horizontal: 18), color: Brand.cream.withValues(alpha: .2)),
                            Expanded(child: stats),
                          ],
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Panelin sağ üstündeki yer düğmesi: seçilen şehir (yoksa "Konumum"); dokununca yer seçme sayfası açılır.
class _PlaceChip extends StatelessWidget {
  const _PlaceChip({required this.name, required this.onTap});

  final String? name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final i18n = I18n.instance;
    final label = name ?? i18n.t('mobileWeatherPlace.chipDevice', const {}, 'Konumum');
    return Semantics(
      button: true,
      label: i18n.t('mobileWeatherPlace.change', {'place': label}, 'Hava için yer: {{place}}. Değiştirmek için dokun'),
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        scale: .95,
        child: ConstrainedBox(
          // Görünüm küçük, dokunma alanı en az 44 dp.
          constraints: BoxConstraints(minHeight: 44, maxWidth: MediaQuery.sizeOf(context).width * .42),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.mapPin, size: 13, color: Brand.cream.withValues(alpha: .78)),
              const SizedBox(width: 5),
              Flexible(
                child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(11.5, w: 6, c: Brand.cream.withValues(alpha: .78))),
              ),
              const SizedBox(width: 3),
              Icon(LucideIcons.chevronDown, size: 13, color: Brand.cream.withValues(alpha: .6)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Gerçek hava yokken panelin yerine: uydurma "20°, UV 3" göstermez. Yer belli değilse yer seçtirir; yer belliyse
/// (hava servisi/bağlantı yanıt vermiyor) "yeniden dene" der ve yeri değiştirmeyi de sunar.
class _WeatherMissing extends StatelessWidget {
  const _WeatherMissing({required this.placeKnown, this.onPlace, this.onRetry});

  final bool placeKnown;
  final VoidCallback? onPlace;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final i18n = I18n.instance;
    final retry = placeKnown && onRetry != null;
    final action = retry ? onRetry : onPlace;
    Widget pill(String label, IconData icon, VoidCallback onTap) => Semantics(
          button: true,
          excludeSemantics: true,
          label: label,
          child: Pressable(
            onTap: onTap,
            scale: .96,
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(color: Brand.cream, borderRadius: BorderRadius.circular(999)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 17, color: Brand.forest),
                  const SizedBox(width: 8),
                  Flexible(child: Text(label, style: tx(14.5, w: 7, c: Brand.forest))),
                ],
              ),
            ),
          ),
        );
    return Container(
      key: const Key('weather-missing'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: Brand.cream.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Brand.cream.withValues(alpha: .2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(i18n.t('mobileToday.weatherPanel.title'), style: tx(12.5, w: 6, c: Brand.cream.withValues(alpha: .78))),
          const SizedBox(height: 10),
          Semantics(
            header: true,
            child: Text(
              retry
                  ? i18n.t('mobileWeatherPlace.unavailableTitle', const {}, 'Hava şu an alınamadı')
                  : i18n.t('mobileWeatherPlace.missingTitle', const {}, 'Hava için bir yer seç'),
              style: Brand.serif(24, color: Brand.cream, h: 1.12, ls: -.5),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            retry
                ? i18n.t('mobileWeatherPlace.unavailableBody', const {}, 'Bağlantı ya da hava servisi geçici olarak yanıt vermiyor. Biraz sonra kendiliğinden yenilenir.')
                : i18n.t('mobileWeatherPlace.missingBody', const {}, 'Konumunu ya da şehrini seçersen güneş kremi, nemlendirici ve balm önerileri bugünün gerçek havasına göre gelir.'),
            style: tx(13.5, c: Brand.cream.withValues(alpha: .82), h: relaxed),
          ),
          if (action != null) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 14,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (retry)
                  pill(i18n.t('mobileWeatherPlace.retry', const {}, 'Yeniden dene'), LucideIcons.refreshCw, onRetry!)
                else
                  pill(i18n.t('mobileWeatherPlace.pick', const {}, 'Yer seç'), LucideIcons.mapPin, onPlace!),
                if (retry && onPlace != null)
                  Semantics(
                    button: true,
                    excludeSemantics: true,
                    label: i18n.t('mobileWeatherPlace.pick', const {}, 'Yer seç'),
                    child: Pressable(
                      onTap: onPlace,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        child: Center(
                          widthFactor: 1,
                          child: Text(
                            i18n.t('mobileWeatherPlace.pick', const {}, 'Yer seç'),
                            style: tx(13.5, w: 6, c: Brand.cream.withValues(alpha: .86)).copyWith(decoration: TextDecoration.underline, decorationColor: Brand.cream.withValues(alpha: .6)),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
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
