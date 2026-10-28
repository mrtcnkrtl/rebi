/// Dashboard / Check-in ekranlarındaki saf rutin mantığı (web: `pages/Dashboard.jsx`,
/// `lib/structuredRoutineBadges.jsx`). Rutin satırları backend'den geldiği gibi
/// `Map` olarak tutulur; bilinmeyen alanlar kaybolmaz, snapshot'a aynen yazılır.
/// Kullanıcıya giden sabit metinler seçili dilde (`mobileRoutineHints`); çeviri yüklenmemişse Türkçe.
library;

import 'i18n.dart';
import 'interpolate.dart';

typedef RoutineItem = Map<String, dynamic>;

/// JS truthiness: null, false, 0, "" → false.
bool truthy(Object? v) {
  if (v == null) return false;
  if (v is bool) return v;
  if (v is num) return v != 0 && !v.isNaN;
  if (v is String) return v.isNotEmpty;
  return true;
}

/// JS `String(n)`: 2.0 → "2", 0.5 → "0.5".
String jsString(Object? v) {
  if (v == null) return '';
  if (v is double && v.isFinite && v == v.truncateToDouble()) return v.toInt().toString();
  return v.toString();
}

String str(Object? v) => v == null ? '' : jsString(v);

num stepOrder(RoutineItem item) {
  final v = item['step_order'];
  return v is num ? v : 50;
}

List<int> _intList(Object? v) {
  if (v is! List) return const [];
  return v.whereType<num>().map((e) => e.toInt()).toList();
}

List<int> weeklyDays(RoutineItem item) => _intList(item['weekly_days']);

/// Kararlı sıralama (JS `Array.prototype.sort` ES2019'dan beri kararlıdır; Dart'ınki değil).
List<RoutineItem> sortByStepOrder(Iterable<RoutineItem> items) {
  final indexed = items.toList().asMap().entries.toList()
    ..sort((a, b) {
      final c = stepOrder(a.value).compareTo(stepOrder(b.value));
      return c != 0 ? c : a.key.compareTo(b.key);
    });
  return indexed.map((e) => e.value).toList();
}

String pickAction(RoutineItem? item, {required bool localized}) {
  if (item == null) return '';
  return localized && truthy(item['action_localized']) ? str(item['action_localized']) : str(item['action']);
}

String pickDetail(RoutineItem? item, {required bool localized}) {
  if (item == null) return '';
  return localized && truthy(item['detail_localized']) ? str(item['detail_localized']) : str(item['detail']);
}

class _HintRule {
  const _HintRule(this.id, this.pattern, this.text);

  final String id;
  final RegExp pattern;
  final String text;
}

final _hintRules = [
  _HintRule(
    'retinoid',
    RegExp(r'\bretinol\b|retinal|adapalen|adapalene|tretinoin|retinoid'),
    'Retinoid (retinol, retinal, adapalen vb.) rutininde: sabah kullanmayın.',
  ),
  _HintRule('bakuchiol', RegExp('bakuchiol'), 'Bakuchiol rutininde: sabah kullanmayın.'),
  _HintRule(
    'arbutin_leke',
    RegExp(r'arbutin|alfa[\s-]?arbutin|traneksamik|kojik|hidrokinon'),
    'Leke odaklı aktif (arbutin, traneksamik vb.) rutininde: sabah kullanmayın.',
  ),
  _HintRule(
    'aha',
    RegExp(r'glikolik|glycolic|laktik|lactic|mandelik|\baha\b'),
    'AHA (glikolik, laktik vb.) rutininde: sabah kullanmayın.',
  ),
  _HintRule('bha', RegExp(r'salisilik|salicylic|\bbha\b'), 'BHA (salisilik asit) rutininde: sabah kullanmayın.'),
  _HintRule('benzoil', RegExp(r'benzoil\s*peroksit|benzoyl'), 'Benzoil peroksit rutininde: sabah kullanmayın.'),
  _HintRule('azelaik', RegExp('azelaik|azelaic'), 'Azelaik asit (tedavi konsantrasyonu) rutininde: sabah kullanmayın.'),
];

/// Rutin metninde geçen akşam / planda sınırlı aktifler için tek satırlık sabah uyarısı.
List<String> computeEveningActivesMorningHints(List<RoutineItem> routine) {
  if (routine.isEmpty) return const [];
  final blob = routine.map((r) => '${str(r['action'])} ${str(r['detail'])}').join(' ').toLowerCase();
  final seen = <String>{};
  final out = <String>[];
  for (final r in _hintRules) {
    if (!r.pattern.hasMatch(blob)) continue;
    if (!seen.add(r.id)) continue;
    out.add(I18n.instance.t('mobileRoutineHints.morning.${r.id}', const {}, r.text));
  }
  return out;
}

/// Backend weekly_days: 0=Pzt … 6=Paz — Dart weekday: 1=Pzt … 7=Paz.
int getTurkeyWeekdayIndex([DateTime? d]) => (d ?? DateTime.now()).weekday - 1;

final _weeklyUsage = RegExp(r'\bhaftada\s*\d+(?:\s*[-–]\s*\d+)?\s*(?:gece|kez|kere|defa|gün)\b', caseSensitive: false);
final _weeklyUsageCapture = RegExp(r'\bhaftada\s*(\d+)(?:\s*[-–]\s*(\d+))?\s*(?:gece|kez|kere|defa|gün)\b');

/// detail metninde haftalık sıklık ifadesi var mı? (gece, kez, kere, defa, gün)
bool isWeeklyUsageItem(RoutineItem item) => _weeklyUsage.hasMatch(str(item['detail']).toLowerCase());

/// Backend weekly_days yoksa: metindeki N ile tam N gün (Pzt–Paz aralığına yayılım).
List<int> getDefaultWeeklyDays(String? detail) {
  final m = _weeklyUsageCapture.firstMatch((detail ?? '').toLowerCase());
  if (m == null) return const [];
  final a = int.parse(m.group(1)!);
  final b = m.group(2) != null ? int.parse(m.group(2)!) : null;
  final n = [b != null ? (a < b ? a : b) : a, 7].reduce((x, y) => x < y ? x : y);
  if (n < 1) return const [];
  if (n >= 7) return const [0, 1, 2, 3, 4, 5, 6];
  if (n == 1) return const [0];
  final days = <int>{};
  for (var i = 0; i < n; i++) {
    days.add(((i * 6) / (n - 1)).round().clamp(0, 6).toInt());
  }
  return days.toList()..sort();
}

final _pausePrefix = RegExp(r'^⏸️\s*', unicode: true);
final _pauseSuffix = RegExp(r'\s*—\s*ARA VER\s*$', caseSensitive: false, unicode: true);
final _notNowSuffix = RegExp(r'\s*—\s*şimdilik kullanma\s*$', caseSensitive: false, unicode: true);
final _dashSplit = RegExp(r'\s*[—–]\s*');
final _inci = RegExp(r'\s*\(INCI[^)]*\)\s*', caseSensitive: false);

/// Uzun rutin satırından okunur kısa başlık (INCI ve kimyasal ön ek gizlenir).
String friendlyRoutineTitle(String? action, [String fallbackTitle = 'This step']) {
  if (action == null || action.isEmpty) return fallbackTitle;
  final s = action.replaceFirst(_pausePrefix, '').replaceFirst(_pauseSuffix, '').replaceFirst(_notNowSuffix, '').trim();
  final parts = s.split(_dashSplit).map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
  if (parts.length >= 2) {
    final human = parts[1].replaceAll(_inci, '').trim();
    if (human.isNotEmpty && human.length < 140) return human;
  }
  final one = (parts.isNotEmpty ? parts[0] : s).replaceAll(_inci, '').trim();
  return one.isEmpty ? fallbackTitle : one;
}

/// flow_debug veya başlık metninden seviye (kart rengi için).
String dailyBalanceLevel(RoutineItem? item, Map<String, dynamic>? flowDebug) {
  final risk = flowDebug?['risk_info'];
  final fromDebug = risk is Map ? risk['level'] : null;
  if (truthy(fromDebug)) return fromDebug.toString();
  final a = str(item?['action']).toLowerCase();
  if (a.contains('kriz')) return 'crisis';
  if (a.contains('yüksek')) return 'high';
  if (a.contains('orta')) return 'moderate';
  return 'normal';
}

const _lifestyleCategories = ['Zihin', 'Yaşam', 'Beslenme'];

bool _isDailyBalance(RoutineItem r) => str(r['action']).startsWith('Günlük denge:');

String _timeLower(RoutineItem r) => str(r['time']).trim().toLowerCase();

class WeeklyItem {
  const WeeklyItem(this.item, this.weeklyKey, this.displayDays);

  final RoutineItem item;
  final String weeklyKey;
  final List<int> displayDays;
}

class DayPlan {
  const DayPlan(this.morning, this.evening);

  final List<RoutineItem> morning;
  final List<RoutineItem> evening;
}

/// Rutin kategorileri — Dashboard'daki `useMemo` hesaplarının tamamı.
class RoutineView {
  RoutineView(this.routine) {
    productItems = routine.where((r) => !_lifestyleCategories.contains(r['category'])).toList();
    lifestyleItems = routine.where((r) => _lifestyleCategories.contains(r['category'])).toList();
    morningProducts = sortByStepOrder(productItems.where((r) => r['time'] == 'Sabah' || r['time'] == 'sabah'));
    eveningProducts = sortByStepOrder(productItems.where((r) => r['time'] == 'Akşam' || r['time'] == 'akşam'));
    nutritionItems = lifestyleItems.where((r) => r['category'] == 'Beslenme').toList();
    dailyBalanceItem = routine.where(_isDailyBalance).firstOrNull;
    wellnessItems = lifestyleItems.where((r) => r['category'] != 'Beslenme' && !_isDailyBalance(r)).toList();
    dailyLifestyleItems = sortByStepOrder(lifestyleItems.where((r) {
      final t = str(r['time']).toLowerCase();
      if (t != 'günlük' && t != 'gunluk') return false;
      return !_isDailyBalance(r);
    }));
    wellnessMorningItems = sortByStepOrder(wellnessItems.where((r) {
      final t = _timeLower(r);
      return t == 'sabah' || t == 'morning';
    }));
    wellnessEveningItems = sortByStepOrder(wellnessItems.where((r) {
      final t = _timeLower(r);
      return t == 'akşam' || t == 'evening';
    }));
    eveningMorningHints = computeEveningActivesMorningHints(routine);

    final weekly = productItems.where((r) => weeklyDays(r).isNotEmpty || isWeeklyUsageItem(r)).toList();
    weeklyItems = [
      for (var i = 0; i < weekly.length; i++)
        WeeklyItem(
          weekly[i],
          '${str(weekly[i]['action'])}-$i',
          weeklyDays(weekly[i]).isNotEmpty ? weeklyDays(weekly[i]) : getDefaultWeeklyDays(str(weekly[i]['detail'])),
        ),
    ];

    bool onDay(RoutineItem item, int d) {
      final wd = weeklyDays(item);
      return wd.isEmpty || wd.contains(d);
    }

    routineByDay = {
      for (var d = 0; d < 7; d++)
        d: DayPlan(
          morningProducts.where((i) => onDay(i, d)).toList(),
          eveningProducts.where((i) => onDay(i, d)).toList(),
        ),
    };

    final seen = <String>{};
    routineIngredientsList = [];
    for (final item in [...morningProducts, ...eveningProducts]) {
      final key = str(item['action']).trim();
      if (key.isNotEmpty && seen.add(key)) routineIngredientsList.add(key);
    }
  }

  final List<RoutineItem> routine;
  late final List<RoutineItem> productItems;
  late final List<RoutineItem> lifestyleItems;
  late final List<RoutineItem> morningProducts;
  late final List<RoutineItem> eveningProducts;
  late final List<RoutineItem> nutritionItems;
  late final RoutineItem? dailyBalanceItem;
  late final List<RoutineItem> wellnessItems;
  late final List<RoutineItem> dailyLifestyleItems;
  late final List<RoutineItem> wellnessMorningItems;
  late final List<RoutineItem> wellnessEveningItems;
  late final List<String> eveningMorningHints;
  late final List<WeeklyItem> weeklyItems;
  late final Map<int, DayPlan> routineByDay;
  late final List<String> routineIngredientsList;
}

const _familyLabels = {
  'retinol': 'Retinol',
  'bha': 'BHA',
  'aha': 'AHA',
  'azelaic': 'Azelaik',
  'vitamin_c': 'C vit.',
  'niacinamide': 'B3',
  'benzoyl': 'BP',
  'bakuchiol': 'Bakuchiol',
  'pigment': 'Leke',
};

/// Backend `run_flow` structured alanları: strength_pct, frequency_per_week, ramp_stage, active_families.
List<String> structuredRoutineBadges(RoutineItem item) {
  final action = str(item['action']);
  final isRiskSummary =
      action.startsWith('Günlük denge:') || (action.contains('Günlük denge') && item['category'] == 'Yaşam');
  if (isRiskSummary) return const [];

  final famRaw = item['active_families'];
  final fam = famRaw is List ? famRaw.map(str).toList() : const <String>[];
  final freq = item['frequency_per_week'];
  final has = truthy(item['strength_pct']) || freq != null || truthy(item['ramp_stage']) || fam.isNotEmpty;
  if (!has) return const [];

  final chips = <String>[];
  if (item['ramp_stage'] == 'starter') chips.add(I18n.instance.t('mobileRoutineHints.starter', const {}, 'Alıştırma'));
  if (truthy(item['strength_pct'])) chips.add(interpolate(I18n.instance.t('mobileRoutineHints.percent', const {}, '%{{n}}'), {'n': jsString(item['strength_pct'])}));
  if (freq is num && freq > 0) {
    chips.add(freq >= 7
        ? I18n.instance.t('mobileRoutineHints.everyDay', const {}, 'Her gün')
        : interpolate(I18n.instance.t('mobileRoutineHints.perWeek', const {}, '{{n}}×/hafta'), {'n': jsString(freq)}));
  }
  if (fam.isNotEmpty) chips.add(fam.take(4).map((f) => I18n.instance.t('mobileRoutineHints.families.$f', const {}, _familyLabels[f] ?? f)).join(' · '));
  return chips;
}

/// Liste alanını `RoutineItem` listesine çevirir (bozuk girdiler atlanır).
List<RoutineItem> asRoutine(Object? v) {
  if (v is! List) return const [];
  return v.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
}
