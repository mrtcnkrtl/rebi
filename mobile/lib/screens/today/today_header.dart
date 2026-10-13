import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../ui/tw.dart';
import 'today_clock.dart';

/// Günün saatine göre selamlama (`mobileToday.greet.*`) ve tarih.
class TodayHeader extends StatelessWidget {
  const TodayHeader({super.key, required this.name, required this.dateLine, this.trailing});

  final String name;
  final String dateLine;

  /// Sağ üstteki öğe (hesap kısayolu).
  final Widget? trailing;

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
                style: tx(26, w: 8, h: tight),
              ),
              const SizedBox(height: 4),
              Text(dateLine, style: tx(14, c: Tw.gray500)),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 12), trailing!],
      ],
    );
  }
}
