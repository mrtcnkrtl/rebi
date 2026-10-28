import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../tw.dart';

/// Eğilim grafikleri (yeni bağımlılık yok; `CustomPaint`). Değerler soldan sağa eskiden yeniye
/// sıralıdır, `null` o gün için kayıt olmadığı anlamına gelir. Renkleri `build` içinde çözülür,
/// bu yüzden açık / koyu mod ile birlikte değişir. Ekran okuyucu için `semanticLabel` özetini okur.
const _chartHeight = 88.0;

/// Çizgi grafikte birleştirilen en uzun kayıtsız boşluk (nokta sayısı).
const maxGapSlots = 3;

/// Günlük sütunlar (örn. su). `reference` kesikli hedef çizgisidir.
class TrendBars extends StatelessWidget {
  const TrendBars({
    super.key,
    required this.values,
    required this.maxY,
    required this.color,
    required this.semanticLabel,
    this.reference,
    this.height = _chartHeight,
  });

  final List<double?> values;
  final double maxY;
  final Color color;
  final double? reference;
  final double height;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) => _Chart(
        height: height,
        semanticLabel: semanticLabel,
        painter: _BarsPainter(values, maxY, color, Tw.gray200, Tw.gray400, reference),
      );
}

/// Çizgi grafik. `band` (alt, üst) hafif renkli bir aralık çizer; kayıtsız günlerde çizgi kopar.
class TrendLine extends StatelessWidget {
  const TrendLine({
    super.key,
    required this.values,
    required this.minY,
    required this.maxY,
    required this.color,
    required this.semanticLabel,
    this.band,
    this.height = _chartHeight,
  });

  final List<double?> values;
  final double minY;
  final double maxY;
  final Color color;
  final (double, double)? band;
  final double height;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) => _Chart(
        height: height,
        semanticLabel: semanticLabel,
        painter: _LinePainter(values, minY, maxY, color, Tw.gray200, Tw.green500.withValues(alpha: .16), band),
      );
}

/// Gün kutuları: değer 0–1 arası doluluk. `null` kayıt yok (soluk), 0 kayıt var ama yapılmamış (gri).
class TrendStrip extends StatelessWidget {
  const TrendStrip({super.key, required this.values, required this.color, required this.semanticLabel, this.height = 28});

  final List<double?> values;
  final Color color;
  final double height;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) => _Chart(
        height: height,
        semanticLabel: semanticLabel,
        painter: _StripPainter(values, color, Tw.gray100, Tw.gray300),
      );
}

class _Chart extends StatelessWidget {
  const _Chart({required this.height, required this.semanticLabel, required this.painter});

  final double height;
  final String semanticLabel;
  final CustomPainter painter;

  @override
  Widget build(BuildContext context) => Semantics(
        label: semanticLabel,
        image: true,
        child: ExcludeSemantics(
          child: SizedBox(
            height: height,
            width: double.infinity,
            child: CustomPaint(painter: painter),
          ),
        ),
      );
}

Paint _fill(Color c) => Paint()..color = c;

void _dashedHLine(Canvas canvas, double y, double width, Paint paint) {
  const dash = 5.0, gap = 4.0;
  for (var x = 0.0; x < width; x += dash + gap) {
    canvas.drawLine(Offset(x, y), Offset(math.min(x + dash, width), y), paint);
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter(this.values, this.maxY, this.color, this.track, this.refColor, this.reference);

  final List<double?> values;
  final double maxY;
  final Color color;
  final Color track;
  final Color refColor;
  final double? reference;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty || maxY <= 0) return;
    final slot = size.width / values.length;
    final barW = (slot * .64).clamp(2.0, 18.0);
    final base = size.height - 1;
    final usable = base - 2;

    canvas.drawLine(Offset(0, base), Offset(size.width, base), Paint()..color = track..strokeWidth = 1);
    for (var i = 0; i < values.length; i++) {
      final cx = slot * (i + .5);
      final v = values[i];
      // Kayıt yok: tabanda küçük soluk işaret; kayıt var ama çok düşük: en az 3 px görünür.
      final h = v == null ? 2.0 : math.max(3.0, usable * (v / maxY).clamp(0.0, 1.0));
      final rect = RRect.fromRectAndCorners(
        Rect.fromLTWH(cx - barW / 2, base - h, barW, h),
        topLeft: const Radius.circular(3),
        topRight: const Radius.circular(3),
      );
      canvas.drawRRect(rect, _fill(v == null ? track : color));
    }
    final ref = reference;
    if (ref != null && ref > 0 && ref <= maxY) {
      _dashedHLine(
        canvas,
        base - usable * (ref / maxY),
        size.width,
        Paint()
          ..color = refColor
          ..strokeWidth = 1.2,
      );
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      !listEquals(old.values, values) || old.maxY != maxY || old.color != color || old.track != track || old.refColor != refColor || old.reference != reference;
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.values, this.minY, this.maxY, this.color, this.grid, this.bandColor, this.band);

  final List<double?> values;
  final double minY;
  final double maxY;
  final Color color;
  final Color grid;
  final Color bandColor;
  final (double, double)? band;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty || maxY <= minY) return;
    const pad = 6.0;
    final h = size.height - pad * 2;
    double yOf(double v) => pad + h * (1 - ((v - minY) / (maxY - minY)).clamp(0.0, 1.0));

    final b = band;
    if (b != null) {
      final top = yOf(b.$2), bottom = yOf(b.$1);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(0, top, size.width, bottom), const Radius.circular(4)), _fill(bandColor));
    }
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final f in const [0.0, .5, 1.0]) {
      final y = pad + h * f;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final slot = size.width / values.length;
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final dotR = values.length <= 14 ? 3.4 : 2.6;

    // Kısa boşluklar (en çok 3 kayıtsız gün) çizgiyle birleşir; daha uzunsa çizgi kopar, uydurma eğilim çizilmez.
    Path? run;
    var last = -1;
    void flush() {
      if (run != null) canvas.drawPath(run!, line);
      run = null;
    }

    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      if (v == null) continue;
      final p = Offset(slot * (i + .5), yOf(v));
      if (run != null && i - last > maxGapSlots + 1) flush();
      if (run == null) {
        run = Path()..moveTo(p.dx, p.dy);
      } else {
        run!.lineTo(p.dx, p.dy);
      }
      last = i;
    }
    flush();

    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      if (v == null) continue;
      final p = Offset(slot * (i + .5), yOf(v));
      canvas.drawCircle(p, dotR + 1.2, _fill(Tw.surface));
      canvas.drawCircle(p, dotR, _fill(color));
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      !listEquals(old.values, values) ||
      old.minY != minY ||
      old.maxY != maxY ||
      old.color != color ||
      old.grid != grid ||
      old.bandColor != bandColor ||
      old.band != band;
}

class _StripPainter extends CustomPainter {
  _StripPainter(this.values, this.color, this.empty, this.zero);

  final List<double?> values;
  final Color color;
  final Color empty;
  final Color zero;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final slot = size.width / values.length;
    final gap = slot > 8 ? 2.0 : 1.0;
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      final c = v == null ? empty : (v <= 0 ? zero : color.withValues(alpha: .35 + .65 * v.clamp(0.0, 1.0)));
      final rect = RRect.fromRectAndRadius(Rect.fromLTWH(slot * i + gap / 2, 0, math.max(1.0, slot - gap), size.height), const Radius.circular(4));
      canvas.drawRRect(rect, _fill(c));
    }
  }

  @override
  bool shouldRepaint(_StripPainter old) =>
      !listEquals(old.values, values) || old.color != color || old.empty != empty || old.zero != zero;
}
