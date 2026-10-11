import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../tw.dart';

/// Seçili temanın desenini (kalp, ayıcık, yaprak vb.) sayfa arka planında gösterir.
/// Konumlar sabit — web `ThemePatternOverlay.jsx` / `Themes.jsx` ile aynı yüzdeler.
class ThemePatternOverlay extends StatelessWidget {
  const ThemePatternOverlay({super.key, required this.pattern});

  final String pattern;

  @override
  Widget build(BuildContext context) {
    if (pattern.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: ClipRect(
        child: LayoutBuilder(builder: (context, c) => Stack(children: pagePattern(pattern, c.biggest))),
      ),
    );
  }
}

/// Tema kartındaki küçük desen önizlemesi.
class ThemePatternPreview extends StatelessWidget {
  const ThemePatternPreview({super.key, required this.pattern});

  final String pattern;

  @override
  Widget build(BuildContext context) {
    if (pattern.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: ClipRect(
        child: LayoutBuilder(builder: (context, c) => previewPattern(pattern, c.biggest)),
      ),
    );
  }
}

class _G {
  const _G(this.left, this.top, this.size, this.rotate, [this.char = '']);

  final double left;
  final double top;
  final double size;
  final double rotate;
  final String char;
}

Widget _at(Size s, _G g, Widget child) => Positioned(
      left: s.width * g.left / 100,
      top: s.height * g.top / 100,
      child: Transform.rotate(angle: g.rotate * math.pi / 180, alignment: Alignment.topLeft, child: child),
    );

Widget _emoji(String c, double size) => Text(c, style: emojiStyle(size).copyWith(height: 1));

/// Kalp karakteri (&#10084;) metin olarak boyanır; iOS'ta emojiye dönmesin diye ikon kullanılır.
Widget _heart(double size, Color color) => Icon(Icons.favorite, size: size * 1.05, color: color);

Widget _star(double size, Color color) =>
    Text('✦', style: TextStyle(fontSize: size, height: 1, color: color));

const _pageHearts = [
  _G(8, 12, 14, -8),
  _G(88, 18, 12, 12),
  _G(22, 42, 11, 5),
  _G(72, 38, 13, -14),
  _G(45, 8, 10, 0),
  _G(15, 78, 12, 18),
  _G(85, 72, 11, -6),
  _G(50, 88, 10, 10),
  _G(5, 55, 9, -12),
  _G(92, 48, 10, 8),
];

const _pageBears = [
  _G(10, 20, 18, -6, '🧸'),
  _G(82, 15, 16, 10, '🧸'),
  _G(25, 65, 15, 4, '🧸'),
  _G(70, 58, 17, -8, '🧸'),
  _G(48, 35, 14, 0, '🐻'),
  _G(12, 85, 14, 12, '🧸'),
  _G(88, 82, 13, -10, '🧸'),
];

const _leafChars = ['🌿', '🍃', '🌱'];
const _pageLeaves = [
  _G(12, 18, 0, -20, '0'),
  _G(78, 22, 0, 15, '1'),
  _G(35, 55, 0, 8, '2'),
  _G(65, 48, 0, -12, '0'),
  _G(8, 75, 0, 25, '1'),
  _G(90, 70, 0, -18, '2'),
];

const _catChars = ['🐱', '🐾', '😺', '🐈'];
const _pageCats = [
  _G(14, 25, 0, -5, '0'),
  _G(80, 20, 0, 8, '1'),
  _G(30, 70, 0, 12, '2'),
  _G(75, 65, 0, -10, '3'),
  _G(50, 40, 0, 0, '0'),
];

const _pageStars = [
  _G(10, 15, 8, 0),
  _G(85, 12, 10, 0),
  _G(25, 35, 7, 0),
  _G(70, 30, 9, 0),
  _G(45, 18, 6, 0),
  _G(15, 60, 8, 0),
  _G(88, 55, 7, 0),
  _G(50, 75, 10, 0),
  _G(5, 45, 6, 0),
  _G(92, 40, 8, 0),
];

Widget _sunburst(double alignY, List<double> stops) => DecoratedBox(
      decoration: BoxDecoration(
        gradient: SweepGradient(
          center: Alignment(0, alignY),
          // conic-gradient(from 180deg …): 0° aşağıdan başlar.
          transform: const GradientRotation(math.pi / 2),
          colors: const [
            Tw.fuchsia300,
            Color(0x00F0ABFC),
            Tw.orange300,
            Color(0x00FDBA74),
            Tw.fuchsia400,
            Color(0x00E879F9),
          ],
          stops: stops,
        ),
      ),
    );

/// Sayfa arka planı desenleri (`ThemePatternOverlay.jsx`).
List<Widget> pagePattern(String pattern, Size s) {
  switch (pattern) {
    case 'hearts':
      return [for (final g in _pageHearts) _at(s, g, _heart(g.size, Tw.pink400.withValues(alpha: .35)))];
    case 'bears':
      return [for (final g in _pageBears) _at(s, g, Opacity(opacity: .22, child: _emoji(g.char, g.size)))];
    case 'leaves':
      return [
        for (var i = 0; i < _pageLeaves.length; i++)
          _at(s, _pageLeaves[i],
              Opacity(opacity: .25, child: _emoji(_leafChars[int.parse(_pageLeaves[i].char) % 3], 13.0 + (i % 3)))),
      ];
    case 'cats':
      return [
        for (var i = 0; i < _pageCats.length; i++)
          _at(s, _pageCats[i],
              Opacity(opacity: .2, child: _emoji(_catChars[int.parse(_pageCats[i].char) % 4], 12.0 + (i % 3)))),
      ];
    case 'landscape':
      return [
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: s.height / 3,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Tw.violet200.withValues(alpha: .25), Tw.violet200.withValues(alpha: 0)],
              ),
            ),
          ),
        ),
        Positioned(left: 12, bottom: 8, child: Opacity(opacity: .25, child: _emoji('🏔️', 14))),
        Positioned(right: 20, bottom: 8, child: Opacity(opacity: .25, child: _emoji('🌸', 14))),
        Positioned(right: 32, top: 24, child: Opacity(opacity: .2, child: _emoji('☁️', 12))),
      ];
    case 'sunburst':
      return [
        Positioned.fill(child: Opacity(opacity: .22, child: _sunburst(.5, const [0, 42 / 360, 118 / 360, 198 / 360, 278 / 360, 1]))),
      ];
    case 'waves':
      return [
        Positioned(
          left: -s.width * .25,
          right: -s.width * .25,
          bottom: -4,
          height: 56,
          child: const Opacity(opacity: .8, child: _Stripes(Color(0x1F0EA5E9), 8, 16)),
        ),
        Positioned(
          left: -s.width * .125,
          right: -s.width * .125,
          bottom: 8,
          height: 36,
          child: const Opacity(opacity: .7, child: _Stripes(Color(0x2406B6D4), 6, 14)),
        ),
      ];
    case 'stars':
      return [for (final g in _pageStars) _at(s, g, _star(g.size, Tw.indigo500.withValues(alpha: .3)))];
  }
  return const [];
}

const _prevHearts = [
  _G(8, 14, 14, -8),
  _G(86, 20, 12, 12),
  _G(24, 44, 11, 5),
  _G(70, 40, 13, -12),
  _G(46, 10, 10, 0),
  _G(14, 78, 12, 16),
  _G(84, 74, 11, -6),
  _G(50, 86, 10, 8),
];

const _prevLeaves = [
  _G(12, 18, 13, -18, '🌿'),
  _G(80, 24, 12, 14, '🍃'),
  _G(34, 56, 14, 8, '🌱'),
  _G(66, 48, 12, -14, '🌿'),
  _G(8, 76, 11, 22, '🍃'),
  _G(90, 68, 13, -20, '🌱'),
];

const _prevCats = [
  _G(12, 20, 12, -5, '🐱'),
  _G(78, 18, 11, 8, '🐾'),
  _G(28, 68, 13, 10, '😺'),
  _G(72, 62, 12, -8, '🐈'),
  _G(48, 42, 11, 0, '🐱'),
];

const _prevBears = [
  _G(10, 22, 16, -6, '🧸'),
  _G(82, 16, 15, 8, '🧸'),
  _G(44, 38, 14, 0, '🐻'),
  _G(20, 72, 14, 10, '🧸'),
  _G(76, 70, 13, -10, '🧸'),
];

/// Tema kartı önizlemesi (`Themes.jsx` → `patternPreviews`).
Widget previewPattern(String pattern, Size s) {
  switch (pattern) {
    case 'hearts':
      return Opacity(
        opacity: .2,
        child: Stack(children: [for (final g in _prevHearts) _at(s, g, _heart(g.size, Tw.pink400))]),
      );
    case 'leaves':
      return Opacity(
        opacity: .2,
        child: Stack(children: [for (final g in _prevLeaves) _at(s, g, _emoji(g.char, g.size))]),
      );
    case 'cats':
      return Opacity(
        opacity: .2,
        child: Stack(children: [for (final g in _prevCats) _at(s, g, _emoji(g.char, g.size))]),
      );
    case 'bears':
      return Opacity(
        opacity: .2,
        child: Stack(children: [for (final g in _prevBears) _at(s, g, _emoji(g.char, g.size))]),
      );
    case 'landscape':
      return Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: s.height / 3,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Tw.violet200.withValues(alpha: .3), Tw.violet200.withValues(alpha: 0)],
                ),
              ),
            ),
          ),
          Positioned(left: 8, bottom: 4, child: Opacity(opacity: .3, child: _emoji('🏔️', 10))),
          Positioned(right: 12, bottom: 4, child: Opacity(opacity: .3, child: _emoji('🌸', 10))),
          Positioned(right: 8, top: 4, child: Opacity(opacity: .2, child: _emoji('☁️', 8))),
        ],
      );
    case 'sunburst':
      return Opacity(opacity: .3, child: _sunburst(.4, const [0, 40 / 360, 120 / 360, 200 / 360, 280 / 360, 1]));
    case 'waves':
      return Opacity(
        opacity: .25,
        child: Stack(
          children: [
            Positioned(
              left: -s.width * .25,
              right: -s.width * .25,
              bottom: -8,
              height: 64,
              child: const _Stripes(Color(0x260EA5E9), 8, 16),
            ),
            Positioned(
              left: -s.width * .125,
              right: -s.width * .125,
              bottom: 8,
              height: 40,
              child: const Opacity(opacity: .8, child: _Stripes(Color(0x3306B6D4), 6, 14)),
            ),
          ],
        ),
      );
    case 'stars':
      return Opacity(
        opacity: .25,
        child: Stack(
          children: [
            for (var i = 0; i < 14; i++)
              _at(
                s,
                _G(((i * 17) % 92).toDouble(), ((i * 23) % 88).toDouble(), 6.0 + (i % 4) * 3, 0),
                Opacity(opacity: .4 + (i % 3) * .2, child: _star(6.0 + (i % 4) * 3, Tw.indigo400)),
              ),
          ],
        ),
      );
  }
  return const SizedBox.shrink();
}

/// `repeating-linear-gradient(90deg, transparent gap, renk …)` + üstte yuvarlatılmış kubbe.
class _Stripes extends StatelessWidget {
  const _Stripes(this.color, this.gap, this.period);

  final Color color;
  final double gap;
  final double period;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(999)),
        child: CustomPaint(painter: _StripePainter(color, gap, period), size: Size.infinite),
      );
}

class _StripePainter extends CustomPainter {
  _StripePainter(this.color, this.gap, this.period);

  final Color color;
  final double gap;
  final double period;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (var x = gap; x < size.width; x += period) {
      canvas.drawRect(Rect.fromLTWH(x, 0, period - gap, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StripePainter old) => old.color != color;
}
