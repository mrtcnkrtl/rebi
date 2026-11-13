import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/core/routine_logic.dart';
import 'helpers/app_harness.dart';
void main() {
  test('yapılandırılmış rozetler seçili dilde (TR varsayılan, EN çeviri)', () {
    final item = {'action': 'x', 'strength_pct': 4, 'frequency_per_week': 3, 'ramp_stage': 'starter', 'active_families': ['niacinamide', 'pigment']};
    expect(structuredRoutineBadges(item), ['Alıştırma', '%4', '3×/hafta', 'B3 · Leke']);
    loadTestI18n('en');
    expect(structuredRoutineBadges(item), ['Ramp-up', '4%', '3×/week', 'B3 · Spots']);
    loadTestI18n('tr');
    expect(structuredRoutineBadges(item), ['Alıştırma', '%4', '3×/hafta', 'B3 · Leke']);
  });
}
