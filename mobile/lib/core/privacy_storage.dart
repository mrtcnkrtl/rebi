import 'local_store.dart';

/// Bir hesaba ait cihazdaki kişisel veriyi sil (web: `lib/privacyStorage.js`).
Future<void> clearUserLocalData(String? userId) async {
  if (userId == null || userId.isEmpty) return;
  final keys = [
    'rebi-chat-history_$userId',
    'rebi-chat-usage_$userId',
    'rebi_track_accepted_$userId',
    'rebi_track_snapshot_$userId',
    'rebi_checkin_log_$userId',
    'rebi_legal_consent_v2_$userId',
    'rebi_legal_consent_v1_$userId',
  ];
  for (final key in keys) {
    await LocalStore.instance.remove(key);
  }
  await LocalStore.instance.remove('rebi-chat-history');
}
