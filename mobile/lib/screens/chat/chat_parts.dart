import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/chat_context.dart';
import '../../core/chat_failure.dart';
import '../../core/i18n.dart';
import '../../state/theme_controller.dart';
import '../../ui/tw.dart';
import '../../ui/brand/brand_mark.dart';
import '../../ui/brand/motion.dart';
import '../../ui/brand/palette.dart';
import '../../ui/widgets/common.dart';

/// Sohbetin üst sahnesi: seçili temanın derin tonunda, krem yazılı (Bugün, karşılama ve girişle aynı dil). Soldan sağa:
/// (oturumsuzken) geri, Rebi imzası (yanıt hazırlanırken karosu nefes alır), kota hapı ve "Temizle". Sohbet boşken altında
/// büyük karşılama sorusu ve (varsa) "Rebi bugünü biliyor" çipleri görünür; ilk mesajla bunlar katlanıp sahne ince bir
/// çubuğa iner. Kabuğun ayrı logo çubuğu yoktur (çift başlık olmasın).
class ChatStage extends StatelessWidget {
  const ChatStage({
    super.key,
    required this.theme,
    required this.title,
    required this.usageLabel,
    required this.canClear,
    required this.onClear,
    required this.expanded,
    required this.thinking,
    this.onBack,
    this.contextItems = const [],
    this.onContextTap,
    this.introducing = false,
    this.heroLift = 0,
  });

  final RebiTheme theme;

  /// Boş sohbetteki karşılama sorusu.
  final String title;

  /// Kalan mesaj hakkı ("Bugün 4 / 5", "Plus · sınırsız"); yoksa null.
  final String? usageLabel;
  final bool canClear;
  final VoidCallback onClear;

  /// true: sohbet boş, büyük sahne. false: konuşma var, ince çubuk.
  final bool expanded;

  /// Yanıt hazırlanıyor: imza karosu nefes alır.
  final bool thinking;

  /// Verilirse (oturumsuz sohbet) soldaki geri düğmesi görünür.
  final VoidCallback? onBack;
  final List<ChatContextItem> contextItems;
  final VoidCallback? onContextTap;

  /// Oturumsuz karşılama ("Önce tanışalım"): sağdaki silik "R" sabit durmaz, sayfa açılırken kendini çizer (girişin sahnesiyle aynı).
  final bool introducing;

  /// Uzun ekranda sahneyi yükseltir (girişteki gibi başlık alta oturur, "R" imzası büyür): davetin altında boş kalan yer sahnenin olur.
  final double heroLift;

  @override
  Widget build(BuildContext context) {
    final i18n = I18n.instance;
    final top = MediaQuery.paddingOf(context).top;
    final cream = Brand.cream;
    final hero = Padding(
      key: const ValueKey('hero'),
      padding: EdgeInsets.only(top: 14 + heroLift, right: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Reveal(
            delay: const Duration(milliseconds: 80),
            offset: const Offset(0, 12),
            child: Semantics(header: true, child: Text(title, style: Brand.serif(31, color: cream, h: 1.1, ls: -.9))),
          ),
          if (contextItems.isNotEmpty)
            ChatContextStrip(items: contextItems, theme: theme, onTap: onContextTap ?? () {}, padding: const EdgeInsets.only(top: 6, bottom: 2)),
        ],
      ),
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
        child: ColoredBox(
          color: theme.stage,
          child: Stack(
            children: [
              if (expanded)
                Positioned(
                  right: -56 - heroLift * .25,
                  top: -4,
                  child: introducing ? DrawnWatermark(size: 210 + heroLift * .6) : const BrandWatermark(size: 210),
                ),
              Padding(
                padding: EdgeInsets.fromLTRB(20, top + 6, 8, 18),
                // Üst çubuk ekranın değil içeriğin yeridir: sistem yazısı %200 olsa da en çok %130 büyür.
                child: MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1.3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        height: 52,
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Row(
                                children: [
                                  if (onBack != null) ...[_BackCircle(onTap: onBack!), const SizedBox(width: 10)],
                                  _Presence(thinking: thinking),
                                  const SizedBox(width: 10),
                                  Flexible(
                                    child: Text('Rebi', maxLines: 1, overflow: TextOverflow.ellipsis, style: Brand.serif(23, weight: 600, color: cream, ls: -.5, h: 1)),
                                  ),
                                ],
                              ),
                            ),
                            // Kota hapı dar ekran ve büyük yazıda orantılı küçülür (yalnızca hap; dokunulan "Temizle" hiç küçülmez,
                            // dokunma alanı 48 dp kalır).
                            if (usageLabel != null)
                              Flexible(
                                flex: 2,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerRight,
                                  child: Container(
                                    margin: const EdgeInsets.only(right: 2),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(999), border: Border.all(color: cream.withValues(alpha: .26))),
                                    child: Text(usageLabel!, maxLines: 1, style: tx(11, w: 6, c: cream.withValues(alpha: .88))),
                                  ),
                                ),
                              ),
                            // Boş sohbette silinecek bir şey yok: düğme yalnızca konuşma varken görünür.
                            if (canClear)
                              TextButton(
                                onPressed: onClear,
                                style: TextButton.styleFrom(
                                  minimumSize: const Size(48, 48),
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: Text(i18n.t('chat.clear'), style: tx(13, w: 6, c: cream.withValues(alpha: .82))),
                              ),
                          ],
                        ),
                      ),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 380),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.topLeft,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          layoutBuilder: (current, previous) => Stack(alignment: Alignment.topLeft, children: [...previous, ?current]),
                          child: expanded ? hero : const SizedBox(key: ValueKey('collapsed'), width: double.infinity),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Geri düğmesi (oturumsuz sohbet → karşılama): krem çerçeveli yuvarlak, dokunma alanı 48 dp.
class _BackCircle extends StatelessWidget {
  const _BackCircle({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: I18n.instance.t('mobileNav.back'),
      button: true,
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        scale: .92,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Brand.cream.withValues(alpha: .26), width: 1.3)),
              child: Icon(LucideIcons.chevronLeft, size: 21, color: Brand.cream),
            ),
          ),
        ),
      ),
    );
  }
}

/// Rebi imzası: marka karosu. Yanıt hazırlanırken karonun çevresinde iki halka sırayla yayılır ("dinliyor/düşünüyor").
/// "Animasyonları azalt" açıkken halka durağan ve soluktur.
class _Presence extends StatefulWidget {
  const _Presence({required this.thinking});

  final bool thinking;

  @override
  State<_Presence> createState() => _PresenceState();
}

class _PresenceState extends State<_Presence> with SingleTickerProviderStateMixin {
  static const _size = 34.0;
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1900));

  void _sync() {
    if (widget.thinking && !reduceMotion(context)) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _Presence old) {
    super.didUpdateWidget(old);
    if (old.thinking != widget.thinking) _sync();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = reduceMotion(context);
    return SizedBox.square(
      dimension: _size,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          if (widget.thinking)
            for (var i = 0; i < 2; i++)
              AnimatedBuilder(
                animation: _c,
                builder: (context, _) {
                  final p = still ? .5 : (_c.value + i * .5) % 1;
                  return Opacity(
                    opacity: (1 - p) * .55,
                    child: Transform.scale(
                      scale: 1 + .7 * p,
                      child: DecoratedBox(
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(_size * BrandMark.cornerRadius), border: Border.all(color: Brand.cream, width: 1.4)),
                        child: const SizedBox.square(dimension: _size),
                      ),
                    ),
                  );
                },
              ),
          const BrandMark(size: _size),
        ],
      ),
    );
  }
}

/// Yeni eklenen mesaj kısa bir süzülme ve belirmeyle gelir (eski mesajlar kaydırılınca yeniden oynamaz: yalnızca ekran
/// açıkken eklenenler bunu kullanır). "Animasyonları azalt" açıkken doğrudan görünür.
class MessageEnter extends StatelessWidget {
  const MessageEnter({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, v, child) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, (1 - v) * 14), child: child)),
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
    this.padding = const EdgeInsets.fromLTRB(16, 4, 16, 4),
  });

  final List<ChatContextItem> items;
  final RebiTheme theme;
  final VoidCallback onTap;
  final EdgeInsetsGeometry padding;

  IconData _icon(String id) => switch (id) {
    'weather' => LucideIcons.sunMedium,
    'routine' => LucideIcons.listChecks,
    'water' => LucideIcons.droplet,
    'makeup' => LucideIcons.sparkles,
    _ => LucideIcons.packageCheck,
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
          height: 56,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: padding,
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 4),
            itemBuilder: (context, i) {
              final item = items[i];
              // Hap görünümü küçük (32 dp), dokunma alanı 48 dp.
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: onTap,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Center(
                      widthFactor: 1,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        // Koyu üst sahnede: krem çerçeveli, saydam çip.
                        decoration: ShapeDecoration(color: Brand.cream.withValues(alpha: .08), shape: StadiumBorder(side: BorderSide(color: Brand.cream.withValues(alpha: .24)))),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(_icon(item.id), size: 13, color: Brand.cream.withValues(alpha: .86)),
                            const SizedBox(width: 6),
                            Text(item.text, maxLines: 1, style: tx(12, w: 5, c: Brand.cream.withValues(alpha: .92))),
                          ],
                        ),
                      ),
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
              boxShadow: mine || Tw.dark ? null : const [BoxShadow(color: Color(0x0F0B3D38), blurRadius: 12, offset: Offset(0, 3))],
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(mine ? 18 : 6),
                bottomRight: Radius.circular(mine ? 6 : 18),
              ),
            ),
            child: mine
                ? SelectionArea(
                    child: Text(text, style: tx(14, c: Colors.white, h: relaxed)),
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
    ChatFailure.rateLimited => LucideIcons.hourglass,
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
              minHeight: 48,
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
