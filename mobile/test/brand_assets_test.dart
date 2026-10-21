import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/ui/brand/brand_mark.dart';

/// Marka varlıklarının tek kaynağı: uygulama içi `BrandMark`'ın geometrisi (`BrandGlyph`).
/// Yalnızca `REBI_BRAND_ASSETS=1` ile üretir; ardından eklenti iOS ve Android ikon boyutlarını çıkarır:
///
///     cd mobile && REBI_BRAND_ASSETS=1 flutter test test/brand_assets_test.dart && dart run flutter_launcher_icons
///
/// Üretilenler:
/// - `assets/icon/icon.png` (1024, tam kaplayan karo; iOS ve eski Android ikonlarının kaynağı),
///   `assets/icon/icon-maskable.png` (1024, Android uyarlanabilir ikon önü; harf güvenli bölgede),
///   `assets/icon/play-store-512.png` (Play Console ikonu),
/// - `android/.../drawable-*dpi/ic_stat_rebi.png` (tek renkli bildirim simgesi),
/// - `android/.../drawable-v31/splash_logo.xml` (Android 12+ açılış logosu; vektör olduğu için her çözünürlükte keskin).
///
/// Android 12+ sistem açılış ekranı simgeyi 288 dp alana büyütür; PNG kullanılırsa pikselleşir, bu yüzden vektördür.
/// Bu dosya her zaman çalışan iki koruma da içerir: ikon kaynakları ≥1024 px olmalı ve açılış vektörü geometriyle
/// güncel olmalı (geometriyi değiştirip yeniden üretmeyi unutmak CI'da yakalanır).
bool get _generate => Platform.environment['REBI_BRAND_ASSETS'] == '1';

const _res = 'android/app/src/main/res';
const _splashXml = '$_res/drawable-v31/splash_logo.xml';

/// Harf + parıltı birlikte karenin ortasında dursun diye uygulanan kaydırma (harfin gövdesi sağa, parıltı sağ üste çeker).
const _optical = Offset(-.03, .01);

/// Tam kaplayan ikonda harfin ölçeği (1 = uygulama içi `BrandMark` oranı).
const _iconScale = .92;

/// Uyarlanabilir ikonda görünen alan ön planın 72/108'idir; harf bunun içinde kalsın.
const _maskableScale = _iconScale * 72 / 108;

/// Android açılış simgesi: 288 dp tuval, ortada Flutter açılışındaki karo ile aynı boyutta (104 dp) karo.
const _splashCanvas = 288.0;
const _splashTile = 104.0;

String _n(double v) {
  final r = double.parse(v.toStringAsFixed(3));
  return r == r.roundToDouble() ? r.round().toString() : r.toString();
}

String _argb(Color c) => '#${c.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';

/// Android 12+ açılış logosu (VectorDrawable). Harf ve parıltı `BrandGlyph`'tan gelir.
String splashLogoXml() {
  const o = (_splashCanvas - _splashTile) / 2;
  const t = _splashTile;
  const r = t * BrandMark.cornerRadius;
  final tile = 'M${_n(o + r)} ${_n(o)}H${_n(o + t - r)}A${_n(r)} ${_n(r)} 0 0 1 ${_n(o + t)} ${_n(o + r)}'
      'V${_n(o + t - r)}A${_n(r)} ${_n(r)} 0 0 1 ${_n(o + t - r)} ${_n(o + t)}H${_n(o + r)}'
      'A${_n(r)} ${_n(r)} 0 0 1 ${_n(o)} ${_n(o + t - r)}V${_n(o + r)}A${_n(r)} ${_n(r)} 0 0 1 ${_n(o + r)} ${_n(o)}Z';
  const at = Offset(o, o);
  final letter = BrandGlyph.svg(BrandGlyph.letter, scale: t, at: at);
  final star = BrandGlyph.svg(BrandGlyph.star(BrandGlyph.sparkleAt, BrandGlyph.sparkleSize), scale: t, at: at);
  final colors = BrandMark.gradient.colors;
  return '''<?xml version="1.0" encoding="utf-8"?>
<!-- Android 12+ sistem açılış ekranı logosu. ÜRETİLİR: test/brand_assets_test.dart (elle düzenlemeyin). -->
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:aapt="http://schemas.android.com/aapt"
    android:width="${_n(_splashCanvas)}dp"
    android:height="${_n(_splashCanvas)}dp"
    android:viewportWidth="${_n(_splashCanvas)}"
    android:viewportHeight="${_n(_splashCanvas)}">
    <path android:pathData="$tile">
        <aapt:attr name="android:fillColor">
            <gradient
                android:type="linear"
                android:startX="${_n(o)}"
                android:startY="${_n(o)}"
                android:endX="${_n(o + t)}"
                android:endY="${_n(o + t)}"
                android:startColor="${_argb(colors.first)}"
                android:endColor="${_argb(colors.last)}" />
        </aapt:attr>
    </path>
    <path
        android:pathData="$letter"
        android:fillColor="#00000000"
        android:strokeColor="#FFFFFFFF"
        android:strokeWidth="${_n(t * BrandGlyph.stroke)}"
        android:strokeLineCap="round"
        android:strokeLineJoin="round" />
    <path
        android:pathData="$star"
        android:fillColor="#F2FFFFFF" />
</vector>
''';
}

/// [px] kenarlı kareye çizer. [fill] true ise karo gradyanı tüm kareyi kaplar (OS kendi maskesini uygular).
Future<void> _png(
  String path,
  int px, {
  bool fill = false,
  double scale = 1,
  Offset shift = Offset.zero,
  bool sparkle = true,
}) async {
  final s = px.toDouble();
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  if (fill) {
    final rect = Rect.fromLTWH(0, 0, s, s);
    canvas.drawRect(rect, Paint()..shader = BrandMark.gradient.createShader(rect));
  }
  canvas
    ..translate(s / 2 + shift.dx * s, s / 2 + shift.dy * s)
    ..scale(scale)
    ..translate(-s / 2, -s / 2);
  BrandGlyphPainter(1, sparkle ? 1 : 0).paint(canvas, Size(s, s));
  final image = await recorder.endRecording().toImage(px, px);
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes.buffer.asUint8List());
}

/// PNG başlığından (genişlik, yükseklik).
(int, int) _pngSize(String path) {
  final h = ByteData.sublistView(File(path).readAsBytesSync(), 16, 24);
  return (h.getUint32(0), h.getUint32(4));
}

void main() {
  // Üretim modunda atlanır: aynı koşuda henüz yenilenmemiş dosyaları görüp zinciri (`&& dart run ...`) durdurmasın.
  group('marka varlıkları', skip: _generate, () {
    test('ikon kaynakları mağaza boyutunda (en az 1024 px) ve kare', () {
      for (final f in ['icon', 'icon-maskable']) {
        final (w, h) = _pngSize('assets/icon/$f.png');
        expect(w, h, reason: '$f kare olmalı');
        expect(w, greaterThanOrEqualTo(1024), reason: '$f: iOS 1024 ikonu ve Android 12 açılışı büyütülünce pikselleşir');
      }
    });

    test('Android 12 açılış vektörü BrandGlyph ile güncel', () {
      expect(File(_splashXml).readAsStringSync().replaceAll('\r\n', '\n'), splashLogoXml(),
          reason: 'BrandGlyph değişti: REBI_BRAND_ASSETS=1 flutter test test/brand_assets_test.dart ile yeniden üretin');
    });
  });

  testWidgets('üret', (tester) async {
    await tester.runAsync(() async {
      await _png('assets/icon/icon.png', 1024, fill: true, scale: _iconScale, shift: _optical);
      await _png('assets/icon/icon-maskable.png', 1024, fill: true, scale: _maskableScale, shift: _optical);
      await _png('assets/icon/play-store-512.png', 512, fill: true, scale: _iconScale, shift: _optical);

      // Bildirim küçük simgesi: tek renk, parıltısız (24 dp'de parıltı lekeye dönüşür). Harf 20/24 dp'yi doldurur.
      const stat = {'mdpi': 24, 'hdpi': 36, 'xhdpi': 48, 'xxhdpi': 72, 'xxxhdpi': 96};
      for (final e in stat.entries) {
        await _png('$_res/drawable-${e.key}/ic_stat_rebi.png', e.value, scale: 1.3, shift: const Offset(-.025, -.005), sparkle: false);
      }

      File(_splashXml)
        ..createSync(recursive: true)
        ..writeAsStringSync(splashLogoXml());
    });
  }, skip: !_generate);
}
