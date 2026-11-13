/// Sorun özelinde klinik şiddet anketinin skoru (anket soruları `severityTests.json`'da, soruları sihirbaz sorar:
/// `screens/analyze/analyze_pages.dart`). Web: `components/SeverityTest.jsx`.
///
/// Cevap puanlarının toplamı olası en yüksek toplama oranlanıp 1–10'a çevrilir.
int calculateSeverityScore(Map<String, num> answers, num maxPossible) {
  final total = answers.values.fold<num>(0, (s, v) => s + v);
  final normalized = (total / maxPossible * 9).round() + 1;
  return normalized.clamp(1, 10).toInt();
}
