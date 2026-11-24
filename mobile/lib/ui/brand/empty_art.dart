import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../tw.dart';

/// Boş durum çizimleri: karşılama illüstrasyonuyla aynı dil (krem, orman yeşili, deniz yeşili, şeftali; sol üstten tek
/// ışık), ama küçük ve durağan. Kodla çizilir; yazı, etiket ya da parıltı yoktur. Açık ve koyu temada okunur.
enum EmptyArtKind { shelf, history, journal }

class EmptyArt extends StatelessWidget {
  const EmptyArt(this.kind, {super.key, this.size = 128});

  final EmptyArtKind kind;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _EmptyArtPainter(kind, dark: Tw.dark)),
      ),
    );
  }
}

const _ink = Color(0xFF0B3D38);
const _inkMid = Color(0xFF1B6F65);
const _teal = Color(0xFF0D9488);
const _tealSoft = Color(0xFF8FD3C8);
const _cream = Color(0xFFFBF7F0);
const _paper = Color(0xFFF3EBDD);
const _peach = Color(0xFFF2B79A);
const _peachDeep = Color(0xFFE39776);

Paint _fill(Color c) => Paint()..color = c;

Paint _grad(Rect r, List<Color> colors, {Alignment begin = Alignment.topLeft, Alignment end = Alignment.bottomRight}) =>
    Paint()..shader = LinearGradient(begin: begin, end: end, colors: colors).createShader(r);

Path _leaf(double len, double wid) => Path()
  ..moveTo(0, 0)
  ..quadraticBezierTo(len * .45, -wid, len, 0)
  ..quadraticBezierTo(len * .45, wid, 0, 0)
  ..close();

class _EmptyArtPainter extends CustomPainter {
  const _EmptyArtPainter(this.kind, {required this.dark});

  final EmptyArtKind kind;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);
    canvas.save();
    canvas.translate((size.width - s) / 2, (size.height - s) / 2);
    canvas.scale(s / 100);

    // Zemin: yumuşak bir disk ve altında gölge.
    canvas.drawCircle(const Offset(50, 48), 44, _fill(dark ? Colors.white.withValues(alpha: .06) : _paper));
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(50, 84), width: 58, height: 7),
      Paint()
        ..color = (dark ? Colors.black : _ink).withValues(alpha: dark ? .35 : .10)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.2),
    );

    switch (kind) {
      case EmptyArtKind.shelf:
        _shelf(canvas);
      case EmptyArtKind.history:
        _history(canvas);
      case EmptyArtKind.journal:
        _journal(canvas);
    }
    canvas.restore();
  }

  /// Koyu temada orman yeşili zeminde kaybolur: bir ton açılır.
  Color get _inkOn => dark ? const Color(0xFF3FA294) : _ink;

  void _sprig(Canvas c, Offset at, double angle, {double scale = 1}) {
    c.save();
    c.translate(at.dx, at.dy);
    c.rotate(angle);
    c.scale(scale);
    final stem = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .9
      ..strokeCap = StrokeCap.round
      ..color = dark ? _teal : _inkMid;
    c.drawPath(Path()..moveTo(0, 0)..quadraticBezierTo(8, -2, 18, -1), stem);
    for (var i = 0; i < 4; i++) {
      final x = 4.0 + i * 4.2;
      c.save();
      c.translate(x, -1);
      c.rotate(i.isEven ? -.9 : .9);
      c.drawPath(_leaf(7 - i * .8, 2.4), _fill(i.isEven ? _teal : (dark ? _tealSoft : _inkMid)));
      c.restore();
    }
    c.restore();
  }

  /// Rafım: küçük bir podyumda şişe ve kavanoz, köşede "tamam" mührü.
  void _shelf(Canvas c) {
    // podyum: silindir (alt elips + yan yüz + üst elips)
    const side = Rect.fromLTWH(24, 70.5, 52, 10);
    final sideFill = _grad(side, [const Color(0xFFEDE3D2), const Color(0xFFDCCFB9)], begin: Alignment.centerLeft, end: Alignment.centerRight);
    c.drawOval(const Rect.fromLTWH(24, 76, 52, 9), sideFill);
    c.drawRect(side, sideFill);
    const top = Rect.fromLTWH(24, 66, 52, 9);
    c.drawOval(top, _fill(_cream));
    c.drawOval(top, Paint()..style = PaintingStyle.stroke..strokeWidth = .6..color = _ink.withValues(alpha: .16));
    // şişe (pompalı)
    const body = Rect.fromLTWH(33, 36, 16, 34);
    c.drawRRect(RRect.fromRectAndRadius(body, const Radius.circular(4)), _grad(body, [_tealSoft, _teal]));
    c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(37, 30, 8, 7), const Radius.circular(1.5)), _fill(_inkOn));
    c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(39.5, 24, 3, 7), const Radius.circular(1)), _fill(_inkOn));
    c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(39.5, 24, 9, 2.6), const Radius.circular(1)), _fill(_inkOn));
    c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(36, 48, 10, 11), const Radius.circular(1.5)), _fill(_cream.withValues(alpha: .9)));
    c.drawRect(const Rect.fromLTWH(38, 51, 6, .9), _fill(_inkMid));
    c.drawRect(const Rect.fromLTWH(38, 54, 4, .9), _fill(_inkMid));
    // ışık çizgisi
    c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(35, 39, 2, 26), const Radius.circular(1)), _fill(Colors.white.withValues(alpha: .35)));
    // kavanoz
    const jar = Rect.fromLTWH(52, 55, 18, 15);
    c.drawRRect(RRect.fromRectAndRadius(jar, const Radius.circular(4)), _grad(jar, [_peach, _peachDeep]));
    c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(51, 51, 20, 5.5), const Radius.circular(2)), _fill(_cream));
    c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(54, 58, 2, 9), const Radius.circular(1)), _fill(Colors.white.withValues(alpha: .35)));
    // mühür
    c.drawCircle(const Offset(68, 32), 9, _fill(_inkOn));
    c.drawPath(
      Path()
        ..moveTo(64.2, 32.2)
        ..lineTo(67, 35)
        ..lineTo(72, 29.2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = _cream,
    );
    _sprig(c, const Offset(22, 72), -1.1, scale: .9);
  }

  /// Geçmiş: spiralli bir takvim sayfası; birkaç gün işaretli.
  void _history(Canvas c) {
    const page = Rect.fromLTWH(24, 24, 52, 56);
    c.drawRRect(RRect.fromRectAndRadius(page.shift(const Offset(1.5, 2)), const Radius.circular(7)), _fill(_ink.withValues(alpha: .08)));
    c.drawRRect(RRect.fromRectAndRadius(page, const Radius.circular(7)), _fill(_cream));
    c.drawRRect(
      RRect.fromRectAndCorners(const Rect.fromLTWH(24, 24, 52, 13), topLeft: const Radius.circular(7), topRight: const Radius.circular(7)),
      _grad(const Rect.fromLTWH(24, 24, 52, 13), [_inkMid, _ink]),
    );
    for (final x in [36.0, 64.0]) {
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x - 1.6, 19, 3.2, 9), const Radius.circular(1.6)), _fill(_inkOn));
    }
    // gün ızgarası: 4×3; birkaçı dolu
    const filled = {0, 1, 3, 5, 6};
    for (var r = 0; r < 3; r++) {
      for (var col = 0; col < 4; col++) {
        final i = r * 4 + col;
        final center = Offset(32 + col * 12.0, 47 + r * 11.0);
        if (filled.contains(i)) {
          c.drawCircle(center, 3.6, _fill(_teal));
        } else if (i == 7) {
          c.drawCircle(center, 3.6, _fill(_peach));
        } else {
          c.drawCircle(center, 3.4, Paint()..style = PaintingStyle.stroke..strokeWidth = .9..color = _ink.withValues(alpha: .22));
        }
      }
    }
    _sprig(c, const Offset(70, 82), -2.4, scale: .9);
  }

  /// Cilt günlüğü: üst üste iki fotoğraf karesi (önce / sonra), ortada yumuşak bir yüz silueti.
  void _journal(Canvas c) {
    void photo(Offset center, double angle, Color tone, Color face) {
      c.save();
      c.translate(center.dx, center.dy);
      c.rotate(angle);
      const frame = Rect.fromLTWH(-17, -21, 34, 42);
      c.drawRRect(RRect.fromRectAndRadius(frame.shift(const Offset(1.2, 1.6)), const Radius.circular(4)), _fill(_ink.withValues(alpha: .10)));
      c.drawRRect(RRect.fromRectAndRadius(frame, const Radius.circular(4)), _fill(_cream));
      const pic = Rect.fromLTWH(-13.5, -17.5, 27, 28);
      c.drawRRect(RRect.fromRectAndRadius(pic, const Radius.circular(2.5)), _fill(tone));
      c.save();
      c.clipRRect(RRect.fromRectAndRadius(pic, const Radius.circular(2.5)));
      c.drawOval(const Rect.fromLTWH(-6.5, -13, 13, 15), _fill(face));
      c.drawOval(const Rect.fromLTWH(-12, 1, 24, 16), _fill(face));
      c.restore();
      c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-10, 14, 12, 1.4), const Radius.circular(.7)), _fill(_ink.withValues(alpha: .25)));
      c.restore();
    }

    photo(const Offset(40, 52), -.16, _tealSoft.withValues(alpha: .55), _inkMid.withValues(alpha: .55));
    photo(const Offset(60, 48), .12, _peach.withValues(alpha: .55), _peachDeep);
    // küçük ok: önce → sonra
    c.drawPath(
      Path()
        ..moveTo(44, 20)
        ..quadraticBezierTo(52, 14, 60, 19),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round
        ..color = dark ? _tealSoft : _inkMid,
    );
    c.drawPath(
      Path()
        ..moveTo(57.4, 16.2)
        ..lineTo(60.4, 19.3)
        ..lineTo(56.6, 20.6),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = dark ? _tealSoft : _inkMid,
    );
  }

  @override
  bool shouldRepaint(covariant _EmptyArtPainter old) => old.kind != kind || old.dark != dark;
}
