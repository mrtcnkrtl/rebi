import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../screens/today/today_widgets.dart';
import '../tw.dart';
import 'common.dart';

/// Gruplanmış liste kartı (iOS "inset grouped" dili): tek yüzey, satırlar arası ince çizgi. Ayrı ayrı kartlar yığmak yerine
/// ilgili eylemleri tek yüzeyde toplar; sayfa daha sakin ve taranabilir olur. Dalga yüzeyin üstünde çizilir, köşelerde kırpılır.
class MenuGroup extends StatelessWidget {
  const MenuGroup({super.key, required this.rows});

  /// Genellikle [MenuRow]lar; araya girecek çizgiyi grup koyar.
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return RCard(
      padding: EdgeInsets.zero,
      radius: 22,
      clip: true,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const Hairline(indent: 70),
              rows[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// [MenuGroup] satırı: simge kutusu + başlık + (isteğe bağlı) tek satırlık açıklama + ok. En az 64 dp yüksekliktedir.
class MenuRow extends StatelessWidget {
  const MenuRow({super.key, required this.icon, required this.color, required this.title, required this.onTap, this.hint, this.trailing});

  final IconData icon;
  final Color color;
  final String title;
  final String? hint;
  final VoidCallback onTap;

  /// Verilmezse sağda ok görünür (ör. bir durum hapı konabilir).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: hint == null || hint!.isEmpty ? title : '$title. $hint',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                TodayIconBadge(icon: icon, color: color),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: tx(15, w: 6, c: Tw.gray900, h: snug)),
                      if (hint != null && hint!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(hint!, style: tx(12.5, c: Tw.gray500, h: snug)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                trailing ?? Icon(LucideIcons.chevronRight, size: 18, color: Tw.gray400),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
