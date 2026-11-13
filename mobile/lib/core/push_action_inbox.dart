import 'local_store.dart';
import 'notification_actions.dart';

/// iOS'ta sunucu bildiriminin düğmesine yapılan dokunuşlar. `firebase_messaging` dokunuşu Dart'a düğme
/// kimliği olmadan ilettiği için `ios/Runner/AppDelegate.swift` (`PushActionInbox`) bunları bu anahtara
/// yazar; uygulama oturum açıkken okuyup kaydeder.
const pendingPushActionsKey = 'rebi-pending-push-actions';

/// Bekleyen dokunuşları okur ve siler. Bozuk ya da eksik satırlar atlanır.
Future<List<NotificationActionTap>> takePendingPushActions() async {
  final store = LocalStore.instance;
  // Swift tarafı diske yazdı; önbellekteki değer eski olabilir.
  await store.reload();
  final raw = store.getJson(pendingPushActionsKey);
  if (raw == null) return const [];
  await store.remove(pendingPushActionsKey);
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if (item is Map && '${item['reminder_id'] ?? ''}'.isNotEmpty && '${item['action_id'] ?? ''}'.isNotEmpty)
        NotificationActionTap(
          reminderId: '${item['reminder_id']}',
          actionId: '${item['action_id']}',
          userId: '${item['user_id'] ?? ''}',
        ),
  ];
}
