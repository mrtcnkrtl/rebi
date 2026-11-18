import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/beta_notice.dart';
import '../../core/i18n.dart';
import '../../screens/me_screen.dart' show openSupport;

import '../brand/brand_button.dart';
import '../brand/brand_sheet.dart';
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        BrandEyebrow(i18n.t('mobileBeta.eyebrow')),
        const SizedBox(height: 18),
        Semantics(
          header: true,
          child: Text(i18n.t('mobileBeta.title'), style: Brand.serif(30, color: Brand.ink, h: 1.1, ls: -.8)),
        ),
        const SizedBox(height: 14),
        Text(i18n.t('mobileBeta.body'), style: tx(15, c: Brand.inkSoft, h: 1.55)),
        const SizedBox(height: 24),
        Container(height: 1, color: Brand.inkFaint),
        BrandPromiseRow(icon: LucideIcons.refreshCw, title: i18n.t('mobileBeta.updatesTitle'), body: i18n.t('mobileBeta.updatesBody')),
        Container(height: 1, color: Brand.inkFaint),
        BrandPromiseRow(icon: LucideIcons.messageCircle, title: i18n.t('mobileBeta.teamTitle'), body: i18n.t('mobileBeta.teamBody')),
        Container(height: 1, color: Brand.inkFaint),
        const SizedBox(height: 26),
        BrandButton(onPressed: onDismiss, label: i18n.t('mobileBeta.ok')),
        const SizedBox(height: 6),
        BrandQuietAction(onTap: onReport, label: i18n.t('mobileBeta.report')),
      ],
    );
  }
}

/// Uyarıyı gösterir: perde belirir, sayfa alttan yükselir (animasyonlar azaltılmışsa hemen). Android geri tuşu da kapatır.
Future<void> showBetaNotice(BuildContext context) {
  return showBrandSheet<void>(
    context,
    builder: (ctx) => BrandSheetFrame(
      child: BetaNoticePanel(onDismiss: () => Navigator.of(ctx).pop(), onReport: () => unawaited(openSupport())),
    ),
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
