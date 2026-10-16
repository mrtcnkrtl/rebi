import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/core/local_store.dart';
import 'package:rebi/core/notification_actions.dart';
import 'package:rebi/core/silence_budget.dart';
import 'package:rebi/core/today_plan.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Uygulama kapalıyken bildirim düğmesine basılınca günün kalan bildirimlerini susturma kuralı.
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalStore.init();
  });

  NotificationActionTap tap(String reminderId, String action, {String user = 'u1'}) =>
      NotificationActionTap(reminderId: reminderId, actionId: '$reminderId:$action', userId: user);

  TodayPlan plan({int water = 0, int spf = 0, int target = 2000}) => TodayPlan.fromJson({
        'log_date': '2026-10-10',
        'progress': {'water_ml_total': water, 'spf_refreshes': spf},
        'reminder_settings': {'water_target_ml': target},
      });

  final now = DateTime(2026, 10, 10, 15, 30);

  test('plandan kalan su ve güneş kremi hakkı çıkarılır; hedefi aşan sıfıra iner', () {
    final b = SilenceBudget.fromPlan('u1', plan(water: 750, spf: 1, target: 2500), now);
    expect((b.day, b.waterRemainingMl, b.spfRemaining), ('2026-10-10', 1750, 1));

    final over = SilenceBudget.fromPlan('u1', plan(water: 9000, spf: 7), now);
    expect((over.waterRemainingMl, over.spfRemaining), (0, 0));
  });

  test('su düğmesi kalanı düşer; hedef dolunca su hatırlatıcısı susturulur', () {
    final b = SilenceBudget.fromPlan('u1', plan(water: 1500), now);
    final a250 = resolveNotificationAction('water_intake', 'water_intake:water250')!;
    final a500 = resolveNotificationAction('water_intake', 'water_intake:water500')!;

    final first = b.after('water_intake', a250);
    expect(first.budget.waterRemainingMl, 250);
    expect(first.silenced, isEmpty);

    final second = first.budget.after('water_intake', a500);
    expect(second.budget.waterRemainingMl, 0, reason: 'taşan miktar negatife düşmez');
    expect(second.silenced, {'water_intake'});
  });

  test('güneş kremi düğmesi günlük sınıra ulaşınca susturur', () {
    final b = SilenceBudget.fromPlan('u1', plan(spf: 1), now);
    final done = resolveNotificationAction('spf_refresh', 'spf_refresh:done')!;
    final r = b.after('spf_refresh', done);
    expect(r.budget.spfRemaining, 0);
    expect(r.silenced, {'spf_refresh'});
    expect(SilenceBudget.fromPlan('u1', plan(), now).after('spf_refresh', done).silenced, isEmpty, reason: 'ilk tazeleme: ikincisi kalır');
  });

  test('diğer düğmeler hiçbir şeyi susturmaz', () {
    final b = SilenceBudget.fromPlan('u1', plan(), now);
    for (final (id, action) in const [('routine_morning', 'done'), ('makeup_log', 'yes'), ('nutrition_log', 'junkNo')]) {
      expect(b.after(id, resolveNotificationAction(id, '$id:$action')!).silenced, isEmpty, reason: id);
    }
  });

  test('diske yazılır, aynı kullanıcı ve gün için geri okunur; başkası için okunmaz', () async {
    await SilenceBudget.fromPlan('u1', plan(water: 500, spf: 2), now).save();

    final back = SilenceBudget.read(userId: 'u1', day: '2026-10-10')!;
    expect((back.waterRemainingMl, back.spfRemaining), (1500, 0));
    expect(SilenceBudget.read(userId: 'u2', day: '2026-10-10'), isNull);
    expect(SilenceBudget.read(userId: 'u1', day: '2026-10-11'), isNull, reason: 'dünün özeti bugüne geçmez');
  });

  test('bozuk kayıt okunmaz', () async {
    await LocalStore.instance.setString('rebi_silence_budget', '{bozuk');
    expect(SilenceBudget.read(userId: 'u1', day: '2026-10-10'), isNull);
    await LocalStore.instance.setJson('rebi_silence_budget', {'user_id': 'u1', 'day': '2026-10-10', 'water_remaining_ml': 'x'});
    expect(SilenceBudget.read(userId: 'u1', day: '2026-10-10'), isNull);
  });

  group('silenceAfterAction (arka plan izolatının kullandığı)', () {
    test('hedef dolunca o günün su bildirimlerinin iptal edileceğini söyler ve özeti günceller', () async {
      await SilenceBudget.fromPlan('u1', plan(water: 1700), now).save();

      expect(await silenceAfterAction(tap('water_intake', 'water250'), day: '2026-10-10'), isEmpty);
      expect(SilenceBudget.read(userId: 'u1', day: '2026-10-10')!.waterRemainingMl, 50, reason: 'kalan 300 - 250');
      expect(await silenceAfterAction(tap('water_intake', 'water250'), day: '2026-10-10'), {'water_intake'});
      expect(SilenceBudget.read(userId: 'u1', day: '2026-10-10')!.waterRemainingMl, 0);
    });

    test('özet yoksa, başka kullanıcı ya da gün için ise, düğme bilinmiyorsa hiçbir şeyi susturmaz', () async {
      expect(await silenceAfterAction(tap('water_intake', 'water500'), day: '2026-10-10'), isEmpty, reason: 'özet yok');

      await SilenceBudget.fromPlan('u1', plan(water: 1900), now).save();
      expect(await silenceAfterAction(tap('water_intake', 'water500', user: 'u2'), day: '2026-10-10'), isEmpty);
      expect(await silenceAfterAction(tap('water_intake', 'water500'), day: '2026-10-09'), isEmpty);
      expect(await silenceAfterAction(tap('water_intake', 'uydurma'), day: '2026-10-10'), isEmpty);
      expect(await silenceAfterAction(tap('water_intake', 'water500'), day: ''), isEmpty, reason: 'eski bildirimde gün yok');
      expect(SilenceBudget.read(userId: 'u1', day: '2026-10-10')!.waterRemainingMl, 100, reason: 'hiçbiri özeti değiştirmedi');
    });
  });
}
