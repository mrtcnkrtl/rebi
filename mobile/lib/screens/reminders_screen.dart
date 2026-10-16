import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../core/demo_user.dart';
import '../core/device_location.dart';
import '../core/i18n.dart';
import '../core/reminder_settings.dart';
import '../core/today_plan.dart';
import '../state/auth_controller.dart';
import '../state/home_sync_controller.dart';
import '../state/notifications_controller.dart';
import '../state/theme_controller.dart';
import '../ui/components/notification_widgets.dart';
import '../ui/tw.dart';
import '../ui/widgets/common.dart';
import '../ui/brand/palette.dart';
import 'reminders/delivery_card.dart';
import 'reminders/quiet_card.dart';
import 'reminders/time_picker.dart';
import 'reminders/window_sheet.dart';

// Testler saat seçiciyi bu dosyadan değiştirir.
export 'reminders/time_picker.dart' show reminderTimePicker;

const _categoryIcons = {
  'routine': LucideIcons.listChecks,
  'water': LucideIcons.droplet,
  'makeup': LucideIcons.sparkles,
  'nutrition': LucideIcons.apple,
  'spf': LucideIcons.sunMedium,
  'lip_balm': LucideIcons.heart,
  'checkin': LucideIcons.clipboardCheck,
  'restock': LucideIcons.packageCheck,
};

/// Hatırlatıcı ayarları (`GET/PUT /me/reminder-settings`): uyanma ve uyku saati, su aralığı ve
/// hangi hatırlatıcıların geleceği. Pencereler seçilen saatlere göre anında önizlenir.
class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  late final String? _uid = context.read<AuthController>().user?.id;

  ReminderSettings? _saved;
  ReminderSettings _draft = const ReminderSettings();
  bool _loading = true;
  bool _failed = false;
  bool _saving = false;
  bool _showSaved = false;
  String? _error;
  Timer? _savedTimer;

  bool get _real => _uid != null && _uid != demoUserId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _savedTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final uid = _uid;
    if (!_real) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _failed = false;
    });
    ReminderSettings? loaded;
    try {
      loaded = await fetchReminderSettings(uid!);
    } catch (_) {
      loaded = null;
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _failed = loaded == null;
      if (loaded != null) {
        _saved = loaded;
        _draft = loaded;
      }
    });
  }

  bool get _dirty => _saved != null && !_draft.sameAs(_saved!);

  void _edit(ReminderSettings next) => setState(() {
        _draft = next;
        _error = null;
        _showSaved = false;
      });

  Future<void> _pickTime({required bool wake}) async {
    final picked = await pickClockMinutes(context, wake ? _draft.wakeMinutes : _draft.sleepMinutes);
    if (picked == null || !mounted) return;
    final value = formatClock(picked);
    _edit(wake ? _draft.copyWith(wakeTime: value) : _draft.copyWith(sleepTime: value));
  }

  Future<void> _save() async {
    final uid = _uid;
    if (!_real || _saving || !_dirty || !_draft.dayIsValid) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final result = await saveReminderSettings(uid!, _draft);
    if (!mounted) return;
    if (!result.ok) {
      setState(() {
        _saving = false;
        _error = (result.error ?? '').isEmpty ? I18n.instance.t('mobileReminders.saveFailed') : result.error;
      });
      return;
    }
    final next = result.settings!;
    setState(() {
      _saving = false;
      _saved = next;
      _draft = next;
      _showSaved = true;
    });
    _savedTimer?.cancel();
    _savedTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showSaved = false);
    });
    unawaited(_resyncNotifications(uid));
  }

  /// Yeni saatlerle bugünün planını alıp telefondaki yerel bildirimleri yeniden kurar; böylece
  /// değişiklik panel açılmadan da geçerli olur. Hava bağımlı hatırlatıcılar kaybolmasın diye
  /// konum izni varsa canlı hava istenir.
  Future<void> _resyncNotifications(String uid) async {
    try {
      final notifications = context.read<NotificationsController>();
      final locationAllowed = context.read<HomeSyncController>().snapshot?.consent.locationAllowed == true;
      final at = locationAllowed ? await lookupDeviceLocation() : null;
      final plan = await fetchTodayPlan(uid, lat: at?.lat, lon: at?.lon);
      if (plan != null && mounted) notifications.syncReminders(plan);
    } catch (_) {
      /* bildirimler panel açılınca yeniden kurulur */
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final theme = context.watch<ThemeController>().theme;
    final saved = _saved;

    return ThemedPage(
      theme: theme,
      maxWidth: 672,
      children: [
        Text(i18n.t('mobileReminders.title'), style: heading(30)),
        const SizedBox(height: 4),
        Text(i18n.t('mobileReminders.subtitle'), style: tx(14, c: Tw.gray500)),
        const SizedBox(height: 16),
        NotificationSettingsCard(theme: theme),
        DeliveryCard(theme: theme),
        const SizedBox(height: 16),
        if (_loading && saved == null)
          const Padding(padding: EdgeInsets.symmetric(vertical: 48), child: Center(child: RingSpinner()))
        else if (_failed && saved == null)
          _failedCard(i18n, theme)
        else if (!_real)
          NoticeBox(
            text: i18n.t('mobileReminders.notSynced'),
            bg: Tw.amber50,
            border: Tw.amber200,
            fg: Tw.amber900,
            icon: LucideIcons.info,
            fontSize: 12,
          )
        else ...[
          _dayCard(i18n, theme),
          const SizedBox(height: 16),
          _waterCard(i18n, theme),
          const SizedBox(height: 16),
          _categoriesCard(i18n, theme),
          const SizedBox(height: 16),
          QuietHoursCard(settings: _draft, onChanged: _edit, theme: theme),
          const SizedBox(height: 16),
          if (_error != null) ...[
            NoticeBox(
              text: _error!,
              bg: Tw.red50,
              border: Tw.red200,
              fg: Tw.red700,
              icon: LucideIcons.circleAlert,
              fontSize: 12,
            ),
            const SizedBox(height: 12),
          ],
          if (_showSaved) ...[
            StatusLine(ok: true, text: i18n.t('mobileReminders.saved')),
            const SizedBox(height: 12),
          ],
          PrimaryButton(
            color: theme.primary,
            loading: _saving,
            label: i18n.t('mobileReminders.save'),
            onPressed: _dirty && _draft.dayIsValid ? _save : null,
          ),
        ],
      ],
    );
  }

  Widget _failedCard(I18n i18n, RebiTheme theme) => RCard(
        padding: const EdgeInsets.all(12),
        borderColor: Tw.amber200,
        color: Color.alphaBlend(Tw.amber50.withValues(alpha: .6), Tw.surface),
        child: Row(children: [
          Icon(LucideIcons.wifiOff, size: 18, color: Tw.amber600),
          const SizedBox(width: 10),
          Expanded(child: Text(i18n.t('mobileReminders.loadFailed'), style: tx(12, c: Tw.amber900))),
          TextLink(i18n.t('mobileReminders.retry'), onTap: _load, style: tx(12, w: 6, c: theme.primary)),
        ]),
      );

  Widget _sectionTitle(String text, {String? hint}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: tx(14, w: 7, c: Tw.gray800)),
          if (hint != null) ...[
            const SizedBox(height: 2),
            Text(hint, style: tx(12, c: Tw.gray500, h: snug)),
          ],
        ],
      );

  Widget _dayCard(I18n i18n, RebiTheme theme) {
    return RCard(
      padding: const EdgeInsets.all(16),
      radius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle(i18n.t('mobileReminders.day.title'), hint: i18n.t('mobileReminders.day.hint')),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _timeTile(i18n, theme, wake: true)),
            const SizedBox(width: 12),
            Expanded(child: _timeTile(i18n, theme, wake: false)),
          ]),
          if (!_draft.dayIsValid) ...[
            const SizedBox(height: 10),
            Text(i18n.t('mobileReminders.errors.span'), style: tx(12, c: Tw.red600, h: snug)),
          ],
        ],
      ),
    );
  }

  Widget _timeTile(I18n i18n, RebiTheme theme, {required bool wake}) {
    final value = wake ? _draft.wakeTime : _draft.sleepTime;
    final label = i18n.t('mobileReminders.day.${wake ? 'wake' : 'sleep'}');
    return Semantics(
      button: true,
      label: '$label $value',
      child: Material(
        color: theme.primary.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _pickTime(wake: wake),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(wake ? LucideIcons.sunrise : LucideIcons.moon, size: 17, color: Tw.gray600),
                  const SizedBox(width: 6),
                  Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(12, w: 6, c: Tw.gray600))),
                ]),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value, style: tx(26, w: 8, c: theme.primaryDark)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _waterCard(I18n i18n, RebiTheme theme) {
    return RCard(
      padding: const EdgeInsets.all(16),
      radius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle(i18n.t('mobileReminders.water.title'), hint: i18n.t('mobileReminders.water.hint')),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final minutes in waterIntervalChoices)
              ChoiceChipBox(
                label: i18n.t('mobileReminders.water.every.$minutes'),
                selected: _draft.waterEveryMinutes == minutes,
                radius: 12,
                fontSize: 13,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                activeBorder: Tw.blue500,
                activeBg: Tw.blue50,
                activeText: Tw.blue500,
                onTap: () => _edit(_draft.copyWith(waterEveryMinutes: minutes)),
              ),
          ]),
          const SizedBox(height: 18),
          _sectionTitle(i18n.t('mobileReminders.waterTarget.title'), hint: i18n.t('mobileReminders.waterTarget.hint')),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final ml in waterTargetChoices)
              ChoiceChipBox(
                label: i18n.t('mobileReminders.waterTarget.choice', {'liters': _liters(i18n, ml)}),
                selected: _draft.waterTargetMl == ml,
                radius: 12,
                fontSize: 13,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                activeBorder: Tw.blue500,
                activeBg: Tw.blue50,
                activeText: Tw.blueText,
                onTap: () => _edit(_draft.copyWith(waterTargetMl: ml)),
              ),
          ]),
        ],
      ),
    );
  }

  /// 1500 → "1,5" (Türkçe) / "1.5" (İngilizce).
  String _liters(I18n i18n, int ml) {
    final value = ml / 1000;
    final text = value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toString();
    return i18n.lang == 'tr' ? text.replaceAll('.', ',') : text;
  }

  Widget _categoriesCard(I18n i18n, RebiTheme theme) {
    return RCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      radius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle(i18n.t('mobileReminders.categories.title')),
          const SizedBox(height: 4),
          for (final category in reminderCategories) _categoryRow(i18n, theme, category),
        ],
      ),
    );
  }

  /// Kategorinin seçilen gün düzenine göre pencereleri (ör. "07:30 – 09:30 · 21:00 – 23:00").
  String _windows(I18n i18n, String category) {
    String range(String id, {int? every}) {
      final w = reminderWindow(id, _draft);
      if (w == null) return '';
      if (every != null) {
        return i18n.t('mobileReminders.windowEvery', {
          'start': w.start,
          'end': w.end,
          'every': i18n.t('mobileReminders.water.every.$every'),
        });
      }
      return i18n.t('mobileReminders.window', {'start': w.start, 'end': w.end});
    }

    return switch (category) {
      'routine' => '${range('routine_morning')} · ${range('routine_evening')}',
      'water' => range('water_intake', every: _draft.waterEveryMinutes),
      'makeup' => '${range('makeup_log')} · ${range('makeup_removal')}',
      'nutrition' => range('nutrition_log'),
      'spf' => range('spf_refresh'),
      'lip_balm' => range('lip_balm'),
      'restock' => range('restock_check'),
      _ => range('daily_checkin'),
    };
  }

  /// Kategoride kullanıcının kendi ayarladığı bir pencere var mı.
  bool _hasCustomWindow(String category) =>
      (categoryWindowIds[category] ?? const <String>[]).any(_draft.hasCustomWindow);

  void _editWindows(RebiTheme theme, String category) => showWindowSheet(
        context,
        category: category,
        settings: _draft,
        onChanged: _edit,
        theme: theme,
      );

  Widget _categoryRow(I18n i18n, RebiTheme theme, String category) {
    final on = _draft.isEnabled(category);
    final title = i18n.t('mobileReminders.categories.$category.title');
    final windows = _windows(i18n, category);
    final custom = _hasCustomWindow(category);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Semantics(
              button: true,
              label: '$title. $windows. ${i18n.t('mobileReminders.windowSheet.title')}',
              excludeSemantics: true,
              onTap: () => _editWindows(theme, category),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _editWindows(theme, category),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: (on ? theme.primary : Tw.gray400).withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(_categoryIcons[category], size: 18, color: on ? theme.primary : Tw.gray400),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: tx(14, w: 6, c: on ? Tw.gray800 : Tw.gray400)),
                          const SizedBox(height: 2),
                          Text(i18n.t('mobileReminders.categories.$category.desc'), style: tx(12, c: Tw.gray500, h: snug)),
                          const SizedBox(height: 2),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Flexible(
                                child: Text(
                                  custom ? '$windows · ${i18n.t('mobileReminders.windowSheet.custom')}' : windows,
                                  style: tx(11, w: 5, c: on ? theme.primary : Tw.gray400),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(left: 4, top: 1),
                                child: Icon(LucideIcons.pencil, size: 11, color: on ? theme.primary : Tw.gray400),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Switch(
            value: on,
            onChanged: (v) => _edit(_draft.withCategory(category, v)),
            activeThumbColor: Colors.white,
            activeTrackColor: theme.primary,
          ),
        ],
      ),
    );
  }
}
