import 'user_history.dart';

/// Grafikteki tek nokta: bir gün (7 ve 30 günlük aralık) ya da bir hafta (90 günlük aralık).
class TrendPoint {
  const TrendPoint({required this.start, required this.days, this.value});

  /// Noktanın ilk günü (yerel, saat 00:00).
  final DateTime start;

  /// Noktanın kapsadığı gün sayısı (1 ya da 7).
  final int days;

  /// Kayıtlı günlerin ortalaması; hiç kayıt yoksa null.
  final double? value;
}

class TrendSeries {
  const TrendSeries({required this.points, this.average});

  final List<TrendPoint> points;

  /// Kayıtlı günlerin ortalaması (nokta ortalamalarının ortalaması değil, günlük değerlerin).
  final double? average;

  int get recorded => points.where((p) => p.value != null).length;
  bool get isEmpty => recorded == 0;
}

/// Seçilen aralığın dört eğilimi: su, uyku, stres, rutin tamamlama.
class HistoryTrends {
  const HistoryTrends({
    required this.start,
    required this.end,
    required this.bucketDays,
    required this.water,
    required this.sleep,
    required this.stress,
    required this.routine,
  });

  /// İlk ve son gün (`end` = bugün).
  final DateTime start;
  final DateTime end;

  /// 1: günlük; 7: haftalık ortalama.
  final int bucketDays;

  /// Günlük su (ml).
  final TrendSeries water;

  /// Uyku (saat): check-in, yoksa gün içi kayıt.
  final TrendSeries sleep;

  /// Stres (1–5): check-in, yoksa gün içi kayıtların ortalaması.
  final TrendSeries stress;

  /// Rutin tamamlama (0–1): sabah ve akşamdan işaretlenenin oranı. Hiç kaydı olmayan gün boş.
  final TrendSeries routine;

  bool get isEmpty => water.isEmpty && sleep.isEmpty && stress.isEmpty && routine.isEmpty;
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// `YYYY-MM-DD`
String dayKey(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Aralık 31 günden uzunsa haftalık, değilse günlük noktalar.
int trendBucketDays(int range) => range > 31 ? 7 : 1;

double? _mean(Iterable<double> v) => v.isEmpty ? null : v.fold<double>(0, (a, b) => a + b) / v.length;

double? _sleepOf(HistoryDay d) => d.checkin?.sleepHours ?? d.tracking.sleepHours;
double? _stressOf(HistoryDay d) => d.checkin?.stressLevel?.toDouble() ?? d.tracking.avgStress;
double? _waterOf(HistoryDay d) => d.tracking.progress.waterMl > 0 ? d.tracking.progress.waterMl.toDouble() : null;
double _routineOf(HistoryDay d) => ((d.tracking.progress.morningDone ? 1 : 0) + (d.tracking.progress.eveningDone ? 1 : 0)) / 2;

/// Son `range` günün eğilimleri; `today` eksenin son günüdür. Kaydı olmayan günler boş kalır.
HistoryTrends buildTrends(List<HistoryDay> days, {required int range, required DateTime today}) {
  final end = dateOnly(today);
  final bucket = trendBucketDays(range);
  final buckets = (range / bucket).ceil();
  final start = DateTime(end.year, end.month, end.day - buckets * bucket + 1);
  final byKey = {for (final d in days) d.logDate: d};

  TrendSeries series(double? Function(HistoryDay) pick) {
    final points = <TrendPoint>[];
    final all = <double>[];
    for (var i = 0; i < buckets; i++) {
      final first = DateTime(start.year, start.month, start.day + i * bucket);
      final values = <double>[];
      for (var k = 0; k < bucket; k++) {
        final d = byKey[dayKey(DateTime(first.year, first.month, first.day + k))];
        final v = d == null ? null : pick(d);
        if (v != null) values.add(v);
      }
      all.addAll(values);
      points.add(TrendPoint(start: first, days: bucket, value: _mean(values)));
    }
    return TrendSeries(points: points, average: _mean(all));
  }

  return HistoryTrends(
    start: start,
    end: end,
    bucketDays: bucket,
    water: series(_waterOf),
    sleep: series(_sleepOf),
    stress: series(_stressOf),
    routine: series(_routineOf),
  );
}

/// Bir haftanın (7 gün) özeti.
class WeekStats {
  const WeekStats({
    required this.recordedDays,
    required this.fullRoutineDays,
    required this.checkins,
    required this.spfRefreshes,
    required this.junkDays,
    this.avgWaterMl,
    this.avgSleepHours,
    this.avgStress,
  });

  final int recordedDays;

  /// Sabah ve akşam rutini birlikte işaretlenen gün sayısı.
  final int fullRoutineDays;
  final int checkins;
  final int spfRefreshes;

  /// Abur cubur / şekerli yenen gün sayısı.
  final int junkDays;
  final int? avgWaterMl;
  final double? avgSleepHours;
  final double? avgStress;
}

/// Son 7 gün ve ondan önceki 7 gün. `previous`, o hafta hiç kayıt yoksa null (karşılaştırma gösterilmez).
class WeeklySummary {
  const WeeklySummary({required this.current, this.previous});

  final WeekStats current;
  final WeekStats? previous;
}

WeekStats _weekStats(List<HistoryDay> days) {
  final water = [for (final d in days) ?_waterOf(d)];
  final sleep = [for (final d in days) ?_sleepOf(d)];
  final stress = [for (final d in days) ?_stressOf(d)];
  final avgWater = _mean(water);
  final avgSleep = _mean(sleep);
  final avgStress = _mean(stress);
  return WeekStats(
    recordedDays: days.length,
    fullRoutineDays: days.where((d) => d.tracking.progress.morningDone && d.tracking.progress.eveningDone).length,
    checkins: days.where((d) => d.checkin != null).length,
    spfRefreshes: days.fold(0, (a, d) => a + d.tracking.progress.spfRefreshes),
    junkDays: days.where((d) => d.tracking.junkFood).length,
    avgWaterMl: avgWater?.round(),
    avgSleepHours: avgSleep == null ? null : (avgSleep * 10).round() / 10,
    avgStress: avgStress == null ? null : (avgStress * 10).round() / 10,
  );
}

/// `today` dahil son 7 günü, bir önceki 7 günle karşılaştırır. Bu hafta hiç kayıt yoksa null.
WeeklySummary? summarizeWeeks(List<HistoryDay> days, DateTime today) {
  final end = dateOnly(today);
  List<HistoryDay> within(int fromAgo, int toAgo) {
    final from = dayKey(DateTime(end.year, end.month, end.day - fromAgo));
    final to = dayKey(DateTime(end.year, end.month, end.day - toAgo));
    return [for (final d in days) if (d.logDate.compareTo(from) >= 0 && d.logDate.compareTo(to) <= 0) d];
  }

  final current = within(6, 0);
  if (current.isEmpty) return null;
  final previous = within(13, 7);
  return WeeklySummary(current: _weekStats(current), previous: previous.isEmpty ? null : _weekStats(previous));
}
