import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n.dart';
import '../../state/location_prompt_controller.dart';
import '../../state/theme_controller.dart';
import '../tw.dart';
import '../widgets/common.dart';
import 'notification_widgets.dart';

/// "Bugün" ekranının üstündeki ilk-açılış önerisi: tek seferde **tek** öneri. Önce konum (ekrandaki hava gerçek
/// olur), konum kararı verilince bildirim önerisi.
class FirstRunPrompts extends StatelessWidget {
  const FirstRunPrompts({super.key, required this.location, required this.theme});

  final LocationPromptController? location;
  final RebiTheme theme;

  @override
  Widget build(BuildContext context) {
    final controller = location;
    if (controller == null) return NotificationPromptCard(theme: theme);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => controller.visible
          ? LocationPromptCard(controller: controller, theme: theme)
          : NotificationPromptCard(theme: theme),
    );
  }
}

/// "Hava durumunu bulunduğun yere göre göster" önerisi.
class LocationPromptCard extends StatelessWidget {
  const LocationPromptCard({super.key, required this.controller, required this.theme});

  final LocationPromptController controller;
  final RebiTheme theme;

  @override
  Widget build(BuildContext context) {
    final i18n = I18n.instance;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: RCard(
        padding: const EdgeInsets.all(14),
        borderColor: theme.primaryLight,
        color: Color.alphaBlend(theme.primary.withValues(alpha: .05), Tw.surface),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(LucideIcons.mapPin, size: 18, color: theme.fg),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(i18n.t('mobileLocation.promptTitle'), style: tx(13.5, w: 7, c: Tw.gray800, h: snug)),
                      const SizedBox(height: 3),
                      Text(i18n.t('mobileLocation.promptBody'), style: tx(12, c: Tw.gray600, h: relaxed)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: PrimaryButton(
                    onPressed: controller.busy ? null : controller.allow,
                    loading: controller.busy,
                    color: theme.primary,
                    minHeight: 48,
                    fontSize: 13,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    label: i18n.t('mobileLocation.promptEnable'),
                  ),
                ),
                const SizedBox(width: 12),
                TextLink(
                  i18n.t('mobileLocation.promptLater'),
                  onTap: controller.dismiss,
                  style: tx(12.5, w: 5, c: Tw.gray500),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
