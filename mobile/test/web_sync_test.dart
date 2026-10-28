import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/core/legal_texts.dart';

/// Web ve mobil aynı metinleri göstermeli. Web tarafında metin değişirse bu testler
/// farkı yakalar: çeviriler için `tool/sync_locales.sh`, yasal metin için `lib/core/legal_texts.dart`.
void main() {
  const webLocales = '../frontend/src/locales';
  final webAvailable = Directory(webLocales).existsSync();

  test('çeviri dosyaları web ile birebir aynı', () {
    final web = Directory(webLocales).listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.json'));
    expect(web, isNotEmpty);
    for (final f in web) {
      final rel = f.path.substring(webLocales.length + 1);
      final mobile = File('assets/locales/$rel');
      expect(mobile.existsSync(), isTrue, reason: '$rel mobilde yok — tool/sync_locales.sh çalıştırın');
      expect(jsonDecode(mobile.readAsStringSync()), jsonDecode(f.readAsStringSync()),
          reason: '$rel farklı — tool/sync_locales.sh çalıştırın');
    }
  }, skip: webAvailable ? false : 'frontend klasörü yok');

  test('KVKK ve açık rıza metinleri web ile birebir aynı', () {
    final src = File('../frontend/src/lib/legalTexts.js').readAsStringSync();
    expect(RegExp(r'LEGAL_UPDATED = "([^"]+)"').firstMatch(src)!.group(1), legalUpdated);
    String unescape(String s) => s.replaceAll(r'\"', '"');
    List<(String, String)> block(String name) {
      final body = RegExp('const $name = \\[(.*?)\\n\\];', dotAll: true).firstMatch(src)!.group(1)!;
      return [
        for (final m in RegExp(r'title: "((?:[^"\\]|\\.)*)",\s*body: "((?:[^"\\]|\\.)*)"').allMatches(body))
          (unescape(m.group(1)!), unescape(m.group(2)!)),
      ];
    }

    for (final (name, kind, lang) in [
      ('TR_KVKK', 'kvkk', 'tr'),
      ('EN_KVKK', 'kvkk', 'en'),
      ('TR_RIZA', 'riza', 'tr'),
      ('EN_RIZA', 'riza', 'en'),
    ]) {
      final web = block(name);
      final mobile = legalSections(kind, lang).map((s) => (s.title, s.body)).toList();
      expect(mobile, web, reason: '$name farklı');
    }
  }, skip: webAvailable ? false : 'frontend klasörü yok');
}
