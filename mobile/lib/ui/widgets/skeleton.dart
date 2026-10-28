import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../tw.dart';
import 'common.dart';

/// Yüklenirken içeriğin yerini tutan nabız atan gri blok. Dönen göstergeden daha sakindir ve
/// sayfa düzeni yüklenince zıplamaz.
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({super.key, this.width, this.height = 14, this.radius = 8});

  final double? width;
  final double height;
  final double radius;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: Color.lerp(Tw.gray100, Tw.gray200, Curves.easeInOut.transform(_controller.value)),
            borderRadius: BorderRadius.circular(widget.radius),
          ),
        ),
      ),
    );
  }
}

/// Kart biçiminde iskelet: başlık satırı, birkaç metin satırı ve isteğe bağlı düğme sırası.
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key, this.lines = 2, this.withActions = false});

  final int lines;
  final bool withActions;

  @override
  Widget build(BuildContext context) {
    return RCard(
      padding: const EdgeInsets.all(14),
      radius: 20,
      child: Semantics(
        label: I18n.instance.t('mobileCommon.loading'),
        container: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(children: [
              SkeletonBox(width: 40, height: 40, radius: 13),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(width: 120, height: 14),
                    SizedBox(height: 8),
                    SkeletonBox(width: 80, height: 11),
                  ],
                ),
              ),
            ]),
            for (var i = 0; i < lines; i++) ...[
              const SizedBox(height: 10),
              SkeletonBox(height: 11, width: i.isEven ? double.infinity : 200),
            ],
            if (withActions) ...[
              const SizedBox(height: 14),
              const Row(children: [
                SkeletonBox(width: 88, height: 40, radius: 999),
                SizedBox(width: 8),
                SkeletonBox(width: 72, height: 40, radius: 999),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}
