import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/core/routine_tracking.dart';
import 'package:rebi/screens/reminders/time_picker.dart';
import 'package:rebi/ui/tw.dart';

import 'helpers/app_harness.dart';
import 'helpers/notification_fakes.dart';
import 'helpers/visual.dart';

/// İlk rutin sonrası karşılama: rutini kabul, gün saatleri, bildirim izni.
Map<String, dynamic> _nav() => {
  'routine': routineFixture['routine'],
  'flowDebug': routineFixture['flow_debug'],
  'weather': routineFixture['weather'],
  'userName': 'Ayşe Yılmaz',
  'concern': 'acne',
};

void main() {
  final originalPicker = reminderTimePicker;
  tearDown(() => reminderTimePicker = originalPicker);

  testWidgets('üç adım: kabul → saatler → bildirim izni → Bugün', (tester) async {
    final notifier = FakeReminderNotifier(permission: false);
    final h = await pumpApp(tester, location: '/dashboard/welcome', extra: _nav(), notifier: notifier);

    expect(find.text('Rutinin hazır, Ayşe.'), findsOneWidget);
    expect(find.text('sabah adımı'), findsOneWidget);
    expect(isRoutineTrackingAccepted(testUserId), isFalse);

    await tester.tap(find.text('Takibe başla'));
    await tester.pumpAndSettle();
    expect(isRoutineTrackingAccepted(testUserId), isTrue, reason: 'ilk adım rutini kabul eder');
    expect(find.text('Günün kaçta başlıyor?'), findsOneWidget);

    reminderTimePicker = (context, initial) async => const TimeOfDay(hour: 6, minute: 45);
    await tester.tap(find.text('Uyanış'));
    await tester.pumpAndSettle();
    expect(find.text('06:45'), findsOneWidget);

    await tester.tap(find.text('Devam'));
    await tester.pumpAndSettle();
    expect(h.backend.reminderSettings['wake_time'], '06:45', reason: 'saat sunucuya yazıldı');
    expect(find.text('Hatırlatayım mı?'), findsOneWidget);
    // Örnek bildirimler seçilen saatlerden hesaplanır: sabah rutini uyanışla başlar.
    expect(find.text('06:45'), findsOneWidget);

    await tester.tap(find.text('Bildirimleri aç'));
    await tester.pumpAndSettle();
    expect(notifier.permissionRequests, 1);
    expect(h.router.routeInformationProvider.value.uri.path, '/dashboard');
  });

  testWidgets('"Önce planı incele" rutini kabul etmeden plana götürür', (tester) async {
    final h = await pumpApp(tester, location: '/dashboard/welcome', extra: _nav());
    await tester.tap(find.text('Önce planı incele'));
    await tester.pumpAndSettle();
    expect(isRoutineTrackingAccepted(testUserId), isFalse);
    expect(h.router.routeInformationProvider.value.uri.path, '/dashboard');
  });

  testWidgets('bildirim desteklenmiyorsa iki adımda biter; geçersiz gün düzeni ilerletmez', (tester) async {
    final h = await pumpApp(tester, location: '/dashboard/welcome', extra: _nav());
    await tester.tap(find.text('Takibe başla'));
    await tester.pumpAndSettle();

    reminderTimePicker = (context, initial) async => const TimeOfDay(hour: 18, minute: 0);
    await tester.tap(find.text('Uyanış'));
    await tester.pumpAndSettle();
    expect(find.textContaining('en az 9 saat'), findsOneWidget);
    await tester.tap(find.text('Devam'));
    await tester.pumpAndSettle();
    expect(find.text('Günün kaçta başlıyor?'), findsOneWidget, reason: 'geçersiz düzende düğme kapalı');

    reminderTimePicker = (context, initial) async => const TimeOfDay(hour: 7, minute: 0);
    await tester.tap(find.text('Uyanış'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Devam'));
    await tester.pumpAndSettle();
    expect(h.router.routeInformationProvider.value.uri.path, '/dashboard');
  });

  testWidgets('"Atla" ikinci adımdan doğrudan Bugün\'e götürür', (tester) async {
    final h = await pumpApp(tester, location: '/dashboard/welcome', extra: _nav(), notifier: FakeReminderNotifier());
    expect(find.text('Atla'), findsOneWidget);
    await tester.tap(find.text('Takibe başla'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Atla'));
    await tester.pumpAndSettle();
    expect(isRoutineTrackingAccepted(testUserId), isTrue);
    expect(h.router.routeInformationProvider.value.uri.path, '/dashboard');
  });

  testWidgets('İngilizce metinler', (tester) async {
    await pumpApp(tester, location: '/dashboard/welcome', extra: _nav(), lang: 'en');
    expect(find.text('Your routine is ready, Ayşe.'), findsOneWidget);
    expect(find.text('Start tracking'), findsOneWidget);
  });

  group('görsel', () {
    setUpAll(() async {
      if (screenshotsEnabled) await loadBrandFonts();
    });

    for (final dark in [false, true]) {
      testWidgets('${dark ? 'koyu' : 'acik'} · ilk-gun', (tester) async {
        if (!screenshotsEnabled) return;
        Tw.dark = dark;
        addTearDown(() => Tw.dark = false);
        debugDisableShadows = false;
        try {
          await pumpApp(
            tester,
            location: '/dashboard/welcome',
            extra: _nav(),
            notifier: FakeReminderNotifier(permission: false),
            realFonts: true,
          );
          await shoot(tester, 'ilk-gun-1-${dark ? 'koyu' : 'acik'}');
          await tester.tap(find.text('Takibe başla'));
          await tester.pumpAndSettle();
          await shoot(tester, 'ilk-gun-2-${dark ? 'koyu' : 'acik'}');
          await tester.tap(find.text('Devam'));
          await tester.pumpAndSettle();
          await shoot(tester, 'ilk-gun-3-${dark ? 'koyu' : 'acik'}');
        } finally {
          debugDisableShadows = true;
        }
      });
    }
  });
}
