import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/i18n.dart';
import '../../state/notifications_controller.dart';
import '../../state/theme_controller.dart';
import '../../ui/tw.dart';
import '../../ui/widgets/common.dart';

/// "Bildirimler gelmiyor mu?" kartı: yalnızca bildirimler bu telefonda planlanıyorsa görünür. Test
/// bildirimi 1 dakika sonra gelir (uygulamayı kapatıp beklemek, gerçek hatırlatıcıların yolunu dener);
/// Android'de pil tasarrufunun uygulamayı durdurabileceği anlatılır.
class DeliveryCard extends StatefulWidget {
  const DeliveryCard({super.key, required this.theme});

  final RebiTheme theme;

  @override
  State<DeliveryCard> createState() => _DeliveryCardState();
}

class _DeliveryCardState extends State<DeliveryCard> {
  bool _busy = false;
  TestNotificationResult? _result;

  Future<void> _test(NotificationsController c) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _result = null;
    });
    final result = await c.sendTestNotification();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<NotificationsController>();
    // Sunucu gönderiyorsa telefonun alarm/pil ayarı önemsizdir; kapalıysa gösterecek bir şey yok.
    if (!c.supported || !c.enabled || c.pushActive || c.permissionBlocked) return const SizedBox.shrink();
    final i18n = I18n.instance;
    final theme = widget.theme;
    final android = defaultTargetPlatform == TargetPlatform.android;
    final status = switch (_result) {
      TestNotificationResult.scheduled => (true, i18n.t('mobileNotifications.delivery.testScheduled')),
      TestNotificationResult.blocked => (false, i18n.t('mobileNotifications.delivery.testBlocked')),
      TestNotificationResult.unavailable => (false, i18n.t('mobileNotifications.delivery.testFailed')),
      null => null,
    };
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: RCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(LucideIcons.bellRing, size: 16, color: theme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(i18n.t('mobileNotifications.delivery.title'), style: tx(14, w: 7, c: Tw.gray800)),
                      const SizedBox(height: 2),
                      Text(i18n.t('mobileNotifications.delivery.body'), style: tx(12, c: Tw.gray500, h: snug)),
                    ],
                  ),
                ),
              ],
            ),
            if (android) ...[
              const SizedBox(height: 10),
              Text(i18n.t('mobileNotifications.delivery.batteryTitle'), style: tx(12, w: 7, c: Tw.gray700)),
              const SizedBox(height: 2),
              Text(i18n.t('mobileNotifications.delivery.batteryBody'), style: tx(12, c: Tw.gray500, h: snug)),
            ],
            const SizedBox(height: 12),
            SecondaryButton(
              onPressed: _busy ? null : () => _test(c),
              loading: _busy,
              minHeight: 44,
              fontSize: 14,
              icon: LucideIcons.send,
              label: i18n.t('mobileNotifications.delivery.test'),
            ),
            if (status != null) ...[
              const SizedBox(height: 8),
              StatusLine(ok: status.$1, text: status.$2),
            ],
          ],
        ),
      ),
    );
  }
}
