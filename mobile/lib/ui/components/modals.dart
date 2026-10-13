import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/consent_recovery.dart';
import '../../core/i18n.dart';
import '../../core/legal_consent.dart';
import '../../core/local_store.dart';
import '../../state/auth_controller.dart';
import '../tw.dart';
import '../widgets/common.dart';
import 'legal_consent_fields.dart';

/// Tam ekran karartma + alttan (telefon) / ortadan (tablet) kart.
class _ModalFrame extends StatelessWidget {
  const _ModalFrame({required this.child, this.maxWidth = 384, this.scroll = false});

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

const _ackKey = 'rebi-ai-disclaimer-ack-v1';

/// Yapay zekâ beyanı: cihaz başına bir kez onaylanan açılır kutu.
class AiDisclaimerModal extends StatefulWidget {
  const AiDisclaimerModal({super.key});

  @override
  State<AiDisclaimerModal> createState() => _AiDisclaimerModalState();
}

class _AiDisclaimerModalState extends State<AiDisclaimerModal> {
  bool _open = LocalStore.instance.getString(_ackKey) != '1';

  void _dismiss() {
    LocalStore.instance.setString(_ackKey, '1');
    setState(() => _open = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_open) return const SizedBox.shrink();
    final i18n = context.i18n;
    return _ModalFrame(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Tw.teal600,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Tw.teal600.withValues(alpha: .2), blurRadius: 15, offset: const Offset(0, 8))],
            ),
            child: const Icon(LucideIcons.sparkles, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 16),
          Text(i18n.t('common.aiDisclaimerTitle'), textAlign: TextAlign.center, style: tx(18, w: 9)),
          const SizedBox(height: 8),
          Text(i18n.t('common.aiDisclaimer'), textAlign: TextAlign.center, style: tx(14, c: Tw.gray600, h: relaxed)),
          const SizedBox(height: 24),
          SizedBox(width: double.infinity, child: PrimaryButton(onPressed: _dismiss, label: i18n.t('common.aiDisclaimerAck'))),
        ],
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
    return _ModalFrame(
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
