import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/i18n.dart';
import '../../state/notifications_controller.dart';
import '../../state/theme_controller.dart';
import '../tw.dart';
import '../widgets/common.dart';

/// Panelde, kullanıcı hiç seçim yapmadıysa çıkan "hatırlatıcıları bildirim olarak al" önerisi.
class NotificationPromptCard extends StatefulWidget {
  const NotificationPromptCard({super.key, required this.theme});

  final RebiTheme theme;

  @override
  State<NotificationPromptCard> createState() => _NotificationPromptCardState();
}

class _NotificationPromptCardState extends State<NotificationPromptCard> {
  bool _busy = false;

  Future<void> _enable(NotificationsController c) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await c.enable();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<NotificationsController>();
    if (!c.promptVisible) return const SizedBox.shrink();
    final i18n = context.i18n;
    final theme = widget.theme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: RCard(
        padding: const EdgeInsets.all(12),
        borderColor: theme.primaryLight,
        color: Color.alphaBlend(theme.primary.withValues(alpha: .05), Colors.white),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(LucideIcons.bell, size: 18, color: theme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(i18n.t('mobileNotifications.promptTitle'), style: tx(13, w: 7, c: Tw.gray800)),
                      const SizedBox(height: 2),
                      Text(i18n.t('mobileNotifications.promptBody'), style: tx(11, c: Tw.gray600, h: relaxed)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: PrimaryButton(
                    onPressed: _busy ? null : () => _enable(c),
                    loading: _busy,
                    color: theme.primary,
                    minHeight: 40,
                    fontSize: 13,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    label: i18n.t('mobileNotifications.promptEnable'),
                  ),
                ),
                const SizedBox(width: 12),
                TextLink(
                  i18n.t('mobileNotifications.promptLater'),
                  onTap: c.dismissPrompt,
                  style: tx(12, w: 5, c: Tw.gray500),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Hatırlatıcı saatleri ekranına giden satır (Profil).
class ReminderSettingsLink extends StatelessWidget {
  const ReminderSettingsLink({super.key, required this.theme});

  final RebiTheme theme;

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    return RCard(
      padding: EdgeInsets.zero,
      onTap: () => context.push('/dashboard/reminders'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(LucideIcons.clock, size: 16, color: theme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(i18n.t('mobileReminders.open'), style: tx(14, w: 7, c: Tw.gray800)),
                  const SizedBox(height: 2),
                  Text(i18n.t('mobileReminders.openHint'), style: tx(12, c: Tw.gray500, h: relaxed)),
                ],
              ),
            ),
            const Icon(LucideIcons.chevronRight, size: 18, color: Tw.gray400),
          ],
        ),
      ),
    );
  }
}

/// Profil ekranındaki bildirim anahtarı.
class NotificationSettingsCard extends StatefulWidget {
  const NotificationSettingsCard({super.key, required this.theme});

  final RebiTheme theme;

  @override
  State<NotificationSettingsCard> createState() => _NotificationSettingsCardState();
}

class _NotificationSettingsCardState extends State<NotificationSettingsCard> {
  bool _busy = false;

  Future<void> _toggle(NotificationsController c, bool value) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (value) {
        await c.enable();
      } else {
        await c.disable();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<NotificationsController>();
    if (!c.supported) return const SizedBox.shrink();
    final i18n = context.i18n;
    final theme = widget.theme;
    final status = c.permissionBlocked
        ? i18n.t('mobileNotifications.blocked')
        : c.enabled
            ? i18n.t(c.pushActive ? 'mobileNotifications.modePush' : 'mobileNotifications.modeLocal')
            : null;
    return RCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.bell, size: 16, color: theme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(i18n.t('mobileNotifications.title'), style: tx(14, w: 7, c: Tw.gray800)),
                const SizedBox(height: 4),
                Text(i18n.t('mobileNotifications.description'), style: tx(12, c: Tw.gray500, h: relaxed)),
                if (status != null) ...[
                  const SizedBox(height: 6),
                  Text(status, style: tx(11, w: 5, c: c.permissionBlocked ? Tw.amber900 : Tw.emerald700)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch(
            value: c.enabled,
            onChanged: _busy ? null : (v) => _toggle(c, v),
            activeThumbColor: Colors.white,
            activeTrackColor: theme.primary,
          ),
        ],
      ),
    );
  }
}
