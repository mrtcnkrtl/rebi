import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Basit foto kalite ipuçları: ortalama parlaklık + basit keskinlik vekili.
/// Tıbbi ölçüm değil; kullanıcıyı daha tutarlı selfie için yönlendirir (web: `lib/imageQuality.js`).
class PhotoQuality {
  const PhotoQuality({
    this.meanLuma,
    this.variance,
    this.sharpnessApprox,
    this.tooDark = false,
    this.tooBlurry = false,
  });

  final double? meanLuma;
  final double? variance;
  final double? sharpnessApprox;
  final bool tooDark;
  final bool tooBlurry;

  static const empty = PhotoQuality();
}

double _round(double v, int factor) => (v * factor).round() / factor;

/// RGBA piksellerinden ölçüm (saf fonksiyon; testlerde doğrudan kullanılır).
PhotoQuality computePhotoQuality(Uint8List rgba, int w, int h) {
  final n = rgba.length ~/ 4;
  if (n == 0) return PhotoQuality.empty;
  final gray = Float64List(n);
  var sum = 0.0;
  var sumSq = 0.0;
  for (var i = 0, gi = 0; i + 3 < rgba.length; i += 4, gi++) {
    final y = 0.299 * rgba[i] + 0.587 * rgba[i + 1] + 0.114 * rgba[i + 2];
    gray[gi] = y;
    sum += y;
    sumSq += y * y;
  }
  final mean = sum / n;
  final variance = math.max(0.0, sumSq / n - mean * mean);

  // Laplacian benzeri: komşu farklarının ortalama mutlak değeri (küçük = bulanık)
  var lapSum = 0.0;
  var lapCount = 0;
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final idx = y * w + x;
      final c = gray[idx];
      final nbr = (gray[idx - 1] + gray[idx + 1] + gray[idx - w] + gray[idx + w]) / 4;
      lapSum += (c - nbr).abs();
      lapCount++;
    }
  }
  final sharpness = lapCount > 0 ? lapSum / lapCount : 0.0;

  return PhotoQuality(
    meanLuma: _round(mean / 255, 1000),
    variance: _round(variance, 10),
    sharpnessApprox: _round(sharpness, 100),
    tooDark: mean < 42,
    tooBlurry: sharpness < 2.2 && variance < 180,
  );
}

/// Görseli en uzun kenarı 160 px olacak şekilde yerel olarak küçültüp ölçer.
Future<PhotoQuality> analyzeSkinPhotoQuality(Uint8List? bytes) async {
  if (bytes == null || bytes.isEmpty) return PhotoQuality.empty;
  try {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    const maxSide = 160;
    final scale = math.min(1.0, math.min(maxSide / descriptor.width, maxSide / descriptor.height));
    final w = math.max(8, (descriptor.width * scale).round());
    final h = math.max(8, (descriptor.height * scale).round());
    final codec = await descriptor.instantiateCodec(targetWidth: w, targetHeight: h);
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final iw = frame.image.width;
    final ih = frame.image.height;
    frame.image.dispose();
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
    if (data == null) return PhotoQuality.empty;
    return computePhotoQuality(data.buffer.asUint8List(), iw, ih);
  } catch (_) {
    return PhotoQuality.empty;
  }
}
