import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/chat_context.dart';
import '../../core/chat_failure.dart';
import '../../core/i18n.dart';
import '../../state/theme_controller.dart';
import '../../ui/tw.dart';
import '../../ui/brand/palette.dart';
import '../../ui/widgets/common.dart';

/// Sohbet başlığı: Rebi imzası, kota hapı ve "Temizle".
class ChatHeader extends StatelessWidget {
  const ChatHeader({
    super.key,
    required this.theme,
    required this.usageLabel,
    required this.canClear,
    required this.onClear,
  });

  final RebiTheme theme;

  /// Kalan mesaj hakkı ("Bugün 4 / 5", "Plus · sınırsız"); yoksa null.
  final String? usageLabel;
  final bool canClear;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final i18n = I18n.instance;
    // Başlık çubuğu ekranın değil içeriğin yeridir: sistem yazısı %200 olsa da en çok %130 büyür.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: _build(i18n),
    );
  }

  Widget _build(I18n i18n) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      decoration: BoxDecoration(
        color: Tw.surface.withValues(alpha: .8),
        border: Border(bottom: BorderSide(color: Tw.gray100)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: theme.primary.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(LucideIcons.sparkles, size: 19, color: theme.fg),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('Rebi', style: heading(22, h: 1.1)),
                    if (usageLabel != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Tw.gray50,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: Tw.gray100),
                        ),
                        child: Text(
                          usageLabel!,
                          style: tx(11, w: 6, c: Tw.gray600),
                        ),
                      ),
                  ],
                ),
                Text(
                  i18n.t('chat.subtitle'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tx(12, c: Tw.gray500),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: canClear ? onClear : null,
            style: TextButton.styleFrom(
              minimumSize: const Size(44, 44),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              i18n.t('chat.clear'),
              style: tx(13, w: 6, c: canClear ? Tw.gray600 : Tw.gray300),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Rebi bugünü biliyor": sohbetin bugün hakkında bildiği şeyler tek satırda; dokununca Bugün açılır.
class ChatContextStrip extends StatelessWidget {
  const ChatContextStrip({
    super.key,
    required this.items,
    required this.theme,
    required this.onTap,
  });

  final List<ChatContextItem> items;
  final RebiTheme theme;
  final VoidCallback onTap;

  IconData _icon(String id) => switch (id) {
    'weather' => LucideIcons.sunMedium,
    'routine' => LucideIcons.listChecks,
    'water' => LucideIcons.droplet,
    'makeup' => LucideIcons.sparkles,
    _ => LucideIcons.packageCheck,
  };

  Color _color(String id) => switch (id) {
    'weather' => Tw.amber600,
    'routine' => theme.fg,
    'water' => Tw.blue500,
    'makeup' => Tw.pink500,
    _ => Tw.orange600,
  };

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final i18n = I18n.instance;
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Semantics(
        container: true,
        label: i18n.t('mobileChat.contextLabel'),
        child: SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (context, i) {
              final item = items[i];
              return Material(
                color: Tw.surface,
                shape: StadiumBorder(side: BorderSide(color: Tw.gray100)),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: onTap,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_icon(item.id), size: 13, color: _color(item.id)),
                        const SizedBox(width: 6),
                        Text(
                          item.text,
                          maxLines: 1,
                          style: tx(12, w: 5, c: Tw.gray700),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Düz metin yanıtı okunaklı gösterir: boş satırla ayrılan paragraflar, "• " / "- " maddeleri (asılı girinti)
/// ve ":" ile biten kısa satırlar alt başlık olarak. (Sunucu markdown'ı zaten düz metne çevirir.)
class ReplyText extends StatelessWidget {
  const ReplyText(this.text, {super.key, required this.color});

  final String text;
  final Color color;

  static final _bullet = RegExp(r'^\s*(?:[•\-\*]|\d{1,2}[.)])\s+');

  @override
  Widget build(BuildContext context) {
    final style = tx(14, c: color, h: relaxed);
    final blocks = <Widget>[];
    final lines = text.replaceAll('\r\n', '\n').trim().split('\n');
    for (var i = 0; i < lines.length; i++) {
      final raw = lines[i].trimRight();
      if (raw.trim().isEmpty) continue;
      final next = i + 1 < lines.length ? lines[i + 1] : '';
      final bullet = _bullet.firstMatch(raw);
      Widget block;
      if (bullet != null) {
        final marker = raw.substring(0, bullet.end).trim();
        final numbered = RegExp(r'^\d').hasMatch(marker);
        block = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: numbered ? 22 : 14,
              child: Text(numbered ? marker : '•', style: style),
            ),
            Expanded(child: Text(raw.substring(bullet.end), style: style)),
          ],
        );
      } else if (raw.trim().endsWith(':') &&
          raw.trim().length <= 48 &&
          _bullet.hasMatch(next)) {
        block = Text(
          raw.trim(),
          style: style.copyWith(fontWeight: FontWeight.w700),
        );
      } else {
        block = Text(raw, style: style);
      }
      blocks.add(
        Padding(
          padding: EdgeInsets.only(top: blocks.isEmpty ? 0 : 6),
          child: block,
        ),
      );
    }
    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: blocks,
      ),
    );
  }
}

/// Bir sohbet balonu. Kullanıcının balonu vurgu rengiyle dolu, Rebi'ninki yüzey rengi ve ince çerçeveli.
class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.text,
    required this.mine,
    required this.theme,
  });

  final String text;
  final bool mine;
  final RebiTheme theme;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: .88,
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Align(
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: mine ? theme.primary : Tw.surface,
              border: mine ? null : Border.all(color: Tw.gray100),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(mine ? 18 : 6),
                bottomRight: Radius.circular(mine ? 6 : 18),
              ),
            ),
            child: mine
                ? SelectableText(
                    text,
                    style: tx(14, c: Colors.white, h: relaxed),
                  )
                : ReplyText(text, color: Tw.gray800),
          ),
        ),
      ),
    );
  }
}

/// Rebi yanıtı hazırlarken: üç nokta + kısa not.
class TypingBubble extends StatefulWidget {
  const TypingBubble({super.key, required this.theme});

  final RebiTheme theme;

  @override
  State<TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<TypingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final i18n = I18n.instance;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Tw.surface,
          border: Border.all(color: Tw.gray100),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomRight: Radius.circular(18),
            bottomLeft: Radius.circular(6),
          ),
        ),
        child: Semantics(
          liveRegion: true,
          label: i18n.t('chat.thinking'),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: _c,
                builder: (_, _) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < 3; i++)
                      Container(
                        width: 6,
                        height: 6,
                        margin: EdgeInsets.only(right: i == 2 ? 0 : 4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: widget.theme.primary.withValues(
                            alpha: .25 + .6 * _pulse(i),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  i18n.t('chat.thinking'),
                  style: tx(12, c: Tw.gray500),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 0–1: i. noktanın o anki parlaklığı (noktalar sırayla yanar).
  double _pulse(int i) {
    final t = (_c.value + (2 - i) * .18) % 1.0;
    return t < .5 ? t * 2 : (1 - t) * 2;
  }
}

/// Yanıt alınamadı: sohbetin içine metin yazmak yerine sakin bir kart ve "Tekrar dene".
class ChatErrorCard extends StatelessWidget {
  const ChatErrorCard({
    super.key,
    required this.failure,
    required this.theme,
    required this.onRetry,
    this.status,
  });

  final ChatFailure failure;
  final RebiTheme theme;
  final VoidCallback onRetry;

  /// Sunucunun HTTP durumu (destek için küçük yazılır); ağ hatasında null.
  final int? status;

  IconData get _icon => switch (failure) {
    ChatFailure.offline => LucideIcons.wifiOff,
    ChatFailure.server => LucideIcons.cloudOff,
    ChatFailure.auth => LucideIcons.lock,
    ChatFailure.generic => LucideIcons.circleAlert,
  };

  @override
  Widget build(BuildContext context) {
    final i18n = I18n.instance;
    return RCard(
      padding: const EdgeInsets.all(14),
      radius: 18,
      borderColor: Tw.amber200,
      color: Color.alphaBlend(Tw.amber50.withValues(alpha: .6), Tw.surface),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(_icon, size: 18, color: Tw.amber600),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      i18n.t(failure.messageKey),
                      style: tx(13, c: Tw.amber900, h: snug),
                    ),
                    if (status != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        '($status)',
                        style: tx(11, c: Tw.amber900.withValues(alpha: .7)),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: SecondaryButton(
              onPressed: onRetry,
              minHeight: 40,
              fontSize: 13,
              icon: LucideIcons.refreshCw,
              borderColor: Tw.amber200,
              textColor: Tw.amber900,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              label: i18n.t('mobileChat.retry'),
            ),
          ),
        ],
      ),
    );
  }
}
