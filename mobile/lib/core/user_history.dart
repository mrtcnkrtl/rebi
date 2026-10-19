import 'api.dart';
import 'reminder_settings.dart' show defaultWaterTargetMl;
import 'today_plan.dart';

/// Bir günün check-in kaydı (`daily_logs`).
class HistoryCheckin {
  const HistoryCheckin({this.skinFeeling, this.sleepHours, this.stressLevel, this.riskScore});

  factory HistoryCheckin.fromJson(Map<String, dynamic> j) => HistoryCheckin(
        skinFeeling: j['skin_feeling']?.toString(),
        sleepHours: _num(j['sleep_hours']),
        stressLevel: _num(j['stress_level'])?.toInt(),
        riskScore: _num(j['risk_score'])?.toInt(),
      );

  /// `iyi` | `kuru` | `yagli` | `kirik` | `irritasyon`
  final String? skinFeeling;
  final double? sleepHours;

  /// 1–5
  final int? stressLevel;
  final int? riskScore;
}

/// Bir günün gün içi kayıtlarının özeti (`daily_events` toplamı).
class HistoryTracking {
  const HistoryTracking({
    this.progress = const DayProgress(),
    this.sleepHours,
    this.avgStress,
    this.junkFood = false,
    this.productsFinished = 0,
    this.eventsCount = 0,
  });

  factory HistoryTracking.fromJson(Object? json) {
    final j = json is Map ? json.cast<String, dynamic>() : const <String, dynamic>{};
    final nutrition = j['nutrition'] is Map ? (j['nutrition'] as Map).cast<String, dynamic>() : const <String, dynamic>{};
    return HistoryTracking(
      progress: DayProgress.fromJson(j),
      sleepHours: _num(j['sleep_hours']),
      avgStress: _num(j['avg_stress']),
      junkFood: nutrition['junk_food'] == true,
      productsFinished: j['products_finished'] is List ? (j['products_finished'] as List).length : 0,
      eventsCount: _num(j['events_count'])?.toInt() ?? 0,
    );
  }

  final DayProgress progress;
  final double? sleepHours;
  final double? avgStress;
  final bool junkFood;
  final int productsFinished;
  final int eventsCount;
}

class HistoryDay {
  const HistoryDay({required this.logDate, required this.tracking, this.checkin});

  factory HistoryDay.fromJson(Map<String, dynamic> j) => HistoryDay(
        logDate: '${j['log_date'] ?? ''}',
        tracking: HistoryTracking.fromJson(j['tracking']),
        checkin: j['checkin'] is Map ? HistoryCheckin.fromJson((j['checkin'] as Map).cast<String, dynamic>()) : null,
      );

  /// `YYYY-MM-DD`
  final String logDate;
  final HistoryTracking tracking;
  final HistoryCheckin? checkin;

  DateTime? get date => DateTime.tryParse(logDate);

  /// Gün içi kaydı ya da check-in'i var mı (boş günler listede gösterilmez).
  bool get hasData => tracking.eventsCount > 0 || checkin != null;
}

class HistoryAssessment {
  const HistoryAssessment({required this.concern, this.severityScore, this.createdAt});

  factory HistoryAssessment.fromJson(Map<String, dynamic> j) => HistoryAssessment(
        concern: '${j['concern'] ?? ''}',
        severityScore: _num(j['severity_score'])?.toInt(),
        createdAt: j['created_at'] == null ? null : DateTime.tryParse('${j['created_at']}')?.toLocal(),
      );

  final String concern;
  final int? severityScore;
  final DateTime? createdAt;
}

/// `GET /me/history` yanıtı.
class UserHistory {
  const UserHistory({required this.days, required this.assessments, required this.synced, this.waterTargetMl = defaultWaterTargetMl});

  factory UserHistory.fromJson(Map<String, dynamic> j) {
    final days = [
      for (final d in (j['days'] is List ? j['days'] as List : const []))
        if (d is Map) HistoryDay.fromJson(d.cast<String, dynamic>()),
    ].where((d) => d.logDate.isNotEmpty && d.hasData).toList()
      // Sunucu eskiden yeniye döner; liste en yeni gün üstte gösterilir.
      ..sort((a, b) => b.logDate.compareTo(a.logDate));
    return UserHistory(
      days: days,
      assessments: [
        for (final a in (j['assessments'] is List ? j['assessments'] as List : const []))
          if (a is Map) HistoryAssessment.fromJson(a.cast<String, dynamic>()),
      ],
      synced: j['synced'] != false,
      waterTargetMl: _num(j['water_target_ml'])?.toInt().clamp(500, 6000) ?? defaultWaterTargetMl,
    );
  }

  /// En yeni gün başta.
  final List<HistoryDay> days;
  final List<HistoryAssessment> assessments;

  /// false: kullanıcı verisi sunucuda tutulmuyor.
  final bool synced;

  /// Kullanıcının günlük su hedefi (ml): grafik referansı ve "hedefi tutturulan gün" sayısı. Eski sunucuda varsayılan.
  final int waterTargetMl;
}

/// Seçilen aralığın tek bakışta özeti.
class HistorySummary {
  const HistorySummary({
    required this.recordedDays,
    required this.checkins,
    required this.fullRoutineDays,
    this.avgWaterMl,
    this.avgSleepHours,
    this.avgRiskScore,
  });

  final int recordedDays;
  final int checkins;

  /// Sabah ve akşam rutini birlikte işaretlenen gün sayısı.
  final int fullRoutineDays;

  /// Su kaydı olan günlerin ortalaması (ml); hiç su kaydı yoksa null.
  final int? avgWaterMl;

  /// Check-in'deki uyku saati; check-in yapılmayan günlerde gün içi uyku kaydı.
  final double? avgSleepHours;
  final int? avgRiskScore;
}

HistorySummary summarizeHistory(List<HistoryDay> days) {
  final water = [for (final d in days) if (d.tracking.progress.waterMl > 0) d.tracking.progress.waterMl];
  final sleep = [
    for (final d in days)
      if (d.checkin?.sleepHours != null) d.checkin!.sleepHours! else if (d.tracking.sleepHours != null) d.tracking.sleepHours!,
  ];
  final risk = [for (final d in days) if (d.checkin?.riskScore != null) d.checkin!.riskScore!];
  double avg(List<num> v) => v.fold<double>(0, (sum, n) => sum + n) / v.length;
  return HistorySummary(
    recordedDays: days.length,
    checkins: days.where((d) => d.checkin != null).length,
    fullRoutineDays: days.where((d) => d.tracking.progress.morningDone && d.tracking.progress.eveningDone).length,
    avgWaterMl: water.isEmpty ? null : avg(water).round(),
    avgSleepHours: sleep.isEmpty ? null : (avg(sleep) * 10).round() / 10,
    avgRiskScore: risk.isEmpty ? null : avg(risk).round(),
  );
}

double? _num(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');

/// `days`: 1–90 (sunucu üst sınırı). Başarısızlıkta null döner.
Future<UserHistory?> fetchHistory(String userId, {int days = 30}) async {
  final res = await apiGet('/me/history', query: {
    'user_id': userId,
    'days': '${days.clamp(1, 90)}',
    'utc_offset_minutes': localUtcOffsetMinutes(),
  });
  return res.ok ? UserHistory.fromJson(res.data) : null;
}
