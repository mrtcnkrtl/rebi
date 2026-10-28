import 'dart:math' as math;

import 'demo_user.dart';
import 'local_store.dart';
import 'routine_tracking.dart';

/// Günlük check-in geçmişi (cihazda) — profilde seri ve rutin sadakati için.
const routineStreakGoalDays = 30;

String _logKey(String userId) => 'rebi_checkin_log_$userId';

/// Web `new Date().toISOString().slice(0, 10)` ile aynı: UTC takvim günü.
String ymdToday([DateTime? now]) => (now ?? DateTime.now()).toUtc().toIso8601String().substring(0, 10);

String ymdAddDays(String ymd, int delta) {
  final p = ymd.split('-').map(int.parse).toList();
  final dt = DateTime(p[0], p[1], p[2] + delta);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${dt.year.toString().padLeft(4, '0')}-${two(dt.month)}-${two(dt.day)}';
}

class CheckInLogEntry {
  const CheckInLogEntry(this.d, this.applied);

  final String d;
  final bool applied;

  Map<String, dynamic> toJson() => {'d': d, 'applied': applied};
}

/// Başarılı check-in sonrası çağır (aynı gün tekrar gönderilirse güncellenir).
Future<void> recordCheckInSuccess(String? userId, {required bool appliedRoutine, DateTime? now}) async {
  if (userId == null || userId.isEmpty || userId == demoUserId) return;
  final today = ymdToday(now);
  var arr = getCheckInLog(userId).where((x) => x.d != today).toList()
    ..add(CheckInLogEntry(today, appliedRoutine))
    ..sort((a, b) => b.d.compareTo(a.d));
  if (arr.length > 120) arr = arr.sublist(0, 120);
  await LocalStore.instance.setJson(_logKey(userId), arr.map((e) => e.toJson()).toList());
}

List<CheckInLogEntry> getCheckInLog(String? userId) {
  if (userId == null || userId.isEmpty) return [];
  final v = LocalStore.instance.getJson(_logKey(userId));
  if (v is! List) return [];
  return v
      .whereType<Map>()
      .where((x) => x['d'] is String)
      .map((x) => CheckInLogEntry(x['d'] as String, x['applied'] == true))
      .toList();
}

/// Takvim günü üst üste check-in (bugün veya dün ile başlayabilir).
int computeCheckInStreak(List<CheckInLogEntry> log, {DateTime? now}) {
  if (log.isEmpty) return 0;
  final days = log.map((x) => x.d).toSet();
  var start = ymdToday(now);
  if (!days.contains(start)) {
    start = ymdAddDays(start, -1);
    if (!days.contains(start)) return 0;
  }
  var streak = 0;
  var cur = start;
  while (days.contains(cur)) {
    streak += 1;
    cur = ymdAddDays(cur, -1);
  }
  return streak;
}

class ProfileRoutineStats {
  const ProfileRoutineStats({
    required this.streak,
    required this.totalCheckIns,
    required this.appliedRatePercent,
    required this.goalProgress,
    required this.daysSinceAccept,
    required this.hasAcceptedRoutine,
  });

  final int streak;
  final int totalCheckIns;
  final int? appliedRatePercent;
  final int goalProgress;
  final int? daysSinceAccept;
  final bool hasAcceptedRoutine;
}

ProfileRoutineStats getProfileRoutineStats(String userId) {
  final snap = getRoutineSnapshot(userId);
  final acceptedAt = snap?['acceptedAt'];
  final log = getCheckInLog(userId);
  final streak = computeCheckInStreak(log);
  final appliedCount = log.where((x) => x.applied).length;
  final appliedRatePercent = log.isNotEmpty ? (appliedCount / log.length * 100).round() : null;
  int? daysSinceAccept;
  if (acceptedAt is num && acceptedAt > 0) {
    final diff = DateTime.now().millisecondsSinceEpoch - acceptedAt.toInt();
    daysSinceAccept = diff < 0 ? 0 : diff ~/ 86400000;
  }
  final goalProgress = math.min(100, (streak / routineStreakGoalDays * 100).round());
  final routine = snap?['routine'];
  return ProfileRoutineStats(
    streak: streak,
    totalCheckIns: log.length,
    appliedRatePercent: appliedRatePercent,
    goalProgress: goalProgress,
    daysSinceAccept: daysSinceAccept,
    hasAcceptedRoutine: routine is List && routine.isNotEmpty,
  );
}
