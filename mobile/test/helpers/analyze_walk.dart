import 'package:flutter/material.dart' show Key, TextField;
import 'package:flutter_test/flutter_test.dart';

import 'app_harness.dart';

/// Analiz sihirbazında (erkek, normal cilt) en kısa yoldan istenen sayfaya gider; erişilebilirlik ve görsel testlerde
/// kullanılır. Sayfalar: basics, skinType, concerns, severity, waterSleep, stressIntro, smoking, tolerance, photo, summary.
/// "severity" yolu sivilceyi seçer (anket + bölge sorusu gelir); diğerleri genel bakım seçer.
Future<void> analyzeWalkTo(WidgetTester t, String page) async {
  Future<void> next() => tapFinder(t, find.byKey(const Key('flow-next')));
  await tapFinder(t, find.byKey(const Key('flow-start')));
  if (page == 'basics') return;
  await t.enterText(find.widgetWithText(TextField, '25'), '28');
  await settle(t, 3);
  await next();
  await tapText(t, packS('gender.male'));
  if (page == 'skinType') return;
  await tapText(t, packS('skinPicker.normal.label'));
  final acne = page == 'severity';
  await tapText(t, packS(acne ? 'concern.acne' : 'concern.general'));
  if (page == 'concerns') return;
  await next();
  if (acne) {
    await next(); // bölgeler
    return;
  }
  if (page == 'waterSleep') return;
  await next();
  if (page == 'stressIntro') return;
  await tapFinder(t, find.byKey(const Key('flow-skip')));
  if (page == 'smoking') return;
  await tapText(t, packS('smokingAmount.0'));
  await tapText(t, packS('alcoholFreq.0'));
  await tapText(t, packS('makeup.frequency.0'));
  await tapText(t, packS('activesExperience.none'));
  if (page == 'tolerance') return;
  await next();
  if (page == 'photo') return;
  await next();
}
