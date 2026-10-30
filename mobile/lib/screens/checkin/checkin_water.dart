import '../../core/i18n.dart';
import '../../core/routine_logic.dart';

/// Check-in su: Türkiye'de sık kullanılan "1 bardak ≈ 250 ml" (2 L ≈ 8 bardak).
const mlPerGlass = 250;

/// Su alanındaki metni tam sayı ml'ye çevirir (virgül ondalık, en çok 8000 ml); boş ya da geçersizse null.
int? parseWaterMlInput(String? raw) {
  final s = (raw ?? '').trim().replaceFirst(',', '.');
  if (s.isEmpty) return null;
  final n = num.tryParse(s);
  if (n == null || !n.isFinite || n < 0) return null;
  final r = n.round();
  return r > 8000 ? 8000 : r;
}

/// "yaklaşık 6 bardak" / "about 6 glasses" (uygulama dilinde).
String formatGlassesLabel(int ml) {
  final i18n = I18n.instance;
  if (ml <= 0) return i18n.t('mobileCheckin.water.zeroGlasses');
  final glasses = ml / mlPerGlass;
  final num rounded = (glasses - glasses.round()).abs() < 0.05 ? glasses.round() : (glasses * 10).round() / 10;
  return i18n.t('mobileCheckin.water.aboutGlasses', {'n': jsString(rounded)});
}
