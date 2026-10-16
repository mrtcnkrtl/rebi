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

  /// Bildirimin düştüğü yerel gün (`2026-10-10`).
  String get day => localDayKey(at);

  /// Bildirime iliştirilen yük: ekran, hatırlatıcı, kullanıcı ve gün.
  NotificationPayload get payload => NotificationPayload(route: route, reminderId: reminderId, userId: userId, day: day);

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

/// iOS en fazla 64 bekleyen yerel bildirim tutar. Birkaçı test bildirimine ve işletim sistemine kalsın.
const maxScheduledNotifications = 56;

/// Bugünden sonra kaç gün için koşulsuz (her gün tekrar eden) hatırlatıcılar önceden kurulur. Uygulama bu
/// süre açılmazsa bildirimler biter; sunucu push'u açıksa o süre boyunca da sunucu gönderir.
const scheduleFutureDays = 2;

/// Güneş kremi bir günde en çok bu kadar kez hatırlatılır (sunucudaki `SPF_REFRESH_MAX_PER_DAY`).
const spfRefreshMaxPerDay = 2;

/// Yerel gün anahtarı (`2026-10-10`).
String localDayKey(DateTime at) =>
    '${at.year.toString().padLeft(4, '0')}-${at.month.toString().padLeft(2, '0')}-${at.day.toString().padLeft(2, '0')}';

/// Bir hatırlatıcının pencere içindeki gönderim dakikaları (sunucudaki `_slots` ile aynı kural; ikisi de
/// `contract/reminder_slots.json` ile sınanır). Sessiz saate denk gelen dakikalar düşer; tek seferlik bir
/// hatırlatıcının dakikası sessiz saate düşüyorsa, pencere izin veriyorsa sessiz saatin bitişine ertelenir.
List<int> reminderSlots(Reminder r, {ClockRange? quiet}) {
  final start = Reminder.minutesOf(r.start);
  final end = Reminder.minutesOf(r.end);
  if (start == null || end == null || end < start) return const [];
  final every = r.everyMinutes;
  final oneShot = every == null || every <= 0;
  final slots = oneShot ? [start] : [for (var m = start; m <= end; m += every) m];
  if (quiet == null) return slots;
  final kept = [for (final m in slots) if (!inQuietHours(m, quiet)) m];
  if (kept.isEmpty && oneShot) {
    final quietEnd = quiet.endMinutes;
    if (start < quietEnd && quietEnd <= end && !inQuietHours(quietEnd, quiet)) return [quietEnd];
  }
  return kept;
}

/// Sunucunun bugün için ürettiği hatırlatıcılar, şu anki ilerlemeye göre süzülmüş hâli. Plan sunucudan
/// alındıktan sonra yapılan işler (ya da henüz gönderilmemiş, cihazda bekleyen kayıtlar) hemen yansır:
/// hedefi dolan su, işaretlenen rutin, cevaplanan soru için bildirim kalmaz; makyaj yapıldı denince
/// temizleme hatırlatıcısı gelir. Kurallar sunucudaki `build_reminders` ile aynıdır.
List<Reminder> remindersFor(TodayPlan plan) {
  final p = plan.progress;
  final s = plan.settings;
  bool satisfied(String id) => switch (id) {
        'routine_morning' => p.morningDone,
        'routine_evening' => p.eveningDone,
        'makeup_log' => p.makeupLogged,
        'makeup_removal' => !p.makeupUsed || p.makeupRemoved,
        'water_intake' => p.waterMl >= s.waterTargetMl,
        'spf_refresh' => p.spfRefreshes >= spfRefreshMaxPerDay,
        'nutrition_log' => p.nutritionLogged,
        'daily_checkin' => plan.checkinDone,
        _ => false,
      };
  final kept = [for (final r in plan.reminders) if (!satisfied(r.id)) r];
  if (p.makeupUsed && !p.makeupRemoved && s.isEnabled('makeup') && !kept.any((r) => r.id == 'makeup_removal')) {
    final window = reminderWindow('makeup_removal', s)!;
    kept.add(Reminder(
      id: 'makeup_removal',
      title: '',
      body: '',
      start: window.start,
      end: window.end,
      logEvent: 'makeup',
    ));
  }
  return kept;
}

String routeForReminder(String? reminderId) => switch (reminderId) {
      'daily_checkin' => '/dashboard/checkin',
      'restock_check' => '/dashboard/shelf',
      _ => '/dashboard',
    };

/// Bugünün kalan hatırlatıcılarından ve sonraki günlerin koşulsuz hatırlatıcılarından bildirim listesi çıkarır.
///
/// [today] bugün için hatırlatıcılardır (bkz. [remindersFor]; yapılan işler düşmüştür). Geçmiş
/// saatler atlanır. Sonraki günler için yalnızca havaya ve yapılan işe bağlı olmayanlar bilinir
/// (`docs/MOBIL-API.md` → "Hatırlatıcı kimlikleri"); bunlar [settings]e (gün düzeni, kendi pencereleri,
/// su aralığı, kapatılan kategoriler) göre [futureDays] gün için kurulur. SPF, dudak balsamı ve makyaj
/// temizliği uygulama açılınca bugünün gerçek planıyla kurulur. [settings]teki sessiz saatlere denk
/// gelen bildirimler kurulmaz. En yakın [limit] bildirim kalır. [textFor] başlık/gövdeyi arayüz diline
/// göre verir, [actionsFor] bildirimin altındaki düğmeleri.
List<PlannedNotification> planNotifications({
  required List<Reminder> today,
  required DateTime now,
  required ({String title, String body}) Function(Reminder r) textFor,
  List<NotificationActionSpec> Function(Reminder r)? actionsFor,
  ReminderSettings settings = const ReminderSettings(),
  String userId = '',
  bool includeTomorrow = true,
  int futureDays = scheduleFutureDays,
  int limit = maxScheduledNotifications,
}) {
  final items = <PlannedNotification>[];

  void addDay(DateTime day, Iterable<Reminder> reminders, {required bool onlyFuture}) {
    for (final r in reminders) {
      final text = textFor(r);
      final actions = actionsFor?.call(r) ?? const <NotificationActionSpec>[];
      for (final minute in reminderSlots(r, quiet: settings.quiet)) {
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
    final daily = dailyReminders(settings);
    for (var i = 1; i <= futureDays; i++) {
      addDay(DateTime(now.year, now.month, now.day + i), daily, onlyFuture: false);
    }
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
