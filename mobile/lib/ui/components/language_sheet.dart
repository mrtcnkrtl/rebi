import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n.dart';
import '../brand/palette.dart';
import '../tw.dart';

const languageLabels = {'tr': 'Türkçe', 'en': 'English'};

/// Dil seçimi alt sayfası (açılış ve giriş ekranlarındaki dil rozetinden açılır).
Future<void> showLanguageSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: Tw.surfaceRaised,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (_) => const _LanguageSheet(),
  );
}

class _LanguageSheet extends StatelessWidget {
  const _LanguageSheet();

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(i18n.t('lang.label'), style: heading(24)),
            ),
            for (final lng in supportedLangs)
              _Option(
                label: languageLabels[lng] ?? lng,
                selected: i18n.lang == lng,
                onTap: () {
                  I18n.instance.changeLanguage(lng);
                  Navigator.of(context).pop();
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? Tw.teal50 : Tw.gray50,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: selected ? Tw.teal500 : Tw.gray100, width: 1.5),
            ),
            child: Row(
              children: [
                Expanded(child: Text(label, style: tx(16, w: selected ? 7 : 5, c: selected ? Tw.teal700 : Tw.gray800))),
                if (selected) Icon(LucideIcons.check, size: 20, color: Tw.teal600),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
