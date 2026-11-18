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
  const NotificationPayload({
    required this.route,
    this.reminderId = '',
    this.userId = '',
    this.day = '',
    this.title = '',
    this.body = '',
    this.actions = const [],
  });

  final String route;
  final String reminderId;
  final String userId;

  /// Bildirimin düştüğü yerel gün (`2026-10-10`); eski bildirimlerde boş.
  final String day;

  /// Bildirimin metni ve düğmeleri: uygulama kapalıyken "30 dk sonra"ya basılınca bildirim, arka plan izolatında
  /// (çeviri ve plan yokken) bunlarla yeniden kurulur. Eski bildirimlerde boş.
  final String title;
  final String body;
  final List<NotificationActionSpec> actions;

  String encode() => jsonEncode({
        'route': route,
        'reminder_id': reminderId,
        'user_id': userId,
        'day': day,
        if (title.isNotEmpty) 'title': title,
        if (body.isNotEmpty) 'body': body,
        if (actions.isNotEmpty) 'actions': [for (final a in actions) {'id': a.id, 'label': a.label}],
      });

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
        title: '${j['title'] ?? ''}',
        body: '${j['body'] ?? ''}',
        actions: [
          for (final a in (j['actions'] is List ? j['actions'] as List : const []))
            if (a is Map && '${a['id'] ?? ''}'.isNotEmpty && '${a['label'] ?? ''}'.isNotEmpty)
              NotificationActionSpec('${a['id']}', '${a['label']}'),
        ],
      );
    } catch (_) {
      return null;
    }
  }
}

/// Bildirimde hızlı düğme olarak sunulabilecek en çok eylem (Android'in sınırı 3'tür).
const maxNotificationActions = 3;

List<ReminderAction> _eventActions(String reminderId) => [
      for (final a in reminderActions(Reminder(id: reminderId, title: '', body: '', start: '', end: '')))
        if (a.type != null) a,
    ];

/// Bir hatırlatıcının bildirim düğmeleri: soruya verilebilecek **her** makul cevap (Android en fazla 3 düğme gösterir).
/// Kullanıcı tek bir cevaba zorlanmaz; ayrıntı isteyen cevaplar (ne yedin, nasıl temizledin) kısa cevabı yazar, ayrıntı
/// uygulamadan eklenir. Ekran açan eylemler (check-in, Rafım) bildirime dokunmakla zaten açılır.
///
/// - Rutin: **Yaptım · 30 dk sonra · Bugün atla** (erteleme kayıt yazmaz, bildirimi yeniden kurar).
/// - Su: **İçtim** (bir bardak, 250 ml) · **İçmedim**. Uygulama içindeki "+250 / +500 ml" düğmeleri orada kalır.
List<ReminderAction> notificationQuickActions(String reminderId) {
  if (reminderId == 'water_intake') return const [waterDrankAction, waterNotDrunkAction];
  final events = _eventActions(reminderId);
  if (events.isNotEmpty && (reminderId == 'routine_morning' || reminderId == 'routine_evening')) {
    return [events.first, snoozeAction, ...events.skip(1)].take(maxNotificationActions).toList();
  }
  return events.take(maxNotificationActions).toList();
}

String notificationActionId(String reminderId, ReminderAction action) => '$reminderId:${action.labelKey}';

/// Düğme kimliğinden olay eylemini bulur; bilinmiyorsa null. Önceki sürümde kurulmuş ve henüz gelmemiş bildirimlerin
/// düğmeleri (`water_intake:water250`) de çözülür: uygulama güncellenince onlara dokunmak kayıpsız çalışır.
ReminderAction? resolveNotificationAction(String reminderId, String actionId) {
  for (final a in [...notificationQuickActions(reminderId), ..._eventActions(reminderId)]) {
    if (notificationActionId(reminderId, a) == actionId) return a;
  }
  return null;
}

/// Cevap verilince o günün aynı hatırlatıcısından kalan bildirimler de susmalı mı? Yalnızca "doldurulan" sorular
/// (su hedefe kadar, güneş kremi günlük sınıra kadar) ve "içmedim" sürer; diğer her cevap soruyu kapatır.
bool actionClosesReminder(ReminderAction action) {
  if (action.snoozeMinutes != null) return false;
  return switch (action.type) {
    null || 'water_intake' || 'water_skipped' || 'spf_refresh' => false,
    _ => true,
  };
}

/// Düğmeye dokunulunca olayı **yalnızca kuyruğa alır**. Arka plan izolatında oturum (Supabase)
/// yoktur, gönderim orada yapılamaz; kuyruk uygulama açılınca ([EventOutbox.reload]) gönderilir.
Future<bool> queueNotificationAction(NotificationActionTap tap) async {
  final action = resolveNotificationAction(tap.reminderId, tap.actionId);
  final type = action?.type;
  if (action == null || type == null || tap.userId.isEmpty) return false;
  return queueDailyTrackingEvent(tap.userId, type, action.payload);
}
