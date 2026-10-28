import 'dart:convert';
import 'dart:io';

import 'package:rebi/core/routine_tracking.dart';

import 'app_harness.dart';

/// Görsel galeri ve mağaza ekran görüntüleri için ortak örnek hesap ("Ayşe", dolu bir gün).
/// Veri API sözleşmesindeki gerçek örnek yanıtlardan gelir (`contract/*.json`); uydurma yalnızca ürün adları ve kişi.
Map<String, dynamic> contractJson(String name) =>
    (jsonDecode(File('../contract/$name.json').readAsStringSync()) as Map).cast<String, dynamic>();

/// Rutin onaylanmış (analiz sihirbazı atlanır) bir kullanıcının yerel kayıtları.
Map<String, Object> demoPrefs() => {
      trackAcceptedKey(testUserId): '1',
      trackSnapshotKey(testUserId): jsonEncode({
        'routine': routineFixture['routine'],
        'userName': 'Ayşe',
        'weather': routineFixture['weather'],
        'flowDebug': routineFixture['flow_debug'],
        'acceptedAt': DateTime.now().millisecondsSinceEpoch - 3 * 86400000,
      }),
    };

/// Sabah rutini yarım, su 750 ml, rafta biten ürünler, geçmiş grafikleri dolu.
FakeBackend demoBackend() {
  final routine = routineFixture['routine'] as List;
  final b = FakeBackend();
  final plan = contractJson('today_plan');
  b.todayPlan = {...plan, 'user_id': testUserId, 'log_date': '2026-10-10', 'routine': routine, 'has_routine': true};
  b.waterMl = 750;
  // Rafım: rutindeki güneş kremi bitti, bir de rutin dışı ürün.
  b.productsOut = [
    {'product': 'SPF 30+ (mat bitişli, yağsız SPF)', 'step_order': 40, 'finished_at': '2026-10-08T10:00:00+00:00', 'log_date': '2026-10-08', 'days_out': 2},
    {'product': 'Gece kremi', 'step_order': null, 'finished_at': '2026-10-02T10:00:00+00:00', 'log_date': '2026-10-02', 'days_out': 8},
  ];
  b.snapshot = {
    ...b.snapshot,
    'has_routine': true,
    'routine': routine,
    'profile': {'full_name': 'Ayşe Yılmaz', 'skin_type': 'oily', 'age': 29, 'gender': 'female', 'city': 'İstanbul'},
  };
  b.profile = {'full_name': 'Ayşe Yılmaz', 'skin_type': 'oily', 'age': 29, 'gender': 'female', 'city': 'İstanbul'};
  b.history = {...b.history, ...contractJson('me_history'), 'user_id': testUserId};
  return b;
}
