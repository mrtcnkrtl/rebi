import 'today_plan.dart';

/// Check-in sorularına bugünkü takip kayıtlarından önceden doldurulan cevaplar.
/// Kullanıcı hepsini değiştirebilir; kayıt yoksa ilgili soru boş kalır (atlanmış sayılır).
class CheckinPrefill {
  const CheckinPrefill({this.waterMl, this.makeupUsed, this.removalMethod, this.extras = const {}});

  /// Bugün içilen toplam su (ml); kayıt yoksa null.
  final int? waterMl;

  /// Makyaj yapıldı mı; kayıt yoksa null.
  final bool? makeupUsed;

  /// Makyaj nasıl temizlendi (`cleanser`, `double`, `water`, `wipe`, `none`); yapıldıysa ve biliniyorsa.
  final String? removalMethod;

  /// Evet / hayır ek soruları (`high_glycemic_intake_today`, `heavy_dairy_today`, `spf_applied_today`).
  final Map<String, bool> extras;

  /// Doldurulan cevap sayısı: su, makyaj, temizleme yöntemi ve her ek soru ayrı sayılır.
  int get count => (waterMl != null ? 1 : 0) + (makeupUsed != null ? 1 : 0) + (removalMethod != null ? 1 : 0) + extras.length;

  bool get isEmpty => count == 0;
}

/// Bugünün ilerlemesinden (`/daily_tracking/today` → `aggregated`) check-in cevapları çıkarır.
///
/// - Su: toplam 0'dan büyükse.
/// - Makyaj: kayıt varsa evet / hayır; yapıldıysa ve yöntem biliniyorsa yöntem.
/// - Şekerli ya da abur cubur → `high_glycemic_intake_today`, süt ürünü → `heavy_dairy_today`. Beslenme kaydı
///   varsa olmayan seçenekler "hayır" sayılır; kayıt yoksa soru boş kalır.
/// - Güneş kremi bugün yenilendiyse `spf_applied_today` evet (yenilenmediyse bilinmez, boş).
CheckinPrefill checkinPrefill(DayProgress p) {
  final extras = <String, bool>{};
  if (p.nutritionLogged) {
    final n = p.nutrition;
    final sugary = n['sweets'] == true || n['snacks'] == true;
    final legacyJunk = n['junk_food'] == true && n['sweets'] == null && n['snacks'] == null && n['fried_food'] == null;
    extras['high_glycemic_intake_today'] = sugary || legacyJunk;
    extras['heavy_dairy_today'] = n['dairy'] == true;
  }
  if (p.spfRefreshes > 0) extras['spf_applied_today'] = true;

  return CheckinPrefill(
    waterMl: p.waterMl > 0 ? p.waterMl : null,
    makeupUsed: p.makeupLogged ? p.makeupUsed : null,
    removalMethod: p.makeupLogged && p.makeupUsed ? p.removalMethod : null,
    extras: extras,
  );
}
