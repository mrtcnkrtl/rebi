import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n.dart';
import '../tw.dart';
import '../brand/palette.dart';

List<(IconData, String, Color)> get _steps => [
  (LucideIcons.cloudSun, I18n.instance.t('mobileMisc.loadingWeather'), Tw.blue500),
  (LucideIcons.bookOpen, I18n.instance.t('mobileMisc.loadingLiterature'), Tw.purple500),
  (LucideIcons.brain, I18n.instance.t('mobileMisc.loadingAi'), Tw.teal500),
  (LucideIcons.sparkles, I18n.instance.t('mobileMisc.loadingRoutine'), Tw.amber500),
];

/// Rutin üretilirken gösterilen adım adım bekleme ekranı (web: `LoadingScreen.jsx`).
class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen> with TickerProviderStateMixin {
  int _current = 0;
  Timer? _timer;
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..repeat(reverse: true);
  late final AnimationController _bounce =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 500))..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 2500), (_) {
      if (_current < _steps.length - 1) setState(() => _current++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulse.dispose();
    _bounce.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Tw.teal50, Tw.surface]),
      ),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 384),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FadeTransition(
                  opacity: Tween(begin: 1.0, end: .5).animate(_pulse),
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      color: Tw.teal600,
                    ),
                    child: const Icon(LucideIcons.leaf, size: 40, color: Colors.white),
                  ),
                ),
                const SizedBox(height: 32),
                Text(I18n.instance.t('mobileMisc.loadingTitle'), style: heading(26)),
                const SizedBox(height: 8),
                Text(I18n.instance.t('mobileMisc.loadingSubtitle'), textAlign: TextAlign.center, style: tx(16, c: Tw.gray500)),
                const SizedBox(height: 40),
                for (var i = 0; i < _steps.length; i++) ...[
                  _StepRow(index: i, current: _current, bounce: _bounce),
                  const SizedBox(height: 16),
                ],
                const SizedBox(height: 24),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    height: 8,
                    color: Tw.gray100,
                    alignment: Alignment.centerLeft,
                    child: AnimatedFractionallySizedBox(
                      duration: const Duration(milliseconds: 1000),
                      curve: Curves.easeOut,
                      widthFactor: (_current + 1) / _steps.length,
                      child: Container(
                        color: Tw.teal600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.index, required this.current, required this.bounce});

  final int index;
  final int current;
  final AnimationController bounce;

  @override
  Widget build(BuildContext context) {
    final step = _steps[index];
    final active = index == current;
    final done = index < current;
    final opacity = active ? 1.0 : (done ? .7 : .3);

    Widget icon = done
        ? const Icon(LucideIcons.check, size: 20, color: Colors.white)
        : Icon(step.$1, size: 20, color: active ? step.$3 : Tw.gray400);
    if (active) {
      icon = AnimatedBuilder(
        animation: bounce,
        builder: (context, child) => Transform.translate(offset: Offset(0, -4 * bounce.value), child: child),
        child: icon,
      );
    }

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 500),
      opacity: opacity,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 500),
        scale: active ? 1.02 : 1,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 500),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: active ? Tw.surface : (done ? Tw.teal50.withValues(alpha: .5) : Colors.transparent),
            borderRadius: BorderRadius.circular(16),
            boxShadow: active ? [BoxShadow(color: Tw.gray200.withValues(alpha: .5), blurRadius: 15, offset: const Offset(0, 8))] : null,
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 500),
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: active ? Tw.teal100 : (done ? Tw.teal500 : Tw.gray100),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(child: icon),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  step.$2,
                  style: tx(16, w: 5, c: active ? Tw.gray900 : (done ? Tw.teal700 : Tw.gray400)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
