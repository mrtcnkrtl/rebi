import 'dart:convert';

import 'notification_actions.dart';
import 'reminder_schedule.dart';

/// Sunucudan gelen yalnızca-veri hatırlatıcısı (`docs/MOBIL-API.md` → "Bildirim verisi").
///
/// Android'de sistemin gösterdiği FCM bildirimi düğme taşıyamaz. Cihaz `actions_supported: true` ile
/// kaydolunca sunucu başlık ve gövdeyi veri içinde gönderir; uygulama bildirimi yerel bildirim olarak,
/// yerel hatırlatıcılarla aynı düğmeler ve aynı yükle kurar. Düğmeye dokunuş böylece aynı yoldan
/// ([rebiNotificationBackground] → kuyruk) kaydedilir.
class PushReminder {
  const PushReminder({
    required this.id,
    required this.title,
    required this.body,
    required this.reminderId,
    required this.payload,
    this.actions = const [],
  });

  /// Bildirim kimliği: aynı hatırlatıcının aynı penceresi iki kez gelirse üst üste yazılır.
  final int id;
  final String title;
  final String body;
  final String reminderId;
  final NotificationPayload payload;
  final List<NotificationActionSpec> actions;

  /// Veri mesajını okur. Sistem bildirimi olarak gelmiş (başlığı veride olmayan) ya da hatırlatıcı
  /// olmayan mesajlarda null döner; onları sistem zaten gösterir.
  static PushReminder? fromData(Map<String, dynamic> data) {
    final reminderId = '${data['reminder_id'] ?? ''}'.trim();
    final title = '${data['title'] ?? ''}'.trim();
    final body = '${data['body'] ?? ''}'.trim();
    if (reminderId.isEmpty || title.isEmpty) return null;
    final day = '${data['log_date'] ?? ''}'.trim();
    final slot = '${data['slot'] ?? ''}'.trim();
    final openPath = '${data['open_path'] ?? ''}'.trim();
    final serverLabels = _labels(data['actions']);
    return PushReminder(
      id: pushNotificationId(reminderId, day, slot),
      title: title,
      body: body,
      reminderId: reminderId,
      payload: NotificationPayload(
        route: openPath.startsWith('/') ? openPath : routeForReminder(reminderId),
        reminderId: reminderId,
        userId: '${data['user_id'] ?? ''}'.trim(),
        day: day,
      ),
      // Düğmeler uygulamanın kendi listesinden kurulur (kimlik ve kayıt yükü uygulamada);
      // sunucu yalnızca metni verir, sunucunun bilmediği düğme eklenmez.
      actions: [
        for (final a in notificationQuickActions(reminderId))
          if (serverLabels[a.labelKey] case final label?)
            NotificationActionSpec(notificationActionId(reminderId, a), label),
      ],
    );
  }

  static Map<String, String> _labels(Object? raw) {
    if (raw is! String || raw.isEmpty) return const {};
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const {};
      return {
        for (final item in list)
          if (item is Map && '${item['id'] ?? ''}'.isNotEmpty && '${item['label'] ?? ''}'.isNotEmpty)
            '${item['id']}': '${item['label']}',
      };
    } catch (_) {
      return const {};
    }
  }
}

/// Yerel hatırlatıcıların (1..56) ve test bildiriminin (9001) üstünde, kararlı bir kimlik.
int pushNotificationId(String reminderId, String day, String slot) {
  // FNV-1a: `String.hashCode` izolatlar arasında aynı olmak zorunda değil.
  var hash = 0x811c9dc5;
  for (final unit in utf8.encode('$reminderId|$day|$slot')) {
    hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
  }
  return 100000 + hash % 1000000;
}
