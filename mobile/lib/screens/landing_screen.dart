import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../core/i18n.dart';
import '../state/auth_controller.dart';
import '../ui/brand/brand_button.dart';
import '../ui/brand/brand_caps.dart';
import '../ui/brand/brand_mark.dart';
import '../ui/brand/motion.dart';
import '../ui/brand/palette.dart';
import '../ui/brand/public_top_bar.dart';
import '../ui/brand/welcome_art.dart';
import '../ui/tw.dart';

/// Uygulama oturumsuz açıldığında karşılamanın **giriş sekansı** oynasın mı? `buildRouter(splash: true)` bunu işaretler;
/// ilk karşılama kendi başlarken tüketir (sonraki ziyaretler, ör. girişten geri dönüş, sekansı yeniden oynatmaz).
bool landingIntroPending = false;

/// Sekansın toplam süresi. Sırayla: marka kurulur (0–1,6 sn), sol üste süzülür (1,8–2,6 sn), sahne ve içerik belirir.
const _introDuration = Duration(milliseconds: 3000);

/// Sekansın aşamaları (toplam sürenin oranı): kahraman çizim ve alt içerik bu eşiklerde kurulur.
const _heroAt = .76;
const _contentAt = .80;

/// Sayfanın en az olacağı yükseklik: normalde 680; dar ekranda (<360) +80, yazı büyütülünce yazı oranında artar.
double _minHeight(BuildContext context, double width) {
  final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
  return 680 + (width < 360 ? 80 : 0) + (scale > 1 ? (scale - 1) * 340 : 0);
}

/// Karşılama (web: `pages/Landing.jsx`): giriş yapmadan önce açılan sayfa. Tek odak, sıfır etiket: derin orman yeşili
/// zeminde tek bir kahraman görsel (podyum üstünde ürünler; ışığı günün saatine göre gündüz/akşam/gece), altında iki satırlık
/// başlık, kısa açıklama ve tek ana düğme.
///
/// Uygulama ilk açılırken açılış ekranı bu sayfanın içinde oynar (tek sekans): ekranın ortasındaki marka karosu ve "Rebi"
/// yazısı kurulup sol üst köşeye süzülür, sahne ve içerik onun ardından belirir. Sayfadan çıkarken içerik yukarı süzülüp
/// solar, zemin yerinde kalır (kayıt sayfasının krem paneli aynı zeminin üstüne yükselir).
class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> with SingleTickerProviderStateMixin {
  bool _playIntro = false;
  bool _started = false;
  bool _skipped = false;
  bool _showHero = true;
  bool _showContent = true;
  AnimationController? _intro;

  @override
  void initState() {
    super.initState();
    _playIntro = landingIntroPending;
    landingIntroPending = false;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_playIntro || _started) return;
    _started = true;
    if (reduceMotion(context)) {
      _playIntro = false;
      return;
    }
    _showHero = false;
    _showContent = false;
    _intro = AnimationController(vsync: this, duration: _introDuration)
      ..addListener(_onTick)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed && mounted) setState(() {});
      })
      ..forward();
  }

  void _onTick() {
    final t = _intro!.value;
    if ((!_showHero && t >= _heroAt) || (!_showContent && t >= _contentAt)) {
      setState(() {
        if (t >= _heroAt) _showHero = true;
        if (t >= _contentAt) _showContent = true;
      });
    }
  }

  /// Sekans sürerken ekrana dokunmak sekansı atlatır (son hâle geçer; içerik hemen belirmeye başlar).
  void _skip() {
    final intro = _intro;
    if (intro == null || intro.isCompleted) return;
    setState(() => _skipped = true);
    intro.value = 1;
  }

  @override
  void dispose() {
    _intro?.dispose();
    super.dispose();
  }

  /// Sayfadan çıkarken (ya da geri dönerken) yalnızca içerik süzülür ve solar; zemin sabit kalır. `go()` yeni rotayı üstüne
  /// bindirir: çıkışı alttaki rotanın `secondaryAnimation`ı, dönüşteki girişi rotanın kendi `animation`ı sürer.
  Widget _exitEffect(Widget content) {
    final route = ModalRoute.of(context);
    final enter = route?.animation;
    final leave = route?.secondaryAnimation;
    if (enter == null || leave == null) return content;
    return AnimatedBuilder(
      animation: Listenable.merge([enter, leave]),
      child: content,
      builder: (context, child) {
        // Çıkışta içerik, geçişin ~%60'ında tamamen kaybolur (yükselen panelin arkasında hayalet gibi kalmasın).
        final v = Curves.easeOutCubic.transform(enter.value.clamp(0.0, 1.0)) * (1 - Curves.easeIn.transform((leave.value * 1.7).clamp(0.0, 1.0)));
        if (v >= 1) return child!;
        return Opacity(opacity: v, child: Transform.translate(offset: Offset(0, -34 * (1 - v)), child: child));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final authed = context.watch<AuthController>().user != null;
    final chatHref = authed ? '/dashboard/chat' : '/rebi';
    final light = HeroLight.at(heroClock());
    final intro = _intro;
    final playing = intro != null && !intro.isCompleted;
    final overlay = SystemUiOverlayStyle.light.copyWith(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Brand.forest,
      systemNavigationBarIconBrightness: Brightness.light,
    );

    Widget topBar() {
      const bar = PublicTopBar(onDark: true);
      if (intro == null) return const Reveal(offset: Offset.zero, child: bar);
      // Marka giriş katmanında süzülüp yerleşir; çubuktaki marka gizli kalır, dil seçici en sonda belirir.
      return AnimatedBuilder(
        animation: intro,
        builder: (context, _) => PublicTopBar(onDark: true, brandOpacity: 0, trailingOpacity: _iv(intro.value, .75, .95)),
      );
    }

    final content = Column(
      children: [
        SizedBox(height: MediaQuery.paddingOf(context).top),
        topBar(),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: _showHero ? HeroArt(key: const ValueKey('hero'), light: light) : const SizedBox.shrink(),
          ),
        ),
        // Alt içerik her zaman kurulur (yerleşim sabit kalsın), ama belirmesi sekansın eşiğine göre geciktirilir; atlayınca
        // anahtar değişir ve gecikmesiz yeniden başlar.
        KeyedSubtree(
          key: ValueKey(_skipped),
          child: _Bottom(
            offsetMs: intro == null || _skipped ? 0 : (_introDuration.inMilliseconds * _contentAt).round(),
            authed: authed,
            onPrimary: () => context.go(
              authed ? '/dashboard' : '/auth?next=${Uri.encodeComponent('/dashboard/analyze')}&mode=signup',
            ),
            onLogin: () => context.go('/auth'),
            onChat: () => context.go(chatHref),
          ),
        ),
      ],
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: ColoredBox(
        color: Brand.forest,
        child: LayoutBuilder(
          builder: (context, box) {
            final inset = MediaQuery.paddingOf(context).top;
            Widget glow = DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -.32),
                  radius: .85,
                  colors: [light.glow.withValues(alpha: .32), light.glow.withValues(alpha: .07), Colors.transparent],
                  stops: const [0, .55, 1],
                ),
              ),
            );
            if (intro != null) {
              glow = AnimatedBuilder(
                animation: intro,
                child: glow,
                builder: (context, child) => Opacity(opacity: _iv(intro.value, .58, .90), child: child),
              );
            }
            final stack = Stack(
              children: [
                Positioned.fill(child: glow),
                Positioned.fill(child: _exitEffect(content)),
                if (intro != null)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedBuilder(
                        animation: intro,
                        builder: (context, _) => _BrandIntro(t: intro.value, viewport: Size(box.maxWidth, box.maxHeight), inset: inset),
                      ),
                    ),
                  ),
              ],
            );
            return SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: SizedBox(
                // Asgari yükseklik: dar ekranda ve büyük sistem yazısında metin satırları çoğalır; sayfa o zaman kaydırılır.
                height: math.max(box.maxHeight, _minHeight(context, box.maxWidth)),
                // Ağaç yapısı sabit kalır (sekans bitince alt öğelerin durumu kaybolmasın); sekans sürerken dokunuşlar içeriğe
                // (henüz görünmeyen düğmelere) ulaşmaz, ekranın herhangi bir yerine dokunmak sekansı atlatır.
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: playing ? _skip : null,
                  child: AbsorbPointer(absorbing: playing, child: stack),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

double _iv(double t, double a, double b, [Curve curve = Curves.easeOutCubic]) => curve.transform(Interval(a, b).transform(t));

/// Giriş sekansının marka katmanı: ekranın ortasında kurulan karo + "Rebi" (+ ince çizgi ve slogan) sol üst köşedeki
/// yerine süzülür. t=0'da karo ekranın tam ortasında ve [BrandMark.launchSize] boyundadır (yerel açılışla birebir örtüşür).
/// Sekans bitince marka bu katmanda, üst çubuktaki yerinde kalır (çubuktaki marka gizli); böylece geçişte kayma olmaz.
class _BrandIntro extends StatelessWidget {
  const _BrandIntro({required this.t, required this.viewport, required this.inset});

  final double t;
  final Size viewport;
  final double inset;

  // Kurulum düzeni (dp): karo, yazı, çizgi ve slogan tek blok; blok ekranın ortasında durur.
  static const _gapTileWord = 26.0;
  static const _wordH = 54.0;
  static const _gapWordRule = 16.0;
  static const _gapRuleTag = 16.0;
  static const _tagH = 14.0;
  static const _blockH = BrandMark.launchSize + _gapTileWord + _wordH + _gapWordRule + 1 + _gapRuleTag + _tagH;

  // Yerleşim (dp): üst çubuktaki markanın yeri (`PublicTopBar`: soldan 24, karo 28, boşluk 10; çubuk 8'de başlar, 52 yüksek).
  static const _barTile = 28.0;
  static const _barTileLeft = 24.0;
  static const _barWordLeft = _barTileLeft + _barTile + 10;
  static const _barWordSize = 27.0;

  /// "Rebi"nin 54 punto genişliği (ortalamak için). Sistem yazı ölçeği marka yazısını büyütmez.
  static double _wordWidth() {
    final tp = TextPainter(
      text: TextSpan(text: 'Rebi', style: Brand.serif(54, weight: 600, ls: -1.6, h: 1)),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )..layout();
    return tp.width;
  }

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final lang = i18n.lang;
    final w = viewport.width;
    final vh = viewport.height;
    final blockTop = (vh - _blockH) / 2;

    final lift = _iv(t, .07, .25, Curves.easeInOutCubic);
    final word = _iv(t, .15, .40, Curves.easeInOutCubic);
    final rule = _iv(t, .35, .47);
    final tag = _iv(t, .38, .55);
    final travel = _iv(t, .58, .84, Curves.easeInOutCubic);
    final lockupFade = 1 - _iv(t, .58, .68);

    // Karo: önce ekranın ortasından blok konumuna yükselir, sonra sol üstteki yerine küçülerek süzülür.
    final tileLockupY = lerpDouble(vh / 2, blockTop + BrandMark.launchSize / 2, lift)!;
    final tileCenter = Offset.lerp(Offset(w / 2, tileLockupY), Offset(_barTileLeft + _barTile / 2, inset + 34), travel)!;
    final tileSize = lerpDouble(BrandMark.launchSize, _barTile, travel)!;

    // Yazı: harf harf belirir; sonra yazı boyutu 54'ten 27'ye inerken sol üstteki yerine oturur.
    final fs = lerpDouble(54, _barWordSize, travel)!;
    final wordCx = blockTop + BrandMark.launchSize + _gapTileWord + _wordH / 2;
    final wordCy = lerpDouble(wordCx, inset + 34, travel)!;
    final wordLeft = lerpDouble(w / 2 - _wordWidth() / 2, _barWordLeft, travel)!;
    final style = Brand.serif(fs, weight: 600, color: Brand.cream, ls: lerpDouble(-1.6, -.8, travel)!, h: 1);
    const letters = ['R', 'e', 'b', 'i'];

    final ruleTop = blockTop + BrandMark.launchSize + _gapTileWord + _wordH + _gapWordRule;
    final tagTop = blockTop + _blockH - _tagH;

    return Semantics(
        label: 'Rebi',
        excludeSemantics: true,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            if (lockupFade > 0) ...[
              Positioned(
                top: ruleTop,
                left: 0,
                right: 0,
                height: 1,
                child: Center(child: Opacity(opacity: lockupFade, child: Container(width: 32 * rule, height: 1, color: Brand.cream.withValues(alpha: .4)))),
              ),
              Positioned(
                top: tagTop,
                left: -20,
                right: -20,
                height: _tagH,
                child: Opacity(
                  opacity: tag * lockupFade,
                  child: Transform.translate(
                    offset: Offset(0, (1 - tag) * 6),
                    child: Text(
                      brandCaps(i18n.t('landing.heroBadge'), lang),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.visible,
                      textScaler: TextScaler.noScaling,
                      style: tx(11.5, w: 6, c: Brand.cream.withValues(alpha: .8), ls: brandTracking(lang, 2.4), h: 1.2),
                    ),
                  ),
                ),
              ),
            ],
            Positioned(
              left: wordLeft,
              top: wordCy - fs / 2,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < letters.length; i++)
                    Builder(
                      builder: (context) {
                        final p = Curves.easeOutCubic.transform(Interval(i * .17, i * .17 + .49).transform(word));
                        return Opacity(
                          opacity: p,
                          child: Transform.translate(offset: Offset(0, (1 - p) * 14), child: Text(letters[i], textScaler: TextScaler.noScaling, style: style)),
                        );
                      },
                    ),
                ],
              ),
            ),
            Positioned(
              left: tileCenter.dx - tileSize / 2,
              top: tileCenter.dy - tileSize / 2,
              child: BrandMark(size: tileSize),
            ),
          ],
        ),
    );
  }
}

/// Başlık, açıklama, ana düğme, tek satırlık ikincil eylem ve yasal metin; sırayla, sakin bir şekilde belirir.
/// [offsetMs]: belirmenin başlamasından önce beklenecek süre (giriş sekansı bitene kadar).
class _Bottom extends StatelessWidget {
  const _Bottom({required this.offsetMs, required this.authed, required this.onPrimary, required this.onLogin, required this.onChat});

  final int offsetMs;
  final bool authed;
  final VoidCallback onPrimary;
  final VoidCallback onLogin;
  final VoidCallback onChat;

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final small = MediaQuery.sizeOf(context).width < 360;
    final action = tx(14.5, w: 6, c: Brand.cream.withValues(alpha: .9));
    final legal = tx(11.5, w: 5, c: Brand.cream.withValues(alpha: .62));

    Widget tap(Widget child, VoidCallback onTap) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ConstrainedBox(
        // Dokunma alanı en az 48 dp; görünüm metin kadar.
        constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
        child: Center(
          widthFactor: 1,
          heightFactor: 1,
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: child),
        ),
      ),
    );

    Widget reveal(int ms, Widget child, {double dy = 14}) => Reveal(
      delay: Duration(milliseconds: offsetMs + ms),
      duration: const Duration(milliseconds: 650),
      offset: Offset(0, dy),
      child: child,
    );

    final chat = tap(
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.messageCircle, size: 17, color: Brand.cream.withValues(alpha: .9)),
          const SizedBox(width: 8),
          Flexible(child: Text(i18n.t('landing.ctaChat'), style: action)),
        ],
      ),
      onChat,
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(26, 8, 26, 6 + bottom),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Headline(text: i18n.t('mobileLanding.heroTitle'), size: small ? 32 : 38, delay: Duration(milliseconds: offsetMs)),
              const SizedBox(height: 12),
              reveal(
                140,
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    i18n.t('mobileLanding.heroSub'),
                    textAlign: TextAlign.center,
                    style: tx(small ? 15 : 16, c: Brand.cream.withValues(alpha: .76), h: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              reveal(
                300,
                BrandButton(
                  onDark: true,
                  onPressed: onPrimary,
                  label: authed ? i18n.t('mobileLanding.openApp') : i18n.t('landing.ctaBuildRoutine'),
                  trailingIcon: LucideIcons.arrowRight,
                  // Düğme belirdikten kısa süre sonra üstünden bir kez ışık bandı geçer.
                  shimmerDelay: Duration(milliseconds: offsetMs + 300 + 650 + 250),
                ),
              ),
              const SizedBox(height: 4),
              reveal(
                420,
                authed
                    ? Center(child: chat)
                    : Row(
                        children: [
                          Expanded(child: Center(child: tap(Text(i18n.t('auth.login'), style: action), onLogin))),
                          Container(width: 1, height: 20, color: Brand.cream.withValues(alpha: .22)),
                          Expanded(child: Center(child: chat)),
                        ],
                      ),
                dy: 8,
              ),
              reveal(
                520,
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 4,
                  children: [
                    tap(Text(i18n.t('legal.kvkkTitle'), style: legal), () => context.push('/kvkk')),
                    Text('·', style: legal),
                    tap(Text(i18n.t('legal.rizaTitle'), style: legal), () => context.push('/riza')),
                  ],
                ),
                dy: 6,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Karşılama başlığı: belirirken Fraunces'in yazı tipi eksenleri de oturur (ağırlık 320→500, yumuşaklık 0→40); harfler
/// "inceden kalına" yerleşir. Satır sonları sabittir, yazı genişliği yalnızca son hâlden dar olduğu için taşma olmaz.
class _Headline extends StatefulWidget {
  const _Headline({required this.text, required this.size, required this.delay});

  final String text;
  final double size;
  final Duration delay;

  @override
  State<_Headline> createState() => _HeadlineState();
}

class _HeadlineState extends State<_Headline> with SingleTickerProviderStateMixin {
  static const _run = Duration(milliseconds: 1300);
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.delay + _run);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (reduceMotion(context)) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final start = widget.delay.inMilliseconds / (widget.delay + _run).inMilliseconds;
    return Semantics(
      header: true,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final p = Curves.easeOutCubic.transform(Interval(start, 1).transform(_c.value));
          final fade = Curves.easeOut.transform(Interval(start, start + (1 - start) * .5).transform(_c.value));
          final base = Brand.serif(widget.size, color: Brand.cream, ls: -1.1, h: 1.08);
          final style = base.copyWith(
            fontVariations: [
              FontVariation('opsz', widget.size.clamp(9, 144).toDouble()),
              FontVariation('SOFT', 40 * p),
              const FontVariation('WONK', 0),
              FontVariation('wght', 320 + 180 * p),
            ],
          );
          return Opacity(
            opacity: fade,
            child: Transform.translate(
              offset: Offset(0, 18 * (1 - fade)),
              child: Text(widget.text, textAlign: TextAlign.center, style: style),
            ),
          );
        },
      ),
    );
  }
}
