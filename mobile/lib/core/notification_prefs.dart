import 'local_store.dart';

/// Bildirim tercihi kullanıcı başınadır; varsayılan kapalıdır (kullanıcı kendisi açar).
String _enabledKey(String userId) => 'rebi_notifications_enabled_v1_$userId';

String _promptKey(String userId) => 'rebi_notifications_prompt_dismissed_v1_$userId';

/// true: açık, false: kullanıcı kapattı, null: hiç seçilmedi.
bool? notificationsEnabledFor(String? userId) {
  if (userId == null || userId.isEmpty) return null;
  return switch (LocalStore.instance.getString(_enabledKey(userId))) {
    '1' => true,
    '0' => false,
    _ => null,
  };
}

Future<void> setNotificationsEnabled(String userId, bool enabled) =>
    LocalStore.instance.setString(_enabledKey(userId), enabled ? '1' : '0');

bool notificationPromptDismissed(String? userId) {
  if (userId == null || userId.isEmpty) return false;
  return LocalStore.instance.getString(_promptKey(userId)) == '1';
}

Future<void> dismissNotificationPrompt(String userId) => LocalStore.instance.setString(_promptKey(userId), '1');

/// Hesap silinirken ya da yerel veri temizlenirken.
Future<void> clearNotificationPrefs(String userId) async {
  await LocalStore.instance.remove(_enabledKey(userId));
  await LocalStore.instance.remove(_promptKey(userId));
}
