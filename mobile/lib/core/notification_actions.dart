import 'dart:convert';

import 'daily_tracking.dart';
import 'today_plan.dart';

/// Bildirimde gösterilen hızlı eylem düğmesi ("+250 ml", "Yaptım").
class NotificationActionSpec {
  const NotificationActionSpec(this.id, this.label);

  final String id;
  final String label;
}

/// Bildirimdeki düğmeye dokunuldu.
class NotificationActionTap {
  const NotificationActionTap({required this.reminderId, required this.actionId, required this.userId});

  final String reminderId;
  final String actionId;
  final String userId;
}

/// Bir bildirime iliştirilen yük: açılacak ekran, hangi hatırlatıcı, hangi kullanıcı ve hangi gün için
/// kurulduğu. Kullanıcı kimliği, hesap değişince eski hesabın bildiriminden kayıt gitmesin diye vardır;
/// gün, uygulama kapalıyken düğmeye basılınca o günün kalan bildirimlerini susturabilmek için.
class NotificationPayload {
  const NotificationPayload({required this.route, this.reminderId = '', this.userId = '', this.day = ''});

  final String route;
  final String reminderId;
  final String userId;

  /// Bildirimin düştüğü yerel gün (`2026-10-10`); eski bildirimlerde boş.
  final String day;

  String encode() => jsonEncode({'route': route, 'reminder_id': reminderId, 'user_id': userId, 'day': day});

  /// Eski biçim yalnızca ekran yoludur (`/dashboard`); onu da okur. Okunamazsa null.
  static NotificationPayload? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    if (!raw.startsWith('{')) return raw.startsWith('/') ? NotificationPayload(route: raw) : null;
    try {
      final j = jsonDecode(raw);
      if (j is! Map) return null;
      final route = '${j['route'] ?? ''}';
      if (route.isEmpty) return null;
      return NotificationPayload(
        route: route,
        reminderId: '${j['reminder_id'] ?? ''}',
        userId: '${j['user_id'] ?? ''}',
        day: '${j['day'] ?? ''}',
      );
    } catch (_) {
      return null;
    }
  }
}

/// Bildirimde hızlı düğme olarak sunulabilecek en çok eylem (Android'in sınırı 3'tür).
const maxNotificationActions = 3;

/// Bir hatırlatıcının bildirim düğmeleri: yalnızca olay kaydeden eylemler. Ekran ya da seçim
/// sayfası açanlar (check-in, "nasıl temizledin") bildirime dokunmakla zaten açılır.
List<ReminderAction> notificationQuickActions(String reminderId) => [
      for (final a in reminderActions(Reminder(id: reminderId, title: '', body: '', start: '', end: '')))
        if (a.type != null) a,
    ].take(maxNotificationActions).toList();

String notificationActionId(String reminderId, ReminderAction action) => '$reminderId:${action.labelKey}';

/// Düğme kimliğinden olay eylemini bulur; bilinmiyorsa null.
ReminderAction? resolveNotificationAction(String reminderId, String actionId) {
  for (final a in notificationQuickActions(reminderId)) {
    if (notificationActionId(reminderId, a) == actionId) return a;
  }
  return null;
}

/// Düğmeye dokunulunca olayı **yalnızca kuyruğa alır**. Arka plan izolatında oturum (Supabase)
/// yoktur, gönderim orada yapılamaz; kuyruk uygulama açılınca ([EventOutbox.reload]) gönderilir.
Future<bool> queueNotificationAction(NotificationActionTap tap) async {
  final action = resolveNotificationAction(tap.reminderId, tap.actionId);
  final type = action?.type;
  if (action == null || type == null || tap.userId.isEmpty) return false;
  return queueDailyTrackingEvent(tap.userId, type, action.payload);
}
