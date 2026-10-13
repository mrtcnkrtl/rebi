import 'i18n.dart';
import 'routine_logic.dart';

/// Bakım ürünü adımı mı (yaşam / beslenme önerisi değil).
bool isSkincareStep(RoutineItem item) => item['category'] == 'Bakım' || item['category'] == 'Koruma';

/// Adımın "nasıl uygularım" metni: rutin satırında yazıyorsa o, yoksa adım sırasına göre
/// (temizleyici, serum, nemlendirici, güneş koruyucu) varsayılan.
String routineStepUsage(RoutineItem item, I18n i18n) {
  final usageRaw = item['usage'] != null ? str(item['usage']).trim() : '';
  if (usageRaw.isNotEmpty) return usageRaw;
  if (!isSkincareStep(item)) return '';
  final order = stepOrder(item);
  return i18n.t(
    order <= 15
        ? 'dashboard.defaultUsage.cleanser'
        : order <= 25
            ? 'dashboard.defaultUsage.serum'
            : order <= 35
                ? 'dashboard.defaultUsage.moisturizer'
                : order >= 40
                    ? 'dashboard.defaultUsage.sunscreen'
                    : 'dashboard.defaultUsage.generic',
  );
}
