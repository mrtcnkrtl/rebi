import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n.dart';
import '../../state/theme_controller.dart';
import '../../ui/tw.dart';
import '../../ui/brand/palette.dart';
import '../../ui/widgets/common.dart';

/// Sohbet hakkı doldu: sohbetin altında sakin bir bilgi kartı (eskiden ekranı karartan koyu panel).
///
/// [offer] false ise (satın alma yolu yok; v1 mağaza sürümü) yalnızca "limit doldu" bilgisi ve "Tamam" çıkar;
/// Plus tanıtımı, madde listesi ve düğmeleri çıkmaz.
class ChatLimitCard extends StatelessWidget {
  const ChatLimitCard({
    super.key,
    required this.theme,
    required this.month,
    required this.offer,
    required this.onClose,
    required this.onPlus,
  });

  final RebiTheme theme;

  /// true: aylık Plus kotası doldu; false: günlük ücretsiz hak doldu.
  final bool month;
  final bool offer;
  final VoidCallback onClose;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    final i18n = I18n.instance;
    final title = offer
        ? i18n.t(month ? 'chat.paywallTitleMonth' : 'chat.paywallTitleDay')
        : i18n.t(month ? 'mobileChat.limit.titleMonth' : 'mobileChat.limit.titleDay');
    final body = offer
        ? i18n.t(month ? 'chat.paywallBodyMonth' : 'chat.paywallBodyDay')
        : i18n.t(month ? 'mobileChat.limit.bodyMonth' : 'mobileChat.limit.bodyDay');

    Widget bullet(String text) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(top: 7, right: 8),
              child: Container(width: 5, height: 5, decoration: BoxDecoration(color: theme.primary, shape: BoxShape.circle)),
            ),
            Expanded(child: Text(text, style: tx(12, c: Tw.gray600, h: snug))),
          ]),
        );

    return RCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      radius: 20,
      borderColor: theme.primaryLight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: theme.primary.withValues(alpha: .12), borderRadius: BorderRadius.circular(12)),
                child: Icon(offer ? LucideIcons.crown : LucideIcons.messageCircle, size: 18, color: theme.fg),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        offer ? 'REBI PLUS' : i18n.t('mobileChat.limit.label'),
                        style: tx(11, w: 7, c: Tw.gray500, ls: 1.2),
                      ),
                      const SizedBox(height: 2),
                      Text(title, style: heading(20, h: 1.2)),
                      const SizedBox(height: 6),
                      Text(body, style: tx(13, c: Tw.gray600, h: relaxed)),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                onPressed: onClose,
                icon: Icon(LucideIcons.x, size: 18, color: Tw.gray500),
              ),
            ],
          ),
          if (offer) bullet(i18n.t('chat.paywallBulletUnlimited')),
          if (offer) bullet(i18n.t('mobileChat.limit.bulletData')),
          if (offer) bullet(i18n.t('mobileChat.limit.bulletThemes')),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _actions(i18n),
          ),
        ],
      ),
    );
  }

  Widget _actions(I18n i18n) {
    Widget primary(String label, IconData icon, VoidCallback onTap) => PrimaryButton(
          onPressed: onTap,
          color: theme.primary,
          icon: icon,
          label: label,
          minHeight: 46,
          fontSize: 14,
        );
    Widget secondary(String label, VoidCallback onTap, {IconData? icon}) => SecondaryButton(
          onPressed: onTap,
          minHeight: 46,
          fontSize: 14,
          icon: icon,
          borderColor: theme.primaryLight,
          textColor: theme.fg,
          label: label,
        );

    if (offer) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        primary(i18n.t('mobileChat.limit.plusOpen'), LucideIcons.crown, onPlus),
        const SizedBox(height: 8),
        secondary(i18n.t('mobileChat.limit.notNow'), onClose),
      ]);
    }
    return secondary(i18n.t('mobileChat.limit.close'), onClose);
  }
}
