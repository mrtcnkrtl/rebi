import 'api.dart';
import 'routine_logic.dart';
import 'today_plan.dart';

/// Rıza ve gizlilik izinleri (`GET /me/snapshot` → `consent`).
class ConsentState {
  const ConsentState({
    this.legalAccepted = false,
    this.aiAllowed = false,
    this.locationAllowed = false,
    this.photoAllowed = false,
  });

  factory ConsentState.fromJson(Object? json) {
    final j = json is Map ? json.cast<String, dynamic>() : const <String, dynamic>{};
    return ConsentState(
      legalAccepted: j['legal_accepted'] == true,
      aiAllowed: j['ai_processing_allowed'] == true,
      locationAllowed: j['location_processing_allowed'] == true,
      photoAllowed: j['photo_processing_allowed'] == true,
    );
  }

  final bool legalAccepted;
  final bool aiAllowed;
  final bool locationAllowed;
  final bool photoAllowed;

  /// Eksikse tüm yapay zekâ uçları 403 döner; kullanıcı onay ekranına alınmalı.
  bool get complete => legalAccepted && aiAllowed;
}

/// Açılış paketi: `GET /me/snapshot`.
class UserSnapshot {
  const UserSnapshot({
    required this.userId,
    required this.logDate,
    required this.profile,
    required this.hasRoutine,
    required this.routine,
    required this.progress,
    required this.checkinDone,
    required this.consent,
    required this.plus,
    required this.synced,
    this.chatCursor,
  });

  factory UserSnapshot.fromJson(Map<String, dynamic> j) => UserSnapshot(
        userId: '${j['user_id'] ?? ''}',
        logDate: '${j['log_date'] ?? ''}',
        profile: j['profile'] is Map ? (j['profile'] as Map).cast<String, dynamic>() : const {},
        hasRoutine: j['has_routine'] == true,
        routine: asRoutine(j['routine']),
        progress: DayProgress.fromJson(j['progress']),
        checkinDone: j['checkin_done'] == true,
        chatCursor: j['chat_cursor'] is num ? (j['chat_cursor'] as num).toInt() : null,
        consent: ConsentState.fromJson(j['consent']),
        plus: j['plus'] == true,
        // Alan yoksa sunucu veritabanı kullanıyor sayılır; yalnızca açıkça `false` ise değil.
        synced: j['synced'] != false,
      );

  final String userId;
  final String logDate;
  final Map<String, dynamic> profile;
  final bool hasRoutine;
  final List<RoutineItem> routine;
  final DayProgress progress;
  final bool checkinDone;
  final int? chatCursor;
  final ConsentState consent;
  final bool plus;

  /// false: kullanıcı verisi sunucuda tutulmuyor (demo / veritabanı yok); rıza durumu bilinemez.
  final bool synced;
}

/// Başarısızlıkta (ağ yok, 401, 5xx) null döner; çağıran yerel veriye düşer.
Future<UserSnapshot?> fetchMeSnapshot(String userId) async {
  final res = await apiGet('/me/snapshot', query: {'user_id': userId, 'utc_offset_minutes': localUtcOffsetMinutes()});
  return res.ok ? UserSnapshot.fromJson(res.data) : null;
}
