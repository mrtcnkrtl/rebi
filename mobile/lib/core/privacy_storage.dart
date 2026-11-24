import 'event_outbox.dart';
import 'local_store.dart';
import 'location_prefs.dart';
import 'notification_prefs.dart';

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
  // Yukarıdaki liste eskiyebilir (analiz taslağı, hava konumu, adım seçimleri, yapay zekâ paylaşım tercihi…):
  // hesabın kimliğini anahtarında taşıyan her kayıt kişiseldir ve gider. Kimlik bir UUID olduğundan başka
  // hesabın anahtarına denk gelmez.
  await LocalStore.instance.removeWhere((key) => key.contains(userId));
  // Mobil: gönderilmeyi bekleyen gün içi kayıtlar da kişisel veridir.
  await EventOutbox.instance.clear(userId);
  await clearNotificationPrefs(userId);
  await clearLocationPrefs(userId);
}
