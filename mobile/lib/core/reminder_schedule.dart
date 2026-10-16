import 'notification_actions.dart';
import 'reminder_settings.dart';
import 'today_plan.dart';

/// Telefona kurulacak tek bir bildirim.
class PlannedNotification {
  const PlannedNotification({
    required this.id,
    required this.at,
    required this.title,
    required this.body,
    required this.reminderId,
    required this.route,
    this.userId = '',
    this.actions = const [],
  });

  final int id;

  /// Yerel duvar saati.
  final DateTime at;
  final String title;
  final String body;
  final String reminderId;

  /// Bildirime dokunulunca açılacak ekran.
  final String route;

  /// Bildirimin kurulduğu kullanıcı.
  final String userId;

  /// Bildirimin altındaki hızlı eylem düğmeleri.
  final List<NotificationActionSpec> actions;

  /// Bildirime iliştirilen yük: ekran, hatırlatıcı ve kullanıcı.
  NotificationPayload get payload => NotificationPayload(route: route, reminderId: reminderId, userId: userId);

  PlannedNotification withId(int next) => PlannedNotification(
        id: next,
        at: at,
        title: title,
        body: body,
        reminderId: reminderId,
        route: route,
        userId: userId,
        actions: actions,
      );
}

/// iOS en fazla 64 bekleyen yerel bildirim tutar; biz çok daha azını kurarız.
const maxScheduledNotifications = 40;

/// Bir hatırlatıcının pencere içindeki gönderim dakikaları (sunucudaki `_slots` ile aynı kural).
List<int> reminderSlots(Reminder r) {
  final start = Reminder.minutesOf(r.start);
  final end = Reminder.minutesOf(r.end);
  if (start == null || end == null || end < start) return const [];
  final every = r.everyMinutes;
  if (every == null || every <= 0) return [start];
  return [for (var m = start; m <= end; m += every) m];
}

String routeForReminder(String? reminderId) => switch (reminderId) {
      'daily_checkin' => '/dashboard/checkin',
      'restock_check' => '/dashboard/shelf',
      _ => '/dashboard',
    };

/// Bugünün kalan hatırlatıcılarından ve yarının koşulsuz hatırlatıcılarından bildirim listesi çıkarır.
///
/// [today] sunucunun bugün için ürettiği listedir; yapılan işler zaten düşmüştür. Geçmiş
/// saatler atlanır. Yarın için yalnızca havaya ve yapılan işe bağlı olmayanlar bilinir
/// (`docs/MOBIL-API.md` → "Hatırlatıcı kimlikleri"); bunlar [settings]e (gün düzeni, su aralığı,
/// kapatılan kategoriler) göre kurulur. SPF, dudak balsamı ve makyaj temizliği uygulama
/// açılınca bugünün gerçek planıyla kurulur. [textFor] başlık/gövdeyi arayüz diline göre verir,
/// [actionsFor] bildirimin altındaki düğmeleri.
List<PlannedNotification> planNotifications({
  required List<Reminder> today,
  required DateTime now,
  required ({String title, String body}) Function(Reminder r) textFor,
  List<NotificationActionSpec> Function(Reminder r)? actionsFor,
  ReminderSettings settings = const ReminderSettings(),
  String userId = '',
  bool includeTomorrow = true,
  int limit = maxScheduledNotifications,
}) {
  final items = <PlannedNotification>[];

  void addDay(DateTime day, Iterable<Reminder> reminders, {required bool onlyFuture}) {
    for (final r in reminders) {
      final text = textFor(r);
      final actions = actionsFor?.call(r) ?? const <NotificationActionSpec>[];
      for (final minute in reminderSlots(r)) {
        final at = DateTime(day.year, day.month, day.day, minute ~/ 60, minute % 60);
        if (onlyFuture && !at.isAfter(now)) continue;
        items.add(PlannedNotification(
          id: 0,
          at: at,
          title: text.title,
          body: text.body,
          reminderId: r.id,
          route: routeForReminder(r.id),
          userId: userId,
          actions: actions,
        ));
      }
    }
  }

  addDay(now, today, onlyFuture: true);
  if (includeTomorrow) {
    addDay(DateTime(now.year, now.month, now.day + 1), dailyReminders(settings), onlyFuture: false);
  }

  // Aynı anda gelen bildirimler arasında sıra: önce zaman, sonra kimlik (kararlı).
  items.sort((a, b) {
    final byTime = a.at.compareTo(b.at);
    return byTime != 0 ? byTime : a.reminderId.compareTo(b.reminderId);
  });
  return [for (var i = 0; i < items.length && i < limit; i++) items[i].withId(i + 1)];
}

/// Aynı liste ikinci kez kurulmasın diye parmak izi.
String scheduleSignature(List<PlannedNotification> items) => items
    .map((n) => '${n.at.millisecondsSinceEpoch}|${n.reminderId}|${n.title}|${n.body}|${n.userId}|'
        '${n.actions.map((a) => '${a.id}=${a.label}').join(',')}')
    .join('\n');
