import 'local_store.dart';

String _promptKey(String userId) => 'rebi_location_prompt_dismissed_v1_$userId';

/// Kullanıcı "Bugün" ekranındaki konum önerisini kapattı (ya da izin penceresini bir kez gördü).
bool locationPromptDismissed(String? userId) {
  if (userId == null || userId.isEmpty) return false;
  return LocalStore.instance.getString(_promptKey(userId)) == '1';
}

Future<void> dismissLocationPrompt(String userId) => LocalStore.instance.setString(_promptKey(userId), '1');

/// Hesap silinirken ya da yerel veri temizlenirken.
Future<void> clearLocationPrefs(String userId) => LocalStore.instance.remove(_promptKey(userId));
