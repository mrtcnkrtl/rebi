import 'api.dart';

/// `GET /me/assessment/last`: son analizin cevapları. Yeni analizde sihirbaz bunlarla açılır,
/// kullanıcı her soruyu baştan doldurmak yerine değişenleri düzeltir.
class LastAssessment {
  const LastAssessment({
    required this.found,
    this.createdAt,
    this.concern = '',
    this.severityScore,
    this.lifestyle = const {},
    this.fullName = '',
    this.age,
    this.gender = '',
  });

  factory LastAssessment.fromJson(Map<String, dynamic> j) => LastAssessment(
        found: j['found'] == true,
        createdAt: _text(j['created_at']),
        concern: _text(j['concern']) ?? '',
        severityScore: j['severity_score'] is num ? (j['severity_score'] as num).toInt() : null,
        lifestyle: j['lifestyle_data'] is Map ? (j['lifestyle_data'] as Map).cast<String, dynamic>() : const {},
        fullName: _text(j['full_name']) ?? '',
        age: j['age'] is num ? (j['age'] as num).toInt() : null,
        gender: _text(j['gender']) ?? '',
      );

  final bool found;
  final String? createdAt;
  final String concern;
  final int? severityScore;

  /// `assessments.lifestyle_data`: sunucunun kaydettiği ham cevaplar.
  final Map<String, dynamic> lifestyle;
  final String fullName;
  final int? age;
  final String gender;

  /// Sihirbazın `applyDraft` beklediği biçime çevirir (sunucu alan adları → form alanları).
  /// Fotoğraf ve konum taşınmaz: ikisi de o ana aittir, yeniden sorulur.
  Map<String, dynamic> toDraftAnswers() {
    final l = lifestyle;
    List<String> strList(Object? v) => v is List ? v.whereType<String>().toList() : const [];

    // `concerns` sunucuda [{id, severity_score, zones, duration, frequency, note}] olarak durur.
    final concernRows = l['concerns'] is List ? (l['concerns'] as List).whereType<Map>().toList() : const <Map>[];
    final ids = <String>[];
    final zones = <String, List<String>>{};
    final timeline = <String, Map<String, String>>{};
    for (final row in concernRows) {
      final id = _text(row['id']);
      if (id == null || ids.contains(id)) continue;
      ids.add(id);
      // Motor bölgeleri sol/sağ yanak olarak açar; sihirbazda tek "yanak" seçeneği var.
      final rowZones = <String>[];
      for (final z in strList(row['zones'])) {
        final zone = (z == 'left_cheek' || z == 'right_cheek') ? 'cheeks' : z;
        if (!rowZones.contains(zone)) rowZones.add(zone);
      }
      if (rowZones.isNotEmpty) zones[id] = rowZones;
      final fields = <String, String>{};
      for (final f in const ['duration', 'frequency', 'note']) {
        final v = _text(row[f]);
        if (v != null) fields[f] = v;
      }
      if (fields.isNotEmpty) timeline[id] = fields;
    }
    if (ids.isEmpty && concern.isNotEmpty) ids.add(concern);

    // Şiddet anketinin tek tek cevapları sunucuda saklanmıyor (yalnız skor), bu yüzden
    // `severityAnswers` taşınmaz: anket yeniden çözülür, cildin bugünkü hâli ölçülür.
    return {
      'name': fullName,
      'age': age == null ? '' : '$age',
      'gender': gender.isNotEmpty ? gender : _text(l['gender']) ?? '',
      // Döngü evresi son adet tarihinden hesaplanıyor ve tarih saklanmıyor: yalnız
      // tarih gerektirmeyen durumlar taşınır, düzenli/düzensiz döngü yeniden sorulur.
      'hormonalStatus': _text(l['cycle_phase']) == 'menopause'
          ? 'menopause'
          : (l['is_pregnant'] == true ? 'pregnant' : ''),
      'skinType': _text(l['skin_type']) ?? '',
      'concerns': ids,
      'concernZones': zones,
      'concernTimeline': timeline,
      'specialFlags': l['special_flags'] is Map ? l['special_flags'] : const {},
      'triggers': strList(l['triggers']),
      'pastTreatments': strList(l['past_treatments']),
      'expectations': strList(l['expectations']),
      'nutrition': l['nutrition'] is Map ? l['nutrition'] : const {},
      'waterIntake': l['water_intake'],
      'sleepHours': l['sleep_hours'],
      'smokingPerDay': l['smoking_per_day'],
      'smokingYears': l['smoking_years'],
      'alcoholFreq': l['alcohol_frequency'],
      'alcoholAmt': l['alcohol_amount'],
      'makeupFreq': l['makeup_frequency'],
      'makeupRemoval': l['makeup_removal'],
      'shavingFreq': l['shaving_frequency'],
      'shavingAfter': l['shaving_after'],
      'activesExperience': l['actives_experience'],
      'activesTolerance': l['actives_tolerance'] is Map ? l['actives_tolerance'] : const {},
    };
  }
}

/// Son analizi okur. Bulunamazsa / okunamazsa null döner: sihirbaz boş formla açılır.
Future<LastAssessment?> fetchLastAssessment(String userId) async {
  final res = await apiGet('/me/assessment/last', query: {'user_id': userId});
  if (!res.ok) return null;
  final parsed = LastAssessment.fromJson(res.data);
  return parsed.found ? parsed : null;
}

String? _text(Object? v) {
  final s = v?.toString().trim() ?? '';
  return s.isEmpty ? null : s;
}
