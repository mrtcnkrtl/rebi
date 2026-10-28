import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart' show MaterialApp, Scaffold, Scrollable, SizedBox, Size, Switch, Text, TimeOfDay;
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
import 'helpers/notification_fakes.dart';

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

    testWidgets('günlük su hedefi seçilir ve kaydedilir', (tester) async {
      final h = await pumpApp(tester, location: '/dashboard/reminders');
      expect(find.text(tr('mobileReminders.waterTarget.title')), findsOneWidget);

      await tapText(tester, tr('mobileReminders.waterTarget.choice', {'liters': '2,5'}));
      await tapText(tester, tr('mobileReminders.save'));

      expect(h.backend.bodyOf('/me/reminder-settings')['water_target_ml'], 2500);
      expect(h.backend.reminderSettings['water_target_ml'], 2500);
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

  group('kendi saat aralığın', () {
    String sheetTitle() => tr('mobileReminders.windowSheet.title');
    Finder closeSheet() => find.text(tr('mobileReminders.windowSheet.done'));

    testWidgets('kategoriye dokunmak saat sayfasını açar; seçilen aralık satırda "senin ayarın" olarak görünür ve kaydedilir',
        (tester) async {
      pickTimes({'start': const TimeOfDay(hour: 15, minute: 0)});
      final h = await pumpApp(tester, location: '/dashboard/reminders');

      await tapText(tester, tr('mobileReminders.categories.lip_balm.title'));
      expect(find.text(sheetTitle()), findsOneWidget);
      expect(find.text(tr('mobileReminders.windowSheet.ids.lip_balm')), findsWidgets, reason: 'satır başlığı');
      expect(find.text('12:00'), findsOneWidget, reason: 'varsayılan 12:00–13:00');

      await tapText(tester, tr('mobileReminders.windowSheet.start'));
      expect(find.text('15:00'), findsOneWidget);
      expect(find.text('16:00'), findsOneWidget, reason: 'başlangıç bitişe yaklaşınca bitiş bir saat ileri alınır');
      expect(find.text(tr('mobileReminders.windowSheet.custom')), findsOneWidget);
      expect(saveEnabled(tester), isTrue, reason: 'sayfa açıkken ekranın taslağı da güncellenir');

      await tapFinder(tester, closeSheet());
      expect(find.textContaining(tr('mobileReminders.window', {'start': '15:00', 'end': '16:00'})), findsOneWidget);
      expect(find.textContaining(tr('mobileReminders.windowSheet.custom')), findsOneWidget);

      await tapText(tester, tr('mobileReminders.save'));
      final body = h.backend.bodyOf('/me/reminder-settings');
      expect((body['windows'] as Map)['lip_balm'], {'start': '15:00', 'end': '16:00'});
      expect((body['windows'] as Map)['routine_morning'], isNull);
      expect(h.backend.reminderSettings['windows'], {'lip_balm': {'start': '15:00', 'end': '16:00'}});
    });

    testWidgets('birden çok hatırlatıcılı kategoride her biri ayrı ayrı ayarlanır', (tester) async {
      pickTimes({'start': const TimeOfDay(hour: 8, minute: 0)});
      await pumpApp(tester, location: '/dashboard/reminders');

      await tapText(tester, tr('mobileReminders.categories.routine.title'));
      expect(find.text(tr('mobileReminders.windowSheet.ids.routine_morning')), findsOneWidget);
      expect(find.text(tr('mobileReminders.windowSheet.ids.routine_evening')), findsOneWidget);

      // İlk "Başlangıç" kutusu sabah rutinine ait: 07:30–09:30 → 08:00–09:30.
      await tapFinder(tester, find.text(tr('mobileReminders.windowSheet.start')).first);
      expect(find.text('08:00'), findsOneWidget);
      expect(find.text(tr('mobileReminders.windowSheet.custom')), findsOneWidget, reason: 'yalnızca sabah rutini özelleşti');
      expect(find.text(tr('mobileReminders.windowSheet.reset')), findsOneWidget);
    });

    testWidgets('çok kısa aralık ve gün dışı aralık reddedilir, taslak değişmez', (tester) async {
      pickTimes({'end': const TimeOfDay(hour: 12, minute: 5)});
      await pumpApp(tester, location: '/dashboard/reminders');
      await tapText(tester, tr('mobileReminders.categories.lip_balm.title'));

      await tapText(tester, tr('mobileReminders.windowSheet.end'));
      expect(find.text(tr('mobileReminders.windowSheet.errors.short', {'minutes': '15'})), findsOneWidget);
      expect(saveEnabled(tester), isFalse);
      expect(find.text(tr('mobileReminders.windowSheet.custom')), findsNothing);

      pickTimes({'start': const TimeOfDay(hour: 5, minute: 0)});
      await tapText(tester, tr('mobileReminders.windowSheet.start'));
      expect(
        find.text(tr('mobileReminders.windowSheet.errors.outsideDay', {'wake': '07:30', 'sleep': '23:00'})),
        findsOneWidget,
      );
      expect(saveEnabled(tester), isFalse);
    });

    testWidgets('"varsayılana dön" özel aralığı kaldırır; varsayılanla aynı seçim özel sayılmaz', (tester) async {
      pickTimes({'start': const TimeOfDay(hour: 15, minute: 0)});
      await pumpApp(tester, location: '/dashboard/reminders');
      await tapText(tester, tr('mobileReminders.categories.lip_balm.title'));
      await tapText(tester, tr('mobileReminders.windowSheet.start'));
      expect(saveEnabled(tester), isTrue);

      await tapText(tester, tr('mobileReminders.windowSheet.reset'));
      expect(find.text('12:00'), findsOneWidget);
      expect(find.text(tr('mobileReminders.windowSheet.custom')), findsNothing);
      expect(saveEnabled(tester), isFalse, reason: 'başa dönüldü: kaydedilecek bir şey yok');

      pickTimes({'start': const TimeOfDay(hour: 12, minute: 0)});
      await tapText(tester, tr('mobileReminders.windowSheet.start'));
      expect(find.text(tr('mobileReminders.windowSheet.custom')), findsNothing);
      expect(saveEnabled(tester), isFalse);
    });

    testWidgets('güneş kremi sayfası UV notunu gösterir; kendi saati seçilince not kalkar', (tester) async {
      pickTimes({'start': const TimeOfDay(hour: 10, minute: 0)});
      await pumpApp(tester, location: '/dashboard/reminders');
      await tapText(tester, tr('mobileReminders.categories.spf.title'));
      expect(find.text(tr('mobileReminders.windowSheet.spfNote')), findsOneWidget);

      await tapText(tester, tr('mobileReminders.windowSheet.start'));
      expect(find.text(tr('mobileReminders.windowSheet.spfNote')), findsNothing);
    });

    testWidgets('sunucudan gelen özel aralık ve sessiz saat ekranda görünür', (tester) async {
      final backend = FakeBackend();
      backend.reminderSettings = {
        ...backend.reminderSettings,
        'windows': {'lip_balm': {'start': '14:00', 'end': '14:45'}},
        'quiet': {'start': '22:00', 'end': '07:00'},
      };
      await pumpApp(tester, location: '/dashboard/reminders', backend: backend);

      expect(find.textContaining(tr('mobileReminders.window', {'start': '14:00', 'end': '14:45'})), findsOneWidget);
      expect(find.text('22:00'), findsOneWidget, reason: 'sessiz saat başlangıcı');
      expect(find.text('07:00'), findsOneWidget, reason: 'sessiz saat bitişi (gece yarısını aşar)');
    });
  });

  group('sessiz saatler', () {
    Finder quietSwitch() => find.byType(Switch).last;

    testWidgets('anahtar açılınca önerilen aralık gelir; saatler seçilir ve kaydedilir; kapatınca silinir', (tester) async {
      pickTimes({'end': const TimeOfDay(hour: 14, minute: 0)});
      final h = await pumpApp(tester, location: '/dashboard/reminders');
      expect(find.text(tr('mobileReminders.quiet.title')), findsOneWidget);
      expect(find.text(tr('mobileReminders.quiet.from')), findsNothing, reason: 'kapalıyken saat kutuları yok');

      await tapFinder(tester, quietSwitch());
      expect(find.text(tr('mobileReminders.quiet.from')), findsOneWidget);
      expect(find.text('12:00'), findsOneWidget);
      expect(find.text('13:00'), findsOneWidget);
      expect(saveEnabled(tester), isTrue);

      await tapText(tester, tr('mobileReminders.quiet.to'));
      expect(find.text('14:00'), findsOneWidget);
      await tapText(tester, tr('mobileReminders.save'));
      expect(h.backend.bodyOf('/me/reminder-settings')['quiet'], {'start': '12:00', 'end': '14:00'});

      await tapFinder(tester, quietSwitch());
      expect(find.text(tr('mobileReminders.quiet.from')), findsNothing);
      await tapText(tester, tr('mobileReminders.save'));
      expect(h.backend.bodyOf('/me/reminder-settings')['quiet'], isNull);
      expect(h.backend.reminderSettings['quiet'], isNull);
    });

    testWidgets('başlangıç ile bitiş aynı olamaz', (tester) async {
      pickTimes({'end': const TimeOfDay(hour: 12, minute: 0)});
      await pumpApp(tester, location: '/dashboard/reminders');
      await tapFinder(tester, quietSwitch());
      await tapText(tester, tr('mobileReminders.quiet.to'));

      expect(find.text(tr('mobileReminders.quiet.errors.same')), findsOneWidget);
      expect(find.text('13:00'), findsOneWidget, reason: 'bitiş değişmedi');
    });

    testWidgets('gece yarısını aşan aralık seçilebilir', (tester) async {
      pickTimes({'start': const TimeOfDay(hour: 22, minute: 0), 'end': const TimeOfDay(hour: 7, minute: 0)});
      final h = await pumpApp(tester, location: '/dashboard/reminders');
      await tapFinder(tester, quietSwitch());
      await tapText(tester, tr('mobileReminders.quiet.from'));
      await tapText(tester, tr('mobileReminders.quiet.to'));
      await tapText(tester, tr('mobileReminders.save'));

      expect(h.backend.bodyOf('/me/reminder-settings')['quiet'], {'start': '22:00', 'end': '07:00'});
    });
  });

  group('bildirimler gelmiyor mu?', () {
    Finder testButton() => find.text(tr('mobileNotifications.delivery.test'));

    // `runAsync` değil: denetleyicinin sırası sahte zamanlayıcıda başladığı için ancak çizim döngüsüyle ilerler.
    Future<void> enableNotifications(WidgetTester tester, Harness h) async {
      unawaited(h.notifications.enable());
      await settle(tester);
    }

    testWidgets('bildirimler kapalıysa kart görünmez', (tester) async {
      await pumpApp(tester, location: '/dashboard/reminders', notifier: FakeReminderNotifier());
      expect(find.text(tr('mobileNotifications.delivery.title')), findsNothing);
    });

    testWidgets('bildirimler telefonda planlanıyorsa test düğmesi ve pil ipucu görünür; test bildirimi kurulur', (tester) async {
      final notifier = FakeReminderNotifier();
      final h = await pumpApp(tester, location: '/dashboard/reminders', notifier: notifier);
      await enableNotifications(tester, h);

      expect(find.text(tr('mobileNotifications.delivery.title')), findsOneWidget);
      expect(find.text(tr('mobileNotifications.delivery.batteryTitle')), findsOneWidget, reason: 'Android varsayılan test platformu');

      await tapFinder(tester, testButton());
      await settle(tester);
      expect(notifier.tests, hasLength(1));
      expect(find.text(tr('mobileNotifications.delivery.testScheduled')), findsOneWidget);
    });

    testWidgets('izin geri alınmışsa test için önce izin verilmesi söylenir', (tester) async {
      final notifier = FakeReminderNotifier();
      final h = await pumpApp(tester, location: '/dashboard/reminders', notifier: notifier);
      await enableNotifications(tester, h);

      notifier.permission = false;
      await tapFinder(tester, testButton());
      await settle(tester);

      expect(notifier.tests, isEmpty);
      expect(find.text(tr('mobileNotifications.blocked')), findsWidgets, reason: 'izin uyarısı bildirim kartında');
    });

    testWidgets('test kurulamazsa hata mesajı gösterilir', (tester) async {
      final notifier = FakeReminderNotifier()..testSucceeds = false;
      final h = await pumpApp(tester, location: '/dashboard/reminders', notifier: notifier);
      await enableNotifications(tester, h);

      await tapFinder(tester, testButton());
      await settle(tester);
      expect(find.text(tr('mobileNotifications.delivery.testFailed')), findsOneWidget);
    });

    testWidgets('sunucu push\'u gönderiyorsa kart görünmez (telefonun pil ayarı önemsiz)', (tester) async {
      final backend = FakeBackend()..pushConfigured = true;
      final notifier = FakeReminderNotifier();
      final h = await pumpApp(tester, location: '/dashboard/reminders', backend: backend, notifier: notifier, push: FakePushClient());
      await enableNotifications(tester, h);

      expect(h.notifications.pushActive, isTrue);
      expect(find.text(tr('mobileNotifications.delivery.title')), findsNothing);
    });
  });

  group('320 px ve büyük yazı', () {
    for (final lang in ['tr', 'en']) {
      testWidgets('saat sayfası ve sessiz saat kartı taşmaz ($lang, %200 yazı)', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2.0;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final backend = FakeBackend();
        backend.reminderSettings = {
          ...backend.reminderSettings,
          'quiet': {'start': '22:00', 'end': '07:00'},
          'windows': {'routine_morning': {'start': '08:00', 'end': '09:00'}},
        };
        await pumpApp(tester, location: '/dashboard/reminders', backend: backend, size: const Size(320, 640), lang: lang);
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -2400));
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException()?.toString(), isNull);

        await tester.drag(find.byType(Scrollable).first, const Offset(0, 2400));
        await tester.pump(const Duration(milliseconds: 300));
        await tapText(tester, tr('mobileReminders.categories.routine.title'));
        expect(find.text(tr('mobileReminders.windowSheet.title')), findsOneWidget);
        expect(tester.takeException()?.toString(), isNull);
      });
    }
  });
}
