import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n.dart';
import '../../core/reminder_settings.dart';
import '../../state/theme_controller.dart';
import '../../ui/tw.dart';
import '../../ui/widgets/app_sheet.dart';
import '../../ui/widgets/common.dart';
import 'clock_tile.dart';
import 'time_picker.dart';

/// Bir kategorinin hatırlatıcı saat aralıklarını düzenleten alt sayfa. Her geçerli seçim [onChanged] ile hemen
/// bildirilir (ekranın taslağı güncellenir); kayıt ekrandaki "Kaydet" ile yapılır.
Future<void> showWindowSheet(
  BuildContext context, {
  required String category,
  required ReminderSettings settings,
  required ValueChanged<ReminderSettings> onChanged,
  required RebiTheme theme,
}) {
  final i18n = I18n.instance;
  return AppSheet.show<void>(
    context,
    title: i18n.t('mobileReminders.windowSheet.title'),
    subtitle: i18n.t('mobileReminders.categories.$category.title'),
    body: (c) => _WindowBody(category: category, initial: settings, onChanged: onChanged, theme: theme),
  );
}

class _WindowBody extends StatefulWidget {
  const _WindowBody({required this.category, required this.initial, required this.onChanged, required this.theme});

  final String category;
  final ReminderSettings initial;
  final ValueChanged<ReminderSettings> onChanged;
  final RebiTheme theme;

  @override
  State<_WindowBody> createState() => _WindowBodyState();
}

class _WindowBodyState extends State<_WindowBody> {
  late ReminderSettings _s = widget.initial;
  final Map<String, WindowProblem> _problems = {};

  void _apply(ReminderSettings next) {
    setState(() => _s = next);
    widget.onChanged(next);
  }

  Future<void> _pick(String id, {required bool start}) async {
    final w = reminderWindow(id, _s)!;
    final picked = await pickClockMinutes(context, parseClock(start ? w.start : w.end) ?? 0);
    if (picked == null || !mounted) return;
    var range = ClockRange(start ? formatClock(picked) : w.start, start ? w.end : formatClock(picked));
    if (start && range.endMinutes - range.startMinutes < minWindowMinutes) {
      // Başlangıç bitişe yaklaştı: bitiş bir saat ileri alınır (uyku saatini aşmadan).
      range = ClockRange(range.start, formatClock((picked + 60).clamp(0, _s.sleepMinutes)));
    }
    final problem = windowProblem(range, _s);
    if (problem != null) {
      setState(() => _problems[id] = problem);
      return;
    }
    setState(() => _problems.remove(id));
    final fallback = defaultReminderWindow(id, _s)!;
    // Varsayılanla aynı seçim "özel" sayılmaz: gün düzeni değişince pencere onunla birlikte kayar.
    final isDefault = range.start == fallback.start && range.end == fallback.end;
    _apply(_s.withWindow(id, isDefault ? null : range));
  }

  void _reset(String id) {
    setState(() => _problems.remove(id));
    _apply(_s.withWindow(id, null));
  }

  String _problemText(I18n i18n, WindowProblem problem) => switch (problem) {
        WindowProblem.tooShort => i18n.t('mobileReminders.windowSheet.errors.short', {'minutes': '$minWindowMinutes'}),
        WindowProblem.outsideDay => i18n.t('mobileReminders.windowSheet.errors.outsideDay', {
            'wake': _s.wakeTime,
            'sleep': _s.sleepTime,
          }),
      };

  @override
  Widget build(BuildContext context) {
    final i18n = I18n.instance;
    final theme = widget.theme;
    final ids = categoryWindowIds[widget.category] ?? const <String>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(i18n.t('mobileReminders.windowSheet.hint'), style: tx(12, c: Tw.gray500, h: snug)),
        for (final id in ids) ...[
          const SizedBox(height: 18),
          _row(i18n, theme, id),
        ],
        if (widget.category == 'spf' && !_s.hasCustomWindow('spf_refresh')) ...[
          const SizedBox(height: 14),
          Text(i18n.t('mobileReminders.windowSheet.spfNote'), style: tx(11, c: Tw.gray500, h: snug)),
        ],
        const SizedBox(height: 20),
        PrimaryButton(
          color: theme.primary,
          label: i18n.t('mobileReminders.windowSheet.done'),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _row(I18n i18n, RebiTheme theme, String id) {
    final w = reminderWindow(id, _s)!;
    final custom = _s.hasCustomWindow(id);
    final problem = _problems[id];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Expanded(child: Text(i18n.t('mobileReminders.windowSheet.ids.$id'), style: tx(14, w: 7, c: Tw.gray800))),
          if (custom)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: theme.primary.withValues(alpha: .12), borderRadius: BorderRadius.circular(999)),
              child: Text(i18n.t('mobileReminders.windowSheet.custom'), style: tx(10, w: 7, c: theme.primaryDark)),
            ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: ClockTile(
              label: i18n.t('mobileReminders.windowSheet.start'),
              value: w.start,
              theme: theme,
              onTap: () => _pick(id, start: true),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Icon(LucideIcons.arrowRight, size: 16, color: Tw.gray400),
          ),
          Expanded(
            child: ClockTile(
              label: i18n.t('mobileReminders.windowSheet.end'),
              value: w.end,
              theme: theme,
              onTap: () => _pick(id, start: false),
            ),
          ),
        ]),
        if (problem != null) ...[
          const SizedBox(height: 6),
          Text(_problemText(i18n, problem), style: tx(12, c: Tw.red600, h: snug)),
        ],
        if (custom) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextLink(
              i18n.t('mobileReminders.windowSheet.reset'),
              onTap: () => _reset(id),
              style: tx(12, w: 6, c: theme.fg),
            ),
          ),
        ],
      ],
    );
  }
}
