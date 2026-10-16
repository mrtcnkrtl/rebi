import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../core/reminder_settings.dart';
import '../../state/theme_controller.dart';
import '../../ui/tw.dart';
import '../../ui/widgets/common.dart';
import 'clock_tile.dart';
import 'time_picker.dart';

/// Sessiz saatler kartı: açıkken seçilen aralıkta hiçbir hatırlatıcı bildirimi gelmez.
class QuietHoursCard extends StatefulWidget {
  const QuietHoursCard({super.key, required this.settings, required this.onChanged, required this.theme});

  final ReminderSettings settings;
  final ValueChanged<ReminderSettings> onChanged;
  final RebiTheme theme;

  @override
  State<QuietHoursCard> createState() => _QuietHoursCardState();
}

class _QuietHoursCardState extends State<QuietHoursCard> {
  bool _sameTimes = false;

  /// Açılınca önerilen aralık (öğle arası).
  static const _suggested = ClockRange('12:00', '13:00');

  Future<void> _pick({required bool start}) async {
    final quiet = widget.settings.quiet ?? _suggested;
    final picked = await pickClockMinutes(context, start ? quiet.startMinutes : quiet.endMinutes);
    if (picked == null || !mounted) return;
    final next = start ? ClockRange(formatClock(picked), quiet.end) : ClockRange(quiet.start, formatClock(picked));
    if (next.start == next.end) {
      setState(() => _sameTimes = true);
      return;
    }
    setState(() => _sameTimes = false);
    widget.onChanged(widget.settings.withQuiet(next));
  }

  @override
  Widget build(BuildContext context) {
    final i18n = I18n.instance;
    final theme = widget.theme;
    final quiet = widget.settings.quiet;
    return RCard(
      padding: const EdgeInsets.all(16),
      radius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(i18n.t('mobileReminders.quiet.title'), style: tx(14, w: 7, c: Tw.gray800)),
                    const SizedBox(height: 2),
                    Text(i18n.t('mobileReminders.quiet.hint'), style: tx(12, c: Tw.gray500, h: snug)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Switch(
                value: quiet != null,
                onChanged: (on) {
                  setState(() => _sameTimes = false);
                  widget.onChanged(widget.settings.withQuiet(on ? _suggested : null));
                },
                activeThumbColor: Colors.white,
                activeTrackColor: theme.primary,
              ),
            ],
          ),
          if (quiet != null) ...[
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: ClockTile(
                  label: i18n.t('mobileReminders.quiet.from'),
                  value: quiet.start,
                  theme: theme,
                  onTap: () => _pick(start: true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ClockTile(
                  label: i18n.t('mobileReminders.quiet.to'),
                  value: quiet.end,
                  theme: theme,
                  onTap: () => _pick(start: false),
                ),
              ),
            ]),
            if (_sameTimes) ...[
              const SizedBox(height: 8),
              Text(i18n.t('mobileReminders.quiet.errors.same'), style: tx(12, c: Tw.red600, h: snug)),
            ],
          ],
        ],
      ),
    );
  }
}
