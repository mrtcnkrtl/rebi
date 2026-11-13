import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n.dart';
import '../../state/theme_controller.dart';
import '../../ui/brand/brand_caps.dart';
import '../../ui/brand/motion.dart';
import '../../ui/brand/palette.dart';
import '../../ui/tw.dart';
import '../../ui/widgets/common.dart';

/// Rutini olmayan kullanıcının (ilk giriş) karşılaması: üst sahnenin altına binen "İlk adım" kartı. Küçük etiket, Fraunces
/// başlık, kısa açıklama, kendini çizen üç adımlık yol ("nasıl çalışır"), tek ana düğme ve ikincil sohbet eylemi.
class TodayEmptyStart extends StatelessWidget {
  const TodayEmptyStart({super.key, required this.theme, required this.onStart, required this.onChat});

  final RebiTheme theme;
  final VoidCallback onStart;
  final VoidCallback onChat;

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final lang = i18n.lang;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Reveal(
          delay: const Duration(milliseconds: 120),
          duration: const Duration(milliseconds: 700),
          offset: const Offset(0, 26),
          child: RCard(
            radius: 28,
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(width: 22, height: 1.5, color: theme.accent),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        brandCaps(i18n.t('mobileToday.empty.eyebrow'), lang),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tx(11, w: 7, c: Tw.gray500, ls: brandTracking(lang, 2.0)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(i18n.t('mobileToday.empty.title'), style: heading(28, h: 1.12)),
                const SizedBox(height: 10),
                Text(i18n.t('mobileToday.empty.body'), style: tx(15, c: Tw.gray600, h: 1.5)),
                const SizedBox(height: 22),
                _Steps(theme: theme),
                const SizedBox(height: 22),
                PrimaryButton(
                  onPressed: onStart,
                  color: theme.primary,
                  label: i18n.t('dashboard.startAnalyze'),
                  trailingIcon: LucideIcons.arrowRight,
                ),
                const SizedBox(height: 10),
                SecondaryButton(
                  onPressed: onChat,
                  borderColor: theme.primaryLight,
                  textColor: theme.fg,
                  icon: LucideIcons.messageCircle,
                  label: i18n.t('dashboard.chatWithAi'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        Reveal(
          delay: const Duration(milliseconds: 420),
          duration: const Duration(milliseconds: 600),
          offset: const Offset(0, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.shieldCheck, size: 14, color: Tw.gray500),
              const SizedBox(width: 6),
              Flexible(child: Text(i18n.t('mobileAuth.trust'), textAlign: TextAlign.center, style: tx(12, c: Tw.gray500))),
            ],
          ),
        ),
      ],
    );
  }
}

/// Üç adımlık "nasıl çalışır" yolu: numaralı daireler ve aralarındaki çizgi sırayla çizilir (tek seferlik, sakin).
class _Steps extends StatefulWidget {
  const _Steps({required this.theme});

  final RebiTheme theme;

  @override
  State<_Steps> createState() => _StepsState();
}

class _StepsState extends State<_Steps> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));
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
    final i18n = context.i18n;
    final steps = [
      (i18n.t('mobileToday.empty.step1'), i18n.t('mobileToday.empty.step1Sub')),
      (i18n.t('mobileToday.empty.step2'), i18n.t('mobileToday.empty.step2Sub')),
      (i18n.t('mobileToday.empty.step3'), i18n.t('mobileToday.empty.step3Sub')),
    ];
    final theme = widget.theme;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        double iv(double a, double b) => Curves.easeOutCubic.transform(Interval(a, b).transform(_c.value));
        return Column(
          children: [
            for (var i = 0; i < steps.length; i++)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Opacity(
                    opacity: iv(i * .3, i * .3 + .22),
                    child: Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: theme.primaryLight),
                      child: Text('${i + 1}', style: Brand.serif(16, weight: 600, color: Tw.dark ? theme.fg : theme.deep, ls: 0, h: 1)),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    // Çizgi, bu adımın dairesinden sonraki adımın dairesine iner; metin bloğunun içinde (ölçüm gerektirmeden)
                    // çizilir: üstten 36, alta kadar (alttaki boşluk bir sonraki dairenin üstüne ulaşır).
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Opacity(
                          opacity: iv(i * .3 + .05, i * .3 + .3),
                          child: Padding(
                            padding: EdgeInsets.only(top: 2, bottom: i < steps.length - 1 ? 22 : 0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(steps[i].$1, style: tx(15, w: 7, c: Tw.gray900, h: 1.25)),
                                const SizedBox(height: 2),
                                Text(steps[i].$2, style: tx(13, c: Tw.gray500, h: 1.35)),
                              ],
                            ),
                          ),
                        ),
                        if (i < steps.length - 1)
                          PositionedDirectional(
                            start: -32,
                            top: 38,
                            bottom: 4,
                            width: 2,
                            child: FractionallySizedBox(
                              heightFactor: iv(i * .3 + .1, i * .3 + .42),
                              alignment: Alignment.topCenter,
                              child: DecoratedBox(decoration: BoxDecoration(color: theme.primaryLight, borderRadius: BorderRadius.circular(1))),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        );
      },
    );
  }
}
