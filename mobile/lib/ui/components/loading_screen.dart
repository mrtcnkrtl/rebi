import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/i18n.dart';
import '../../state/theme_controller.dart';
import '../brand/brand_mark.dart';
import '../brand/motion.dart';
import '../brand/palette.dart';
import '../tw.dart';

/// Rutin üretilirken (birkaç saniyeden bir-iki dakikaya) gösterilen bekleme ekranı. Uygulamanın dilindedir: temanın derin tonunda
/// tam ekran sahne, krem Fraunces başlık, dört adımlı sakin bir zaman çizelgesi (biten adım solar ve tik alır, sıradaki nefes alır).
/// Adımlar gerçek ilerleme değil, sürecin ne yaptığını anlatır; son adım iş bitene kadar sürer. "Animasyonları azalt" açıkken nefes yoktur.
class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen> with SingleTickerProviderStateMixin {
  static const _stepKeys = ['weather', 'science', 'ai', 'build'];

  int _current = 0;
  Timer? _timer;
  late final AnimationController _breath = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 2800), (_) {
      if (_current < _stepKeys.length - 1) setState(() => _current++);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _breath.stop();
      _breath.value = 0;
    } else if (!_breath.isAnimating) {
      _breath.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final theme = context.watch<ThemeController>().theme;
    final cream = Brand.cream;
    final top = MediaQuery.paddingOf(context).top;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: ColoredBox(
        color: theme.stage,
        child: Stack(
          children: [
            const Positioned(right: -64, top: -18, child: BrandWatermark(size: 260)),
            SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(28, top + 56, 28, bottom + 32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: MediaQuery.withClampedTextScaling(
                    maxScaleFactor: 1.4,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Reveal(
                          offset: const Offset(0, 14),
                          child: Semantics(
                            header: true,
                            child: Text(i18n.t('mobileAnalyze.loading.title'), style: Brand.serif(36, color: cream, h: 1.08, ls: -1)),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Reveal(
                          delay: const Duration(milliseconds: 120),
                          offset: const Offset(0, 10),
                          child: Text(i18n.t('mobileAnalyze.loading.subtitle'), style: tx(15, c: cream.withValues(alpha: .8), h: 1.45)),
                        ),
                        const SizedBox(height: 44),
                        for (var i = 0; i < _stepKeys.length; i++)
                          _Step(
                            label: i18n.t('mobileAnalyze.loading.${_stepKeys[i]}'),
                            state: i < _current ? _StepState.done : (i == _current ? _StepState.active : _StepState.pending),
                            last: i == _stepKeys.length - 1,
                            breath: _breath,
                            ink: theme.stage,
                          ),
                        const SizedBox(height: 36),
                        Text(i18n.t('mobileAnalyze.loading.note'), style: tx(13, c: cream.withValues(alpha: .66), h: 1.5)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _StepState { done, active, pending }

/// Zaman çizelgesi satırı: sol düğüm (biten: dolu + tik; sıradaki: nefes alan halka; bekleyen: silik halka) ve altına inen ince çizgi.
class _Step extends StatelessWidget {
  const _Step({required this.label, required this.state, required this.last, required this.breath, required this.ink});

  final String label;
  final _StepState state;
  final bool last;
  final Animation<double> breath;

  /// Dolu düğmenin içindeki tik rengi (sahnenin derin tonu).
  final Color ink;

  @override
  Widget build(BuildContext context) {
    final cream = Brand.cream;
    final active = state == _StepState.active;
    final done = state == _StepState.done;
    final textColor = active ? cream : cream.withValues(alpha: done ? .62 : .38);

    Widget node = AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? cream.withValues(alpha: .92) : Colors.transparent,
        border: Border.all(color: cream.withValues(alpha: active ? .95 : (done ? .92 : .3)), width: active ? 2 : 1.5),
      ),
      child: done
          ? Icon(LucideIcons.check, size: 15, color: ink)
          : (active ? Center(child: Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: cream))) : null),
    );
    if (active) {
      node = AnimatedBuilder(
        animation: breath,
        builder: (context, child) => Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 26 + 14 * breath.value,
              height: 26 + 14 * breath.value,
              decoration: BoxDecoration(shape: BoxShape.circle, color: cream.withValues(alpha: .14 * (1 - breath.value))),
            ),
            child!,
          ],
        ),
        child: node,
      );
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 40,
            child: Column(
              children: [
                SizedBox(width: 40, height: 40, child: Center(child: node)),
                if (!last) Expanded(child: Container(width: 1.5, color: cream.withValues(alpha: done ? .5 : .18))),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 9, bottom: last ? 0 : 22),
              child: Semantics(
                liveRegion: active,
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 400),
                  style: tx(16, w: active ? 6 : 5, c: textColor, h: 1.35),
                  child: Text(label),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
