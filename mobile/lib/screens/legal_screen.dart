import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/i18n.dart';
import '../core/legal_texts.dart';
import '../ui/tw.dart';
import '../ui/widgets/common.dart';
import '../ui/brand/palette.dart';

/// `/kvkk` ve `/riza` (web: `pages/Legal.jsx`). Form üstüne açıldığı için geri dönüş formu korur.
class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key, required this.kind});

  final String kind;

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final sections = legalSections(kind, i18n.lang);
    final title = kind == 'riza' ? i18n.t('legal.rizaTitle') : i18n.t('legal.kvkkTitle');

    void back() {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/auth');
      }
    }

    void open(String other) {
      if (other == kind) return;
      context.pushReplacement('/$other');
    }

    final linkStyle = tx(12, c: Tw.gray400).copyWith(decoration: TextDecoration.underline, decorationColor: Tw.gray400);

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Tw.teal50, Tw.surface]),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
            child: CenteredBox(
              maxWidth: 672,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: InkWell(
                      onTap: back,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.arrowLeft, size: 16, color: Tw.teal700),
                            const SizedBox(width: 6),
                            Text(i18n.t('legal.backToAuth'), style: tx(14, w: 5, c: Tw.teal700)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(color: Tw.teal600, borderRadius: BorderRadius.circular(16)),
                        child: const Icon(LucideIcons.shield, size: 20, color: Colors.white),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: heading(28)),
                            const SizedBox(height: 4),
                            Text(i18n.t('legal.updated', {'date': legalUpdated}), style: tx(12, c: Tw.gray500)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  RCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < sections.length; i++) ...[
                          if (i > 0) const SizedBox(height: 24),
                          Text(sections[i].title, style: tx(14, w: 7)),
                          const SizedBox(height: 6),
                          Text(sections[i].body, style: tx(14, c: Tw.gray700, h: relaxed)),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  Wrap(
                    alignment: WrapAlignment.center,
                    children: [
                      GestureDetector(onTap: () => open('kvkk'), child: Text(i18n.t('legal.kvkkTitle'), style: linkStyle)),
                      Text(' · ', style: tx(12, c: Tw.gray400)),
                      GestureDetector(onTap: () => open('riza'), child: Text(i18n.t('legal.rizaTitle'), style: linkStyle)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
