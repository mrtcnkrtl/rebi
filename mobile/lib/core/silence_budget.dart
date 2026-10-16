import 'local_store.dart';
import 'notification_actions.dart';
import 'reminder_schedule.dart';
import 'today_plan.dart';

const _storeKey = 'rebi_silence_budget';

/// O günün kalan "doldurulacak" miktarları: su hedefine kaç ml, güneş kremine kaç kez kaldı.
///
/// Uygulama **kapalıyken** bildirimdeki düğmeye ("+500 ml") dokunulunca arka plan izolatında ne plan ne
/// oturum vardır; ama hedef dolduysa o günün kalan su bildirimleri de gelmemeli. Bu yüzden plan her
/// kurulduğunda bu küçük özet diske yazılır ve düğme basılınca oradan okunup düşülür.
class SilenceBudget {
  const SilenceBudget({
    required this.userId,
    required this.day,
    required this.waterRemainingMl,
    required this.spfRemaining,
  });

  /// Planın o anki ilerlemesinden (bekleyen kayıtlar dahil) özet çıkarır.
  factory SilenceBudget.fromPlan(String userId, TodayPlan plan, DateTime now) => SilenceBudget(
        userId: userId,
        day: localDayKey(now),
        waterRemainingMl: (plan.settings.waterTargetMl - plan.progress.waterMl).clamp(0, 1 << 30),
        spfRemaining: (spfRefreshMaxPerDay - plan.progress.spfRefreshes).clamp(0, spfRefreshMaxPerDay),
      );

  /// Diskteki özet; yoksa ya da başka kullanıcı/gün içinse null.
  static SilenceBudget? read({required String userId, required String day}) {
    final j = LocalStore.instance.getJson(_storeKey);
    if (j is! Map || j['user_id'] != userId || j['day'] != day) return null;
    final water = j['water_remaining_ml'];
    final spf = j['spf_remaining'];
    if (water is! num || spf is! num) return null;
    return SilenceBudget(userId: userId, day: day, waterRemainingMl: water.toInt(), spfRemaining: spf.toInt());
  }

  final String userId;
  final String day;
  final int waterRemainingMl;
  final int spfRemaining;

  Future<void> save() => LocalStore.instance.setJson(_storeKey, {
        'user_id': userId,
        'day': day,
        'water_remaining_ml': waterRemainingMl,
        'spf_remaining': spfRemaining,
      });

  /// Düğmenin etkisini düşer. Dönüş: yeni özet ve o günün kalan bildirimleri **susturulması gereken**
  /// hatırlatıcı kimlikleri (hedef doldu / günlük sınıra ulaşıldı).
  ({SilenceBudget budget, Set<String> silenced}) after(String reminderId, ReminderAction action) {
    var water = waterRemainingMl;
    var spf = spfRemaining;
    final silenced = <String>{};
    switch (action.type) {
      case 'water_intake':
        final ml = action.payload['ml'];
        if (ml is num) water = (water - ml.toInt()).clamp(0, 1 << 30);
        if (water == 0) silenced.add('water_intake');
      case 'spf_refresh':
        spf = (spf - 1).clamp(0, spfRefreshMaxPerDay);
        if (spf == 0) silenced.add('spf_refresh');
    }
    return (
      budget: SilenceBudget(userId: userId, day: day, waterRemainingMl: water, spfRemaining: spf),
      silenced: silenced,
    );
  }
}

/// Uygulama kapalıyken bildirim düğmesine dokunulunca çağrılır. Özeti günceller ve o günün kalan
/// bildirimlerinden hangi hatırlatıcılarınkinin iptal edileceğini döner (özet yoksa boş).
Future<Set<String>> silenceAfterAction(NotificationActionTap tap, {required String day}) async {
  if (tap.userId.isEmpty || day.isEmpty) return const {};
  final action = resolveNotificationAction(tap.reminderId, tap.actionId);
  if (action == null) return const {};
  await LocalStore.instance.reload();
  final budget = SilenceBudget.read(userId: tap.userId, day: day);
  if (budget == null) return const {};
  final next = budget.after(tap.reminderId, action);
  await next.budget.save();
  return next.silenced;
}
