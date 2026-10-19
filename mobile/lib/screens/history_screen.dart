import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../core/demo_user.dart';
import '../core/history_trends.dart';
import '../core/i18n.dart';
import '../core/user_history.dart';
import '../state/auth_controller.dart';
import '../state/theme_controller.dart';
import '../ui/tw.dart';
import '../ui/widgets/common.dart';
import '../ui/widgets/skeleton.dart';
import '../ui/widgets/trend_charts.dart';
import '../ui/brand/palette.dart';

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
        Text(i18n.t('mobileHistory.title'), style: heading(30)),
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
          const Column(children: [SkeletonCard(lines: 2), SizedBox(height: 12), SkeletonCard(lines: 2), SizedBox(height: 12), SkeletonCard(lines: 2)])
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
            ..._weekSection(i18n, theme, history.days, history.waterTargetMl),
            _trendsSection(i18n, history.days, history.waterTargetMl),
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
        padding: const EdgeInsets.all(16),
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
      padding: const EdgeInsets.all(16),
      borderColor: theme.primaryLight,
      color: Color.alphaBlend(theme.primary.withValues(alpha: .05), Tw.surface),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Icon(LucideIcons.chartLine, size: 16, color: theme.primary),
            const SizedBox(width: 8),
            Text(i18n.t('mobileHistory.summaryTitle'), style: tx(13.5, w: 7, c: Tw.gray800)),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 12, runSpacing: 4, children: [for (final l in lines) Text(l, style: tx(12, c: Tw.gray700))]),
        ],
      ),
    );
  }

  // ---- Bu hafta ----

  List<Widget> _weekSection(I18n i18n, RebiTheme theme, List<HistoryDay> days, int waterTargetMl) {
    final week = summarizeWeeks(days, DateTime.now(), waterTargetMl: waterTargetMl);
    if (week == null) return const [];
    final cur = week.current, prev = week.previous;
    final nf = NumberFormat.decimalPattern(i18n.lang);
    final nf1 = NumberFormat('#,##0.0', i18n.lang);

    _Delta? delta(num? now, num? before, {required bool? goodWhenHigher, required String Function(num) fmt}) {
      if (prev == null || now == null || before == null) return null;
      final d = now - before;
      if (d.abs() < .05) return null;
      final good = goodWhenHigher == null ? null : (d > 0) == goodWhenHigher;
      return _Delta(text: '${d > 0 ? '+' : '-'}${fmt(d.abs())}', up: d > 0, good: good);
    }

    String whole(num n) => nf.format(n.round());
    String one(num n) => nf1.format(n);

    final rows = <Widget>[
      _weekRow(i18n, LucideIcons.calendarCheck, 'routine', i18n.t('mobileHistory.week.routineValue', {'n': cur.fullRoutineDays}),
          delta(cur.fullRoutineDays, prev?.fullRoutineDays, goodWhenHigher: true, fmt: whole)),
      if (cur.avgWaterMl != null)
        _weekRow(i18n, LucideIcons.droplet, 'water', i18n.t('mobileHistory.week.waterValue', {'ml': nf.format(cur.avgWaterMl)}),
            delta(cur.avgWaterMl, prev?.avgWaterMl, goodWhenHigher: true, fmt: (n) => '${whole(n)} ml')),
      if (cur.avgWaterMl != null)
        _weekRow(i18n, LucideIcons.target, 'waterGoal', i18n.t('mobileHistory.week.waterGoalValue', {'n': cur.waterGoalDays, 'ml': nf.format(waterTargetMl)}),
            delta(cur.waterGoalDays, prev?.waterGoalDays, goodWhenHigher: true, fmt: whole)),
      if (cur.avgSleepHours != null)
        _weekRow(i18n, LucideIcons.moon, 'sleep', i18n.t('mobileHistory.week.sleepValue', {'h': one(cur.avgSleepHours!)}),
            delta(cur.avgSleepHours, prev?.avgSleepHours, goodWhenHigher: true, fmt: (n) => '${one(n)} ${i18n.t('mobileHistory.trends.hoursUnit')}')),
      if (cur.avgStress != null)
        _weekRow(i18n, LucideIcons.brain, 'stress', i18n.t('mobileHistory.week.stressValue', {'n': one(cur.avgStress!)}),
            delta(cur.avgStress, prev?.avgStress, goodWhenHigher: false, fmt: one)),
      if (cur.spfRefreshes > 0)
        _weekRow(i18n, LucideIcons.sun, 'spf', i18n.t('mobileHistory.week.spfValue', {'n': cur.spfRefreshes}),
            delta(cur.spfRefreshes, prev?.spfRefreshes, goodWhenHigher: null, fmt: whole)),
      if (cur.checkins > 0)
        _weekRow(i18n, LucideIcons.clipboardCheck, 'checkins', i18n.t('mobileHistory.week.checkinsValue', {'n': cur.checkins}),
            delta(cur.checkins, prev?.checkins, goodWhenHigher: true, fmt: whole)),
      if (cur.makeupDays > 0)
        _weekRow(
          i18n,
          LucideIcons.sparkles,
          'makeup',
          cur.makeupRemovedDays == cur.makeupDays
              ? i18n.t('mobileHistory.week.makeupValueAllRemoved', {'n': cur.makeupDays})
              : i18n.t('mobileHistory.week.makeupValue', {'n': cur.makeupDays, 'removed': cur.makeupRemovedDays}),
          delta(cur.makeupDays, prev?.makeupDays, goodWhenHigher: null, fmt: whole),
        ),
      if (cur.junkDays > 0)
        _weekRow(i18n, LucideIcons.cookie, 'junk', i18n.t('mobileHistory.week.junkValue', {'n': cur.junkDays}),
            delta(cur.junkDays, prev?.junkDays, goodWhenHigher: false, fmt: whole)),
    ];

    return [
      RCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Icon(LucideIcons.calendarDays, size: 16, color: theme.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(i18n.t('mobileHistory.week.title'), style: tx(13.5, w: 7, c: Tw.gray800))),
            ]),
            const SizedBox(height: 2),
            Text(i18n.t(prev == null ? 'mobileHistory.week.subtitleNoPrev' : 'mobileHistory.week.subtitle'), style: tx(11, c: Tw.gray500, h: relaxed)),
            const SizedBox(height: 8),
            for (final r in rows) r,
          ],
        ),
      ),
      const SizedBox(height: 16),
    ];
  }

  Widget _weekRow(I18n i18n, IconData icon, String labelKey, String value, _Delta? delta) {
    final color = delta == null
        ? Tw.gray500
        : switch (delta.good) {
            true => Tw.green700,
            false => Tw.amber800,
            null => Tw.gray500,
          };
    final label = i18n.t('mobileHistory.week.$labelKey');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, size: 14, color: Tw.gray500)),
        const SizedBox(width: 8),
        Expanded(
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 2,
            children: [
              Text(label, style: tx(12, c: Tw.gray600)),
              Wrap(spacing: 8, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(value, style: tx(12, w: 6, c: Tw.gray800)),
                if (delta != null)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(delta.up ? LucideIcons.trendingUp : LucideIcons.trendingDown, size: 13, color: color),
                    const SizedBox(width: 2),
                    Flexible(
                      child: Text(
                        delta.text,
                        semanticsLabel: '${delta.text} ${i18n.t(delta.up ? 'mobileHistory.week.up' : 'mobileHistory.week.down')}',
                        style: tx(11, w: 6, c: color),
                      ),
                    ),
                  ]),
              ]),
            ],
          ),
        ),
      ]),
    );
  }

  // ---- Eğilimler ----

  Widget _trendsSection(I18n i18n, List<HistoryDay> days, int waterTargetMl) {
    final t = buildTrends(days, range: _range, today: DateTime.now());
    final nf = NumberFormat.decimalPattern(i18n.lang);
    final nf1 = NumberFormat('#,##0.0', i18n.lang);
    final hours = i18n.t('mobileHistory.trends.hoursUnit');
    List<double?> values(TrendSeries s) => [for (final p in s.points) p.value];
    double maxOf(TrendSeries s) => s.points.fold<double>(0, (m, p) => math.max(m, p.value ?? 0));
    double minOf(TrendSeries s) => s.points.fold<double>(double.infinity, (m, p) => math.min(m, p.value ?? double.infinity));

    final waterAvg = t.water.average;
    final sleepAvg = t.sleep.average;
    final stressAvg = t.stress.average;
    final routineAvg = t.routine.average;

    String label(String name, TrendSeries s, String avg) =>
        i18n.t('mobileHistory.trends.chartLabel', {'name': name, 'n': s.recorded, 'avg': avg});

    final waterText = waterAvg == null ? null : '${nf.format(waterAvg.round())} ml';
    final sleepText = sleepAvg == null ? null : '${nf1.format(sleepAvg)} $hours';
    final stressText = stressAvg == null ? null : i18n.t('mobileHistory.week.stressValue', {'n': nf1.format(stressAvg)});
    final routineText = routineAvg == null ? null : i18n.t('mobileHistory.trends.routineRate', {'n': (routineAvg * 100).round()});

    final sleepMin = t.sleep.isEmpty ? 4.0 : math.max(0.0, math.min(4.0, minOf(t.sleep).floorToDouble() - 1));
    final sleepMax = t.sleep.isEmpty ? 10.0 : math.max(10.0, maxOf(t.sleep).ceilToDouble() + 1);
    final waterMax = math.max(waterTargetMl.toDouble(), maxOf(t.water)) * 1.1;
    final weekly = t.bucketDays > 1 ? '${i18n.t('mobileHistory.trends.weeklyNote')} ' : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(padding: const EdgeInsets.only(left: 4), child: Text(i18n.t('mobileHistory.trends.title'), style: heading(22, h: 1.2))),
        const SizedBox(height: 10),
        _trendCard(
          i18n,
          t,
          icon: LucideIcons.droplet,
          color: Tw.blue500,
          title: i18n.t('mobileHistory.trends.water'),
          average: waterText,
          series: t.water,
          note: '$weekly${i18n.t('mobileHistory.trends.waterTarget', {'ml': nf.format(waterTargetMl)})}',
          chart: () => TrendBars(
            values: values(t.water),
            maxY: waterMax,
            reference: waterTargetMl.toDouble(),
            color: Tw.blue500,
            semanticLabel: label(i18n.t('mobileHistory.trends.water'), t.water, waterText ?? ''),
          ),
        ),
        const SizedBox(height: 12),
        _trendCard(
          i18n,
          t,
          icon: LucideIcons.moon,
          color: Tw.indigo500,
          title: i18n.t('mobileHistory.trends.sleep'),
          average: sleepText,
          series: t.sleep,
          note: '$weekly${i18n.t('mobileHistory.trends.sleepBand')}',
          chart: () => TrendLine(
            values: values(t.sleep),
            minY: sleepMin,
            maxY: sleepMax,
            band: (7, 9),
            color: Tw.indigo500,
            semanticLabel: label(i18n.t('mobileHistory.trends.sleep'), t.sleep, sleepText ?? ''),
          ),
        ),
        const SizedBox(height: 12),
        _trendCard(
          i18n,
          t,
          icon: LucideIcons.brain,
          color: Tw.orange600,
          title: i18n.t('mobileHistory.trends.stress'),
          average: stressText,
          series: t.stress,
          note: '$weekly${i18n.t('mobileHistory.trends.stressHint')}',
          chart: () => TrendLine(
            values: values(t.stress),
            minY: 1,
            maxY: 5,
            color: Tw.orange600,
            semanticLabel: label(i18n.t('mobileHistory.trends.stress'), t.stress, stressText ?? ''),
          ),
        ),
        const SizedBox(height: 12),
        _trendCard(
          i18n,
          t,
          icon: LucideIcons.calendarCheck,
          color: Tw.green600,
          title: i18n.t('mobileHistory.trends.routine'),
          average: routineText,
          series: t.routine,
          note: '$weekly${i18n.t('mobileHistory.trends.routineHint')}',
          chart: () => TrendStrip(
            values: values(t.routine),
            color: Tw.green600,
            semanticLabel: i18n.t('mobileHistory.trends.routineLabel', {'n': t.routine.recorded, 'avg': ((routineAvg ?? 0) * 100).round()}),
          ),
        ),
      ],
    );
  }

  Widget _trendCard(
    I18n i18n,
    HistoryTrends t, {
    required IconData icon,
    required Color color,
    required String title,
    required String? average,
    required TrendSeries series,
    required String note,
    required Widget Function() chart,
  }) {
    final date = DateFormat.MMMd(i18n.lang);
    return RCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 2,
                children: [
                  Text(title, style: tx(13.5, w: 7, c: Tw.gray800)),
                  if (average != null) Text(i18n.t('mobileHistory.trends.avg', {'v': average}), style: tx(12, w: 6, c: Tw.gray700)),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 10),
          if (series.isEmpty)
            Text(i18n.t('mobileHistory.trends.noData'), style: tx(12, c: Tw.gray500))
          else ...[
            chart(),
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(date.format(t.start), style: tx(10, c: Tw.gray500)),
              Text(date.format(t.end), style: tx(10, c: Tw.gray500)),
            ]),
            const SizedBox(height: 4),
            Text(note, style: tx(10, c: Tw.gray500, h: relaxed)),
          ],
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
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: tx(14, w: 7, c: Tw.gray800)),
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
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Icon(LucideIcons.scan, size: 16, color: theme.primary),
            const SizedBox(width: 8),
            Text(i18n.t('mobileHistory.assessmentsTitle'), style: tx(13.5, w: 7, c: Tw.gray800)),
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

/// Haftalık özetteki değişim: `good` true yeşil, false uyarı rengi, null nötr.
class _Delta {
  const _Delta({required this.text, required this.up, required this.good});

  final String text;
  final bool up;
  final bool? good;
}
