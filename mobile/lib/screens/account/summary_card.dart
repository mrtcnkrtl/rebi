import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n.dart';
import '../../state/theme_controller.dart';
import '../../ui/tw.dart';
import '../../ui/widgets/common.dart';
import 'account_parts.dart';

/// Üyelik tarihi, uygulama dilinde ("30 Ekim 2026" / "October 30, 2026"); okunamazsa "—".
String formatJoined(String? iso, String lang) {
  if (iso == null || iso.isEmpty) return '—';
  try {
    return DateFormat.yMMMMd(lang).format(DateTime.parse(iso).toLocal());
  } catch (_) {
    return '—';
  }
}

/// Hesap özeti: e-posta, üyelik tarihi ve (varsa) Plus durumu. Sahneye binen ilk karttır.
class AccountSummaryCard extends StatelessWidget {
  const AccountSummaryCard({super.key, required this.theme, required this.email, required this.createdAt, required this.plus});

  final RebiTheme theme;
  final String? email;
  final String? createdAt;
  final bool plus;

  @override
  Widget build(BuildContext context) {
    final i18n = I18n.instance;
    return RCard(
      padding: const EdgeInsets.all(18),
      radius: 24,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccountSectionTitle(icon: LucideIcons.shield, color: theme.fg, text: i18n.t('profile.accountSummary')),
          const SizedBox(height: 14),
          _line(LucideIcons.mail, email == null || email!.isEmpty ? '—' : email!),
          const SizedBox(height: 10),
          _line(LucideIcons.calendar, i18n.t('profile.membership', {'date': formatJoined(createdAt, i18n.lang)})),
          if (plus) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Tw.amber50,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Tw.amber200),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.crown, size: 14, color: Tw.amber700),
                    const SizedBox(width: 6),
                    Text(i18n.t('profile.plusActive'), style: tx(12.5, w: 6, c: Tw.amber800)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _line(IconData icon, String text) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, size: 16, color: Tw.gray500)),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: tx(14.5, c: Tw.gray700, h: snug))),
        ],
      );
}
