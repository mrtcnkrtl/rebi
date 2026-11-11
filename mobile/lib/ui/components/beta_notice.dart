import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/beta_notice.dart';
import '../../core/i18n.dart';
import '../../screens/me_screen.dart' show openSupport;
import '../brand/beta_badge.dart';
import '../brand/brand_mark.dart';
import '../brand/motion.dart';
import '../brand/palette.dart';
import '../tw.dart';
import '../widgets/common.dart';
import 'modals.dart';

/// Beta uyarısının içeriği: marka karosu + "BETA" etiketi, kısa bir başlık, iki cümle ve tek eylem. Süs yok; ton sakin ve
/// dürüst ("hâlâ geliştiriyoruz, hata görebilirsin"), korkutmaz. İkincil eylem, hatayı bildirmenin yolunu verir.
class BetaNoticePanel extends StatelessWidget {
  const BetaNoticePanel({super.key, required this.onDismiss, required this.onReport});

  final VoidCallback onDismiss;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const ExcludeSemantics(child: BrandMark(size: 44)),
            const SizedBox(width: 12),
            const BetaBadge(),
          ],
        ),
        const SizedBox(height: 20),
        Semantics(
          header: true,
          child: Text(i18n.t('mobileBeta.title', const {}, 'Rebi şimdilik beta sürümünde'), style: heading(25, h: 1.14)),
        ),
        const SizedBox(height: 10),
        Text(
          i18n.t(
            'mobileBeta.body',
            const {},
            'Uygulamayı senin için hâlâ geliştiriyoruz. Bu yüzden zaman zaman hatalarla ya da beklenmedik davranışlarla karşılaşabilirsin.',
          ),
          style: tx(14.5, c: Tw.gray600, h: relaxed),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: TextLink(
            i18n.t('mobileBeta.report', const {}, 'Bir şey ters giderse bize yaz'),
            onTap: onReport,
            style: tx(14, w: 6, c: Tw.teal700),
            underline: true,
          ),
        ),
        const SizedBox(height: 14),
        PrimaryButton(onPressed: onDismiss, label: i18n.t('mobileBeta.ok', const {}, 'Anladım')),
      ],
    );
  }
}

/// Uyarıyı gösterir: perde ve kart birlikte yumuşakça belirir (animasyonlar azaltılmışsa hemen). Android geri tuşu da kapatır.
Future<void> showBetaNotice(BuildContext context) {
  final instant = reduceMotion(context);
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.transparent,
    transitionDuration: instant ? Duration.zero : const Duration(milliseconds: 460),
    pageBuilder: (ctx, _, _) => ModalFrame(
      maxWidth: 420,
      scroll: true,
      child: BetaNoticePanel(
        onDismiss: () => Navigator.of(ctx).pop(),
        onReport: () => unawaited(openSupport()),
      ),
    ),
    transitionBuilder: (ctx, animation, _, child) {
      final t = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeIn);
      return FadeTransition(
        opacity: t,
        child: SlideTransition(position: Tween<Offset>(begin: const Offset(0, .035), end: Offset.zero).animate(t), child: child),
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
