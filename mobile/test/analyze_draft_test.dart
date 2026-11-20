import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/core/analyze_draft.dart';
import 'package:rebi/core/routine_tracking.dart';
import 'package:rebi/screens/analyze/analyze_form.dart';

import 'helpers/analyze_walk.dart';
import 'helpers/app_harness.dart';

/// Analiz sihirbazının yarım kalan cevapları: çıkışta, uygulama kapanınca ve yanlışlıkla
/// başa dönünce kaybolmaz; yeni analiz önceki cevaplarla açılabilir.
void main() {
  Map<String, Object> acceptedPrefs() => {
        trackAcceptedKey(testUserId): '1',
        trackSnapshotKey(testUserId): jsonEncode({
          'routine': routineFixture['routine'],
          'userName': 'Ayşe Test',
          'acceptedAt': DateTime.now().millisecondsSinceEpoch - 3 * 86400000,
        }),
      };

  Map<String, dynamic>? draftAnswers() {
    final d = getAnalyzeDraft(testUserId);
    final a = d?['answers'];
    return a is Map ? a.cast<String, dynamic>() : null;
  }

  testWidgets('cevaplar yazılırken taslağa kaydedilir', (tester) async {
    await pumpApp(tester, location: '/dashboard/analyze');
    await analyzeWalkTo(tester, 'skinType');

    final answers = draftAnswers();
    expect(answers, isNotNull, reason: 'yarım kalan cevaplar cihazda tutulmalı');
    expect(answers!['age'], '28');
    expect(answers['gender'], 'male');
    expect(getAnalyzeDraft(testUserId)!['pageId'], 'skinType');
  });

  testWidgets('sihirbaza dönülünce cevaplar geri gelir ve şerit baştan başlatır', (tester) async {
    // Cihazda yarım kalmış bir analiz: kullanıcı cilt tipi sayfasında bırakmış.
    final draft = jsonEncode({
      'savedAt': DateTime.now().millisecondsSinceEpoch,
      'pageId': 'skinType',
      'stressTest': false,
      'answers': {'name': 'Ayşe Test', 'age': '28', 'gender': 'male'},
    });
    await pumpApp(tester, location: '/dashboard/analyze', prefs: {analyzeDraftKey(testUserId): draft});

    expect(find.text(tr('mobileAnalyze.skinType.title')), findsOneWidget);
    expect(find.text(tr('analyze.again.resumedNote')), findsOneWidget);

    await tester.tap(find.byKey(const Key('analyze-start-over')));
    await settle(tester, 3);
    expect(find.text(tr('mobileAnalyze.basics.title')), findsOneWidget);
    expect(getAnalyzeDraft(testUserId), isNull, reason: '"baştan başla" taslağı silmeli');
  });

  testWidgets('14 günden eski taslak sorulmaz', (tester) async {
    final stale = jsonEncode({
      'savedAt': DateTime.now().subtract(const Duration(days: 15)).millisecondsSinceEpoch,
      'pageId': 'skinType',
      'answers': {'name': 'Ayşe Test', 'age': '28', 'gender': 'male'},
    });
    await pumpApp(tester, location: '/dashboard/analyze', prefs: {analyzeDraftKey(testUserId): stale});
    expect(find.text(tr('mobileAnalyze.intro.title')), findsOneWidget);
    expect(find.text(tr('analyze.again.resumedNote')), findsNothing);
  });

  testWidgets('yeni analiz: önceki analizin cevaplarıyla açılır', (tester) async {
    final backend = FakeBackend()
      ..lastAssessment = {
        'user_id': testUserId,
        'found': true,
        'assessment_id': 'a1',
        'created_at': '2026-11-01T08:00:00+00:00',
        'concern': 'acne',
        'severity_score': 6,
        'lifestyle_data': {
          'skin_type': 'oily',
          'water_intake': 1.5,
          'sleep_hours': 6,
          'concerns': [
            {'id': 'acne', 'severity_score': 6, 'zones': ['left_cheek', 'right_cheek'], 'duration': '1-3', 'frequency': 'weekly'},
          ],
          'triggers': ['stress'],
          'actives_experience': 'regular',
        },
        'full_name': 'Ayşe Test',
        'age': 31,
        'gender': 'female',
        'synced': true,
      };

    await pumpApp(tester, location: '/dashboard/analyze', prefs: acceptedPrefs(), backend: backend);
    await tapText(tester, tr('analyze.newAnalyzeFull'));
    expect(find.text(tr('mobileAnalyze.again.title')), findsOneWidget);
    await tester.tap(find.byKey(const Key('analyze-again-keep')));
    await settle(tester, 4);

    expect(find.text(tr('analyze.again.prefilledNote')), findsOneWidget);
    final answers = draftAnswers();
    expect(answers!['age'], '31');
    expect(answers['gender'], 'female');
    expect(answers['skinType'], 'oily');
    expect(answers['concerns'], ['acne']);
    // Motorun sol/sağ yanak ayrımı sihirbazın tek "yanak" seçeneğine döner.
    expect((answers['concernZones'] as Map)['acne'], ['cheeks']);
    expect(answers['triggers'], ['stress']);
    expect(answers['activesExperience'], 'regular');
  });

  test('"baştan başla" stres, beslenme, işaret ve tolerans cevaplarını da sıfırlar', () {
    final form = AnalyzeForm(name: 'Eski Ad');
    form.age.text = '31';
    form.gender = 'female';
    form.skinType = 'oily';
    form.concerns.add('acne');
    form.concernZones['acne'] = ['cheeks'];
    form.specialFlags['stings_with_products'] = true;
    form.pssAnswers[3] = 4;
    form.pssTouched[3] = true;
    form.nutrition['sugar'] = 3;
    form.activesTolerance['retinol'] = 'bad';
    form.waterIntake = 1;
    form.shavingFreq = 7;
    form.shavingAfter = 'ingrown';

    form.resetAnswers(name: 'Yeni Ad');

    expect(form.name.text, 'Yeni Ad');
    expect(form.age.text, '');
    expect(form.gender, '');
    expect(form.skinType, '');
    expect(form.concerns, isEmpty);
    expect(form.concernZones, isEmpty);
    expect(form.anyFlag, isFalse);
    expect(form.pssAnswers, everyElement(0));
    expect(form.pssTouched, everyElement(false));
    expect(form.nutrition, {'fastfood': 0, 'sugar': 0, 'dairy': 0, 'veggies': 3});
    expect(form.activesTolerance['retinol'], 'good');
    expect(form.waterIntake, 2);
    expect(form.shavingFreq, 0);
    expect(form.shavingAfter, '');
    expect(form.hasAnswers, isFalse);
    form.dispose();
  });

  testWidgets('rutin üretilince taslak silinir ve geri gelmez', (tester) async {
    await pumpApp(tester, location: '/dashboard/analyze');
    // En kısa yoldan özete git ve rutini oluştur.
    await analyzeWalkTo(tester, 'summary');
    expect(getAnalyzeDraft(testUserId), isNotNull, reason: 'özette hâlâ yarım cevaplar var');

    await tapText(tester, tr('mobileAnalyze.summary.create'));
    await settle(tester, 20);

    // Ekran kapanırken taslağı yeniden yazmamalı: yoksa sonraki analizde eski cevaplar sorulur.
    expect(getAnalyzeDraft(testUserId), isNull);
  });

  testWidgets('önceki analiz okunamazsa boş formla açılır', (tester) async {
    final backend = FakeBackend()..lastAssessmentFails = true;
    await pumpApp(tester, location: '/dashboard/analyze', prefs: acceptedPrefs(), backend: backend);
    await tapText(tester, tr('analyze.newAnalyzeFull'));
    await tester.tap(find.byKey(const Key('analyze-again-keep')));
    await settle(tester, 4);
    expect(find.text(tr('mobileAnalyze.basics.title')), findsOneWidget);
    expect(find.text(tr('analyze.again.prefilledNote')), findsNothing);
  });
}
