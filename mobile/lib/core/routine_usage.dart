import 'i18n.dart';
import 'routine_logic.dart';

/// Bakım ürünü adımı mı (yaşam / beslenme önerisi değil).
bool isSkincareStep(RoutineItem item) => item['category'] == 'Bakım' || item['category'] == 'Koruma';

final _legacyUsagePatterns = <RegExp>[
  RegExp(r'Sıklık/güç hafif düşürüldü:[^.]*\.\s*Tahriş riski azaltıldı\.\s*', caseSensitive: false),
  RegExp(r'Tempo yumuşatıldı:[^.]*\.\s*Bariyer öncelikli\.\s*', caseSensitive: false),
  RegExp(r'Yaşam verilerine göre bu adım geçici duraklatıldı[^.]*\.(?:\s*\([^)]*\))?\s*', caseSensitive: false),
  RegExp(r'Sıklık check-in ile yeniden planlanır\.\s*', caseSensitive: false),
  RegExp(r'Check-in:\s*cilt hissi[^.]*\.\s*', caseSensitive: false),
  RegExp(r'Check-in süreci:\s*beslenme[^.]*\.\s*', caseSensitive: false),
];

/// Eski motor usage jargonu — kullanıcıya göstermeden önce temizle.
String sanitizeRoutineUsage(String usage) {
  var d = usage.trim();
  if (d.isEmpty) return '';
  for (var i = 0; i < 8; i++) {
    final prev = d;
    for (final p in _legacyUsagePatterns) {
      d = d.replaceAll(p, '');
    }
    d = d.replaceAll(RegExp(r'\s{2,}'), ' ').replaceAll(RegExp(r'\s+\.'), '.').trim();
    if (d == prev) break;
  }
  return d;
}

/// Adımın "nasıl uygularım" metni: rutin satırında yazıyorsa o, yoksa adım sırasına göre
/// (temizleyici, serum, nemlendirici, güneş koruyucu) varsayılan.
String routineStepUsage(RoutineItem item, I18n i18n) {
  final usageRaw = sanitizeRoutineUsage(item['usage'] != null ? str(item['usage']).trim() : '');
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
