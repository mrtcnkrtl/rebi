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
  });

  final int id;

  /// Yerel duvar saati.
  final DateTime at;
  final String title;
  final String body;
  final String reminderId;

  /// Bildirime dokunulunca açılacak ekran.
  final String route;
}

/// Yarın için kurulan, koşulsuz her gün tekrar eden hatırlatıcılar ve pencereleri
/// (`docs/MOBIL-API.md` → "Hatırlatıcı kimlikleri"). Havaya ve yapılan işe bağlı olanlar
/// (SPF, dudak balsamı, makyaj temizliği) yarın için bilinemez; uygulama açılınca bugünün
/// gerçek planıyla yeniden kurulur.
const dailyReminderDefaults = <Reminder>[
  Reminder(id: 'routine_morning', title: '', body: '', start: '07:30', end: '09:30'),
  Reminder(id: 'water_intake', title: '', body: '', start: '09:00', end: '21:00', everyMinutes: 120),
  Reminder(id: 'makeup_log', title: '', body: '', start: '10:00', end: '11:00'),
  Reminder(id: 'nutrition_log', title: '', body: '', start: '20:00', end: '20:30'),
  Reminder(id: 'routine_evening', title: '', body: '', start: '21:00', end: '23:00'),
  Reminder(id: 'daily_checkin', title: '', body: '', start: '21:00', end: '22:30'),
];

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

String routeForReminder(String? reminderId) => reminderId == 'daily_checkin' ? '/dashboard/checkin' : '/dashboard';

/// Bugünün kalan hatırlatıcılarından ve yarının koşulsuz hatırlatıcılarından bildirim listesi çıkarır.
///
/// [today] sunucunun bugün için ürettiği listedir; yapılan işler zaten düşmüştür. Geçmiş
/// saatler atlanır. [textFor] başlık/gövdeyi arayüz diline göre verir.
List<PlannedNotification> planNotifications({
  required List<Reminder> today,
  required DateTime now,
  required ({String title, String body}) Function(Reminder r) textFor,
  bool includeTomorrow = true,
  int limit = maxScheduledNotifications,
}) {
  final items = <PlannedNotification>[];

  void addDay(DateTime day, Iterable<Reminder> reminders, {required bool onlyFuture}) {
    for (final r in reminders) {
      final text = textFor(r);
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
        ));
      }
    }
  }

  addDay(now, today, onlyFuture: true);
  if (includeTomorrow) {
    addDay(DateTime(now.year, now.month, now.day + 1), dailyReminderDefaults, onlyFuture: false);
  }

  // Aynı anda gelen bildirimler arasında sıra: önce zaman, sonra kimlik (kararlı).
  items.sort((a, b) {
    final byTime = a.at.compareTo(b.at);
    return byTime != 0 ? byTime : a.reminderId.compareTo(b.reminderId);
  });
  return [
    for (var i = 0; i < items.length && i < limit; i++)
      PlannedNotification(
        id: i + 1,
        at: items[i].at,
        title: items[i].title,
        body: items[i].body,
        reminderId: items[i].reminderId,
        route: items[i].route,
      ),
  ];
}

/// Aynı liste ikinci kez kurulmasın diye parmak izi.
String scheduleSignature(List<PlannedNotification> items) =>
    items.map((n) => '${n.at.millisecondsSinceEpoch}|${n.reminderId}|${n.title}|${n.body}').join('\n');
