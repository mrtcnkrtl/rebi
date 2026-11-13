import 'package:flutter/material.dart';

import '../../ui/tw.dart';

/// Hesap kartlarının bölüm başlığı: küçük çizgi simge + kalın başlık.
class AccountSectionTitle extends StatelessWidget {
  const AccountSectionTitle({super.key, required this.icon, required this.color, required this.text, this.textColor});

  final IconData icon;
  final Color color;
  final String text;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Expanded(child: Semantics(header: true, child: Text(text, style: tx(15, w: 7, c: textColor ?? Tw.gray800, h: snug)))),
      ],
    );
  }
}

/// Satırın tamamı dokunulabilir onay kutusu (en az 48 dp); etiket ve kutu tek ekran okuyucu düğümüdür.
class AccountCheckboxRow extends StatelessWidget {
  const AccountCheckboxRow({super.key, required this.value, required this.onChanged, required this.label});

  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: InkWell(
        onTap: () => onChanged(!value),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: Checkbox(
                  value: value,
                  onChanged: (v) => onChanged(v ?? false),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(label, style: tx(14, c: Tw.gray700, h: snug))),
            ],
          ),
        ),
      ),
    );
  }
}
