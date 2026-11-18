import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/ai_sharing.dart';
import '../../core/consent_recovery.dart';
import '../../core/demo_user.dart';
import '../../core/i18n.dart';
import '../../core/legal_consent.dart';
import '../../state/auth_controller.dart';
import '../brand/brand_button.dart';
import '../brand/brand_sheet.dart';
import '../brand/motion.dart';
import '../brand/palette.dart';
import '../tw.dart';
import '../widgets/common.dart';
import 'legal_consent_fields.dart';

/// Tam ekran karartma + alttan (telefon) / ortadan (tablet) kart.
class ModalFrame extends StatelessWidget {
  const ModalFrame({super.key, required this.child, this.maxWidth = 384, this.scroll = false});

  final Widget child;
  final double maxWidth;
  final bool scroll;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final wide = mq.size.width >= 768;
    final bottomPad = mq.padding.bottom > 16 ? mq.padding.bottom : 16.0;
    Widget card = Container(
      width: double.infinity,
      constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: mq.size.height * .85),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Tw.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Tw.teal100),
        boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 50, offset: Offset(0, 25))],
      ),
      child: scroll ? SingleChildScrollView(child: child) : child,
    );
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(child: ColoredBox(color: Tw.fixedSlate950.withValues(alpha: .6))),
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 32 + mq.padding.top, 16, bottomPad + mq.viewInsets.bottom),
              child: Align(alignment: wide ? Alignment.center : Alignment.bottomCenter, child: card),
            ),
          ),
        ],
      ),
    );
  }
}

/// Üçüncü taraf yapay zekâ ile veri paylaşımı izninin içeriği: ne gönderilir, kime, ne için, ne gönderilmez,
/// nasıl geri alınır. Hem yapay zekâ ekranlarında kendiliğinden açılan kutuda hem de gönderimden hemen önce
/// ([ensureAiSharing]) aynı metin gösterilir.
///
/// Uyarı kutusu değil, beta karşılamasıyla aynı editoryal dil: çizgili etiket, serif başlık, kısa giriş; gönderilen
/// veriler ikonlu sakin bir listede, alıcı / gönderilmeyenler / kontrol ince çizgilerle ayrılmış üç vaat olarak.
/// Eylemler ([AiSharingActions]) sayfanın altında sabit durur; içerik kaydırılsa da görünür kalır.
class AiSharingPanel extends StatelessWidget {
  const AiSharingPanel({super.key});

  /// Gönderilen veri satırlarının ikonları; metindeki sırayla eşleşir (fazlası varsa son ikon tekrarlanır).
  static const _itemIcons = [
    LucideIcons.user,
    LucideIcons.scanFace,
    LucideIcons.heartPulse,
    LucideIcons.calendarCheck,
    LucideIcons.messageCircle,
    LucideIcons.cloudSun,
  ];

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final items = i18n.t('mobileAiSharing.items').split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final hairline = Container(height: 1, color: Brand.inkFaint);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        BrandEyebrow(i18n.t('mobileAiSharing.eyebrow')),
        const SizedBox(height: 18),
        Semantics(
          header: true,
          child: Text(i18n.t('mobileAiSharing.title'), style: Brand.serif(28, color: Brand.ink, h: 1.12, ls: -.7)),
        ),
        const SizedBox(height: 12),
        Text(i18n.t('mobileAiSharing.intro'), style: tx(15, c: Brand.inkSoft, h: 1.55)),
        const SizedBox(height: 26),
        Semantics(header: true, child: BrandEyebrow(i18n.t('mobileAiSharing.whatTitle'), rule: false)),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: Tw.dark ? Tw.surfaceRaised : Brand.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Brand.inkFaint),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Column(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) Padding(padding: const EdgeInsetsDirectional.only(start: 46), child: hairline),
                _DataRow(icon: _itemIcons[i.clamp(0, _itemIcons.length - 1)], text: items[i]),
              ],
            ],
          ),
        ),
        const SizedBox(height: 22),
        hairline,
        BrandPromiseRow(icon: LucideIcons.building2, title: i18n.t('mobileAiSharing.whoTitle'), body: i18n.t('mobileAiSharing.who')),
        hairline,
        BrandPromiseRow(icon: LucideIcons.eyeOff, title: i18n.t('mobileAiSharing.notSentTitle'), body: i18n.t('mobileAiSharing.notSent')),
        hairline,
        BrandPromiseRow(
          icon: LucideIcons.slidersHorizontal,
          title: i18n.t('mobileAiSharing.controlTitle'),
          body: i18n.t('mobileAiSharing.control'),
        ),
        hairline,
        const SizedBox(height: 10),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Pressable(
            onTap: () => context.push('/kvkk'),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      i18n.t('mobileAiSharing.privacyLink'),
                      style: tx(
                        13.5,
                        w: 6,
                        c: Tw.teal700,
                        h: 1.35,
                      ).copyWith(decoration: TextDecoration.underline, decorationColor: Tw.teal700.withValues(alpha: .35)),
                    ),
                  ),
                  const SizedBox(width: 4),
                  ExcludeSemantics(child: Icon(LucideIcons.arrowUpRight, size: 15, color: Tw.teal700)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        AiDisclaimer(color: Brand.inkSoft),
      ],
    );
  }
}

/// Gönderilen tek veri: yumuşak nane dairede ince ikon ve kısa açıklama.
class _DataRow extends StatelessWidget {
  const _DataRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(color: Brand.tint(0), shape: BoxShape.circle),
              child: Icon(icon, size: 16, color: Tw.dark ? Brand.teal : Brand.tealDeep),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(text, style: tx(13.5, c: Brand.ink, h: 1.4)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Sayfanın altına sabitlenen eylemler: tek ana düğme, altında süssüz "Şimdi değil".
class AiSharingActions extends StatelessWidget {
  const AiSharingActions({super.key, required this.onAllow, required this.onDecline});

  final VoidCallback onAllow;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BrandButton(onPressed: onAllow, label: i18n.t('mobileAiSharing.allow'), height: 54),
        const SizedBox(height: 2),
        BrandQuietAction(onTap: onDecline, label: i18n.t('mobileAiSharing.decline')),
      ],
    );
  }
}

/// İzin sayfası: içerik kayar, eylemler altta sabit.
class AiSharingSheet extends StatelessWidget {
  const AiSharingSheet({super.key, required this.onAllow, required this.onDecline});

  final VoidCallback onAllow;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) => BrandSheetFrame(
    maxWidth: 480,
    footer: AiSharingActions(onAllow: onAllow, onDecline: onDecline),
    child: const AiSharingPanel(),
  );
}

String _aiUserId(BuildContext context) => context.read<AuthController>().user?.id ?? demoUserId;

/// İzin açıklamasını gösterir; kullanıcının seçimini döndürür (kaydetmez).
Future<bool> showAiSharingDialog(BuildContext context) async {
  final allowed = await showBrandSheet<bool>(
    context,
    builder: (ctx) => AiSharingSheet(onAllow: () => Navigator.of(ctx).pop(true), onDecline: () => Navigator.of(ctx).pop(false)),
  );
  return allowed == true;
}

/// Yapay zekâya veri gidecek bir isteğin hemen öncesinde çağrılır: izin yoksa açıklamayı gösterip sorar.
/// İzin verildiyse (ya da daha önce verilmişse) true döner; kullanıcı vazgeçerse istek gönderilmemelidir.
Future<bool> ensureAiSharing(BuildContext context) async {
  final uid = _aiUserId(context);
  if (hasAiSharingConsent(uid)) return true;
  if (!await showAiSharingDialog(context)) return false;
  await setAiSharingConsent(uid, true);
  return true;
}

/// Yapay zekâ ekranlarında (panel, sohbet) izin verilmemişse kendiliğinden açılan kutu.
/// "Şimdi değil" yalnızca bu açılışta kapatır; izin olmadan yapay zekâ isteği gönderilmez ([ensureAiSharing]).
class AiSharingModal extends StatefulWidget {
  const AiSharingModal({super.key});

  @override
  State<AiSharingModal> createState() => _AiSharingModalState();
}

class _AiSharingModalState extends State<AiSharingModal> {
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    aiSharingChanges.addListener(_onChange);
  }

  @override
  void dispose() {
    aiSharingChanges.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final uid = context.watch<AuthController>().user?.id ?? demoUserId;
    if (_dismissed || hasAiSharingConsent(uid)) return const SizedBox.shrink();
    return AiSharingSheet(onAllow: () => setAiSharingConsent(uid, true), onDecline: () => setState(() => _dismissed = true));
  }
}

/// Rıza kaydı eksik oturumlarda onayı yeniden almak için açılan kutu.
class ConsentRecoveryModal extends StatefulWidget {
  const ConsentRecoveryModal({super.key});

  @override
  State<ConsentRecoveryModal> createState() => _ConsentRecoveryModalState();
}

class _ConsentRecoveryModalState extends State<ConsentRecoveryModal> {
  bool _open = false;
  bool _kvkk = false;
  bool _riza = false;
  bool _location = false;
  bool _photo = false;
  bool _saving = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _open = consentRecoveryPending;
    consentRecoveryRequests.addListener(_onRequest);
  }

  @override
  void dispose() {
    consentRecoveryRequests.removeListener(_onRequest);
    super.dispose();
  }

  void _onRequest() {
    if (mounted) setState(() => _open = true);
  }

  Future<void> _submit() async {
    final user = context.read<AuthController>().user;
    if (!_kvkk || !_riza || _saving || user == null) return;
    setState(() {
      _saving = true;
      _error = '';
    });
    try {
      await recordLegalConsent(user.id, ConsentPermissions(ai: true, location: _location, photo: _photo));
      if (mounted) setState(() => _open = false);
    } catch (e) {
      if (mounted) {
        final msg = e.toString().replaceFirst('Exception: ', '');
        setState(() => _error = msg.isEmpty ? I18n.instance.t('auth.legalRequired') : msg);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthController>().user;
    if (!_open || user == null) return const SizedBox.shrink();
    final i18n = context.i18n;
    return ModalFrame(
      maxWidth: 448,
      scroll: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: Tw.teal600, borderRadius: BorderRadius.circular(16)),
              child: const Icon(LucideIcons.shieldCheck, color: Colors.white, size: 24),
            ),
          ),
          const SizedBox(height: 16),
          Text(i18n.t('common.consentRecoveryTitle'), style: tx(18, w: 9)),
          const SizedBox(height: 8),
          Text(
            i18n.t('common.consentRecoveryBody'),
            style: tx(14, c: Tw.gray600, h: relaxed),
          ),
          const SizedBox(height: 16),
          LegalConsentFields(
            kvkk: _kvkk,
            riza: _riza,
            location: _location,
            photo: _photo,
            onKvkk: (v) => setState(() => _kvkk = v),
            onRiza: (v) => setState(() => _riza = v),
            onLocation: (v) => setState(() => _location = v),
            onPhoto: (v) => setState(() => _photo = v),
          ),
          if (_error.isNotEmpty) ...[const SizedBox(height: 12), Text(_error, style: tx(14, c: Tw.rose600))],
          const SizedBox(height: 20),
          PrimaryButton(
            onPressed: (!_kvkk || !_riza || _saving) ? null : _submit,
            label: i18n.t('common.consentRecoveryCta'),
            child: _saving
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(i18n.t('common.consentRecoveryCta'), style: tx(16, w: 6, c: Colors.white)),
                      ),
                    ],
                  )
                : null,
          ),
        ],
      ),
    );
  }
}
