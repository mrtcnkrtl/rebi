import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n.dart';
import '../brand/palette.dart';
import '../tw.dart';
import '../widgets/common.dart';

/// KVKK + açık rıza (zorunlu) ve konum/fotoğraf (isteğe bağlı) onay kutuları.
/// Metin bağlantıları formu kaybetmemek için sayfanın üstüne açılır (web: yeni sekme).
///
/// Sakin görünüm: iki zorunlu onay açıkta durur; isteğe bağlı izinler tek satıra katlanır (varsayılan kapalı ve hiçbiri
/// önceden işaretli değildir; kullanıcı açıp işaretler, kaç tanesinin açık olduğu satırda görünür).
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
  bool _optionalOpen = false;

  @override
  void dispose() {
    _kvkkTap.dispose();
    _rizaTap.dispose();
    super.dispose();
  }

  Widget _row({required bool value, required ValueChanged<bool> onChanged, required Widget label}) {
    return MergeSemantics(
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: Checkbox(
                  value: value,
                  onChanged: (v) => onChanged(v ?? false),
                  activeColor: Brand.forest,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  side: BorderSide(color: Brand.ink.withValues(alpha: .35), width: 1.5),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Padding(padding: const EdgeInsets.only(top: 2), child: label)),
            ],
          ),
        ),
      ),
    );
  }

  /// "İsteğe bağlı izinler" satırı: dokununca açılıp kapanır, açık izin sayısı küçük bir etiketle görünür.
  Widget _optionalHeader(String label) {
    final count = (widget.location ? 1 : 0) + (widget.photo ? 1 : 0);
    return Semantics(
      button: true,
      expanded: _optionalOpen,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: () => setState(() => _optionalOpen = !_optionalOpen),
        borderRadius: BorderRadius.circular(10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: tx(13, w: 6, c: Brand.ink))),
                    if (count > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(color: Brand.inkFaint, borderRadius: BorderRadius.circular(999)),
                        child: Text('$count/2', style: tx(11, w: 7, c: Brand.inkSoft)),
                      ),
                    ],
                  ],
                ),
              ),
              AnimatedRotation(
                turns: _optionalOpen ? .5 : 0,
                duration: const Duration(milliseconds: 220),
                child: Icon(LucideIcons.chevronDown, size: 18, color: Brand.inkSoft),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final base = tx(13, c: Brand.inkSoft, h: 1.5);
    final link = tx(13, w: 7, c: Brand.ink, h: 1.5).copyWith(decoration: TextDecoration.underline, decorationColor: Brand.teal);
    final kvkkBefore = i18n.t('auth.kvkkBefore').trim();
    final rizaBefore = i18n.t('auth.rizaBefore').trim();

    return Column(
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
        const SizedBox(height: 4),
        _row(
          value: widget.riza,
          onChanged: widget.onRiza,
          label: Text.rich(TextSpan(style: base, children: [
            if (rizaBefore.isNotEmpty) TextSpan(text: '$rizaBefore '),
            TextSpan(text: i18n.t('auth.rizaLink'), style: link, recognizer: _rizaTap),
            TextSpan(text: i18n.t('auth.rizaAfter')),
          ])),
        ),
        Container(
          margin: const EdgeInsets.only(top: 6),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: Brand.inkFaint))),
          child: _optionalHeader(i18n.t('auth.optionalPermissions')),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _optionalOpen
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _row(value: widget.location, onChanged: widget.onLocation, label: Text(i18n.t('auth.locationConsent'), style: base)),
                    const SizedBox(height: 4),
                    _row(value: widget.photo, onChanged: widget.onPhoto, label: Text(i18n.t('auth.photoConsent'), style: base)),
                  ],
                )
              : const SizedBox(width: double.infinity),
        ),
        const SizedBox(height: 8),
        const AiDisclaimer(),
      ],
    );
  }
}
