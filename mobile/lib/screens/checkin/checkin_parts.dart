import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../state/theme_controller.dart';
import '../../ui/tw.dart';
import '../../ui/widgets/common.dart';

/// Check-in kartlarının başlığı: renkli çizgi simge + kalın başlık.
class CheckinCardTitle extends StatelessWidget {
  const CheckinCardTitle({super.key, required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: tx(14.5, w: 7, c: Tw.gray800, h: snug))),
      ],
    );
  }
}

/// Seçilebilir kutu (stres düzeyi, cilt hissi): seçiliyken tema çerçevesi ve soluk dolgu, ölçeklenme yok.
class CheckinSelectable extends StatelessWidget {
  const CheckinSelectable({super.key, required this.selected, required this.theme, required this.onTap, required this.child, this.padding});

  final bool selected;
  final RebiTheme theme;
  final VoidCallback onTap;
  final Widget child;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? theme.primaryLight.withValues(alpha: Tw.dark ? .35 : .55) : Tw.gray50,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: selected ? theme.primary : Colors.transparent, width: 1.6),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Büyük Evet / Hayır düğmesi (rutin uygulandı mı): seçiliyken tema dolgusu ve beyaz yazı.
class CheckinYesNo extends StatelessWidget {
  const CheckinYesNo({super.key, required this.label, required this.selected, required this.theme, required this.onTap});

  final String label;
  final bool selected;
  final RebiTheme theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? Tw.fillWithWhiteText(theme.primary) : Tw.gray50,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(label, textAlign: TextAlign.center, style: tx(16, w: selected ? 6 : 5, c: selected ? Colors.white : Tw.gray700)),
          ),
        ),
      ),
    );
  }
}

/// Evet / Hayır / Atla düğmesi (ek sorular, makyaj); [plain] "Atla" gibi ikincil seçenekler içindir.
class CheckinTri extends StatelessWidget {
  const CheckinTri({super.key, required this.label, required this.selected, required this.theme, required this.onTap, this.plain = false});

  final String label;
  final bool selected;
  final RebiTheme theme;
  final VoidCallback onTap;
  final bool plain;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? theme.primaryLight.withValues(alpha: Tw.dark ? .35 : .55) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: selected ? theme.primary : Tw.gray200, width: selected ? 1.6 : 1.3),
            ),
            child: Text(label, textAlign: TextAlign.center, style: tx(13.5, w: selected ? 6 : 5, c: plain ? Tw.gray600 : Tw.gray900)),
          ),
        ),
      ),
    );
  }
}

/// Evet / Hayır / Atla — check-in ek soruları. Soru ve açıklama `mobileCheckin.extras.<anahtar>` içindedir;
/// [value] null ise cevap verilmemiştir ("Atla" cevabı da null'a döner).
class CheckinExtraQuestion extends StatelessWidget {
  const CheckinExtraQuestion({super.key, required this.questionKey, required this.value, required this.theme, required this.onChanged});

  final String questionKey;
  final bool? value;
  final RebiTheme theme;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    final i18n = I18n.instance;
    final description = i18n.t('mobileCheckin.extras.$questionKey.d', const {}, '');
    return RCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(i18n.t('mobileCheckin.extras.$questionKey.q'), style: tx(14.5, w: 7, c: Tw.gray800, h: snug)),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(description, style: tx(12.5, c: Tw.gray600, h: relaxed)),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: CheckinTri(label: i18n.t('common.yes'), selected: value == true, theme: theme, onTap: () => onChanged(true))),
              const SizedBox(width: 8),
              Expanded(child: CheckinTri(label: i18n.t('common.no'), selected: value == false, theme: theme, onTap: () => onChanged(false))),
              const SizedBox(width: 8),
              Expanded(child: CheckinTri(label: i18n.t('common.skip'), selected: false, theme: theme, plain: true, onTap: () => onChanged(null))),
            ],
          ),
        ],
      ),
    );
  }
}
