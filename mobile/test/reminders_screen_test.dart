import 'dart:convert';

import 'package:flutter/material.dart' show MaterialApp, Scaffold, SizedBox, Size, Switch, Text, TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:rebi/core/i18n.dart';
import 'package:rebi/core/demo_user.dart';
import 'package:rebi/core/reminder_settings.dart';
import 'package:rebi/core/routine_tracking.dart';
import 'package:rebi/screens/reminders_screen.dart';
import 'package:rebi/state/theme_controller.dart';
import 'package:rebi/ui/components/notification_widgets.dart';
import 'package:rebi/ui/widgets/common.dart';

import 'helpers/app_harness.dart';

/// Hatırlatıcı ayarları ekranı (`/dashboard/reminders`): gün düzeni, su aralığı, kategoriler.
void main() {
  final routine = routineFixture['routine'] as List;
  final originalPicker = reminderTimePicker;

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

  Finder saveButton() => find.widgetWithText(PrimaryButton, tr('mobileReminders.save'));
  bool saveEnabled(WidgetTester tester) => tester.widget<PrimaryButton>(saveButton()).onPressed != null;

  void pickTimes(Map<String, TimeOfDay> byCall) {
    var call = 0;
    final answers = byCall.values.toList();
    reminderTimePicker = (context, initial) async => answers[call++ % answers.length];
  }

  tearDown(() => reminderTimePicker = originalPicker);

  group('yükleme', () {
    testWidgets('sunucudaki ayar saatler, su aralığı ve pencerelerle görünür', (tester) async {
      final backend = FakeBackend();
      backend.reminderSettings = {
        ...backend.reminderSettings,
        'wake_time': '06:30',
        'sleep_time': '22:30',
        'water_every_minutes': 90,
        'enabled': {...(backend.reminderSettings['enabled'] as Map), 'lip_balm': false},
      };
      final h = await pumpApp(tester, location: '/dashboard/reminders', backend: backend);

      expect(h.backend.calls('/me/reminder-settings').single.url.queryParameters['user_id'], testUserId);
      expect(find.text(tr('mobileReminders.title')), findsOneWidget);
      expect(find.text('06:30'), findsOneWidget);
      expect(find.text('22:30'), findsOneWidget);
      expect(find.text(tr('mobileReminders.categories.water.title')), findsOneWidget);
      // Uyanma 06:30 → sabah rutini 06:30–08:30; uyku 22:30 → akşam rutini 20:30–22:30.
      final windows = '${tr('mobileReminders.window', {'start': '06:30', 'end': '08:30'})} · '
          '${tr('mobileReminders.window', {'start': '20:30', 'end': '22:30'})}';
      expect(find.text(windows), findsOneWidget);
      final every = tr('mobileReminders.water.every.90');
      expect(find.text(tr('mobileReminders.windowEvery', {'start': '08:00', 'end': '20:30', 'every': every})), findsOneWidget);
      expect(saveEnabled(tester), isFalse, reason: 'değişiklik yokken kaydet kapalı');
    });

    testWidgets('yükleme hatasında uyarı çıkar, tekrar denenince gelir', (tester) async {
      final backend = FakeBackend()..reminderSettingsFails = true;
      final h = await pumpApp(tester, location: '/dashboard/reminders', backend: backend);
      expect(find.text(tr('mobileReminders.loadFailed')), findsOneWidget);
      expect(saveButton(), findsNothing);

      h.backend.reminderSettingsFails = false;
      await tapText(tester, tr('mobileReminders.retry'));
      expect(find.text(tr('mobileReminders.loadFailed')), findsNothing);
      expect(find.text('07:30'), findsOneWidget);
    });

    testWidgets('demo hesapta ayar sunucuya yazılmayacağı söylenir, form yoktur', (tester) async {
      final h = await pumpApp(tester, location: '/dashboard/reminders', user: fakeUser(id: demoUserId));
      expect(find.text(tr('mobileReminders.notSynced')), findsOneWidget);
      expect(saveButton(), findsNothing);
      expect(h.backend.calls('/me/reminder-settings'), isEmpty);
    });
  });

  group('düzenleme ve kaydetme', () {
    testWidgets('uyanma saati değişince pencereler kayar, kaydedince sunucuya gider ve bildirimler yeniden kurulur',
        (tester) async {
      pickTimes({'wake': const TimeOfDay(hour: 6, minute: 0)});
      final h = await pumpApp(tester, location: '/dashboard/reminders');
      final planCalls = h.backend.calls('/today/plan').length;

      await tapText(tester, tr('mobileReminders.day.wake'));
      expect(find.text('06:00'), findsOneWidget);
      expect(
        find.text('${tr('mobileReminders.window', {'start': '06:00', 'end': '08:00'})} · '
            '${tr('mobileReminders.window', {'start': '21:00', 'end': '23:00'})}'),
        findsOneWidget,
        reason: 'sabah penceresi uyanmaya göre, akşam penceresi uykuya göre',
      );
      expect(saveEnabled(tester), isTrue);

      await tapText(tester, tr('mobileReminders.save'));
      await settle(tester);
      final body = h.backend.bodyOf('/me/reminder-settings');
      expect(body['user_id'], testUserId);
      expect(body['wake_time'], '06:00');
      expect(body['sleep_time'], '23:00');
      expect(body['water_every_minutes'], 120);
      expect((body['enabled'] as Map).keys, reminderCategories);
      expect(find.text(tr('mobileReminders.saved')), findsOneWidget);
      expect(saveEnabled(tester), isFalse, reason: 'kaydedilen ayar artık değişiklik sayılmaz');
      expect(h.backend.calls('/today/plan').length, greaterThan(planCalls), reason: 'plan yeni saatlerle yeniden alınır');
    });

    testWidgets('su aralığı ve kategori anahtarı kaydedilir', (tester) async {
      final h = await pumpApp(tester, location: '/dashboard/reminders');

      await tapText(tester, tr('mobileReminders.water.every.180'));
      // Anahtarlar kategori sırasıyla: rutin, su, makyaj, beslenme, güneş kremi, dudak balsamı, check-in.
      final spfSwitch = find.byType(Switch).at(4);
      await tapFinder(tester, spfSwitch);
      expect(saveEnabled(tester), isTrue);

      await tapText(tester, tr('mobileReminders.save'));
      final body = h.backend.bodyOf('/me/reminder-settings');
      expect(body['water_every_minutes'], 180);
      expect((body['enabled'] as Map)['spf'], isFalse);
      expect((body['enabled'] as Map)['water'], isTrue);
      expect(h.backend.reminderSettings['water_every_minutes'], 180);
    });

    testWidgets('değişiklik geri alınınca kaydet yine kapanır', (tester) async {
      await pumpApp(tester, location: '/dashboard/reminders');
      await tapText(tester, tr('mobileReminders.water.every.60'));
      expect(saveEnabled(tester), isTrue);
      await tapText(tester, tr('mobileReminders.water.every.120'));
      expect(saveEnabled(tester), isFalse);
    });

    testWidgets('uyanma ile uyku arası 9 saatten kısaysa uyarı çıkar ve kaydedilemez', (tester) async {
      pickTimes({'sleep': const TimeOfDay(hour: 15, minute: 0)});
      final h = await pumpApp(tester, location: '/dashboard/reminders');

      await tapText(tester, tr('mobileReminders.day.sleep'));
      expect(find.text(tr('mobileReminders.errors.span')), findsOneWidget);
      expect(saveEnabled(tester), isFalse);

      await tapText(tester, tr('mobileReminders.save'));
      expect(h.backend.calls('/me/reminder-settings').where((r) => r.method == 'PUT'), isEmpty);
    });

    testWidgets('saat seçici kapatılırsa hiçbir şey değişmez', (tester) async {
      reminderTimePicker = (context, initial) async => null;
      await pumpApp(tester, location: '/dashboard/reminders');
      await tapText(tester, tr('mobileReminders.day.wake'));
      expect(find.text('07:30'), findsOneWidget);
      expect(saveEnabled(tester), isFalse);
    });

    testWidgets('sunucu reddederse nedeni gösterilir ve değişiklik korunur', (tester) async {
      final backend = FakeBackend()
        ..reminderSettingsPutStatus = 422
        ..reminderSettingsPutDetail = 'Su aralığı geçersiz.';
      await pumpApp(tester, location: '/dashboard/reminders', backend: backend);
      await tapText(tester, tr('mobileReminders.water.every.60'));
      await tapText(tester, tr('mobileReminders.save'));

      expect(find.text('Su aralığı geçersiz.'), findsOneWidget);
      expect(saveEnabled(tester), isTrue, reason: 'tekrar denenebilir');
      expect(find.text(tr('mobileReminders.saved')), findsNothing);
    });

    testWidgets('ağ ya da sunucu hatasında genel mesaj çıkar', (tester) async {
      final backend = FakeBackend()..reminderSettingsPutStatus = 502;
      await pumpApp(tester, location: '/dashboard/reminders', backend: backend);
      await tapText(tester, tr('mobileReminders.water.every.60'));
      await tapText(tester, tr('mobileReminders.save'));
      expect(find.text(tr('mobileReminders.saveFailed')), findsOneWidget);
    });
  });

  group('erişim', () {
    testWidgets('profildeki satır ayar ekranına götürür', (tester) async {
      // Tam Profil ekranı Supabase ister; satırın kendisi yönlendirmeyle birlikte denenir.
      await pumpStandalone(tester, (theme) => const SizedBox.shrink());
      final router = GoRouter(routes: [
        GoRoute(path: '/', builder: (context, state) => Scaffold(body: ReminderSettingsLink(theme: rebiThemes['teal']!))),
        GoRoute(path: '/dashboard/reminders', builder: (context, state) => const Text('AYAR EKRANI')),
      ]);
      await tester.pumpWidget(ChangeNotifierProvider<I18n>.value(
        value: I18n.instance,
        child: MaterialApp.router(routerConfig: router),
      ));
      expect(find.text(tr('mobileReminders.open')), findsOneWidget);
      expect(find.text(tr('mobileReminders.openHint')), findsOneWidget);

      await tester.tap(find.text(tr('mobileReminders.open')));
      await settle(tester, 4);
      expect(find.text('AYAR EKRANI'), findsOneWidget);
    });

    testWidgets('Bugün ekranındaki ayar simgesinden açılır', (tester) async {
      final h = await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs());
      await tapFinder(tester, find.byTooltip(tr('mobileToday.settings')));
      expect(h.router.state.uri.path, '/dashboard/reminders');
    });

    for (final lang in ['tr', 'en']) {
      testWidgets('320×568 çizilir ve taşmaz ($lang)', (tester) async {
        await pumpApp(tester, location: '/dashboard/reminders', size: const Size(320, 568), lang: lang);
        expect(find.text(tr('mobileReminders.title')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
