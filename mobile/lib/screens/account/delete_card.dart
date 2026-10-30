import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/i18n.dart';
import '../../core/privacy_storage.dart';
import '../../state/auth_controller.dart';
import '../../state/notifications_controller.dart';
import '../../ui/tw.dart';
import '../../ui/widgets/common.dart';
import 'account_parts.dart';

/// Hesabı silme onay ifadesi (sunucu da aynısını bekler).
const accountDeletePhrase = 'HESABIMI_SIL';

/// Hesabı kalıcı silme ("tehlikeli bölge"): kullanıcı ifadeyi aynen yazınca düğme açılır. Sunucu silince cihazdaki kişisel veri
/// ve planlı bildirimler de temizlenir (silinmiş hesabın hatırlatıcıları çalmaya devam etmesin), oturum kapanır, karşılamaya dönülür.
class AccountDeleteCard extends StatefulWidget {
  const AccountDeleteCard({super.key});

  @override
  State<AccountDeleteCard> createState() => _AccountDeleteCardState();
}

class _AccountDeleteCardState extends State<AccountDeleteCard> {
  final _phrase = TextEditingController();
  bool _busy = false;
  (String, String) _msg = ('', '');

  @override
  void initState() {
    super.initState();
    _phrase.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _phrase.dispose();
    super.dispose();
  }

  bool get _phraseOk => _phrase.text.trim() == accountDeletePhrase;

  Future<void> _delete() async {
    final auth = context.read<AuthController>();
    final notifications = context.read<NotificationsController>();
    final router = GoRouter.of(context);
    final i18n = I18n.instance;
    final uid = auth.user?.id;
    setState(() => _msg = ('', ''));
    if (uid == null) return;
    if (!_phraseOk) {
      setState(() => _msg = ('err', i18n.t('mobileAccount.delete.phraseMismatch', {'phrase': accountDeletePhrase})));
      return;
    }
    setState(() => _busy = true);
    try {
      final res = await apiPost('/account/delete', {'user_id': uid, 'confirm_text': accountDeletePhrase}, timeout: apiLongTimeout);
      if (!res.ok) throw Exception(detailOr(res.data, i18n.t('mobileAccount.delete.requestFailed')));
      _phrase.clear();
      // Silinen hesabın planlı yerel bildirimleri ve cihaz kaydı da gider (oturum kapanınca kimlik gittiği için önce).
      // Hesap sunucuda gitti: yerel temizlikteki bir hata kullanıcıya "silinemedi" dedirtmemeli, oturum kapanmalı.
      try {
        await notifications.prepareSignOut();
        await clearUserLocalData(uid);
      } catch (_) {
        /* kalan yerel veri bir sonraki girişte temizlenir */
      }
      await auth.signOut();
      router.go('/');
    } catch (e) {
      final m = e.toString().replaceFirst('Exception: ', '');
      if (mounted) setState(() => _msg = ('err', m.isEmpty ? i18n.t('mobileAccount.delete.failed') : m));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final disabled = _busy || !_phraseOk;
    return RCard(
      padding: const EdgeInsets.all(18),
      radius: 24,
      borderColor: Tw.red200,
      color: Color.alphaBlend(Tw.red50.withValues(alpha: .4), Tw.surface),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccountSectionTitle(icon: LucideIcons.trash2, color: Tw.red900, text: i18n.t('mobileAccount.delete.title'), textColor: Tw.red900),
          const SizedBox(height: 10),
          Text(i18n.t('mobileAccount.delete.body'), style: tx(12.5, c: Tw.red900.withValues(alpha: .9), h: relaxed)),
          const SizedBox(height: 14),
          Text.rich(
            TextSpan(children: [
              TextSpan(text: i18n.t('mobileAccount.delete.confirm')),
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(color: Tw.surface.withValues(alpha: .8), borderRadius: BorderRadius.circular(4)),
                  child: Text(accountDeletePhrase, style: tx(12.5, w: 6, c: Tw.red950).copyWith(fontFamily: 'monospace')),
                ),
              ),
            ]),
            style: tx(12.5, w: 6, c: Tw.red950.withValues(alpha: .9)),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _phrase,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.characters,
            style: tx(14).copyWith(fontFamily: 'monospace'),
            decoration: inputDecoration(hint: accountDeletePhrase),
          ),
          if (_msg.$2.isNotEmpty) ...[
            const SizedBox(height: 12),
            StatusLine(ok: _msg.$1 == 'ok', text: _msg.$2, errorColor: Tw.red700),
          ],
          const SizedBox(height: 14),
          Opacity(
            opacity: disabled ? .5 : 1,
            child: Material(
              color: Tw.surface,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: disabled ? null : _delete,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 52),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: Tw.red600, width: 1.6)),
                  child: Center(
                    child: _busy
                        ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Tw.red700))
                        : Text(i18n.t('mobileAccount.delete.button'), style: tx(15, w: 6, c: Tw.red700)),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
