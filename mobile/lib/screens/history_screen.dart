import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../core/demo_user.dart';
import '../core/i18n.dart';
import '../core/user_history.dart';
import '../state/auth_controller.dart';
import '../state/theme_controller.dart';
import '../ui/tw.dart';
import '../ui/widgets/common.dart';

/// Geçmiş günler (`GET /me/history`): her gün için gün içi kayıtlar ve check-in.
/// Web'de karşılığı yok; mobilde profilden ve panelden açılır.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  static const _ranges = [7, 30, 90];

  int _range = 30;
  UserHistory? _history;
  bool _loading = true;
  bool _failed = false;
  int _version = 0;

  late final String? _uid = context.read<AuthController>().user?.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = _uid;
    if (uid == null || uid == demoUserId) {
      setState(() => _loading = false);
      return;
    }
    final version = ++_version;
    setState(() {
      _loading = true;
      _failed = false;
    });
    UserHistory? history;
    try {
      history = await fetchHistory(uid, days: _range);
    } catch (_) {
      history = null;
    }
    // Aralık değiştirilip yeni istek başladıysa bu yanıt eskidir.
    if (!mounted || version != _version) return;
    setState(() {
      _loading = false;
      _failed = history == null;
      if (history != null) _history = history;
    });
  }

  void _setRange(int days) {
    if (days == _range) return;
    setState(() {
      _range = days;
      _history = null;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final theme = context.watch<ThemeController>().theme;
    final history = _history;

    return ThemedPage(
      theme: theme,
      maxWidth: 672,
      children: [
        Text(i18n.t('mobileHistory.title'), style: tx(24, w: 7)),
        const SizedBox(height: 4),
        Text(i18n.t('mobileHistory.subtitle'), style: tx(14, c: Tw.gray500)),
        const SizedBox(height: 16),
        Row(children: [
          for (final r in _ranges) ...[
            if (r != _ranges.first) const SizedBox(width: 8),
            Expanded(
              child: ChoiceChipBox(
                label: i18n.t('mobileHistory.range$r'),
                selected: _range == r,
                radius: 12,
                center: true,
                fontSize: 13,
                padding: const EdgeInsets.symmetric(vertical: 10),
                activeBorder: theme.primary,
                activeBg: theme.primaryLight.withValues(alpha: .4),
                activeText: theme.primaryDark,
                onTap: () => _setRange(r),
              ),
            ),
          ],
        ]),
        const SizedBox(height: 16),
        if (_loading && history == null)
          const Padding(padding: EdgeInsets.symmetric(vertical: 48), child: Center(child: RingSpinner()))
        else if (_failed && history == null)
          _failedCard(i18n, theme)
        else if (history != null) ...[
          if (!history.synced) ...[
            NoticeBox(
              text: i18n.t('mobileHistory.notSynced'),
              bg: Tw.amber50,
              border: Tw.amber200,
              fg: Tw.amber900,
              icon: LucideIcons.info,
              fontSize: 12,
            ),
            const SizedBox(height: 16),
          ],
          if (history.days.isEmpty)
            _emptyCard(i18n)
          else ...[
            _summaryCard(i18n, theme, summarizeHistory(history.days)),
            const SizedBox(height: 16),
            for (final d in history.days) ...[_dayCard(i18n, theme, d), const SizedBox(height: 12)],
          ],
          if (history.assessments.isNotEmpty) ...[
            const SizedBox(height: 8),
            _assessmentsCard(i18n, theme, history.assessments),
          ],
        ] else
          _emptyCard(i18n),
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
          Expanded(child: Text(i18n.t('mobileHistory.loadFailed'), style: tx(12, c: Tw.amber900))),
          TextLink(i18n.t('mobileHistory.retry'), onTap: _load, style: tx(12, w: 6, c: theme.primary)),
        ]),
      );

  Widget _emptyCard(I18n i18n) => RCard(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          Icon(LucideIcons.calendarDays, size: 28, color: Tw.gray300),
          const SizedBox(height: 8),
          Text(i18n.t('mobileHistory.empty'), textAlign: TextAlign.center, style: tx(13, c: Tw.gray500, h: relaxed)),
        ]),
      );

  Widget _summaryCard(I18n i18n, RebiTheme theme, HistorySummary s) {
    final lines = <String>[
      i18n.t('mobileHistory.summary.recordedDays', {'n': s.recordedDays}),
      if (s.checkins > 0) i18n.t('mobileHistory.summary.checkins', {'n': s.checkins}),
      if (s.fullRoutineDays > 0) i18n.t('mobileHistory.summary.fullRoutine', {'n': s.fullRoutineDays}),
      if (s.avgWaterMl != null) i18n.t('mobileHistory.summary.avgWater', {'ml': s.avgWaterMl}),
      if (s.avgSleepHours != null) i18n.t('mobileHistory.summary.avgSleep', {'h': s.avgSleepHours}),
      if (s.avgRiskScore != null) i18n.t('mobileHistory.summary.avgRisk', {'n': s.avgRiskScore}),
    ];
    return RCard(
      padding: const EdgeInsets.all(12),
      borderColor: theme.primaryLight,
      color: Color.alphaBlend(theme.primary.withValues(alpha: .05), Tw.surface),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Icon(LucideIcons.chartLine, size: 16, color: theme.primary),
            const SizedBox(width: 8),
            Text(i18n.t('mobileHistory.summaryTitle'), style: tx(12, w: 7, c: Tw.gray800)),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 12, runSpacing: 4, children: [for (final l in lines) Text(l, style: tx(12, c: Tw.gray700))]),
        ],
      ),
    );
  }

  Widget _chip(String text, {Color? bg, Color? fg, IconData? icon}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: bg ?? Tw.gray100, borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 12, color: fg ?? Tw.gray700), const SizedBox(width: 4)],
          Flexible(child: Text(text, style: tx(10, w: 5, c: fg ?? Tw.gray700))),
        ]),
      );

  Widget _dayCard(I18n i18n, RebiTheme theme, HistoryDay day) {
    final t = day.tracking;
    final p = t.progress;
    final date = day.date;
    final title = date == null ? day.logDate : DateFormat.yMMMMEEEEd(i18n.lang).format(date);
    final chips = <Widget>[
      if (p.waterMl > 0) _chip(i18n.t('mobileHistory.chips.water', {'ml': p.waterMl}), bg: Tw.blue50, fg: Tw.blue500, icon: LucideIcons.droplet),
      if (p.spfRefreshes > 0) _chip(i18n.t('mobileHistory.chips.spf', {'n': p.spfRefreshes}), bg: Tw.amber50, fg: Tw.amber900, icon: LucideIcons.sun),
      if (p.morningDone) _chip(i18n.t('mobileHistory.chips.morning'), bg: Tw.green100, fg: Tw.green700, icon: LucideIcons.check),
      if (p.eveningDone) _chip(i18n.t('mobileHistory.chips.evening'), bg: Tw.green100, fg: Tw.green700, icon: LucideIcons.check),
      if (p.makeupUsed) _chip(i18n.t('mobileHistory.chips.makeupUsed')),
      if (p.makeupRemoved) _chip(i18n.t('mobileHistory.chips.makeupRemoved')),
      if (t.junkFood) _chip(i18n.t('mobileHistory.chips.junk'), bg: Tw.orange100, fg: Tw.orange700),
      if (t.productsFinished > 0) _chip(i18n.t('mobileHistory.chips.products', {'n': t.productsFinished})),
    ];
    final c = day.checkin;
    final checkinParts = <String>[
      if (c?.skinFeeling != null) i18n.t('mobileHistory.feelings.${c!.skinFeeling}', const {}, c.skinFeeling!),
      if (c?.sleepHours != null) i18n.t('mobileHistory.checkin.sleep', {'h': c!.sleepHours}),
      if (c?.stressLevel != null) i18n.t('mobileHistory.checkin.stress', {'n': c!.stressLevel}),
      if (c?.riskScore != null) i18n.t('mobileHistory.checkin.risk', {'n': c!.riskScore}),
    ];

    return RCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: tx(13, w: 7, c: Tw.gray800)),
          if (chips.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: chips),
          ],
          if (c != null) ...[
            const SizedBox(height: 8),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(LucideIcons.clipboardCheck, size: 14, color: theme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  [i18n.t('mobileHistory.checkin.title'), ...checkinParts].join(' · '),
                  style: tx(12, c: Tw.gray600, h: relaxed),
                ),
              ),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _assessmentsCard(I18n i18n, RebiTheme theme, List<HistoryAssessment> items) {
    final pack = Pack(i18n.analyzeWizardPack.cast<String, dynamic>());
    return RCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Icon(LucideIcons.scan, size: 16, color: theme.primary),
            const SizedBox(width: 8),
            Text(i18n.t('mobileHistory.assessmentsTitle'), style: tx(12, w: 7, c: Tw.gray800)),
          ]),
          const SizedBox(height: 8),
          for (final a in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                Expanded(
                  child: Text(
                    [
                      pack.or('concern.${a.concern}', a.concern),
                      if (a.severityScore != null) i18n.t('mobileHistory.severity', {'n': a.severityScore}),
                    ].join(' · '),
                    style: tx(12, c: Tw.gray700),
                  ),
                ),
                if (a.createdAt != null)
                  Text(DateFormat.yMMMd(i18n.lang).format(a.createdAt!), style: tx(11, c: Tw.gray400)),
              ]),
            ),
        ],
      ),
    );
  }
}
