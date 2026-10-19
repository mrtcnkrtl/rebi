import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n.dart';
import '../../state/theme_controller.dart';
import '../../ui/tw.dart';
import '../../ui/widgets/common.dart';

/// Mesaj yazma çubuğu: alan + gönder düğmesi, altında kota notu ve yapay zekâ beyanı.
class ChatComposer extends StatelessWidget {
  const ChatComposer({
    super.key,
    required this.theme,
    required this.controller,
    required this.focusNode,
    required this.locked,
    required this.canSend,
    required this.onSend,
    required this.footer,
    this.compact = false,
  });

  final RebiTheme theme;
  final TextEditingController controller;
  final FocusNode focusNode;

  /// Yanıt beklerken ya da limit dolunca alan salt-okunur (klavye kapanıp açılmasın).
  final bool locked;
  final bool canSend;
  final VoidCallback onSend;
  final Widget footer;

  /// true: kota notu ve yapay zekâ beyanı gizlenir (limit kartı açıkken yer onun).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final i18n = I18n.instance;
    // Büyük yazı boyutunda dipnotlar ekranı kaplamasın: çubuk ekranın %42'siyle sınırlı, taşarsa kayar.
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .42),
      child: SingleChildScrollView(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          decoration: BoxDecoration(
            color: Tw.surface.withValues(alpha: .92),
            border: Border(top: BorderSide(color: Tw.gray100)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      readOnly: locked,
                      textInputAction: TextInputAction.send,
                      minLines: 1,
                      maxLines: 4,
                      onSubmitted: (_) => onSend(),
                      style: tx(14),
                      decoration: inputDecoration(hint: i18n.t('chat.placeholder'), focusColor: theme.primary)
                          .copyWith(hintStyle: tx(14, c: Tw.gray400), hintMaxLines: 1),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Semantics(
                    button: true,
                    enabled: canSend,
                    label: i18n.t('mobileChat.send', const {}, 'Send'),
                    child: Material(
                      color: canSend ? theme.primary : Tw.gray200,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: canSend ? onSend : null,
                        child: SizedBox(
                          width: 48,
                          height: 48,
                          child: Icon(LucideIcons.arrowUp, size: 22, color: canSend ? Colors.white : Tw.gray400),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (!compact) ...[
                const SizedBox(height: 6),
                footer,
                const AiDisclaimer(textAlign: TextAlign.center, padding: EdgeInsets.only(top: 6)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
