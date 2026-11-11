import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../tw.dart';
import 'brand_caps.dart';
import 'palette.dart';

/// Marka yazısının yanındaki küçük "BETA" etiketi: boş, ince çerçeveli hap; dolgu ya da renk yok (süs değil, bilgi).
/// [onDark] orman yeşili sahnede krem, krem zeminde mürekkep rengi. [fixedScale] true ise yazı sistem yazı ölçeğiyle
/// büyümez (üst çubuktaki marka yazısı gibi sabit kalır); kartlarda false bırakılır, erişilebilirlik için büyür.
class BetaBadge extends StatelessWidget {
  const BetaBadge({super.key, this.onDark = false, this.fixedScale = false});

  final bool onDark;
  final bool fixedScale;

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final color = onDark ? Brand.cream.withValues(alpha: .86) : Brand.ink.withValues(alpha: .82);
    final line = onDark ? Brand.cream.withValues(alpha: .34) : Brand.ink.withValues(alpha: .26);
    return Semantics(
      label: i18n.t('mobileBeta.badgeLabel', const {}, 'Beta'),
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(999), border: Border.all(color: line, width: 1.2)),
        child: Text(
          brandCaps(i18n.t('mobileBeta.badge', const {}, 'Beta'), i18n.lang),
          maxLines: 1,
          softWrap: false,
          textScaler: fixedScale ? TextScaler.noScaling : null,
          style: tx(10.5, w: 7, c: color, ls: brandTracking(i18n.lang, 1.5), h: 1.15),
        ),
      ),
    );
  }
}
