import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/core/routine_tracking.dart';
import 'package:rebi/ui/shell/app_shell.dart';
import 'package:rebi/ui/shell/page_stage.dart';
import 'package:rebi/ui/widgets/common.dart' show RCard;
import 'package:rebi/ui/widgets/menu_list.dart';

import 'helpers/app_harness.dart';

/// Ortak üst sahne (`PageStage`/`StagePage`): ana sekmelerin dışındaki ekranlar da aynı dilde açılır; geri bağlantısı sahnenin
/// içindedir, kabuk bu yollarda üst güvenli alanı ve eski geri çubuğunu uygulamaz.
void main() {
  Map<String, Object> acceptedPrefs() => {
        trackAcceptedKey(testUserId): '1',
        trackSnapshotKey(testUserId): jsonEncode({
          'routine': routineFixture['routine'],
          'userName': 'Ayşe Test',
          'weather': routineFixture['weather'],
          'flowDebug': routineFixture['flow_debug'],
          'acceptedAt': DateTime.now().millisecondsSinceEpoch - 3 * 86400000,
        }),
      };

  group('kabuk', () {
    test('hasStage: analiz dışındaki tüm /dashboard yolları sahnelidir', () {
      for (final p in [
        '/dashboard',
        '/dashboard/routine',
        '/dashboard/chat',
        '/dashboard/history',
        '/dashboard/profile',
        '/dashboard/account',
        '/dashboard/shelf',
        '/dashboard/checkin',
        '/dashboard/reminders',
        '/dashboard/themes',
        '/dashboard/subscribe',
      ]) {
        expect(hasStage(p), isTrue, reason: p);
      }
      expect(hasStage('/dashboard/analyze'), isFalse, reason: 'analiz akışı kendi çubuğunu çizer');
      for (final p in ['/', '/auth', '/rebi', '/kvkk']) {
        expect(hasStage(p), isFalse, reason: p);
      }
    });
  });

  group('alt sayfalar', () {
    // Her alt sayfada tek bir "Geri" vardır (sahnenin içinde); eski geri çubuğu ikinci bir tane eklemez.
    for (final path in ['/dashboard/themes', '/dashboard/subscribe', '/dashboard/reminders', '/dashboard/shelf']) {
      testWidgets('$path: sahnede tek "Geri", sekmesine döndürür', (tester) async {
        final h = await pumpApp(tester, location: path, prefs: acceptedPrefs());
        expect(find.text(tr('mobileNav.back')), findsOneWidget);
        expect(find.byType(PageStage), findsOneWidget);
        await tapText(tester, tr('mobileNav.back'));
        final expected = path == '/dashboard/shelf' ? '/dashboard' : '/dashboard/profile';
        expect(h.router.routeInformationProvider.value.uri.path, expected);
      });
    }

    testWidgets('check-in formu sahneyle açılır', (tester) async {
      await pumpApp(tester, location: '/dashboard/checkin', prefs: acceptedPrefs());
      expect(find.byType(PageStage), findsOneWidget);
      expect(find.text(tr('checkin.title')), findsOneWidget);
    });

    testWidgets('check-in: gönder düğmesi sabit çubukta, kapalıyken nedenini söyler', (tester) async {
      final h = await pumpApp(tester, location: '/dashboard/checkin', prefs: acceptedPrefs());
      // Formun sonuna kaydırmadan görünür ve ekrana sığar.
      final submit = find.text(tr('checkin.submit'));
      expect(submit, findsOneWidget);
      expect(tester.getBottomLeft(submit).dy, lessThan(844));
      expect(find.text(tr('mobileCheckin.needSkin')), findsOneWidget);

      await tapText(tester, tr('mobileCheckin.skin.kuru.title'));
      expect(find.text(tr('mobileCheckin.needSkin')), findsNothing);
      await tester.tap(submit);
      await settle(tester, 6);
      expect(h.backend.calls('/daily_checkin'), hasLength(1));
    });

    testWidgets('check-in: bugün yapıldıysa da sahneyle açılır (içerik durum çubuğunun altında kalmaz)', (tester) async {
      final backend = FakeBackend()..checkinStatus = {'already_checked_in': true};
      await pumpApp(tester, location: '/dashboard/checkin', prefs: acceptedPrefs(), backend: backend);
      expect(find.byType(PageStage), findsOneWidget);
      expect(find.text(tr('checkin.alreadyTitle')), findsOneWidget);
      expect(find.text(tr('mobileNav.back')), findsOneWidget);
    });

    for (final path in ['/dashboard/profile', '/dashboard/history']) {
      testWidgets('$path (sekme kökü): geri yoktur, sahne vardır', (tester) async {
        await pumpApp(tester, location: path, prefs: acceptedPrefs());
        expect(find.text(tr('mobileNav.back')), findsNothing);
        expect(find.byType(PageStage), findsOneWidget);
      });
    }
  });

  group('geniş ekran (tablet)', () {
    testWidgets('sahne metni gövdeyle aynı sütunda hizalanır (672 dp)', (tester) async {
      await pumpApp(tester, location: '/dashboard/history', prefs: acceptedPrefs(), size: const Size(1000, 900));
      final title = tester.getTopLeft(find.text(tr('mobileHistory.title'))).dx;
      final card = tester.getTopLeft(find.byType(RCard).first).dx;
      expect(card, closeTo((1000 - 672) / 2 + 16, 1), reason: 'gövde 672 dp sütunda');
      expect(title, closeTo(card + 4, 1), reason: 'başlık kartın 4 dp içinden başlar (telefondaki gibi)');
    });

    testWidgets('telefonda başlık 20 dp, kart 16 dp içeriden başlar', (tester) async {
      await pumpApp(tester, location: '/dashboard/history', prefs: acceptedPrefs());
      expect(tester.getTopLeft(find.text(tr('mobileHistory.title'))).dx, closeTo(20, 1));
      expect(tester.getTopLeft(find.byType(RCard).first).dx, closeTo(16, 1));
    });
  });

  group('klavye', () {
    testWidgets('klavye açılınca alt gezinme çubuğu gizlenir, kapanınca geri gelir', (tester) async {
      await pumpApp(tester, location: '/dashboard/checkin', prefs: acceptedPrefs());
      expect(find.text(tr('mobileNav.history')), findsOneWidget);

      tester.view.viewInsets = const FakeViewPadding(bottom: 900);
      addTearDown(tester.view.resetViewInsets);
      await settle(tester, 3);
      expect(find.text(tr('mobileNav.history')), findsNothing, reason: 'yazarken yer açılır');

      tester.view.resetViewInsets();
      await settle(tester, 3);
      expect(find.text(tr('mobileNav.history')), findsOneWidget);
    });
  });

  group('bileşenler', () {
    testWidgets('StageSegments: seçili segment bildirilir, dokununca değişir, seçiliye dokunmak bir şey yapmaz', (tester) async {
      var value = 30;
      final taps = <int>[];
      await pumpStandalone(
        tester,
        (theme) => Material(
          child: StatefulBuilder(
            builder: (context, setState) => StageSegments<int>(
              theme: theme,
              options: const [(7, '7 gün'), (30, '30 gün'), (90, '90 gün')],
              value: value,
              onChanged: (v) {
                taps.add(v);
                setState(() => value = v);
              },
            ),
          ),
        ),
      );
      final handle = tester.ensureSemantics();
      expect(tester.getSemantics(find.text('30 gün')), matchesSemantics(label: '30 gün', isButton: true, isSelected: true, hasSelectedState: true));
      await tester.tap(find.text('30 gün'));
      await tester.pump();
      expect(taps, isEmpty, reason: 'seçili segment tekrar tetiklemez');
      await tester.tap(find.text('90 gün'));
      await tester.pump();
      expect(taps, [90]);
      expect(value, 90);
      handle.dispose();
    });

    testWidgets('MenuGroup: satırlar arası çizgi, satır dokunması çalışır, açıklama ekran okuyucu etiketine girer', (tester) async {
      var opened = 0;
      await pumpStandalone(
        tester,
        (theme) => Material(
          child: MenuGroup(rows: [
            MenuRow(icon: Icons.shield, color: theme.primary, title: 'Hesap', hint: 'Profil ve izinler', onTap: () => opened++),
            MenuRow(icon: Icons.bolt, color: theme.primary, title: 'Rafım', onTap: () {}),
          ]),
        ),
      );
      final handle = tester.ensureSemantics();
      expect(find.text('Hesap'), findsOneWidget);
      expect(find.text('Profil ve izinler'), findsOneWidget);
      expect(find.bySemanticsLabel('Hesap. Profil ve izinler'), findsOneWidget);
      expect(find.bySemanticsLabel('Rafım'), findsOneWidget, reason: 'açıklamasız satırda yalnız başlık');
      await tester.tap(find.text('Hesap'));
      expect(opened, 1);
      handle.dispose();
    });
  });

  group('aşağı çekip yenileme', () {
    testWidgets('Geçmiş: aşağı çekince geçmiş yeniden istenir', (tester) async {
      final h = await pumpApp(tester, location: '/dashboard/history', prefs: acceptedPrefs());
      final before = h.backend.calls('/me/history').length;
      expect(before, greaterThan(0));

      await tester.fling(find.byType(SingleChildScrollView).first, const Offset(0, 400), 1000);
      await settle(tester, 30);

      expect(h.backend.calls('/me/history').length, before + 1);
    });
  });

  group('yerelleştirme', () {
    testWidgets('check-in İngilizce arayüzde Türkçe sabit metin taşımaz', (tester) async {
      await pumpApp(tester, location: '/dashboard/checkin', prefs: acceptedPrefs(), lang: 'en');
      expect(find.text('How many hours did you sleep last night?'), findsOneWidget);
      expect(find.text('How does your skin feel today?'), findsOneWidget);
      expect(find.text('Irritated'), findsOneWidget);
      for (final turkish in ['Dün gece kaç saat uyudun?', 'Cildin bugün nasıl hissediyor?', 'İrritasyon', 'Bugün stres seviyeni nasıl tanımlarsın?']) {
        expect(find.text(turkish), findsNothing, reason: turkish);
      }
    });

    testWidgets('Görünüm ekranının etiketleri çevrilir', (tester) async {
      await pumpApp(tester, location: '/dashboard/themes', prefs: acceptedPrefs(), lang: 'en');
      expect(find.text('ACCENT COLOR'), findsOneWidget);
      expect(find.text('PREVIEW'), findsOneWidget);
      expect(find.text('VURGU RENGİ'), findsNothing);
      for (final en in ['Forest', 'Sage', 'Powder', 'Lavender']) {
        expect(find.text(en), findsOneWidget, reason: 'tema adı: $en');
      }
      expect(find.text('Orman'), findsNothing);
      expect(find.text('Morning routine'), findsOneWidget, reason: 'önizleme metinleri de çevrilir');
    });
  });
}
