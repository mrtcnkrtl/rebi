import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n.dart';
import '../tw.dart';
import '../widgets/common.dart';

/// KVKK + açık rıza (zorunlu) ve konum/fotoğraf (isteğe bağlı) onay kutuları.
/// Metin bağlantıları formu kaybetmemek için sayfanın üstüne açılır (web: yeni sekme).
class LegalConsentFields extends StatefulWidget {
  const LegalConsentFields({
    super.key,
    required this.kvkk,
    required this.riza,
    required this.location,
    required this.photo,
    required this.onKvkk,
    required this.onRiza,
    required this.onLocation,
    required this.onPhoto,
  });

  final bool kvkk;
  final bool riza;
  final bool location;
  final bool photo;
  final ValueChanged<bool> onKvkk;
  final ValueChanged<bool> onRiza;
  final ValueChanged<bool> onLocation;
  final ValueChanged<bool> onPhoto;

  @override
  State<LegalConsentFields> createState() => _LegalConsentFieldsState();
}

class _LegalConsentFieldsState extends State<LegalConsentFields> {
  late final TapGestureRecognizer _kvkkTap = TapGestureRecognizer()..onTap = () => context.push('/kvkk');
  late final TapGestureRecognizer _rizaTap = TapGestureRecognizer()..onTap = () => context.push('/riza');

  @override
  void dispose() {
    _kvkkTap.dispose();
    _rizaTap.dispose();
    super.dispose();
  }

  Widget _row({required bool value, required ValueChanged<bool> onChanged, required Widget label}) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: Checkbox(
              value: value,
              onChanged: (v) => onChanged(v ?? false),
              activeColor: Tw.teal600,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              side: const BorderSide(color: Tw.gray300, width: 1.5),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Padding(padding: const EdgeInsets.only(top: 2), child: label)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final base = tx(14, c: Tw.gray700, h: relaxed);
    final link = tx(14, w: 6, c: Tw.teal700, h: relaxed).copyWith(decoration: TextDecoration.underline);
    final kvkkBefore = i18n.t('auth.kvkkBefore').trim();
    final rizaBefore = i18n.t('auth.rizaBefore').trim();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Tw.teal50.withValues(alpha: .4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Tw.teal100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _row(
            value: widget.kvkk,
            onChanged: widget.onKvkk,
            label: Text.rich(TextSpan(style: base, children: [
              if (kvkkBefore.isNotEmpty) TextSpan(text: '$kvkkBefore '),
              TextSpan(text: i18n.t('auth.kvkkLink'), style: link, recognizer: _kvkkTap),
              TextSpan(text: i18n.t('auth.kvkkAfter')),
            ])),
          ),
          const SizedBox(height: 12),
          _row(
            value: widget.riza,
            onChanged: widget.onRiza,
            label: Text.rich(TextSpan(style: base, children: [
              if (rizaBefore.isNotEmpty) TextSpan(text: '$rizaBefore '),
              TextSpan(text: i18n.t('auth.rizaLink'), style: link, recognizer: _rizaTap),
              TextSpan(text: i18n.t('auth.rizaAfter')),
            ])),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.only(top: 8),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: Tw.teal100))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(i18n.t('auth.optionalPermissions'), style: tx(12, w: 6, c: Tw.gray600)),
                const SizedBox(height: 8),
                _row(
                  value: widget.location,
                  onChanged: widget.onLocation,
                  label: Text(i18n.t('auth.locationConsent'), style: base),
                ),
                const SizedBox(height: 8),
                _row(
                  value: widget.photo,
                  onChanged: widget.onPhoto,
                  label: Text(i18n.t('auth.photoConsent'), style: base),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const AiDisclaimer(),
        ],
      ),
    );
  }
}
