import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n.dart';
import '../../core/routine_logic.dart';
import '../../core/today_plan.dart';
import '../../core/weather_decisions.dart';
import '../../state/theme_controller.dart';
import '../../state/today_actions.dart';
import '../../ui/brand/glyphs.dart';
import '../../ui/brand/palette.dart';
import '../../ui/tw.dart';
import '../../ui/widgets/common.dart';
import 'today_widgets.dart';

/// "Bugünün havasına göre": güneş kremi, nemlendirici ve dudak balsamı için üç karar. Her satırda karar,
/// tek cümlelik gerekçe ve (güneş kreminde) "yeniledim" düğmesi vardır. Sunucu `weather_decisions` göndermiyorsa
/// (eski sürüm) ayrıntılı `environment_advice` listesi gösterilir.
class WeatherDecisionsCard extends StatelessWidget {
  const WeatherDecisionsCard({super.key, required this.plan, required this.theme, this.actions});

  final TodayPlan plan;
  final RebiTheme theme;

  /// Verilirse güneş kremi satırında "yeniledim" kaydı atılabilir (demo oturumunda null).
  final TodayActions? actions;

  @override
  Widget build(BuildContext context) {
    final i18n = I18n.instance;
    final sourceKey = ['live', 'tracking', 'profile'].contains(plan.weatherSource) ? plan.weatherSource : 'default';
    final d = plan.decisions;

    return RCard(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
      radius: 24,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(padding: const EdgeInsets.only(left: 4, bottom: 12), child: Text(i18n.t('mobileToday.advice.title'), style: heading(22))),
          if (d != null) ...[
            _spf(i18n, d.spf),
            _moisture(i18n, d.moisture),
            _lip(i18n, d.lipBalm, plan.weather),
          ] else ...[
            _fallback(i18n),
          ],
          const SizedBox(height: 6),
          Padding(padding: const EdgeInsets.only(left: 4), child: Text(i18n.t('mobileToday.advice.source.$sourceKey'), style: tx(11, c: Tw.gray500))),
          // Open-Meteo verisi CC BY 4.0 lisanslıdır: gerçek hava gösterilirken kaynak belirtilir (varsayılan değerlerde veri yok).
          if (plan.hasRealWeather) ...[
            const SizedBox(height: 2),
            Padding(padding: const EdgeInsets.only(left: 4), child: Text(i18n.t('mobileToday.advice.attribution'), style: tx(11, c: Tw.gray500))),
          ],
          if (!plan.hasRealWeather) ...[
            const SizedBox(height: 4),
            Padding(padding: const EdgeInsets.only(left: 4), child: Text(i18n.t('mobileToday.advice.locationHint'), style: tx(11, c: Tw.gray500, h: relaxed))),
          ],
        ],
      ),
    );
  }

  Widget _row({
    required IconData icon,
    required Color color,
    required String headline,
    required String reason,
    List<Widget> extra = const [],
    bool muted = false,
  }) {
    // Her karar kendi renginde sakin bir panel: güneş bal, nem su, dudak pudra (renk anlam taşır); gerekmeyen karar nötr.
    final tint = muted ? Tw.gray50 : Color.alphaBlend(color.withValues(alpha: .09), Tw.surface);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(20)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: color.withValues(alpha: .16), shape: BoxShape.circle),
            child: Icon(icon, size: 21, color: Tw.readable(color, bg: Color.alphaBlend(color.withValues(alpha: .16), tint))),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(headline, style: tx(16, w: 7, c: muted ? Tw.gray600 : Tw.gray900, h: 1.25)),
                ),
                if (reason.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(reason, style: tx(13, c: Tw.gray600, h: relaxed)),
                ],
                ...extra,
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _spfAction(I18n i18n, {required bool emphasize}) {
    final a = actions;
    final refreshed = plan.progress.spfRefreshes;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (a != null)
            TodayPill(
              label: i18n.t('mobileToday.spf.done'),
              color: Tw.amber600,
              filled: emphasize,
              onTap: () => a.record('spf_refresh', const {}, message: i18n.t('mobileToday.toast.spf')),
            ),
          if (refreshed > 0)
            Text(i18n.t('mobileToday.spfRefreshed', {'n': refreshed}), style: tx(12, w: 6, c: Tw.emerald700)),
        ],
      ),
    );
  }

  Widget _spf(I18n i18n, SpfDecision spf) {
    final window = spf.window;
    return _row(
      icon: LucideIcons.sunMedium,
      color: Tw.amber600,
      headline: i18n.t('mobileToday.decisions.spf.headline', {'spf': spf.spf}),
      reason: i18n.t('mobileToday.decisions.spf.reason.${spf.level}', {'uv': spf.uv}),
      extra: [
        if (spf.refresh) ...[
          const SizedBox(height: 4),
          Text(
            window != null
                ? i18n.t('mobileToday.decisions.spf.refreshWindow', {'start': window.start, 'end': window.end})
                : i18n.t('mobileToday.decisions.spf.refreshAny'),
            style: tx(12.5, w: 6, c: Tw.amber700, h: relaxed),
          ),
        ],
        _spfAction(i18n, emphasize: spf.refresh && plan.progress.spfRefreshes == 0),
      ],
    );
  }

  Widget _moisture(I18n i18n, MoistureDecision m) => _row(
        icon: LucideIcons.droplet,
        color: Tw.blue500,
        headline: i18n.t('mobileToday.decisions.moisture.headline.${m.kind}'),
        reason: i18n.t('mobileToday.decisions.moisture.reason.${m.kind}', {'humidity': m.humidity, 'temperature': m.temperature}),
        extra: [
          if (m.nightMask) ...[
            const SizedBox(height: 4),
            Text(i18n.t('mobileToday.decisions.moisture.nightMask'), style: tx(12.5, w: 6, c: Tw.blueText, h: relaxed)),
          ],
        ],
      );

  Widget _lip(I18n i18n, LipBalmDecision l, Map<String, dynamic> weather) => _row(
        icon: LucideIcons.heart,
        color: Tw.pink600,
        muted: !l.needed,
        headline: i18n.t(l.needed ? 'mobileToday.decisions.lip.headline.needed' : 'mobileToday.decisions.lip.headline.notNeeded'),
        reason: i18n.t(
          'mobileToday.decisions.lip.reason.${l.needed ? (l.reason ?? 'dry') : 'none'}',
          {'temperature': str(weather['temperature']), 'humidity': str(weather['humidity'])},
        ),
      );

  /// Eski sunucu: ayrıntılı öneri satırları + güneş kremi tazeleme.
  Widget _fallback(I18n i18n) {
    final uv = plan.weather['uv_index'];
    final high = uv is num && uv >= 5;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 2),
          child: Text(
            i18n.t('mobileToday.advice.weatherLine', {
              'temp': str(plan.weather['temperature']),
              'uv': str(plan.weather['uv_index']),
              'humidity': str(plan.weather['humidity']),
            }),
            style: tx(13, w: 6, c: Tw.gray700),
          ),
        ),
        for (final item in plan.environmentAdvice) ...[
          _row(
            icon: glyphForEmoji(str(item['icon']), fallback: LucideIcons.pipette),
            color: theme.primary,
            headline: str(item['action']),
            reason: truthy(item['detail']) ? str(item['detail']) : '',
          ),
        ],
        _row(
          icon: LucideIcons.sunMedium,
          color: Tw.amber600,
          headline: i18n.t('mobileToday.spf.title'),
          reason: i18n.t(high ? 'mobileToday.spf.hintHigh' : 'mobileToday.spf.hint'),
          extra: [_spfAction(i18n, emphasize: high && plan.progress.spfRefreshes == 0)],
        ),
      ],
    );
  }
}
