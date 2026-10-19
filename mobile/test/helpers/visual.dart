import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Görsel kontrol altyapısı: ekranları GERÇEK yazı tipleriyle (Inter, Fraunces, Lucide) PNG olarak yazar.
///
///     REBI_SCREENSHOTS=1 flutter test test/visual_gallery_test.dart
///
/// Çıktı `build/screenshots/`ta durur. Bilerek piksel karşılaştırması (golden) YAPMAZ: yazı tipi işleme Windows,
/// macOS ve Linux'ta piksel piksel aynı olmadığı için CI'da kararsız olurdu. Bu araç gözle bakmak içindir; taşma ve
/// yerleşim hataları ise normal ekran testleriyle (`screens_test`, `text_scale_test`) yakalanır.
bool get screenshotsEnabled => Platform.environment['REBI_SCREENSHOTS'] == '1';

Directory get screenshotDir => Directory('build/screenshots');

/// Mağaza ekran görüntüleri: `REBI_STORE_SHOTS=1 flutter test test/store_screenshots_test.dart` (çıktı `build/store/`).
bool get storeShotsEnabled => Platform.environment['REBI_STORE_SHOTS'] == '1';

bool _fontsLoaded = false;

/// Gerçek yazı tiplerini yükler (bir kez). `flutter test` pubspec'teki yazı tiplerini kendiliğinden yüklemez.
Future<void> loadBrandFonts() async {
  if (_fontsLoaded) return;
  Future<ByteData> bytes(String path) async => ByteData.sublistView(Uint8List.fromList(await File(path).readAsBytes()));

  final inter = FontLoader('Inter')..addFont(bytes('assets/fonts/InterVariable.ttf'));
  final fraunces = FontLoader('Fraunces')..addFont(bytes('assets/fonts/Fraunces.ttf'));
  await inter.load();
  await fraunces.load();

  // Lucide ikonları paketin kendi yazı tipinden gelir (yolu paket yapılandırmasından okunur).
  final config = jsonDecode(File('.dart_tool/package_config.json').readAsStringSync()) as Map<String, dynamic>;
  for (final pkg in (config['packages'] as List).cast<Map<String, dynamic>>()) {
    if (pkg['name'] != 'lucide_icons_flutter') continue;
    final raw = pkg['rootUri'] as String;
    final root = Uri.parse(raw.endsWith('/') ? raw : '$raw/');
    final font = File.fromUri(Directory('.dart_tool').absolute.uri.resolveUri(root).resolve('assets/lucide.ttf'));
    if (font.existsSync()) {
      final lucide = FontLoader('packages/lucide_icons_flutter/Lucide')..addFont(bytes(font.path));
      await lucide.load();
    }
  }
  _fontsLoaded = true;
}

/// Mevcut ekranı `build/screenshots/<name>.png` (ya da [into]) olarak yazar ([width] çıktının piksel genişliği).
Future<void> shoot(WidgetTester tester, String name, {double width = 780, Directory? into}) async {
  final view = tester.binding.renderViews.first;
  final layer = view.debugLayer;
  if (layer is! OffsetLayer) throw StateError('Katman okunamadı: $layer');
  // Katman koordinatları fiziksel pikseldir (cihaz oranı kadar büyük).
  final dpr = tester.view.devicePixelRatio;
  final physical = Size(view.size.width * dpr, view.size.height * dpr);
  await tester.runAsync(() async {
    final image = await layer.toImage(Offset.zero & physical, pixelRatio: width / physical.width);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = into ?? screenshotDir;
    dir.createSync(recursive: true);
    File('${dir.path}/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
    image.dispose();
  });
}
