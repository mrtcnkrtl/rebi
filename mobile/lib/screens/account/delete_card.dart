import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/i18n.dart';
import '../../core/privacy_storage.dart';
import '../../core/subscription.dart';
import '../../state/auth_controller.dart';
import '../../state/notifications_controller.dart';
import '../../ui/tw.dart';
import '../../ui/widgets/common.dart';
import 'account_parts.dart';

/// Sunucunun beklediği onay metni (`/account/delete` → `confirm_text`); dilden bağımsız sabittir.
const accountDeletePhrase = 'HESABIMI_SIL';

/// Kullanıcının kutuya yazdığı onay kelimesi seçili dilde (TR: `HESABIMI SİL`, EN: `DELETE`); sunucuya yine
/// [accountDeletePhrase] gider.
String get typedDeletePhrase => I18n.instance.t('mobileAccount.deletePhrase', const {}, accountDeletePhrase);

/// Onay ifadesini karşılaştırmak için sadeleştirir: büyük/küçük harf, Türkçe i/ı/İ farkı, boşluk, alt çizgi ve tire
/// önemsizdir. Türkçe klavye büyük harfte `i` tuşuyla noktalı **İ** yazar; eskiden "HESABIMI_SİL" hiç eşleşmediği için
/// düğme hiç açılmıyordu.
String foldDeletePhrase(String text) => text
    .replaceAll(RegExp(r'[\s_\-]+'), '')
    .replaceAll('İ', 'I')
    .replaceAll('ı', 'I')
    .replaceAll('i̇', 'I')
    .toUpperCase();

/// Kullanıcının yazdığı metin onay ifadesiyle eşleşiyor mu ([foldDeletePhrase]).
bool deletePhraseMatches(String typed) {
  final folded = foldDeletePhrase(typed);
  return folded.isNotEmpty && folded == foldDeletePhrase(typedDeletePhrase);
}

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

  bool get _phraseOk => deletePhraseMatches(_phrase.text);

  Future<void> _delete() async {
    final auth = context.read<AuthController>();
    final notifications = context.read<NotificationsController>();
    final router = GoRouter.of(context);
    final i18n = I18n.instance;
    final uid = auth.user?.id;
    setState(() => _msg = ('', ''));
    if (uid == null) return;
    if (!_phraseOk) {
      setState(() => _msg = ('err', i18n.t('mobileAccount.delete.phraseMismatch', {'phrase': typedDeletePhrase})));
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
          if (activeStoreTier(context.watch<AuthController>().user) case final tier?) ...[
            const SizedBox(height: 12),
            _SubscriptionWarning(tier: tier),
          ],
          const SizedBox(height: 14),
          Text.rich(
            TextSpan(children: [
              TextSpan(text: i18n.t('mobileAccount.delete.confirm')),
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(color: Tw.surface.withValues(alpha: .8), borderRadius: BorderRadius.circular(4)),
                  child: Text(typedDeletePhrase, style: tx(12.5, w: 6, c: Tw.red950).copyWith(fontFamily: 'monospace')),
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
            decoration: inputDecoration(hint: typedDeletePhrase),
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

/// Mağaza aboneliği olan kullanıcıya: hesabı silmek aboneliği iptal etmez (App Store / Google Play ücret almaya devam
/// eder); önce mağazadan iptal etmesi gerekir. Apple abonelikli uygulamalarda bunun açıkça söylenmesini bekler.
class _SubscriptionWarning extends StatelessWidget {
  const _SubscriptionWarning({required this.tier});

  final String tier;

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final ios = defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      decoration: BoxDecoration(
        color: Tw.amber50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Tw.amber200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: ExcludeSemantics(child: Icon(LucideIcons.creditCard, size: 17, color: Tw.amber700)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      i18n.t('mobileAccount.delete.subscriptionTitle', {'tier': i18n.t('mobileSubscribe.store.tiers.$tier')}),
                      style: tx(13, w: 7, c: Tw.amber900, h: 1.3),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      i18n.t(ios ? 'mobileAccount.delete.subscriptionBodyIos' : 'mobileAccount.delete.subscriptionBodyAndroid'),
                      style: tx(12.5, c: Tw.amber900, h: relaxed),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextLink(
              i18n.t('mobileSubscribe.store.manage'),
              onTap: () => launchUrl(Uri.parse(storeManageSubscriptionsUrl), mode: LaunchMode.externalApplication),
              style: tx(13, w: 7, c: Tw.amber900),
              underline: true,
            ),
          ),
        ],
      ),
    );
  }
}
