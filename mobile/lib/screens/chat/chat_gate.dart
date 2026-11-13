import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n.dart';
import '../../state/theme_controller.dart';
import '../../ui/brand/brand_button.dart';
import '../../ui/brand/motion.dart';
import '../../ui/brand/palette.dart';
import '../../ui/tw.dart';
import 'chat_parts.dart';

/// Oturumsuz "Rebi ile konuş": sohbet bir hesap ister (yanıtlar kullanıcının cildine, rutinine ve rafına göre kurulur, yapay
/// zekâ için açık rıza hesaba yazılır, konuşma hesaba bağlı saklanır), bu yüzden yazı alanı yerine bir **davet** gösterilir.
///
/// Davet bir form değil, konuşmanın ilk adımıdır: Rebi iki kısa mesajla kendini tanıtır ve nedenini söyler; yazı alanının
/// yeri iki net eyleme (Kayıt ol · Giriş yap) bırakılır. Yazılamayan bir alan göstermek ya da dokunuşu sessizce yutmak yerine
/// alanın kendisi çekilir; öneri soruları da yoktur (dokununca gönderilmeyecek bir şeyi öneri diye sunmayız).
/// Üst sahne ([ChatStage], `introducing`) girişin sahnesiyle aynıdır; eylemler girişe bir üst sayfa olarak açılır, geri dönüşte
/// kullanıcı bu davette kalır.
class ChatGate extends StatelessWidget {
  const ChatGate({super.key, required this.theme, required this.onSignUp, required this.onSignIn, this.title});

  final RebiTheme theme;

  /// Sahne ince kaldığında (kısa ekran, büyük yazı) başlık sahneye sığmaz; gövdenin başında görünür.
  final String? title;
  final VoidCallback onSignUp;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    final i18n = I18n.instance;
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 22, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (title != null) Padding(padding: const EdgeInsets.fromLTRB(4, 0, 4, 16), child: Semantics(header: true, child: Text(title!, style: heading(26, h: 1.18)))),
                Reveal(
                  delay: const Duration(milliseconds: 200),
                  offset: const Offset(0, 14),
                  child: ChatBubble(text: i18n.t('mobileChat.gate.hello'), mine: false, theme: theme),
                ),
                const SizedBox(height: 12),
                Reveal(
                  delay: const Duration(milliseconds: 650),
                  offset: const Offset(0, 14),
                  child: ChatBubble(text: i18n.t('mobileChat.gate.why'), mine: false, theme: theme),
                ),
              ],
            ),
          ),
        ),
        _InviteDock(onSignUp: onSignUp, onSignIn: onSignIn),
      ],
    );
  }
}

/// Yazı alanının yerini alan yüzen dock: aynı konum, aynı yüzey dili (yuvarlak, hafif gölgeli); içinde iki eylem ve güven notu.
/// Ana eylem Kayıt ol (bu sayfaya karşılamadan gelen çoğu kişinin hesabı yoktur); Giriş yap aynı genişlikte, çerçeveli.
class _InviteDock extends StatelessWidget {
  const _InviteDock({required this.onSignUp, required this.onSignIn});

  final VoidCallback onSignUp;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    final i18n = I18n.instance;
    final bottom = MediaQuery.paddingOf(context).bottom;
    // Büyük yazı boyutunda dock ekranı kaplamasın: ekranın yarısıyla sınırlı, taşarsa kayar.
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .5),
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.fromLTRB(12, 6, 12, 10 + bottom),
          child: Reveal(
            delay: const Duration(milliseconds: 900),
            offset: const Offset(0, 24),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
              decoration: BoxDecoration(
                color: Tw.surface,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Tw.gray100),
                boxShadow: Tw.dark ? null : const [BoxShadow(color: Color(0x1F0B3D38), blurRadius: 24, offset: Offset(0, 8))],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  BrandButton(
                    key: const Key('chat-gate-signup'),
                    onPressed: onSignUp,
                    label: i18n.t('auth.signup'),
                    trailingIcon: LucideIcons.arrowRight,
                    height: 54,
                  ),
                  const SizedBox(height: 10),
                  BrandButton(
                    key: const Key('chat-gate-signin'),
                    onPressed: onSignIn,
                    label: i18n.t('auth.login'),
                    outlined: true,
                    height: 54,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(padding: const EdgeInsets.only(top: 1), child: Icon(LucideIcons.shieldCheck, size: 14, color: Tw.gray500)),
                      const SizedBox(width: 6),
                      Flexible(child: Text(i18n.t('mobileAuth.trust'), textAlign: TextAlign.center, style: tx(12, c: Tw.gray500, h: snug))),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
