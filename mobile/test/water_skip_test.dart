import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/core/notification_actions.dart';
import 'package:rebi/core/routine_tracking.dart';
import 'package:rebi/core/today_plan.dart';
import 'package:rebi/screens/today/today_clock.dart';

import 'helpers/app_harness.dart';
import 'helpers/notification_fakes.dart';

/// Su hatırlatmasına "İçtim" / "İçmedim" cevabı: ilerleme modeli ve Bugün ekranındaki yansıması. (Bildirim düğmeleri:
/// `notification_actions_test`, sunucu tarafı: `backend/tests/test_push_actions.py`.)
void main() {
  group('DayProgress · içmedim sayısı', () {
    test('sunucu özetinden okunur; yoksa 0', () {
      expect(DayProgress.fromJson({'water_skips': 3}).waterSkips, 3);
      expect(DayProgress.fromJson({}).waterSkips, 0);
      expect(DayProgress.fromJson(null).waterSkips, 0);
    });

    test('"water_skipped" olayı yalnızca sayıyı artırır; su toplamı değişmez (gönderilmemiş olay da böyle gösterilir)', () {
      var p = const DayProgress(waterMl: 500);
      p = p.withEvent('water_skipped', const {});
      p = p.withEvent('water_skipped', const {});

      expect(p.waterSkips, 2);
      expect(p.waterMl, 500);
    });

    test('"İçtim" (250 ml) su toplamını artırır, içmedim sayısına dokunmaz', () {
      final p = const DayProgress(waterSkips: 1).withEvent('water_intake', const {'ml': 250});
      expect((p.waterMl, p.waterSkips), (250, 1));
    });
  });

  group('Bugün ekranı · su kutusu', () {
    final routine = routineFixture['routine'] as List;
    Map<String, Object> acceptedPrefs() => {
          trackAcceptedKey(testUserId): '1',
          trackSnapshotKey(testUserId): jsonEncode({
            'routine': routine,
            'userName': 'Ayşe Test',
            'weather': routineFixture['weather'],
            'flowDebug': routineFixture['flow_debug'],
            'acceptedAt': DateTime.now().millisecondsSinceEpoch - 3 * 86400000,
          }),
        };

    FakeBackend withWaterReminder() {
      final b = FakeBackend();
      b.todayPlan = {
        ...b.todayPlan,
        'has_routine': true,
        'reminders': [
          {'id': 'water_intake', 'title': 'Su içme zamanı', 'body': 'Bir bardak su', 'start': '09:00', 'end': '21:00', 'every_minutes': 120, 'log_event': 'water_intake'},
        ],
      };
      return b;
    }

    setUp(() => todayPanelClock = () => DateTime(2026, 10, 10, 9, 15));
    tearDown(() => todayPanelClock = DateTime.now);

    testWidgets('hiç "içmedim" denmediyse satır yok', (tester) async {
      await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs(), backend: withWaterReminder());
      expect(find.textContaining('“içmedim”'), findsNothing);
    });

    testWidgets('sunucudaki "içmedim" sayısı su kutusunda görünür; su toplamı değişmez', (tester) async {
      final b = withWaterReminder();
      b.todayPlan = {
        ...b.todayPlan,
        'progress': {'water_skips': 2},
      };
      await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs(), backend: b);

      expect(find.text(tr('mobileToday.water.skipped', {'n': 2})), findsOneWidget);
      expect(find.text(tr('mobileToday.waterProgress', {'ml': 0, 'target': 2000})), findsOneWidget, reason: 'içmedim suyu değiştirmez');
    });

    testWidgets('uygulama açıkken bildirimden "İçmedim"e dokunulunca olay yazılır ve su kutusu hemen güncellenir', (tester) async {
      final notifier = FakeReminderNotifier();
      final h = await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs(), backend: withWaterReminder(), notifier: notifier);
      expect(find.textContaining('“içmedim”'), findsNothing);

      notifier.tapAction(const NotificationActionTap(reminderId: 'water_intake', actionId: 'water_intake:waterNo', userId: testUserId));
      await settle(tester);

      expect(h.backend.bodyOf('/daily_tracking/ingest')['type'], 'water_skipped');
      expect(find.text(tr('mobileToday.water.skipped', {'n': 1})), findsOneWidget);
      expect(find.text(tr('mobileToday.waterProgress', {'ml': 0, 'target': 2000})), findsOneWidget);
    });

    testWidgets('"İçtim" bir bardak su ekler', (tester) async {
      final notifier = FakeReminderNotifier();
      final h = await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs(), backend: withWaterReminder(), notifier: notifier);

      notifier.tapAction(const NotificationActionTap(reminderId: 'water_intake', actionId: 'water_intake:waterYes', userId: testUserId));
      await settle(tester);

      expect(h.backend.bodyOf('/daily_tracking/ingest')['payload'], {'ml': 250});
      expect(find.text(tr('mobileToday.waterProgress', {'ml': 250, 'target': 2000})), findsOneWidget);
    });

    testWidgets('hedef dolunca "içmedim" satırı kalkar (hedefe ulaşıldı mesajı yeter)', (tester) async {
      final b = withWaterReminder()..waterMl = 2000;
      b.todayPlan = {
        ...b.todayPlan,
        'progress': {'water_skips': 2},
      };
      await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs(), backend: b);

      expect(find.text(tr('mobileToday.waterGoalReached')), findsOneWidget);
      expect(find.text(tr('mobileToday.water.skipped', {'n': 2})), findsNothing);
    });

    testWidgets('İngilizce arayüzde satır İngilizce', (tester) async {
      final b = withWaterReminder();
      b.todayPlan = {
        ...b.todayPlan,
        'progress': {'water_skips': 1},
      };
      await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs(), backend: b, lang: 'en');

      expect(find.text(tr('mobileToday.water.skipped', {'n': 1})), findsOneWidget);
      expect(tr('mobileToday.water.skipped', {'n': 1}), contains("I didn't"));
    });
  });
}
