import 'package:flutter/material.dart';

import '../../state/theme_controller.dart';
import '../../ui/tw.dart';

/// Dokununca saat seçtiren küçük kutu: üstte ne olduğu, altında saat.
class ClockTile extends StatelessWidget {
  const ClockTile({super.key, required this.label, required this.value, required this.onTap, required this.theme});

  final String label;
  final String value;
  final VoidCallback onTap;
  final RebiTheme theme;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$label $value',
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: theme.primary.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(11, w: 6, c: Tw.gray600)),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value, style: tx(20, w: 8, c: theme.primaryDark)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
