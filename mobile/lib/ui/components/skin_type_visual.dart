import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n.dart';
import '../tw.dart';

const _skinOrder = ['oily', 'dry', 'combination', 'normal', 'sensitive'];

Map<String, Color> get _activeBorder => {
  'oily': Tw.amber400,
  'dry': const Color(0xFFFB923C),
  'combination': Tw.violet400,
  'normal': const Color(0xFF34D399),
  'sensitive': Tw.pink400,
};

Map<String, Color> get _activeRing => {
  'oily': Tw.amber100,
  'dry': Tw.orange100,
  'combination': Tw.violet100,
  'normal': Tw.emerald100,
  'sensitive': Tw.pink100,
};

/// Cilt tipi doku önizlemeleri + rehber (web: `SkinTypeVisual.jsx`).
class SkinTypeVisual extends StatefulWidget {
  const SkinTypeVisual({super.key, required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<SkinTypeVisual> createState() => _SkinTypeVisualState();
}

class _SkinTypeVisualState extends State<SkinTypeVisual> {
  bool _showGuide = false;

  @override
  Widget build(BuildContext context) {
    final sp = Pack(context.i18n.analyzeWizardPack.cast<String, dynamic>());
    String label(String id) => sp.or('skinPicker.$id.label', id);

    final guideSteps = [
      ('skinPicker.morningTitle', 'skinPicker.morningDesc', 'morningSign'),
      ('skinPicker.tissueTitle', 'skinPicker.tissueDesc', 'tissueSign'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final id in _skinOrder) ...[
          _SkinCard(
            id: id,
            label: label(id),
            desc: sp.s('skinPicker.$id.desc'),
            active: widget.value == id,
            onTap: () => widget.onChanged(id),
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 4),
        InkWell(
          onTap: () => setState(() => _showGuide = !_showGuide),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(LucideIcons.circleHelp, size: 14, color: Tw.teal600),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(_showGuide ? sp.s('skinPicker.guideClose') : sp.s('skinPicker.guideOpen'),
                      style: tx(12, c: Tw.teal600)),
                ),
                const SizedBox(width: 6),
                AnimatedRotation(
                  turns: _showGuide ? .5 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: Icon(LucideIcons.chevronDown, size: 12, color: Tw.teal600),
                ),
              ],
            ),
          ),
        ),
        if (_showGuide)
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Tw.teal50.withValues(alpha: .5),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Tw.teal100),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(LucideIcons.circleHelp, size: 16, color: Tw.teal600),
                    const SizedBox(width: 8),
                    Expanded(child: Text(sp.s('skinPicker.guideTitle'), style: tx(14, w: 7))),
                  ],
                ),
                for (var si = 0; si < guideSteps.length; si++) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        width: 20,
                        height: 20,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: Tw.teal500, shape: BoxShape.circle),
                        child: Text('${si + 1}', style: tx(10, w: 7, c: Colors.white)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(sp.s(guideSteps[si].$1), style: tx(12, w: 6, c: Tw.gray800))),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(left: 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(sp.s(guideSteps[si].$2), style: tx(11, c: Tw.gray500)),
                        const SizedBox(height: 8),
                        for (final kid in _skinOrder)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(width: 56, child: Text('${label(kid)}:', style: tx(11, w: 6, c: Tw.gray700))),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(sp.s('skinPicker.${guideSteps[si].$3}.$kid'), style: tx(11, c: Tw.gray500)),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Tw.surface, borderRadius: BorderRadius.circular(12)),
                  child: Text(sp.s('skinPicker.tipLine'), style: tx(11, c: Tw.gray500)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Cilt tipinin doku küçük resmi (çizim): seçim satırlarında soldaki görsel.
class SkinTexture extends StatelessWidget {
  const SkinTexture({super.key, required this.id, this.size = 56});

  final String id;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * .24),
        child: SizedBox(width: size, height: size, child: CustomPaint(painter: _SkinTexturePainter(id))),
      ),
    );
  }
}

class _SkinCard extends StatelessWidget {
  const _SkinCard({required this.id, required this.label, required this.desc, required this.active, required this.onTap});

  final String id;
  final String label;
  final String desc;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Tw.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: active ? _activeBorder[id]! : Tw.gray200, width: 2),
          boxShadow: active ? [BoxShadow(color: _activeRing[id]!, spreadRadius: 2)] : null,
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(width: 56, height: 56, child: CustomPaint(painter: _SkinTexturePainter(id))),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(child: Text(label, style: tx(14, w: 6, c: active ? Tw.gray900 : Tw.gray700))),
                      if (active) ...[
                        const SizedBox(width: 6),
                        Icon(LucideIcons.check, size: 16, color: Tw.teal500),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(desc, style: tx(11, c: Tw.gray500, h: tight)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Webdeki CSS gradyan dokularının çizimi.
class _SkinTexturePainter extends CustomPainter {
  _SkinTexturePainter(this.id);

  final String id;

  Paint _linear(Rect r, List<Color> colors, {List<double>? stops, Alignment begin = Alignment.topLeft, Alignment end = Alignment.bottomRight}) =>
      Paint()..shader = LinearGradient(begin: begin, end: end, colors: colors, stops: stops).createShader(r);

  void _radial(Canvas c, Rect r, Offset center, double radiusFrac, Color color) {
    final radius = r.longestSide * radiusFrac;
    c.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(colors: [color, color.withValues(alpha: 0)])
            .createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  void _diag(Canvas c, Size s, double period, Color color, {bool reverse = false}) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var x = -s.height; x < s.width + s.height; x += period) {
      if (reverse) {
        c.drawLine(Offset(x, 0), Offset(x + s.height, s.height), p);
      } else {
        c.drawLine(Offset(x, s.height), Offset(x + s.height, 0), p);
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    final w = size.width;
    final h = size.height;
    switch (id) {
      case 'oily':
        canvas.drawRect(
            r, _linear(r, const [Color(0xFFFEF3C7), Color(0xFFFDE68A), Color(0xFFFEF9C3), Color(0xFFFDE68A)], stops: const [0, .4, .6, 1]));
        _radial(canvas, r, Offset(w * .3, h * .4), .4, Colors.white.withValues(alpha: .8 * .4));
        _radial(canvas, r, Offset(w * .7, h * .6), .35, Colors.white.withValues(alpha: .6 * .4));
        _radial(canvas, r, Offset(w * .5, h * .3), .3, Colors.white.withValues(alpha: .5 * .4));
        final dot = Paint()..color = Tw.amber300.withValues(alpha: .4);
        const xs = [35, 50, 65, 42, 58];
        const ys = [30, 50, 40, 65, 70];
        for (var i = 0; i < xs.length; i++) {
          canvas.drawCircle(Offset(w * xs[i] / 100 + 2, h * ys[i] / 100 + 2), 2, dot);
        }
      case 'dry':
        canvas.drawRect(r, _linear(r, const [Color(0xFFFEF3E2), Color(0xFFFDE8D0), Color(0xFFF5DCC0)]));
        _diag(canvas, size, 4, const Color(0x26C2966E).withValues(alpha: .15 * .3 * 4));
        _diag(canvas, size, 6, const Color(0x1AC2966E).withValues(alpha: .1 * .3 * 4), reverse: true);
        final wave = Paint()
          ..color = const Color(0xFFC2966E).withValues(alpha: .2)
          ..style = PaintingStyle.stroke
          ..strokeWidth = .5;
        for (var y = 10.0; y < h; y += 20) {
          for (var x = 0.0; x < w; x += 20) {
            final path = Path()
              ..moveTo(x, y)
              ..quadraticBezierTo(x + 5, y - 2, x + 10, y)
              ..quadraticBezierTo(x + 15, y + 2, x + 20, y);
            canvas.drawPath(path, wave);
          }
        }
      case 'combination':
        canvas.drawRect(
          r,
          _linear(
            r,
            const [Color(0xFFFEF3E2), Color(0xFFFEF3E2), Color(0xFFFEF9C3), Color(0xFFFEF9C3), Color(0xFFFEF3E2), Color(0xFFFEF3E2)],
            stops: const [0, .3, .4, .6, .7, 1],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
        );
        final band = Rect.fromLTWH(w / 3, 0, w / 3, h);
        canvas.drawRect(
          band,
          _linear(band, [const Color(0xFFFBBF24).withValues(alpha: .3 * .3), const Color(0xFFFBBF24).withValues(alpha: .15 * .3)],
              begin: Alignment.topCenter, end: Alignment.bottomCenter),
        );
        canvas.save();
        canvas.clipRect(Rect.fromLTWH(0, 0, w * .3, h));
        _diag(canvas, size, 7, const Color(0xFFC2966E).withValues(alpha: .12 * .15 * 4));
        canvas.restore();
        canvas.save();
        canvas.clipRect(Rect.fromLTWH(w * .7, 0, w * .3, h));
        _diag(canvas, size, 7, const Color(0xFFC2966E).withValues(alpha: .12 * .15 * 4));
        canvas.restore();
        final tp = TextPainter(
          text: TextSpan(text: 'T', style: tx(8, w: 6, c: Tw.amber500.withValues(alpha: .5), ls: 1)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset((w - tp.width) / 2, 4));
      case 'normal':
        canvas.drawRect(r, _linear(r, const [Color(0xFFFEF8F0), Color(0xFFFDF2E9), Color(0xFFFEF8F0)]));
        _radial(canvas, r, Offset(w / 2, h / 2), .7 * math.sqrt1_2, Colors.white.withValues(alpha: .4 * .3));
      case 'sensitive':
        canvas.drawRect(r, _linear(r, const [Color(0xFFFEF2F2), Color(0xFFFCE7E7), Color(0xFFFEF2F2)]));
        _radial(canvas, r, Offset(w * .3, h * .4), .5, Tw.red500.withValues(alpha: .2 * .3 * 1.5));
        _radial(canvas, r, Offset(w * .7, h * .6), .45, Tw.red500.withValues(alpha: .15 * .3 * 1.5));
        _radial(canvas, r, Offset(w * .5, h * .7), .4, Tw.red500.withValues(alpha: .1 * .3 * 1.5));
    }
  }

  @override
  bool shouldRepaint(covariant _SkinTexturePainter old) => old.id != id;
}
