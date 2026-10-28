import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../core/reminder_settings.dart';
import '../../core/reminder_text.dart';
import '../../core/today_plan.dart';
import '../../state/theme_controller.dart';
import '../../ui/tw.dart';

/// Gün akışındaki bir hatırlatıcı penceresi (dakika olarak, yerel duvar saati).
class FlowSegment {
  const FlowSegment({required this.id, required this.start, required this.end, required this.done, this.slots = const []});

  final String id;
  final int start;
  final int end;

  /// Yapıldı mı (rutin bitti, makyaj kaydedildi…). İzlenemeyen hatırlatıcılar (dudak balsamı, su) için false.
  final bool done;

  /// Yalnızca su: pencere içindeki hatırlatma dakikaları (nokta olarak çizilir).
  final List<int> slots;

  bool get isWater => id == 'water_intake';
}

/// Kullanıcının günü için hatırlatıcı pencereleri. Sunucu yapılan işleri `reminders` listesinden düşürdüğü için
/// pencereler ayardan (`reminderWindow`) kurulur; böylece biten işler akışta "dolu" olarak kalır. Güneş kremi
/// penceresi, gerçek saatlik UV biliniyorsa onunla, bilinmiyorsa sabit pencereyle çizilir.
List<FlowSegment> buildFlowSegments(TodayPlan plan) {
  final s = plan.settings;
  final p = plan.progress;
  final wake = s.wakeMinutes, sleep = s.sleepMinutes;
  final decisions = plan.decisions;
  final out = <FlowSegment>[];

  void add(String id, {required bool done, bool include = true, (int, int)? window}) {
    if (!include || !s.isEnabled(reminderCategoryOf[id]!)) return;
    final w = window ?? () {
      final r = reminderWindow(id, s);
      final a = r == null ? null : parseClock(r.start), b = r == null ? null : parseClock(r.end);
      return a == null || b == null ? null : (a, b);
    }();
    if (w == null || w.$2 <= w.$1) return;
    out.add(FlowSegment(id: id, start: w.$1, end: w.$2, done: done));
  }

  (int, int)? uvWindow() {
    final w = decisions?.spf.window;
    if (w == null) return null;
    final a = parseClock(w.start), b = parseClock(w.end);
    if (a == null || b == null) return null;
    final start = a.clamp(wake, sleep), end = b.clamp(wake, sleep);
    return end - start >= 30 ? (start, end) : null;
  }

  final uv = plan.weather['uv_index'];
  final spfNeeded = decisions?.spf.refresh ?? (uv is num && uv >= 5);
  final lipNeeded = decisions?.lipBalm.needed ?? plan.reminders.any((r) => r.id == 'lip_balm');

  add('routine_morning', done: p.morningDone);
  add('makeup_log', done: p.makeupLogged);
  add('spf_refresh', done: p.spfRefreshes > 0, include: spfNeeded, window: uvWindow());
  add('lip_balm', done: false, include: lipNeeded);
  add('nutrition_log', done: p.nutritionLogged);
  add('makeup_removal', done: p.makeupRemoved, include: p.makeupUsed);
  add('routine_evening', done: p.eveningDone);
  add('daily_checkin', done: plan.checkinDone);

  if (s.isEnabled('water')) {
    final r = reminderWindow('water_intake', s);
    final a = r == null ? null : parseClock(r.start), b = r == null ? null : parseClock(r.end);
    if (a != null && b != null && b > a) {
      out.add(FlowSegment(
        id: 'water_intake',
        start: a,
        end: b,
        done: p.waterMl >= plan.waterTarget,
        slots: [for (var m = a; m <= b; m += s.waterEveryMinutes) m],
      ));
    }
  }
  return out;
}

Color flowColor(String id, RebiTheme theme) => switch (id) {
      'routine_morning' || 'routine_evening' => theme.primary,
      'water_intake' => Tw.blue500,
      'spf_refresh' => Tw.amber600,
      'makeup_log' || 'makeup_removal' => Tw.pink600,
      'lip_balm' => Tw.pink400,
      'nutrition_log' => Tw.green600,
      'daily_checkin' => Tw.purple500,
      _ => Tw.gray400,
    };

/// Uyanmadan uykuya yatay zaman şeridi: her hatırlatıcının penceresi renkli bir çubuk (yapıldıysa dolu, değilse
/// soluk), su hatırlatmaları üstte noktalar, "şimdi" işareti dikey çizgi. Çakışan pencereler alt alta şeritlere dizilir.
class DayFlowStrip extends StatelessWidget {
  const DayFlowStrip({super.key, required this.plan, required this.theme, required this.now});

  final TodayPlan plan;
  final RebiTheme theme;

  /// Günün dakikası (ör. 09:15 → 555).
  final int now;

  static const double _barHeight = 10;
  static const double _laneGap = 5;
  static const double _bubbleHeight = 20;
  static const double _dotsHeight = 14;
  static const int _maxLanes = 4;

  /// Çakışmayan pencereleri aynı şeride koyar (açgözlü atama). Dönen liste, [segments] ile aynı sırada şerit numarası verir.
  static List<int> assignLanes(List<FlowSegment> segments, {int gapMinutes = 20}) {
    final order = [for (var i = 0; i < segments.length; i++) i]..sort((a, b) => segments[a].start.compareTo(segments[b].start));
    final laneEnds = <int>[];
    final lanes = List<int>.filled(segments.length, 0);
    for (final i in order) {
      var lane = laneEnds.indexWhere((end) => segments[i].start >= end + gapMinutes);
      if (lane < 0) {
        lane = laneEnds.length < _maxLanes ? laneEnds.length : _maxLanes - 1;
        if (lane == laneEnds.length) laneEnds.add(0);
      }
      laneEnds[lane] = segments[i].end;
      lanes[i] = lane;
    }
    return lanes;
  }

  @override
  Widget build(BuildContext context) {
    final i18n = I18n.instance;
    final s = plan.settings;
    final wake = s.wakeMinutes, sleep = s.sleepMinutes;
    final span = (sleep - wake).toDouble();
    final all = buildFlowSegments(plan);
    final water = all.where((e) => e.isWater).toList();
    final bars = all.where((e) => !e.isWater).toList();
    final lanes = assignLanes(bars);
    final laneCount = bars.isEmpty ? 0 : lanes.reduce((a, b) => a > b ? a : b) + 1;
    final inDay = now >= wake && now <= sleep;

    return Semantics(
      label: i18n.t('mobileToday.flow.semantics', {'wake': s.wakeTime, 'sleep': s.sleepTime, 'now': formatClock(now)}),
      child: ExcludeSemantics(
        child: LayoutBuilder(builder: (context, c) {
          final width = c.maxWidth;
          double x(int minute) => ((minute - wake) / span).clamp(0.0, 1.0) * width;
          final barsTop = _bubbleHeight + _dotsHeight + 6;
          final height = barsTop + laneCount * (_barHeight + _laneGap) + 20;
          const bubbleWidth = 46.0;
          final bubbleLeft = (x(now) - bubbleWidth / 2).clamp(0.0, width - bubbleWidth);

          return SizedBox(
            height: height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Şimdi: üstte saat balonu, altına dikey çizgi.
                if (inDay) ...[
                  Positioned(
                    left: x(now) - 1,
                    top: _bubbleHeight - 2,
                    bottom: 16,
                    child: Container(width: 2, decoration: BoxDecoration(color: theme.primaryDark.withValues(alpha: .55), borderRadius: BorderRadius.circular(1))),
                  ),
                  Positioned(
                    left: bubbleLeft,
                    top: 0,
                    width: bubbleWidth,
                    height: _bubbleHeight,
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: theme.primary, borderRadius: BorderRadius.circular(999)),
                      child: Text(formatClock(now), style: tx(10.5, w: 7, c: Colors.white)),
                    ),
                  ),
                ],
                // Su: noktalar.
                for (final w in water)
                  for (final m in w.slots)
                    Positioned(
                      left: x(m) - 3,
                      top: _bubbleHeight + 4,
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: Tw.blue500.withValues(alpha: m <= now ? 1 : .35)),
                      ),
                    ),
                // Çubuklar.
                for (var i = 0; i < bars.length; i++)
                  Positioned(
                    left: x(bars[i].start),
                    width: (x(bars[i].end) - x(bars[i].start)).clamp(8.0, width),
                    top: barsTop + lanes[i] * (_barHeight + _laneGap),
                    height: _barHeight,
                    child: Tooltip(
                      message: '${localReminderTitle(i18n, bars[i].id)} ${formatClock(bars[i].start)}–${formatClock(bars[i].end)}',
                      child: _bar(bars[i]),
                    ),
                  ),
                // Uyanma ve uyku saatleri.
                Positioned(left: 0, bottom: 0, child: Text(s.wakeTime, style: tx(10.5, w: 6, c: Tw.gray500))),
                Positioned(right: 0, bottom: 0, child: Text(s.sleepTime, style: tx(10.5, w: 6, c: Tw.gray500))),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _bar(FlowSegment e) {
    final color = flowColor(e.id, theme);
    return Container(
      decoration: BoxDecoration(
        color: e.done ? color : color.withValues(alpha: Tw.dark ? .28 : .2),
        borderRadius: BorderRadius.circular(_barHeight / 2),
        border: e.done ? null : Border.all(color: color.withValues(alpha: .65), width: 1.2),
      ),
    );
  }
}

/// Şeritteki renklerin açıklaması: yalnızca şeritte bulunan kategoriler, nokta + ad.
class FlowLegend extends StatelessWidget {
  const FlowLegend({super.key, required this.plan, required this.theme});

  final TodayPlan plan;
  final RebiTheme theme;

  static String _group(String id) => switch (id) {
        'routine_morning' || 'routine_evening' => 'routine',
        'water_intake' => 'water',
        'spf_refresh' => 'spf',
        'makeup_log' || 'makeup_removal' => 'makeup',
        'nutrition_log' => 'nutrition',
        'lip_balm' => 'lip',
        _ => 'checkin',
      };

  /// Gruba karşılık gelen çubuk kimlikleri (renk için ilkinin rengi kullanılır).
  static const _representative = {
    'routine': 'routine_morning',
    'water': 'water_intake',
    'spf': 'spf_refresh',
    'makeup': 'makeup_log',
    'nutrition': 'nutrition_log',
    'lip': 'lip_balm',
    'checkin': 'daily_checkin',
  };

  @override
  Widget build(BuildContext context) {
    final i18n = I18n.instance;
    final groups = <String>[];
    for (final e in buildFlowSegments(plan)) {
      final g = _group(e.id);
      if (!groups.contains(g)) groups.add(g);
    }
    if (groups.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        for (final g in groups)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: flowColor(_representative[g]!, theme))),
            const SizedBox(width: 5),
            Text(i18n.t('mobileToday.flow.legend.$g'), style: tx(11, w: 5, c: Tw.gray600)),
          ]),
      ],
    );
  }
}
