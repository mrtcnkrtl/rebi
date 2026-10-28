import 'package:flutter/widgets.dart';

import '../../ui/components/photo_picker.dart';
import '../../ui/components/severity_test.dart' show calculateSeverityScore;

const strongActiveFamilyIds = [
  'retinol',
  'adapalene',
  'bha',
  'aha',
  'benzoyl',
  'azelaic',
  'vitamin_c',
  'vitamin_c_derivatives',
  'bakuchiol',
  'pigment',
  'niacinamide',
  'zinc_pca',
  'sulfur',
  'urea',
];

const concernIds = ['general', 'oiliness', 'pores', 'acne', 'aging', 'dryness', 'pigmentation', 'sensitivity'];

const zoneIds = ['forehead', 'nose', 'cheeks', 'chin', 'undereye', 'lips', 'temples'];

const toleranceLevels = ['never', 'good', 'mild', 'bad'];

/// Son adet tarihinden döngü evresi. Web `new Date("YYYY-MM-DD")` UTC gece yarısı sayar.
String calcCyclePhase(String lastPeriodDate, int cycleLength, {DateTime? now}) {
  if (lastPeriodDate.isEmpty) return 'unknown';
  final p = lastPeriodDate.split('-').map(int.parse).toList();
  final start = DateTime.utc(p[0], p[1], p[2]);
  final diff = ((now ?? DateTime.now()).millisecondsSinceEpoch - start.millisecondsSinceEpoch) / 86400000;
  final days = diff.floor();
  final day = ((days % cycleLength) + cycleLength) % cycleLength;
  if (day <= 5) return 'menstrual';
  if (day <= 13) return 'follicular';
  if (day <= 15) return 'ovulation';
  return 'luteal';
}

/// PSS-10: maddeler 4,5,7,8 (0 tabanlı 3,4,6,7) ters puanlanır. Toplam 0–40.
int pssScore(List<int> answers) {
  var acc = 0;
  for (var i = 0; i < answers.length; i++) {
    acc += const [3, 4, 6, 7].contains(i) ? 4 - answers[i] : answers[i];
  }
  return acc;
}

/// Bir sorunun şiddet anketi soruları (`severityTests.json`); anketi olmayan sorun (ör. genel bakım) için boş.
List<Map> severityQuestionsFor(Map<String, dynamic> pack, String concern) {
  final test = pack[concern];
  if (test is! Map) return const [];
  return (test['questions'] as List? ?? const []).whereType<Map>().toList();
}

/// Cevaplar: analiz sihirbazının tüm girdileri ve backend'e (`POST /generate_routine`) giden gövde.
/// Sihirbazın görünümünden bağımsızdır; web `Analyze.jsx` ile aynı alan kümesini üretir.
class AnalyzeForm {
  AnalyzeForm({String name = ''}) : name = TextEditingController(text: name);

  // Sen
  final TextEditingController name;
  final age = TextEditingController();
  String gender = '';
  String hormonalStatus = '';
  String lastPeriodDate = '';
  int cycleLength = 28;
  double? lat;
  double? lon;

  // Cildin
  String skinType = '';

  /// Seçilen sorunlar; ilki öncelikli sorundur (backend `concern`).
  final List<String> concerns = [];
  final List<String> zones = [];
  final Map<String, bool> specialFlags = {
    'frown_lines': false,
    'smile_lines': false,
    'eye_crows_feet': false,
    'redness_diffuse': false,
    'redness_acne_marks': false,
    'cold_sensitive': false,
    'stings_with_products': false,
  };

  /// Sorun → soru kimliği → seçeneğin puanı. Yalnızca öncelikli sorunun anketi sorulur.
  final Map<String, Map<String, num>> severityAnswers = {};

  // Günlük hayat
  double waterIntake = 2;
  double sleepHours = 7;
  final List<int> pssAnswers = List.filled(10, 0);

  /// Hangi stres sorusu cevaplandı (cevaplanmayan soru varsayılan 0 ile kalır, eski sihirbazla aynı).
  final List<bool> pssTouched = List.filled(10, false);
  int smokingPerDay = 0;
  int smokingYears = 0;
  int alcoholFreq = 0;
  int alcoholAmt = 1;
  int makeupFreq = 0;
  String makeupRemoval = 'cleanser';

  // Ürünler
  String activesExperience = 'occasional';

  /// Her güçlü aktif ailesi: never | good | mild | bad
  final Map<String, String> activesTolerance = {for (final id in strongActiveFamilyIds) id: 'good'};

  // Fotoğraf
  PickedPhoto? photo;
  String photoContext = 'unsure';

  void dispose() {
    name.dispose();
    age.dispose();
  }

  bool get isFemale => gender == 'female';

  /// Adet tarihi gereken durum (düzenli / düzensiz döngü).
  bool get periodNeeded => isFemale && (hormonalStatus == 'regular' || hormonalStatus == 'irregular');

  String get cyclePhase {
    if (!isFemale) return '';
    if (hormonalStatus == 'pregnant') return '';
    if (hormonalStatus == 'menopause') return 'menopause';
    if (periodNeeded && lastPeriodDate.isNotEmpty) return calcCyclePhase(lastPeriodDate, cycleLength);
    return '';
  }

  String get primaryConcern => concerns.isNotEmpty ? concerns.first : 'general';

  bool get locationSet => lat != null && lon != null;

  bool get hasAgingConcern => concerns.contains('aging');
  bool get hasSensitivityConcern => concerns.contains('sensitivity');
  bool get anyFlag => specialFlags.values.any((v) => v);

  int? get ageValue => int.tryParse(age.text.trim());

  /// Zorunlu alanlar tamam mı (ad, yaş).
  bool get basicsDone => name.text.trim().isNotEmpty && (ageValue ?? 0) > 0;

  /// Sorun seçimi değişince alakasız kalan cevapları temizler: genel bakım diğerleriyle birlikte seçilmez,
  /// seçimi kalkan sorunun işaretleri ve anket cevapları gitmez ama gönderilmez.
  void toggleConcern(String id) {
    if (concerns.contains(id)) {
      concerns.remove(id);
    } else if (id == 'general') {
      concerns
        ..clear()
        ..add('general');
    } else {
      concerns
        ..remove('general')
        ..add(id);
    }
    if (!hasAgingConcern) {
      for (final k in const ['frown_lines', 'smile_lines', 'eye_crows_feet']) {
        specialFlags[k] = false;
      }
    }
    if (!hasSensitivityConcern) {
      for (final k in const ['redness_diffuse', 'redness_acne_marks', 'cold_sensitive', 'stings_with_products']) {
        specialFlags[k] = false;
      }
    }
  }

  /// Öncelikli sorunu başa alır.
  void setPrimary(String id) {
    if (!concerns.contains(id)) return;
    concerns
      ..remove(id)
      ..insert(0, id);
  }

  void toggleZone(String id) => zones.contains(id) ? zones.remove(id) : zones.add(id);

  /// Öncelikli sorunun anketi tamamlandıysa 1–10 şiddet skoru, değilse null.
  int? severityScore(Map<String, dynamic> pack) {
    final questions = severityQuestionsFor(pack, primaryConcern);
    if (questions.isEmpty) return null;
    final answers = severityAnswers[primaryConcern] ?? const <String, num>{};
    if (answers.length < questions.length) return null;
    final maxPossible = questions.fold<num>(0, (sum, q) {
      final opts = (q['options'] as List? ?? const []).whereType<Map>();
      final best = opts.map((o) => (o['score'] as num?) ?? 0).fold<num>(-1 << 31, (a, b) => a > b ? a : b);
      return sum + best;
    });
    if (maxPossible <= 0) return null;
    return calculateSeverityScore(answers, maxPossible);
  }

  /// `POST /generate_routine` gövdesi (web `Analyze.jsx` ile aynı alanlar).
  Map<String, dynamic> toBody({required String userId, required String? photoPath, required int? severity}) {
    return {
      'user_id': userId,
      'full_name': name.text,
      'age': ageValue,
      'gender': gender,
      'concern': primaryConcern,
      'skin_type': skinType.isEmpty ? 'normal' : skinType,
      'severity_score': severity ?? 5,
      'water_intake': waterIntake,
      'sleep_hours': sleepHours,
      'stress_score': (pssScore(pssAnswers) * 16 / 40).round(),
      'smoking': smokingPerDay > 0,
      'smoking_per_day': smokingPerDay,
      'smoking_years': smokingYears,
      'alcohol': alcoholFreq > 0,
      'alcohol_frequency': alcoholFreq,
      'alcohol_amount': alcoholAmt,
      'location_lat': lat,
      'location_lon': lon,
      'photo_url': photoPath,
      'is_pregnant': hormonalStatus == 'pregnant',
      'cycle_phase': cyclePhase,
      'acne_zones': primaryConcern == 'general' ? <String>[] : List<String>.of(zones),
      'actives_experience': activesExperience,
      'actives_tolerance': Map<String, String>.of(activesTolerance),
      'makeup_frequency': makeupFreq,
      'makeup_removal': makeupFreq > 0 ? makeupRemoval : 'cleanser',
      'special_flags': anyFlag ? Map<String, bool>.of(specialFlags) : null,
    };
  }
}
