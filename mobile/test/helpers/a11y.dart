import 'package:flutter_test/flutter_test.dart';

/// Erişilebilirlik kuralları: dokunma hedefi (Android 48 dp, iOS 44 dp), dokunulabilir öğenin etiketi ve metin kontrastı.
/// Dönüş: kırılan her düğüm için kısa bir satır; boşsa ekran geçer.
Future<List<String>> a11yFindings(WidgetTester tester, {bool contrast = true}) async {
  final out = <String>{};
  final label = RegExp(r'label: "([^"]*)"');
  final tapSize = RegExp(r'expected tap target size of at least Size\((\d+)\.0, \d+\.0\), but found Size\(([\d.]+), ([\d.]+)\)');
  final ratio = RegExp(r'Expected contrast ratio of at least ([\d.]+) but found ([\d.]+) for a font size of ([\d.]+)');

  String short(String? s) {
    final t = (s ?? '?').replaceAll('\n', ' / ');
    return t.length > 44 ? t.substring(0, 44) : t;
  }

  /// Kural çıktısı `SemanticsNode#…` parçalarından oluşur; her parçadan etiketi ve ölçüyü okur.
  Iterable<String> chunks(String reason) => reason.split('SemanticsNode#').skip(1);

  for (final (name, guideline) in [
    ('dokunma-android', androidTapTargetGuideline),
    ('dokunma-ios', iOSTapTargetGuideline),
    ('etiket', labeledTapTargetGuideline),
  ]) {
    final r = await guideline.evaluate(tester);
    if (r.passed) continue;
    for (final c in chunks(r.reason ?? '')) {
      final size = tapSize.firstMatch(c);
      final text = label.firstMatch(c)?.group(1);
      if (size != null) {
        out.add('$name [${text == null ? c.split('\n').first.replaceAll(RegExp(r'\s+'), ' ') : short(text)}] ${size.group(2)}x${size.group(3)}');
      } else if (c.contains('no label') || c.contains('semantic label')) {
        out.add('$name etiketsiz [${c.split('\n').first.replaceAll(RegExp(r'\s+'), ' ')}]');
      }
    }
  }

  if (contrast) {
    final r = await textContrastGuideline.evaluate(tester);
    if (!r.passed) {
      for (final c in chunks(r.reason ?? '')) {
        final m = ratio.firstMatch(c);
        if (m == null) continue;
        out.add('kontrast [${short(label.firstMatch(c)?.group(1))}] ${m.group(2)} < ${m.group(1)} (${m.group(3)} pt)');
      }
    }
  }
  return out.toList();
}
