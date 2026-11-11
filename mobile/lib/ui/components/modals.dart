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
class AiSharingPanel extends StatelessWidget {
  const AiSharingPanel({super.key, required this.onAllow, required this.onDecline});

  final VoidCallback onAllow;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final body = tx(13.5, c: Tw.gray600, h: relaxed);
    final heading = tx(13.5, w: 8, c: Tw.gray700);
    final items = i18n.t('mobileAiSharing.items').split('\n').where((e) => e.trim().isNotEmpty);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: Tw.teal600, borderRadius: BorderRadius.circular(16)),
            child: const Icon(LucideIcons.sparkles, color: Colors.white, size: 24),
          ),
        ),
        const SizedBox(height: 16),
        Semantics(header: true, child: Text(i18n.t('mobileAiSharing.title'), style: tx(18, w: 9))),
        const SizedBox(height: 8),
        Text(i18n.t('mobileAiSharing.intro'), style: body),
        const SizedBox(height: 14),
        Text(i18n.t('mobileAiSharing.whatTitle'), style: heading),
        const SizedBox(height: 4),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('•  ', style: body),
                Expanded(child: Text(item, style: body)),
              ],
            ),
          ),
        const SizedBox(height: 14),
        Text(i18n.t('mobileAiSharing.whoTitle'), style: heading),
        const SizedBox(height: 4),
        Text(i18n.t('mobileAiSharing.who'), style: body),
        const SizedBox(height: 14),
        Text(i18n.t('mobileAiSharing.notSent'), style: body),
        const SizedBox(height: 8),
        Text(i18n.t('mobileAiSharing.control'), style: body),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextLink(
            i18n.t('mobileAiSharing.privacyLink'),
            onTap: () => context.push('/kvkk'),
            style: tx(13, w: 6, c: Tw.teal700),
            underline: true,
          ),
        ),
        const SizedBox(height: 8),
        const AiDisclaimer(),
        const SizedBox(height: 20),
        PrimaryButton(onPressed: onAllow, label: i18n.t('mobileAiSharing.allow')),
        const SizedBox(height: 8),
        SecondaryButton(onPressed: onDecline, label: i18n.t('mobileAiSharing.decline')),
      ],
    );
  }
}

String _aiUserId(BuildContext context) => context.read<AuthController>().user?.id ?? demoUserId;

/// İzin açıklamasını gösterir; kullanıcının seçimini döndürür (kaydetmez).
Future<bool> showAiSharingDialog(BuildContext context) async {
  final allowed = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.transparent,
    pageBuilder: (ctx, _, _) => ModalFrame(
      maxWidth: 448,
      scroll: true,
      child: AiSharingPanel(
        onAllow: () => Navigator.of(ctx).pop(true),
        onDecline: () => Navigator.of(ctx).pop(false),
      ),
    ),
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
    return ModalFrame(
      maxWidth: 448,
      scroll: true,
      child: AiSharingPanel(
        onAllow: () => setAiSharingConsent(uid, true),
        onDecline: () => setState(() => _dismissed = true),
      ),
    );
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
          Text(i18n.t('common.consentRecoveryBody'), style: tx(14, c: Tw.gray600, h: relaxed)),
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
          if (_error.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(_error, style: tx(14, c: Tw.rose600)),
          ],
          const SizedBox(height: 20),
          PrimaryButton(
            onPressed: (!_kvkk || !_riza || _saving) ? null : _submit,
            label: i18n.t('common.consentRecoveryCta'),
            child: _saving
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      ),
                      const SizedBox(width: 8),
                      Flexible(child: Text(i18n.t('common.consentRecoveryCta'), style: tx(16, w: 6, c: Colors.white))),
                    ],
                  )
                : null,
          ),
        ],
      ),
    );
  }
}
