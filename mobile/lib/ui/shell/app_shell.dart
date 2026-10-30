import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/i18n.dart';
import '../../core/subscription.dart';
import '../../state/auth_controller.dart';
import '../../state/notifications_controller.dart';
import '../../state/theme_controller.dart';
import '../components/language_sheet.dart';
import '../brand/brand_mark.dart';
import '../brand/palette.dart';
import '../components/modals.dart';
import '../tw.dart';
import '../widgets/common.dart';

/// Giriş yapmış kullanıcının beş ana sekmesi.
enum AppTab {
  today('/dashboard', LucideIcons.house, 'mobileNav.today'),
  routine('/dashboard/routine', LucideIcons.listChecks, 'mobileNav.routine'),
  chat('/dashboard/chat', LucideIcons.messageCircle, 'mobileNav.chat'),
  history('/dashboard/history', LucideIcons.calendarDays, 'mobileNav.history'),
  me('/dashboard/profile', LucideIcons.userRound, 'mobileNav.me');

  const AppTab(this.path, this.icon, this.labelKey);

  final String path;
  final IconData icon;
  final String labelKey;
}

/// Bir yolun hangi sekmeye ait olduğu; sekme dışı (genel) sayfalar için null.
AppTab? tabForPath(String path) {
  if (!path.startsWith('/dashboard')) return null;
  if (path == '/dashboard' || path.startsWith('/dashboard/checkin') || path.startsWith('/dashboard/shelf')) return AppTab.today;
  if (path.startsWith('/dashboard/routine') || path.startsWith('/dashboard/analyze')) return AppTab.routine;
  if (path.startsWith('/dashboard/chat')) return AppTab.chat;
  if (path.startsWith('/dashboard/history')) return AppTab.history;
  return AppTab.me;
}

/// Sekme kökü olmayan, üstünde geri çubuğu görünen sayfalar (check-in, analiz, ayarlar…).
bool isSubPage(String path) {
  final tab = tabForPath(path);
  return tab != null && path != tab.path;
}

/// Kendi üst sahnesini çizen yollar: sahne durum çubuğunun altına uzanır, bu yüzden kabuk burada üst güvenli alanı
/// uygulamaz ve geri çubuğu çizmez (alt sayfalarda "Geri" sahnenin içindedir). Sahnesiz kalan tek alt sayfa, kendi
/// akışını çizen analizdir (hızlı fotoğraf yükleme kabuklu kalır).
bool hasStage(String path) {
  if (!path.startsWith('/dashboard')) return false;
  if (path == '/dashboard/analyze') return false;
  return true;
}

/// Düzen: genel sayfalarda (sohbet, yasal) üstte logo ve menü; açılış ve giriş kendi üst çubuğunu çizer; giriş yapmış kullanıcıda
/// `/dashboard*` altında üst çubuk yok, beş sekmeli alt çubuk ve alt sayfalarda geri çubuğu var.
/// Yapay zekâ yüzeylerinde beyan kutusu, oturum varken rıza kurtarma kutusu üstte durur.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.location, required this.child});

  final Uri location;
  final Widget child;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  bool _menuOpen = false;

  @override
  void didUpdateWidget(covariant AppShell old) {
    super.didUpdateWidget(old);
    if (old.location != widget.location && _menuOpen) _menuOpen = false;
  }

  /// Android geri tuşu: alt sayfadan sekmesine, sekmeden Bugün'e, Bugün'de uygulamadan çıkış.
  Future<bool> _onBack() async {
    final router = GoRouter.of(context);
    if (router.canPop()) return false;
    final path = widget.location.path;
    if (_menuOpen) {
      setState(() => _menuOpen = false);
      return true;
    }
    final signedIn = context.read<AuthController>().user != null;
    final tab = tabForPath(path);
    if (signedIn && tab != null) {
      if (isSubPage(path)) {
        router.go(tab.path);
        return true;
      }
      if (tab != AppTab.today) {
        router.go(AppTab.today.path);
        return true;
      }
      return false;
    }
    if (path == '/auth' || path == '/rebi') {
      router.go('/');
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthController>().user;
    final theme = context.watch<ThemeController>().theme;
    final path = widget.location.path;
    final isDashboard = path.startsWith('/dashboard');
    // Oturumsuz `/rebi` bir davettir (yapay zekâ yok): beyan penceresi davetin üstüne binmez, sohbette gösterilir.
    final isAiSurface = isDashboard || (path.startsWith('/rebi') && user != null);
    final inApp = user != null && isDashboard;
    // Analiz sihirbazı (tam form) tam ekran bir akıştır: alt çubuk ve geri çubuğu yoktur, üst güvenli alanı kendisi uygular.
    final focusFlow = inApp && path == '/dashboard/analyze' && widget.location.queryParameters['photo'] != '1';
    // Açılış ve giriş ekranları kendi üst çubuğunu çizer (hero zeminin üstünde).
    final immersive = path == '/' || path == '/auth' || path == '/rebi';

    // Sayfa zemini krem kâğıt (koyu modda koyu): durum çubuğu simgeleri buna göre. Sahnesi olan ekranlar (Bugün) kendi
    // `AnnotatedRegion`ıyla açık simge ister; en üstteki bölge geçerli olur.
    final chrome = (Tw.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Tw.surface,
      systemNavigationBarIconBrightness: Tw.dark ? Brightness.light : Brightness.dark,
    );

    return BackButtonListener(
      onBackButtonPressed: _onBack,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: chrome,
        child: Stack(
        children: [
          Scaffold(
            backgroundColor: Tw.background,
            appBar: inApp || immersive ? null : _Navbar(menuOpen: _menuOpen, onToggleMenu: () => setState(() => _menuOpen = !_menuOpen)),
            body: inApp
                // Krem kâğıt + temanın hafif yıkaması tek yerde çizilir: geri çubuğu ve sayfa aynı zeminde durur.
                ? DecoratedBox(
                    decoration: BoxDecoration(gradient: theme.bg),
                    // Sahneli ekranlarda (`hasStage`) üst sahne durum çubuğunun altına uzanır: güvenli alanı sayfa uygular.
                    child: SafeArea(
                      top: !focusFlow && !hasStage(path),
                      bottom: false,
                      child: Column(
                        children: [
                          if (isSubPage(path) && !focusFlow && !hasStage(path)) _SubBar(path: path),
                          Expanded(child: widget.child),
                        ],
                      ),
                    ),
                  )
                : Stack(
                    children: [
                      Positioned.fill(child: widget.child),
                      if (_menuOpen)
                        Positioned(
                          left: 0,
                          right: 0,
                          top: 0,
                          child: _MobileMenu(onClose: () => setState(() => _menuOpen = false)),
                        ),
                    ],
                  ),
            bottomNavigationBar: inApp && !focusFlow ? _BottomNav(path: path) : null,
          ),
          if (isAiSurface) const Positioned.fill(child: AiDisclaimerModal()),
          if (user != null) const Positioned.fill(child: ConsentRecoveryModal()),
        ],
        ),
      ),
    );
  }
}

/// `sticky top-0 glass border-b` — logo + menü düğmesi (genel sayfalar).
class _Navbar extends StatelessWidget implements PreferredSizeWidget {
  const _Navbar({required this.menuOpen, required this.onToggleMenu});

  final bool menuOpen;
  final VoidCallback onToggleMenu;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Tw.background.withValues(alpha: .9),
        border: Border(bottom: BorderSide(color: Tw.gray100)),
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 64,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => context.go('/'),
                  child: Row(
                    children: [
                      const BrandMark(size: 34),
                      const SizedBox(width: 10),
                      Text('Rebi', style: heading(24)),
                    ],
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: onToggleMenu,
                  icon: Icon(menuOpen ? LucideIcons.x : LucideIcons.menu, size: 24, color: Tw.gray600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Genel sayfalardaki açılır menü: dil seçimi ve giriş (giriş yapmış kullanıcıda uygulamaya dönüş).
class _MobileMenu extends StatelessWidget {
  const _MobileMenu({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final auth = context.watch<AuthController>();
    final user = auth.user;

    void go(String path) {
      onClose();
      context.go(path);
    }

    Widget item(String label, Color color, VoidCallback onTap) => InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: SizedBox(width: double.infinity, child: Text(label, style: tx(16, w: 5, c: color))),
          ),
        );

    return Material(
      color: Tw.surfaceRaised,
      elevation: 2,
      child: Container(
        decoration: BoxDecoration(border: Border(top: BorderSide(color: Tw.gray100))),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(padding: EdgeInsets.only(bottom: 8), child: LanguageSelect()),
            if (user != null) ...[
              item(i18n.t('mobileNav.today'), Tw.gray700, () => go('/dashboard')),
              item(i18n.t('mobileNav.me'), Tw.gray700, () => go('/dashboard/profile')),
              if (plusEntryVisible(user)) item(i18n.t('nav.plus'), Tw.amber700, () => go('/dashboard/subscribe')),
              item(i18n.t('nav.newAnalyze'), Tw.teal600, () => go('/dashboard/analyze')),
              item(i18n.t('nav.logout'), Tw.red500, () {
                onClose();
                signOutAndGoHome(context);
              }),
            ] else
              SizedBox(
                width: double.infinity,
                child: PrimaryButton(onPressed: () => go('/auth'), label: i18n.t('nav.login')),
              ),
          ],
        ),
      ),
    );
  }
}

/// Çıkış: oturum kapanınca yetki gider; cihaz kaydı ve yerel bildirimler önce temizlenir.
Future<void> signOutAndGoHome(BuildContext context) async {
  final router = GoRouter.of(context);
  final auth = context.read<AuthController>();
  final notifications = context.read<NotificationsController>();
  await notifications.prepareSignOut();
  await auth.signOut();
  router.go('/');
}

/// Dil seçici (web: `LanguageSelect.jsx`).
class LanguageSelect extends StatelessWidget {
  const LanguageSelect({super.key});

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 6,
      children: [
        Text(i18n.t('lang.label'), style: tx(11, w: 6, c: Tw.gray500)),
        Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Tw.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Tw.gray200),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: i18n.lang,
              itemHeight: kMinInteractiveDimension,
              dropdownColor: Tw.surfaceRaised,
              // DropdownButton ortam yazı stilini ezer; Inter'i açıkça taşımazsa seçili metin sistem yazı tipine düşer.
              style: tx(13, w: 6, c: Tw.gray700).copyWith(fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily),
              icon: Icon(LucideIcons.chevronDown, size: 14, color: Tw.gray500),
              items: [
                for (final lng in supportedLangs)
                  DropdownMenuItem(value: lng, child: Text(languageLabels[lng] ?? lng)),
              ],
              onChanged: (v) {
                if (v != null) I18n.instance.changeLanguage(v);
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Alt sayfalarda (check-in, analiz, ayarlar…) üstteki geri çubuğu.
class _SubBar extends StatelessWidget {
  const _SubBar({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final parent = tabForPath(path)!;
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
        child: TextButton.icon(
          onPressed: () => context.canPop() ? context.pop() : context.go(parent.path),
          icon: Icon(LucideIcons.chevronLeft, size: 20, color: Tw.gray600),
          label: Text(i18n.t('mobileNav.back'), style: tx(14, w: 6, c: Tw.gray600)),
          style: TextButton.styleFrom(
            foregroundColor: Tw.gray600,
            minimumSize: const Size(48, 40),
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
        ),
      ),
    );
  }
}

/// Alt sekme çubuğu: Bugün · Rutin · Rebi · Geçmiş · Ben.
class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final theme = context.watch<ThemeController>().theme;
    final active = tabForPath(path);

    return Container(
      decoration: BoxDecoration(
        color: Tw.surface.withValues(alpha: .97),
        border: Border(top: BorderSide(color: Tw.gray100)),
      ),
      child: SafeArea(
        top: false,
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 512),
            child: SizedBox(
              height: 64,
              child: Row(
                children: [
                  for (final tab in AppTab.values)
                    Expanded(
                      child: _TabButton(
                        tab: tab,
                        label: i18n.t(tab.labelKey),
                        active: active == tab,
                        color: theme.fg,
                        lightColor: theme.primaryLight,
                        onTap: () {
                          // Başka bir sekmeye geçerken hafif tıkırtı (aynı sekmeye dokunmak yalnızca köke döner).
                          if (active != tab) unawaited(HapticFeedback.selectionClick().catchError((_) {}));
                          context.go(tab.path);
                        },
                      ),
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

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.tab,
    required this.label,
    required this.active,
    required this.color,
    required this.lightColor,
    required this.onTap,
  });

  final AppTab tab;
  final String label;
  final bool active;
  final Color color;
  final Color lightColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
              decoration: BoxDecoration(
                color: active ? lightColor.withValues(alpha: Tw.dark ? .5 : 1) : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Icon(tab.icon, size: 22, color: active ? color : Tw.gray400),
            ),
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                // Sekme çubuğunun yüksekliği sabit (64): çok büyük sistem yazısında etiket onu aşmasın.
                child: Text(
                  label,
                  maxLines: 1,
                  textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.5),
                  style: tx(11, w: active ? 7 : 5, c: active ? color : Tw.gray500),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
