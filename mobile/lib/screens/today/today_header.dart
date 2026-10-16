import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n.dart';
import '../../core/routine_logic.dart';
import '../../core/today_plan.dart';
import '../../ui/brand/palette.dart';
import '../../ui/tw.dart';
import 'today_clock.dart';

/// Günün saatine göre selamlama (`mobileToday.greet.*`), tarih ve tek satırlık hava özeti.
class TodayHeader extends StatelessWidget {
  const TodayHeader({super.key, required this.name, required this.dateLine, this.trailing, this.plan});

  final String name;
  final String dateLine;

  /// Sağ üstteki öğe (hesap kısayolu).
  final Widget? trailing;

  /// Verilirse (ve hava değerleri varsa) tarihin altında "18° · UV 6 · nem %38" özeti görünür.
  final TodayPlan? plan;

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
    final first = name.trim().split(RegExp(r'\s+')).first;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                i18n.t('mobileToday.greet.${greetingKey(todayPanelClock())}', {'name': first}),
                style: heading(32, h: 1.08),
              ),
              const SizedBox(height: 6),
              Text(dateLine, style: tx(14, c: Tw.gray500)),
              if (plan != null && plan!.weather['temperature'] != null) ...[
                const SizedBox(height: 12),
                _WeatherPill(plan: plan!),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 12), trailing!],
      ],
    );
  }
}

/// Tek satırlık hava özeti; hava gerçek bir kaynaktan değilse "tahmini" etiketi taşır.
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
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 14, 6),
      decoration: BoxDecoration(
        color: Tw.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Tw.gray100, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.cloudSun, size: 16, color: Tw.blue500),
          const SizedBox(width: 7),
          Flexible(child: Text(text, style: tx(12.5, w: 6, c: Tw.gray700), maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}
