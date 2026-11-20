import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/core/routine_edits.dart';
import 'package:rebi/core/routine_logic.dart';
import 'package:rebi/core/routine_tracking.dart';

import 'helpers/app_harness.dart';

/// "Rutinimi düzenle": kullanıcı yapmayacağı adımı plandan çıkarır, kendi adımını ekler.
/// Rebi'nin adımlarının metni değişmez; çıkarılan adım silinmez, geri alınabilir.
void main() {
  final routine = (routineFixture['routine'] as List).cast<Map>().map((m) => m.cast<String, dynamic>()).toList();

  Map<String, Object> acceptedPrefs() => {
        trackAcceptedKey(testUserId): '1',
        trackSnapshotKey(testUserId): jsonEncode({
          'routine': routine,
          'userName': 'Ayşe Test',
          'acceptedAt': DateTime.now().millisecondsSinceEpoch - 3 * 86400000,
        }),
      };

  FakeBackend backendWithRoutine() => FakeBackend()..activeRoutine = List<dynamic>.from(routine);

  test('adım kimliği sunucudaki kuralla aynı', () {
    expect(
      routineStepKey({'time': 'Sabah', 'step_order': 10, 'action': 'Temizleme'}),
      'Sabah|10|Temizleme',
    );
    // step_order yoksa boş kalır (sunucu da öyle yapar).
    expect(routineStepKey({'time': 'Akşam', 'action': 'SPF'}), 'Akşam||SPF');
    // Tam sayı değerli ondalık tam sayı gibi yazılır (sunucudaki `_order_text` ile aynı).
    expect(routineStepKey({'time': 'Sabah', 'step_order': 10.0, 'action': 'Temizleme'}), 'Sabah|10|Temizleme');
    expect(routineStepKey({'time': 'Sabah', 'step_order': 10.5, 'action': 'X'}), 'Sabah|10.5|X');
    // Boşluklar kırpılır: aynı adım, aynı kimlik.
    expect(routineStepKey({'time': ' Sabah ', 'step_order': 10, 'action': ' Temizleme '}), 'Sabah|10|Temizleme');
  });

  test('plandan çıkarılan adım hiçbir görünüme girmez', () {
    final view = RoutineView([
      {'time': 'Sabah', 'category': 'Bakım', 'step_order': 10, 'action': 'Temizleme'},
      {'time': 'Sabah', 'category': 'Koruma', 'step_order': 40, 'action': 'SPF 50', 'skipped_by_user': true},
    ]);
    expect(view.morningProducts.map((i) => i['action']), ['Temizleme']);
    expect(view.routine, hasLength(1));
  });

  testWidgets('rutin ekranından düzenleme açılır ve adımlar listelenir', (tester) async {
    await pumpApp(
      tester,
      location: '/dashboard/routine',
      prefs: acceptedPrefs(),
      backend: backendWithRoutine(),
    );
    await tapFinder(tester, find.byKey(const Key('open-routine-edit')));
    expect(find.text(tr('mobileRoutineEdit.title')), findsOneWidget);
    expect(find.text(tr('mobileRoutineEdit.myStepsEmpty')), findsOneWidget);
    // Kaydedilecek bir şey yokken kaydet çubuğu çıkmaz.
    expect(find.byKey(const Key('routine-edit-save')), findsNothing);
  });

  testWidgets('adım kapatılıp kaydedilince plandan çıkar, geri alınabilir', (tester) async {
    final backend = backendWithRoutine();
    await pumpApp(tester, location: '/dashboard/routine/edit', prefs: acceptedPrefs(), backend: backend);

    final key = routineStepKey(routine.first);
    await tapFinder(tester, find.byKey(Key('step-$key')));
    expect(find.text(tr('mobileRoutineEdit.save')), findsOneWidget);

    await tapFinder(tester, find.byKey(const Key('routine-edit-save')));
    expect(find.text(tr('mobileRoutineEdit.saved')), findsOneWidget);

    final sent = backend.bodyOf('/routine/active');
    expect(sent['hidden'], [key]);
    // Sunucu çıkarılanı ayrı tutar; plan onu göstermez ama kayıt kaybolmaz.
    expect(backend.skippedSteps.single['action'], routine.first['action']);
    expect(backend.activeRoutine.map((i) => i['action']), isNot(contains(routine.first['action'])));
    // Cihazdaki kopya da güncellenir (panel çevrimdışı da düzenlenmiş planı gösterir).
    expect(
      asRoutine(getRoutineSnapshot(testUserId)?['routine']).map((i) => i['action']),
      isNot(contains(routine.first['action'])),
    );

    // Geri al: aynı anahtar listeden çıkar.
    await tapFinder(tester, find.byKey(Key('step-$key')));
    await tapFinder(tester, find.byKey(const Key('routine-edit-save')));
    expect(backend.bodyOf('/routine/active')['hidden'], isEmpty);
    expect(backend.skippedSteps, isEmpty);
  });

  testWidgets('kendi adımı eklenir ve kullanıcının adımı olarak işaretlenir', (tester) async {
    final backend = backendWithRoutine();
    await pumpApp(tester, location: '/dashboard/routine/edit', prefs: acceptedPrefs(), backend: backend);

    await tapFinder(tester, find.byKey(const Key('add-user-step')));
    await tester.enterText(find.byKey(const Key('user-step-action')), 'Dudak balmı');
    await settle(tester, 2);
    await tester.enterText(find.byKey(const Key('user-step-detail')), 'Yatmadan önce');
    await settle(tester, 2);
    await tapFinder(tester, find.byKey(const Key('user-step-save')));

    await tapFinder(tester, find.byKey(const Key('routine-edit-save')));
    expect(find.text('Dudak balmı'), findsWidgets);

    final sent = backend.bodyOf('/routine/active');
    expect(sent['added'], [
      {'action': 'Dudak balmı', 'time': 'Sabah', 'detail': 'Yatmadan önce'},
    ]);
    final added = backend.activeRoutine.whereType<Map>().where((i) => i['source'] == 'user').toList();
    expect(added.single['action'], 'Dudak balmı');
  });

  testWidgets('boş adım adı kaydedilemez', (tester) async {
    await pumpApp(tester, location: '/dashboard/routine/edit', prefs: acceptedPrefs(), backend: backendWithRoutine());
    await tapFinder(tester, find.byKey(const Key('add-user-step')));
    await tester.tap(find.byKey(const Key('user-step-save')));
    await settle(tester, 3);
    // Sayfa kapanmadı: ad boşken "Ekle" çalışmaz.
    expect(find.byKey(const Key('user-step-action')), findsOneWidget);
  });

  testWidgets('son adım da çıkarılamaz: plan tamamen boşalmaz', (tester) async {
    final only = <Map<String, dynamic>>[
      {'time': 'Sabah', 'category': 'Bakım', 'step_order': 10, 'action': 'Temizleme: köpük', 'detail': 'Ilık su.'},
    ];
    final backend = FakeBackend()..activeRoutine = List<dynamic>.from(only);
    await pumpApp(tester, location: '/dashboard/routine/edit', prefs: acceptedPrefs(), backend: backend);
    final toggle = find.byKey(Key('step-${routineStepKey(only.first)}'));
    expect(tester.widget<Switch>(toggle).onChanged, isNull);
  });

  testWidgets('kaydetme başarısızsa söylenir, sessizce yutulmaz', (tester) async {
    final backend = backendWithRoutine()..routineEditStatus = 502;
    await pumpApp(tester, location: '/dashboard/routine/edit', prefs: acceptedPrefs(), backend: backend);
    await tapFinder(tester, find.byKey(Key('step-${routineStepKey(routine.first)}')));
    await tapFinder(tester, find.byKey(const Key('routine-edit-save')));
    // Kaydet düğmesi kalır (değişiklik hâlâ kaydedilmedi) ve sebep yazılır.
    expect(find.text(tr('mobileRoutineEdit.save')), findsOneWidget);
    expect(find.text(tr('mobileCommon.errors.busy')), findsOneWidget);
  });

  testWidgets('sunucuya ulaşılamazsa cihazdaki kopya gösterilir', (tester) async {
    final backend = backendWithRoutine()..routineActiveFails = true;
    await pumpApp(tester, location: '/dashboard/routine/edit', prefs: acceptedPrefs(), backend: backend);
    expect(find.text(tr('mobileRoutineEdit.offline')), findsOneWidget);
    expect(find.byKey(Key('step-${routineStepKey(routine.first)}')), findsOneWidget);
  });
}
