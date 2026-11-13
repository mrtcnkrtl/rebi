import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Sistem "animasyonları azalt" ayarı açıksa süslü hareketler kapanır.
bool reduceMotion(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// Ekrana ilk girişte aşağıdan yukarı süzülerek belirir. Gecikme, zamanlayıcı yerine tek bir
/// animasyonun içindeki aralıkla verilir (test ve arka plan dostu).
class Reveal extends StatefulWidget {
  const Reveal({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 650),
    this.offset = const Offset(0, 22),
    this.scaleFrom = 1,
    this.curve = Curves.easeOutCubic,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final Offset offset;

  /// 1'den küçükse öğe bu ölçekten büyüyerek belirir.
  final double scaleFrom;
  final Curve curve;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.delay + widget.duration);
  late final Animation<double> _t = CurvedAnimation(
    parent: _c,
    curve: Interval(
      widget.delay.inMilliseconds / (widget.delay + widget.duration).inMilliseconds,
      1,
      curve: widget.curve,
    ),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (reduceMotion(context)) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: _t.value.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: widget.offset * (1 - _t.value),
          child: Transform.scale(scale: widget.scaleFrom + (1 - widget.scaleFrom) * _t.value, child: child),
        ),
      ),
    );
  }
}

/// Dokunmaya yumuşak "basılma" geri bildirimi verir (dalga yerine küçülme + hafif titreşim). Basarken çabuk küçülür,
/// bırakınca yay gibi hafifçe aşıp yerine oturur (`easeOutBack`).
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, required this.onTap, this.scale = .97, this.haptic = true, this.impact = false});

  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  final bool haptic;

  /// true ise seçim tıkırtısı yerine daha belirgin hafif darbe (ana eylem düğmeleri).
  final bool impact;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _set(true) : null,
        onTapUp: enabled ? (_) => _set(false) : null,
        onTapCancel: enabled ? () => _set(false) : null,
        onTap: enabled
            ? () {
                if (widget.haptic) unawaited((widget.impact ? HapticFeedback.lightImpact() : HapticFeedback.selectionClick()).catchError((_) {}));
                widget.onTap!();
              }
            : null,
        child: AnimatedScale(
          scale: _down ? widget.scale : 1,
          duration: Duration(milliseconds: _down ? 100 : 320),
          curve: _down ? Curves.easeOut : Curves.easeOutBack,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Hata anında içeriği yatayda kısa süre titretir; [trigger] her arttığında oynar.
class Shake extends StatefulWidget {
  const Shake({super.key, required this.child, required this.trigger});

  final Widget child;
  final int trigger;

  @override
  State<Shake> createState() => _ShakeState();
}

class _ShakeState extends State<Shake> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));

  @override
  void didUpdateWidget(covariant Shake old) {
    super.didUpdateWidget(old);
    if (widget.trigger != old.trigger && !reduceMotion(context)) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final dx = math.sin(_c.value * math.pi * 5) * 8 * (1 - _c.value);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
    );
  }
}

/// [child]in üstünden bir kez, yumuşak bir ışık bandı geçirir (ana eylem düğmesine dikkat çeker). [delay] sonra
/// [duration] boyunca oynar; "animasyonları azalt" açıkken hiç oynamaz. Dokunmayı engellemez.
class ShimmerOnce extends StatefulWidget {
  const ShimmerOnce({
    super.key,
    required this.child,
    required this.radius,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 1100),
    this.color = const Color(0xFF14B8A6),
  });

  final Widget child;

  /// Bandın kırpılacağı köşe yarıçapı (düğmeninkiyle aynı).
  final double radius;
  final Duration delay;
  final Duration duration;

  /// Bandın rengi: zemine göre görünür olmalı (krem düğmede turkuaz, koyu düğmede beyaz).
  final Color color;

  @override
  State<ShimmerOnce> createState() => _ShimmerOnceState();
}

class _ShimmerOnceState extends State<ShimmerOnce> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.delay + widget.duration);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!reduceMotion(context)) _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final start = widget.delay.inMilliseconds / (widget.delay + widget.duration).inMilliseconds;
    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) {
                  final p = Curves.easeInOut.transform(Interval(start, 1).transform(_c.value));
                  if (p <= 0 || p >= 1) return const SizedBox.shrink();
                  return CustomPaint(painter: _ShimmerPainter(p, widget.radius, widget.color));
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ShimmerPainter extends CustomPainter {
  _ShimmerPainter(this.p, this.radius, this.color);

  final double p;
  final double radius;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final clip = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));
    canvas.save();
    canvas.clipRRect(clip);
    // Eğik, yumuşak kenarlı bant: soldan sağa süzülür; ortası en parlak, kenarları saydam.
    final w = size.width * .34;
    final x = -w + (size.width + 2 * w) * p;
    canvas.translate(x, size.height / 2);
    canvas.rotate(-.35);
    final band = Rect.fromLTWH(-w / 2, -size.height * 1.2, w, size.height * 2.4);
    canvas.drawRect(
      band,
      Paint()
        ..shader = LinearGradient(
          colors: [color.withValues(alpha: 0), color.withValues(alpha: .22), color.withValues(alpha: 0)],
        ).createShader(band),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ShimmerPainter old) => old.p != p;
}
