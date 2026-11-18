import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../tw.dart';
import 'brand_caps.dart';
import 'motion.dart';
import 'palette.dart';

/// "Klinik sıcaklık" dilindeki alt sayfa: telefonda ekranın altına oturan krem kâğıt (üst köşeler yuvarlak,
/// kenarlıksız), geniş ekranda ortada kart. [footer] verilirse içerik kayarken eylemler altta sabit kalır.
class BrandSheetFrame extends StatelessWidget {
  const BrandSheetFrame({super.key, required this.child, this.footer, this.maxWidth = 460});

  final Widget child;
  final Widget? footer;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final wide = mq.size.width >= 768;
    final bottom = wide ? 0.0 : mq.padding.bottom;
    final radius = wide ? BorderRadius.circular(28) : const BorderRadius.vertical(top: Radius.circular(28));
    final sheetColor = Tw.dark ? Brand.surface : Brand.paper;
    final sheet = Container(
      width: double.infinity,
      constraints: BoxConstraints(maxWidth: wide ? maxWidth : double.infinity, maxHeight: mq.size.height * .9),
      decoration: BoxDecoration(
        // Açıkta krem kâğıt; koyuda kart yüzeyi (kâğıt rengi arka planla karışırdı).
        color: sheetColor,
        borderRadius: radius,
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 40, offset: Offset(0, -6))],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: SingleChildScrollView(padding: EdgeInsets.fromLTRB(28, 30, 28, footer == null ? 14 + bottom : 20), child: child),
            ),
            if (footer != null)
              DecoratedBox(
                decoration: BoxDecoration(
                  color: sheetColor,
                  border: Border(top: BorderSide(color: Brand.inkFaint)),
                ),
                child: Padding(padding: EdgeInsets.fromLTRB(28, 16, 28, 8 + bottom), child: footer),
              ),
          ],
        ),
      ),
    );
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(child: ColoredBox(color: Brand.forestDeep.withValues(alpha: .55))),
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.only(top: 24 + mq.padding.top, bottom: wide ? 24 : 0),
              child: Align(alignment: wide ? Alignment.center : Alignment.bottomCenter, child: sheet),
            ),
          ),
        ],
      ),
    );
  }
}

/// Sayfayı gösterir: perde belirir, sayfa alttan yükselir (animasyonlar azaltılmışsa hemen).
Future<T?> showBrandSheet<T>(BuildContext context, {required Widget Function(BuildContext ctx) builder}) {
  final instant = reduceMotion(context);
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.transparent,
    transitionDuration: instant ? Duration.zero : const Duration(milliseconds: 520),
    pageBuilder: (ctx, _, _) => builder(ctx),
    transitionBuilder: (ctx, animation, _, child) => BrandSheetTransition(animation: animation, child: child),
  );
}

/// Perdenin belirip sayfanın alttan yükseldiği geçiş.
class BrandSheetTransition extends StatelessWidget {
  const BrandSheetTransition({super.key, required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = CurvedAnimation(parent: animation, curve: Curves.easeOutQuart, reverseCurve: Curves.easeInCubic);
    return FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: const Interval(0, .6)),
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, .18), end: Offset.zero).animate(t),
        child: child,
      ),
    );
  }
}

/// Kısa çizgiyle başlayan, aralıklı büyük harfli küçük etiket ("— ERKEN ERİŞİM").
class BrandEyebrow extends StatelessWidget {
  const BrandEyebrow(this.text, {super.key, this.rule = true});

  final String text;
  final bool rule;

  @override
  Widget build(BuildContext context) {
    final lang = context.i18n.lang;
    final label = Text(
      brandCaps(text, lang),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: tx(11, w: 7, c: Brand.inkSoft, ls: brandTracking(lang, 2.0)),
    );
    if (!rule) return label;
    return Row(
      children: [
        Container(width: 22, height: 1.5, color: Brand.tealDeep),
        const SizedBox(width: 10),
        Flexible(child: label),
      ],
    );
  }
}

/// İnce çizgiler arasında tek satırlık vaat: ince çizgili ikon, kalın kısa başlık, altında bir iki cümle.
class BrandPromiseRow extends StatelessWidget {
  const BrandPromiseRow({super.key, required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 15),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: ExcludeSemantics(child: Icon(icon, size: 19, color: Brand.tealDeep)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: tx(14.5, w: 6, c: Brand.ink, h: 1.3)),
                const SizedBox(height: 3),
                Text(body, style: tx(13.5, c: Brand.inkSoft, h: 1.45)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Süssüz ikincil eylem: ortalanmış, yalnızca yazı.
class BrandQuietAction extends StatelessWidget {
  const BrandQuietAction({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Pressable(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Text(label, style: tx(14.5, w: 6, c: Brand.ink, ls: .1)),
        ),
      ),
    );
  }
}
