import 'local_store.dart';

/// Kalıcı rutin takibi: kullanıcı rutini kabul edince snapshot + bayrak.
String trackAcceptedKey(String userId) => 'rebi_track_accepted_$userId';

String trackSnapshotKey(String userId) => 'rebi_track_snapshot_$userId';

int _nowMs() => DateTime.now().millisecondsSinceEpoch;

bool isRoutineTrackingAccepted(String? userId) {
  if (userId == null || userId.isEmpty) return false;
  return LocalStore.instance.getString(trackAcceptedKey(userId)) == '1';
}

Map<String, dynamic>? getRoutineSnapshot(String? userId) {
  if (userId == null || userId.isEmpty) return null;
  final v = LocalStore.instance.getJson(trackSnapshotKey(userId));
  return v is Map ? v.cast<String, dynamic>() : null;
}

/// Mevcut snapshot ile birleştirir (routine ve check-in sonrası güncelleme için).
Future<void> saveRoutineSnapshot(String? userId, Map<String, dynamic> partial) async {
  if (userId == null || userId.isEmpty) return;
  final prev = getRoutineSnapshot(userId) ?? {};
  final next = {...prev, ...partial, 'updatedAt': _nowMs()};
  await LocalStore.instance.setJson(trackSnapshotKey(userId), next);
}

/// Rutini kabul: tam dashboard meta + rutin satırı.
Future<void> acceptRoutineTracking(String? userId, Map<String, dynamic> snapshot) async {
  if (userId == null || userId.isEmpty) return;
  final prev = getRoutineSnapshot(userId) ?? {};
  final merged = {
    ...snapshot,
    // İlk kabul zamanı (profil: hedef gün / yolculuk süresi).
    'acceptedAt': prev['acceptedAt'] is num ? prev['acceptedAt'] : _nowMs(),
    'updatedAt': _nowMs(),
  };
  await saveRoutineSnapshot(userId, merged);
  await LocalStore.instance.setString(trackAcceptedKey(userId), '1');
}

/// İlk analiz tamamlandıysa (kayıtlı rutin veya kabul bayrağı) uzun sihirbaz göstermeyi atla.
bool hasCompletedOnboarding(String? userId) {
  if (userId == null || userId.isEmpty) return false;
  if (isRoutineTrackingAccepted(userId)) return true;
  final r = getRoutineSnapshot(userId)?['routine'];
  return r is List && r.isNotEmpty;
}
