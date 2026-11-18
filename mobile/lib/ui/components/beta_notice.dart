import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/beta_notice.dart';
import '../../core/i18n.dart';
import '../../screens/me_screen.dart' show openSupport;

import '../brand/brand_button.dart';
import '../brand/brand_caps.dart';
import '../brand/motion.dart';
import '../brand/palette.dart';
import '../tw.dart';

/// Beta uyarısının içeriği: "erken erişim" mektubu. Uyarı kutusu gibi değil, uygulamanın editoryal dilinde: çizgili
/// küçük etiket, serif başlık, kısa ve olumlu bir metin, ince çizgiyle ayrılmış iki kısa vaat ve tek ana eylem.
/// Özür dilemez, korkutmaz; hata bildirmenin yolu süssüz ikincil eylemdir.
class BetaNoticePanel extends StatelessWidget {
  const BetaNoticePanel({super.key, required this.onDismiss, required this.onReport});

  final VoidCallback onDismiss;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final lang = i18n.lang;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(width: 22, height: 1.5, color: Brand.tealDeep),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                brandCaps(i18n.t('mobileBeta.eyebrow'), lang),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tx(11, w: 7, c: Brand.inkSoft, ls: brandTracking(lang, 2.0)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Semantics(
          header: true,
          child: Text(i18n.t('mobileBeta.title'), style: Brand.serif(30, color: Brand.ink, h: 1.1, ls: -.8)),
        ),
        const SizedBox(height: 14),
        Text(i18n.t('mobileBeta.body'), style: tx(15, c: Brand.inkSoft, h: 1.55)),
        const SizedBox(height: 24),
        Container(height: 1, color: Brand.inkFaint),
        _Promise(icon: LucideIcons.refreshCw, title: i18n.t('mobileBeta.updatesTitle'), body: i18n.t('mobileBeta.updatesBody')),
        Container(height: 1, color: Brand.inkFaint),
        _Promise(icon: LucideIcons.messageCircle, title: i18n.t('mobileBeta.teamTitle'), body: i18n.t('mobileBeta.teamBody')),
        Container(height: 1, color: Brand.inkFaint),
        const SizedBox(height: 26),
        BrandButton(onPressed: onDismiss, label: i18n.t('mobileBeta.ok')),
        const SizedBox(height: 6),
        Center(
          child: Pressable(
            onTap: onReport,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Text(i18n.t('mobileBeta.report'), style: tx(14.5, w: 6, c: Brand.ink, ls: .1)),
            ),
          ),
        ),
      ],
    );
  }
}

/// İnce çizgiler arasında tek satırlık vaat: ince çizgili ikon, kalın kısa başlık, altında bir cümle.
class _Promise extends StatelessWidget {
  const _Promise({required this.icon, required this.title, required this.body});

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

/// Telefonda ekranın altına oturan krem sayfa (üst köşeler yuvarlak, kenarlıksız); geniş ekranda ortada kart.
class _BetaSheetFrame extends StatelessWidget {
  const _BetaSheetFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final wide = mq.size.width >= 768;
    final bottom = mq.padding.bottom;
    final radius = wide ? BorderRadius.circular(28) : const BorderRadius.vertical(top: Radius.circular(28));
    final sheet = Container(
      width: double.infinity,
      constraints: BoxConstraints(maxWidth: wide ? 460 : double.infinity, maxHeight: mq.size.height * .9),
      decoration: BoxDecoration(
        // Açıkta krem kâğıt; koyuda kart yüzeyi (kâğıt rengi arka planla karışırdı).
        color: Tw.dark ? Brand.surface : Brand.paper,
        borderRadius: radius,
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 40, offset: Offset(0, -6))],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: SingleChildScrollView(padding: EdgeInsets.fromLTRB(28, 30, 28, 14 + (wide ? 0 : bottom)), child: child),
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

/// Uyarıyı gösterir: perde belirir, sayfa alttan yükselir (animasyonlar azaltılmışsa hemen). Android geri tuşu da kapatır.
Future<void> showBetaNotice(BuildContext context) {
  final instant = reduceMotion(context);
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.transparent,
    transitionDuration: instant ? Duration.zero : const Duration(milliseconds: 520),
    pageBuilder: (ctx, _, _) => _BetaSheetFrame(
      child: BetaNoticePanel(onDismiss: () => Navigator.of(ctx).pop(), onReport: () => unawaited(openSupport())),
    ),
    transitionBuilder: (ctx, animation, _, child) {
      final t = CurvedAnimation(parent: animation, curve: Curves.easeOutQuart, reverseCurve: Curves.easeInCubic);
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: const Interval(0, .6)),
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, .18), end: Offset.zero).animate(t),
          child: child,
        ),
      );
    },
  );
}

/// Kabuğa konan görünmez kapı: gerçek uygulama beta uyarısını bekletiyorsa ([betaNoticePending]) açılıştan kısa süre sonra
/// uyarıyı bir kez gösterir. Karşılamanın giriş sekansı sürerken bekler (marka kurulumunun üstüne binmesin), bitince ekranın
/// oturması için bir an daha tanır. Gösterilir gösterilmez "görüldü" yazılır: uyarı cihaz başına bir kez çıkar.
class BetaNoticeGate extends StatefulWidget {
  const BetaNoticeGate({super.key});

  @override
  State<BetaNoticeGate> createState() => _BetaNoticeGateState();
}

class _BetaNoticeGateState extends State<BetaNoticeGate> {
  /// Ekran (ve varsa giriş sekansı) bittikten sonra uyarıdan önceki bekleme.
  static const _settle = Duration(milliseconds: 900);

  Timer? _timer;
  bool _listening = false;

  @override
  void initState() {
    super.initState();
    if (!betaNoticePending) return;
    betaNoticePending = false;
    _listening = true;
    startupSequencePlaying.addListener(_arm);
    // İlk kare çizildikten sonra bakılır: karşılama, giriş sekansı bayrağını kendi kurulumunda yükseltir.
    WidgetsBinding.instance.addPostFrameCallback((_) => _arm());
  }

  void _arm() {
    _timer?.cancel();
    if (!mounted || startupSequencePlaying.value) return;
    _timer = Timer(_settle, _show);
  }

  void _show() {
    if (!mounted) return;
    _stopListening();
    unawaited(markBetaNoticeSeen());
    unawaited(showBetaNotice(context));
  }

  void _stopListening() {
    if (!_listening) return;
    _listening = false;
    startupSequencePlaying.removeListener(_arm);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
