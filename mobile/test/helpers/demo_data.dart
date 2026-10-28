import 'dart:convert';
import 'dart:io';

import 'package:rebi/core/routine_tracking.dart';

import 'app_harness.dart';

/// Görsel galeri ve mağaza ekran görüntüleri için ortak örnek hesap ("Ayşe", dolu bir gün).
/// Veri API sözleşmesindeki gerçek örnek yanıtlardan gelir (`contract/*.json`); uydurma yalnızca ürün adları ve kişi.
Map<String, dynamic> contractJson(String name) =>
    (jsonDecode(File('../contract/$name.json').readAsStringSync()) as Map).cast<String, dynamic>();

/// Mağaza görüntüleri için rutin: sözleşme örneği, ama risk "kriz" yerine dengeli bir gün (mağaza vitrininde kırmızı
/// uyarı görünmesin) ve İngilizce için sunucunun `*_localized` alanları dolu.
List<dynamic> _storeRoutine(String lang) {
  final routine = (jsonDecode(jsonEncode(routineFixture['routine'])) as List).cast<Map<String, dynamic>>();
  for (final item in routine) {
    if (item['action'].toString().startsWith('Günlük denge:')) {
      item['action'] = 'Günlük denge: Normal';
      item['detail'] = _calmDetail['tr'];
    }
    if (lang == 'en') {
      final en = _routineEn[item['action']];
      if (en != null) {
        item['action_localized'] = en.$1;
        if (en.$2.isNotEmpty) item['detail_localized'] = en.$2;
      }
      if (item['action'] == 'Günlük denge: Normal') item['detail_localized'] = _calmDetail['en'];
    }
  }
  return routine;
}

Map<String, dynamic> _storeFlowDebug(String lang) {
  final fd = (jsonDecode(jsonEncode(routineFixture['flow_debug'])) as Map).cast<String, dynamic>();
  fd['risk_info'] = {'score': 5, 'level': 'normal', 'label': 'Normal', 'detail': _calmDetail[lang]};
  if (lang == 'en') {
    fd['skin_type'] = 'Oily';
    fd['severity'] = 'Moderate';
    fd['age_group'] = 'Young adult (20-29)';
  }
  return fd;
}

const _calmDetail = {
  'tr': 'Uykun ve su tüketimin hedefe yakın, stres dengeli. Rutinine düzenli devam etmek yeterli; öğlen güneşinde '
      'güneş kremini tazelemeyi unutma.',
  'en': 'Your sleep and water intake are close to target and stress is balanced. Keep up your routine; remember to '
      'reapply sunscreen in the midday sun.',
};

/// Sözleşme örneğindeki rutin adımlarının İngilizcesi: (eylem, açıklama).
const _routineEn = <String, (String, String)>{
  'Temizleme: Yüzey aktif (SLES-free) köpük temizleyici': ('Cleanse: gentle SLES-free foaming cleanser', ''),
  'Nemlendirici: Niasinamid %4 + Hyaluronik asit (hafif jel)': (
    'Moisturizer: 4% niacinamide + hyaluronic acid (light gel)',
    'Niacinamide in your morning routine: a versatile B3 for barrier, sebum and tone; it matches your goals of '
        'balancing breakouts, pores and oil.',
  ),
  'SPF 30+ (mat bitişli, yağsız SPF)': (
    'SPF 30+ (matte, oil-free sunscreen)',
    'SPF in your morning routine: the key protection for every goal and the basis for managing dark spots and ageing.',
  ),
  'Çift aşama temizlik: yağ/balm bazlı temizleyici + nazik temizleyici': (
    'Double cleanse: oil/balm cleanser + gentle cleanser',
    '',
  ),
  '⏸️ Salisilik asit %1 tonik (BHA, INCI: Salicylic Acid) — alın & T-bölge hedefli — şimdilik kullanma': (
    '⏸️ 1% salicylic acid toner (BHA) — forehead & T-zone — not for now',
    'This step is paused for safety; barrier and calming come first.',
  ),
  'Niasinamid %10 serum (INCI: Niacinamide; niasin ile karıştırma) + Azelaik asit %10-15 (INCI: Azelaic Acid; dikarboksilli asit) (sırayla veya tek formül)': (
    '10% niacinamide serum + 10-15% azelaic acid (in sequence or one formula)',
    'Azelaic acid in your evening routine: a medium-strength option for breakouts and redness/dark spots.',
  ),
  'Gece: Niasinamid %4 + HA (hafif jel, gece)': (
    'Night: 4% niacinamide + HA (light gel)',
    'Niacinamide in your evening routine: a versatile B3 for barrier, sebum and tone.',
  ),
  '5 Dakika Nefes Egzersizi': ('5-minute breathing exercise', 'A short wind-down supports your skin\'s overnight recovery.'),
  'Uyku öncesi protokol': (
    'Pre-sleep routine',
    'Regular, sufficient sleep supports overnight repair. Aim to gradually get closer to 7 hours.',
  ),
  'Seramid + niasinamid içeren bariyer nemlendirici (öncelik)': (
    'Barrier moisturizer with ceramides + niacinamide (priority)',
    'This layer comes first to support your barrier.',
  ),
  'Opsiyonel — bitkisel alternatif (istersen)': (
    'Optional — botanical alternative (if you like)',
    'Entirely optional and not needed for your routine.',
  ),
};

/// Rutin onaylanmış (analiz sihirbazı atlanır) bir kullanıcının yerel kayıtları.
/// [store] true ise mağaza görüntüsü verisi ([_storeRoutine]); [lang] kişi adını ve çevirileri seçer.
Map<String, Object> demoPrefs({String lang = 'tr', bool store = false}) => {
      trackAcceptedKey(testUserId): '1',
      trackSnapshotKey(testUserId): jsonEncode({
        'routine': store ? _storeRoutine(lang) : routineFixture['routine'],
        'userName': lang == 'en' ? 'Emma' : 'Ayşe',
        'weather': routineFixture['weather'],
        'flowDebug': store ? _storeFlowDebug(lang) : routineFixture['flow_debug'],
        'acceptedAt': DateTime.now().millisecondsSinceEpoch - 3 * 86400000,
      }),
    };

/// Sabah rutini yarım, su 750 ml, rafta biten ürünler, geçmiş grafikleri dolu.
FakeBackend demoBackend({String lang = 'tr', bool store = false}) {
  final routine = store ? _storeRoutine(lang) : routineFixture['routine'] as List;
  final en = lang == 'en';
  final b = FakeBackend();
  final plan = contractJson('today_plan');
  b.todayPlan = {...plan, 'user_id': testUserId, 'log_date': '2026-10-10', 'routine': routine, 'has_routine': true};
  b.waterMl = 750;
  // Rafım: rutindeki güneş kremi bitti, bir de rutin dışı ürün.
  b.productsOut = [
    {
      'product': en ? 'SPF 30+ (matte, oil-free sunscreen)' : 'SPF 30+ (mat bitişli, yağsız SPF)',
      'step_order': 40,
      'finished_at': '2026-10-08T10:00:00+00:00',
      'log_date': '2026-10-08',
      'days_out': 2,
    },
    {
      'product': en ? 'Night cream' : 'Gece kremi',
      'step_order': null,
      'finished_at': '2026-10-02T10:00:00+00:00',
      'log_date': '2026-10-02',
      'days_out': 8,
    },
  ];
  final profile = {
    'full_name': en ? 'Emma Wilson' : 'Ayşe Yılmaz',
    'skin_type': 'oily',
    'age': 29,
    'gender': 'female',
    'city': en ? 'London' : 'İstanbul',
  };
  b.snapshot = {...b.snapshot, 'has_routine': true, 'routine': routine, 'profile': profile};
  b.profile = profile;
  b.history = {...b.history, ...contractJson('me_history'), 'user_id': testUserId};
  return b;
}
