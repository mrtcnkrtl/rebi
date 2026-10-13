import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n.dart';
import '../../core/routine_logic.dart';
import '../../core/today_plan.dart';
import '../../state/theme_controller.dart';
import '../../ui/tw.dart';
import '../../ui/widgets/common.dart';

/// Havaya göre bugün kullanılacak ürün önerileri (SPF, nemlendirici, dudak balsamı).
class EnvironmentAdviceCard extends StatelessWidget {
  const EnvironmentAdviceCard({super.key, required this.plan, required this.theme});

  final TodayPlan plan;
  final RebiTheme theme;

  @override
  Widget build(BuildContext context) {
    final i18n = I18n.instance;
    final w = plan.weather;
    String v(String key) => str(w[key]);
    final sourceKey = ['live', 'tracking', 'profile'].contains(plan.weatherSource) ? plan.weatherSource : 'default';

    return RCard(
      padding: const EdgeInsets.all(14),
      radius: 20,
      borderColor: Tw.blue100,
      gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Tw.blue50, Tw.cyan50]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Icon(LucideIcons.cloudSun, size: 18, color: Tw.blue500),
            const SizedBox(width: 8),
            Expanded(child: Text(i18n.t('mobileToday.advice.title'), style: tx(13, w: 7, c: Tw.gray800))),
          ]),
          const SizedBox(height: 4),
          Text(
            i18n.t('mobileToday.advice.weatherLine', {'temp': v('temperature'), 'uv': v('uv_index'), 'humidity': v('humidity')}),
            style: tx(13, w: 6, c: Tw.gray700),
          ),
          Text(i18n.t('mobileToday.advice.source.$sourceKey'), style: tx(10, c: Tw.gray500)),
          if (plan.environmentAdvice.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final item in plan.environmentAdvice)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: .75), borderRadius: BorderRadius.circular(14)),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      emojiText(truthy(item['icon']) ? str(item['icon']) : '🧴', 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(str(item['action']), style: tx(12, w: 7, c: Tw.gray800)),
                            if (truthy(item['detail'])) ...[
                              const SizedBox(height: 2),
                              Text(str(item['detail']), style: tx(11, c: Tw.gray600, h: relaxed)),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
          if (!plan.hasRealWeather)
            Text(i18n.t('mobileToday.advice.locationHint'), style: tx(10, c: Tw.gray500, h: relaxed)),
        ],
      ),
    );
  }
}
