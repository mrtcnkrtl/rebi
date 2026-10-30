import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/i18n.dart';
import '../core/legal_texts.dart';
import '../state/theme_controller.dart';
import '../ui/shell/page_stage.dart';
import '../ui/tw.dart';
import '../ui/widgets/common.dart';

/// `/kvkk` ve `/riza` (web: `pages/Legal.jsx`). Form üstüne açıldığı için geri dönüş formu korur.
/// Uygulamanın diğer ekranlarıyla aynı üst sahneyle açılır; metin tek kartta okunur.
class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key, required this.kind});

  final String kind;

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final theme = context.watch<ThemeController>().theme;
    final sections = legalSections(kind, i18n.lang);
    final title = kind == 'riza' ? i18n.t('legal.rizaTitle') : i18n.t('legal.kvkkTitle');

    void open(String other) {
      if (other == kind) return;
      context.pushReplacement('/$other');
    }

    return Scaffold(
      backgroundColor: Tw.background,
      body: StagePage(
        theme: theme,
        title: title,
        subtitle: i18n.t('legal.updated', {'date': legalUpdated}),
        backTo: '/auth',
        backLabel: i18n.t('legal.backToAuth'),
        bottomPadding: 24 + MediaQuery.paddingOf(context).bottom,
        children: [
          RCard(
            padding: const EdgeInsets.all(20),
            radius: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < sections.length; i++) ...[
                  if (i > 0) const SizedBox(height: 24),
                  Semantics(header: true, child: Text(sections[i].title, style: tx(15, w: 7, c: Tw.gray900, h: snug))),
                  const SizedBox(height: 6),
                  Text(sections[i].body, style: tx(14.5, c: Tw.gray700, h: relaxed)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Diğer metne geçiş: yalnızca açık olmayanı göster (iki metin birbirine tek dokunuşla bağlıdır).
          Center(
            child: TextLink(
              i18n.t(kind == 'riza' ? 'legal.kvkkTitle' : 'legal.rizaTitle'),
              onTap: () => open(kind == 'riza' ? 'kvkk' : 'riza'),
              style: tx(13.5, w: 6, c: Tw.gray600),
              underline: true,
            ),
          ),
        ],
      ),
    );
  }
}
