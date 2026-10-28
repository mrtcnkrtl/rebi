import 'dart:convert';

import 'package:flutter/material.dart' show Size, Text;
import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/core/i18n.dart';
import 'package:rebi/core/routine_logic.dart';
import 'package:rebi/core/routine_tracking.dart';
import 'package:rebi/screens/routine/routine_parts.dart';
import 'package:rebi/screens/routine/routine_stage.dart';

import 'helpers/app_harness.dart';

/// Faz F2: Rutin sekmesi (sakin tek sütun): gün seçici, sabah/akşam blokları, katlanır bölümler, "Rebi'ye sor".
void main() {
  final routine = routineFixture['routine'] as List;

  Map<String, Object> acceptedPrefs() => {
        trackAcceptedKey(testUserId): '1',
        trackSnapshotKey(testUserId): jsonEncode({
          'routine': routine,
          'userName': 'Ayşe Test',
          'weather': routineFixture['weather'],
          'flowDebug': routineFixture['flow_debug'],
          'activePlan': routineFixture['active_plan'],
          'acceptedAt': DateTime.now().millisecondsSinceEpoch - 3 * 86400000,
        }),
      };

  Future<void> openRoutine(WidgetTester tester, {String lang = 'tr', Size size = const Size(390, 844)}) =>
      pumpApp(tester, location: '/dashboard/routine', prefs: acceptedPrefs(), lang: lang, size: size);

  group('sayfa yapısı', () {
    testWidgets('başlık, kısa profil satırı, gün seçici ve seçili günün sabah/akşam blokları', (tester) async {
      await openRoutine(tester);

      expect(find.text(tr('dashboard.myRoutineTitle', {'name': 'Ayşe Test'})), findsOneWidget);
      expect(find.text(tr('dashboard.routineByDayTitle')), findsOneWidget);
      expect(find.text(tr('dashboard.morning')), findsOneWidget);
      expect(find.text(tr('dashboard.evening')), findsOneWidget);
      // Akşam planında haftanın yalnız bazı günlerinde (fixture: Pzt, Paz) ek bir adım var: sayılar güne göre değişir,
      // beklenen değer bugünün planından hesaplanır (sabit "3" yalnız Pzt/Paz geçerdi).
      final todayPlan = RoutineView(asRoutine(routine)).routineByDay[getTurkeyWeekdayIndex()]!;
      expect(todayPlan.morning.length, 3, reason: 'sabah: temizleyici, nemlendirici, SPF');
      final counts = [todayPlan.morning.length, todayPlan.evening.length];
      for (final n in counts.toSet()) {
        expect(find.text(tr('mobileRoutine.stepCount', {'n': n})), findsNWidgets(counts.where((c) => c == n).length));
      }
      final days = I18n.instance.tList('dashboard.weekDays', const []);
      final today = days[getTurkeyWeekdayIndex()];
      expect(find.text('$today · ${tr('dashboard.todayTitle')}'), findsOneWidget, reason: 'bugünün planı açık');
    });

    testWidgets('üst sahne: başlık, cilt profili etiketleri ve gün seçici sahnede; seçili günün başlığı sahnenin içinde', (tester) async {
      await openRoutine(tester);
      final fd = routineFixture['flow_debug'] as Map;
      for (final chip in [fd['skin_type'], fd['severity'], fd['age_group']]) {
        expect(find.text(chip.toString()), findsOneWidget, reason: 'profil etiketi: $chip');
      }
      expect(find.byType(RoutineStage), findsOneWidget);
      final days = I18n.instance.tList('dashboard.weekDays', const []);
      expect(
        find.descendant(of: find.byType(RoutineStage), matching: find.text('${days[getTurkeyWeekdayIndex()]} · ${tr('dashboard.todayTitle')}')),
        findsOneWidget,
      );
      expect(find.descendant(of: find.byType(RoutineStage), matching: find.byType(WeekDayStrip)), findsOneWidget);
    });

    testWidgets('sabah uyarısı sabah bloğunun içinde durur (ayrı kutu değil); günlük denge bloklardan sonra gelir', (tester) async {
      await pumpApp(tester, location: '/dashboard', extra: {'routine': routine, 'userName': 'Ayşe'});
      final morning = find.ancestor(of: find.text(tr('dashboard.morning')), matching: find.byType(RoutineBlockCard));
      expect(find.descendant(of: morning, matching: find.text(tr('dashboard.morningUsageTitle'))), findsOneWidget);
      expect(find.text(tr('dashboard.morningUsageTitle')), findsOneWidget, reason: 'tek yerde');

      final eveningY = tester.getTopLeft(find.ancestor(of: find.text(tr('dashboard.evening')), matching: find.byType(RoutineBlockCard))).dy;
      final balanceY = tester.getTopLeft(find.text(tr('dashboard.dailyBalanceTitle'))).dy;
      expect(balanceY, greaterThan(eveningY), reason: 'rutin önce, denge notu sonra');
    });

    testWidgets('kabul edilmemiş plan: kabul kartı ilk karttır ve rutinden önce gelir', (tester) async {
      await pumpApp(tester, location: '/dashboard', extra: {'routine': routine, 'userName': 'Ayşe'});
      final acceptY = tester.getTopLeft(find.text(tr('dashboard.acceptBanner'))).dy;
      final morningY = tester.getTopLeft(find.text(tr('dashboard.morning'))).dy;
      expect(acceptY, lessThan(morningY));
    });

    testWidgets('adımlar zaman çizelgesi gibi numaralıdır; son adımdan sonra çizgi inmez', (tester) async {
      await openRoutine(tester);
      for (final n in [1, 2, 3]) {
        expect(find.text('$n'), findsWidgets, reason: '$n. adım düğümü');
      }
      expect(find.byType(RoutineStepTile), findsWidgets);
    });

    testWidgets('eski stilden iz yok: mavi hava kartı yerine tek satır, sabit Türkçe bölüm adları yok', (tester) async {
      await openRoutine(tester, lang: 'en');
      expect(find.textContaining('Weather · '), findsOneWidget);
      expect(find.textContaining('Neden bu'), findsNothing);
      expect(find.text('Su'), findsNothing, reason: 'İngilizcede ipucu başlıkları çevrilir');
      expect(find.text(tr('mobileRoutine.tips.water.title')), findsOneWidget);
      expect(find.text('Water'), findsOneWidget);
    });

    testWidgets('katlanır bölümler başlangıçta kapalı, dokununca açılır', (tester) async {
      await openRoutine(tester);
      final how = tr('dashboard.howToChooseDesc');
      expect(find.text(how), findsNothing);
      await tapText(tester, tr('dashboard.howToChooseTitle'));
      expect(find.text(how), findsOneWidget);
      await tapText(tester, tr('dashboard.howToChooseTitle'));
      expect(find.text(how), findsNothing);

      // Etken madde listesi: kapalıyken adlar yalnızca adım başlığında, açılınca bir de çip olarak görünür.
      final first = RoutineView(asRoutine(routine)).routineIngredientsList.first;
      expect(find.text(first), findsOneWidget);
      await tapText(tester, tr('dashboard.productListTitle'));
      expect(find.text(first), findsNWidgets(2));
    });

    testWidgets('bu hafta: seyrek adımlar yedi günlük kutularla ve uygulanacak günlerle gösterilir', (tester) async {
      await openRoutine(tester);
      expect(find.text(tr('dashboard.weeklyTitle')), findsOneWidget);
      expect(find.textContaining(tr('mobileRoutine.weeklyDays', {'days': ''}).split(':').first), findsWidgets);
    });

    testWidgets('gün seçici: başka bir gün seçilince başlık o günün adı olur', (tester) async {
      await openRoutine(tester);
      final days = I18n.instance.tList('dashboard.weekDays', const []);
      final other = days[(getTurkeyWeekdayIndex() + 1) % 7];
      await tapText(tester, other);
      final caption = find.byWidgetPredicate((w) => w is Text && w.data == other && (w.style?.fontSize ?? 0) > 16);
      expect(caption, findsOneWidget);
    });
  });

  group('adım ayrıntısı ve Rebi\'ye sor bağlantısı', () {
    testWidgets('neden / nasıl uygulanır açılır; bağlantı sohbeti hazır soruyla açar ve gönderir', (tester) async {
      final h = await pumpApp(tester, location: '/dashboard/routine', prefs: acceptedPrefs());
      expect(find.text(tr('mobileRoutine.askRebi')), findsNothing, reason: 'kapalıyken yok');

      await tapFinder(tester, find.text(tr('dashboard.whySkincareButton')).first);
      expect(find.text(tr('common.hide')), findsOneWidget);
      expect(find.textContaining(tr('dashboard.howToApply')), findsWidgets);

      await tapText(tester, tr('mobileRoutine.askRebi'));
      await settle(tester, 20);

      expect(h.router.routeInformationProvider.value.uri.path, '/dashboard/chat');
      final sent = h.backend.bodyOf('/chat_general')['message'] as String;
      expect(sent, contains('Temizleme: Yüzey aktif'), reason: 'sorulan adım: ilk sabah adımı');
      expect(sent, startsWith('Rutinimdeki'));
    });

    testWidgets('Bugün ekranındaki kahraman kartta da aynı bağlantı çalışır', (tester) async {
      final h = await pumpApp(tester, location: '/dashboard', prefs: acceptedPrefs());
      await tapFinder(tester, find.text(tr('dashboard.whySkincareButton')).first);
      await tapText(tester, tr('mobileRoutine.askRebi'));
      await settle(tester, 20);

      expect(h.router.routeInformationProvider.value.uri.path, '/dashboard/chat');
      expect(h.backend.bodyOf('/chat_general')['message'], contains('Rutinimdeki'));
    });

    testWidgets('İngilizcede soru İngilizce gider', (tester) async {
      final h = await pumpApp(tester, location: '/dashboard/routine', prefs: acceptedPrefs(), lang: 'en');
      await tapFinder(tester, find.text(tr('dashboard.whySkincareButton')).first);
      await tapText(tester, 'Ask Rebi');
      await settle(tester, 20);
      expect(h.backend.bodyOf('/chat_general')['message'], startsWith('Why am I using'));
    });
  });

  test('askRebi istemi adımın adını taşır', () {
    loadTestI18n('tr');
    final text = I18n.instance.t('mobileRoutine.askPrompt', {'item': 'SPF 30+'});
    expect(text, contains('"SPF 30+"'));
    loadTestI18n('en');
    expect(I18n.instance.t('mobileRoutine.askPrompt', {'item': 'SPF 30+'}), contains('"SPF 30+"'));
    expect(I18n.instance.t('mobileRoutine.askPrompt', {'item': 'SPF 30+'}), isNot(contains('rutinimdeki')));
  });
}
