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
    final bottom = MediaQuery.paddingOf(context).bottom;
    // Büyük yazı boyutunda dipnotlar ekranı kaplamasın: çubuk ekranın %42'siyle sınırlı, taşarsa kayar.
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .42),
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.fromLTRB(12, 6, 12, 8 + bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Yüzen "dock": alan ve gönder düğmesi tek yuvarlak yüzeyde; çerçeve ve gölge yüzeyin kendisindedir.
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Tw.surface,
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(color: Tw.gray100),
                  boxShadow: Tw.dark ? null : const [BoxShadow(color: Color(0x1F0B3D38), blurRadius: 24, offset: Offset(0, 8))],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: controller,
                        focusNode: focusNode,
                        readOnly: locked,
                        textInputAction: TextInputAction.send,
                        minLines: 1,
                        maxLines: 4,
                        cursorColor: theme.primary,
                        onSubmitted: (_) => onSend(),
                        style: tx(15, c: Tw.gray900),
                        decoration: InputDecoration(
                          hintText: i18n.t('chat.placeholder'),
                          hintStyle: tx(15, c: Tw.gray500),
                          hintMaxLines: 1,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                          constraints: const BoxConstraints(minHeight: 48),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Semantics(
                      button: true,
                      enabled: canSend,
                      label: i18n.t('mobileChat.send', const {}, 'Send'),
                      child: AnimatedScale(
                        scale: canSend ? 1 : .92,
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutBack,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          decoration: BoxDecoration(shape: BoxShape.circle, color: canSend ? theme.primary : Tw.gray100),
                          child: Material(
                            type: MaterialType.transparency,
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
                      ),
                    ),
                  ],
                ),
              ),
              if (!compact) ...[
                const SizedBox(height: 8),
                footer,
                const AiDisclaimer(textAlign: TextAlign.center, padding: EdgeInsets.only(top: 4)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
