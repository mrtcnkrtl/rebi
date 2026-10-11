import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/i18n.dart';
import '../../core/routine_tracking.dart';
import '../../state/auth_controller.dart';
import '../../state/theme_controller.dart';
import '../components/modals.dart';
import '../tw.dart';
import '../widgets/common.dart';

/// Web `App.jsx` düzeni: üstte Navbar, `/dashboard*` altında BottomNav,
/// yapay zekâ yüzeylerinde beyan kutusu, oturum varken rıza kurtarma kutusu.
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

  /// Android geri tuşu: sekme yığını boşsa ana panele dön (web: tarayıcı geçmişi).
  Future<bool> _onBack() async {
    final router = GoRouter.of(context);
    if (router.canPop()) return false;
    final path = widget.location.path;
    if (_menuOpen) {
      setState(() => _menuOpen = false);
      return true;
    }
    if (path.startsWith('/dashboard/') && context.read<AuthController>().user != null) {
      router.go('/dashboard');
      return true;
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
    final path = widget.location.path;
    final isDashboard = path.startsWith('/dashboard');
    final isAiSurface = isDashboard || path.startsWith('/rebi');

    return BackButtonListener(
      onBackButtonPressed: _onBack,
      child: Stack(
        children: [
          Scaffold(
            backgroundColor: Colors.white,
            appBar: _Navbar(
              menuOpen: _menuOpen,
              onToggleMenu: () => setState(() => _menuOpen = !_menuOpen),
            ),
            body: Stack(
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
            bottomNavigationBar: user != null && isDashboard ? _BottomNav(path: path) : null,
          ),
          if (isAiSurface) const Positioned.fill(child: AiDisclaimerModal()),
          if (user != null) const Positioned.fill(child: ConsentRecoveryModal()),
        ],
      ),
    );
  }
}

/// `sticky top-0 glass border-b` — logo + menü düğmesi.
class _Navbar extends StatelessWidget implements PreferredSizeWidget {
  const _Navbar({required this.menuOpen, required this.onToggleMenu});

  final bool menuOpen;
  final VoidCallback onToggleMenu;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .8),
            border: Border(bottom: BorderSide(color: Tw.gray100.withValues(alpha: .5))),
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
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Tw.teal500, Tw.teal600],
                              ),
                              boxShadow: [
                                BoxShadow(color: Tw.teal500.withValues(alpha: .2), blurRadius: 15, offset: const Offset(0, 8)),
                              ],
                            ),
                            child: const Icon(LucideIcons.leaf, size: 20, color: Colors.white),
                          ),
                          const SizedBox(width: 8),
                          Text('Rebi', style: tx(20, w: 7)),
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
        ),
      ),
    );
  }
}

/// Webdeki mobil hamburger menüsü.
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
      color: Colors.white,
      elevation: 2,
      child: Container(
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: Tw.gray100))),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(padding: EdgeInsets.only(bottom: 8), child: LanguageSelect()),
            if (user != null) ...[
              item(i18n.t('nav.dashboard'), Tw.gray700, () => go('/dashboard')),
              item(i18n.t('nav.profile'), Tw.gray700, () => go('/dashboard/profile')),
              item(i18n.t('nav.plus'), Tw.amber700, () => go('/dashboard/subscribe')),
              item(i18n.t('nav.newAnalyze'), Tw.teal600, () => go('/dashboard/analyze')),
              item(i18n.t('nav.logout'), Tw.red500, () async {
                onClose();
                final router = GoRouter.of(context);
                await auth.signOut();
                router.go('/');
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

const _langLabels = {'tr': 'Türkçe', 'en': 'English'};

/// Dil seçici (web: `LanguageSelect.jsx`).
class LanguageSelect extends StatelessWidget {
  const LanguageSelect({super.key});

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(i18n.t('lang.label'), style: tx(11, w: 6, c: Tw.gray500)),
        const SizedBox(width: 8),
        Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Tw.gray200),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: i18n.lang,
              isDense: true,
              style: tx(11, w: 6, c: Tw.gray700),
              icon: const Icon(LucideIcons.chevronDown, size: 14, color: Tw.gray500),
              items: [
                for (final lng in supportedLangs)
                  DropdownMenuItem(value: lng, child: Text(_langLabels[lng] ?? lng)),
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

class _Tab {
  const _Tab(this.id, this.label, this.icon);

  final String id;
  final String label;
  final IconData icon;
}

/// Alt sekme çubuğu (web: `BottomNav.jsx`).
class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final theme = context.watch<ThemeController>().theme;
    final user = context.watch<AuthController>().user;
    final analyzeLabel = user != null && hasCompletedOnboarding(user.id) ? i18n.t('nav.reanalyze') : i18n.t('nav.analyze');
    final tabs = [
      _Tab('/dashboard', i18n.t('nav.home'), LucideIcons.house),
      _Tab('/dashboard/checkin', i18n.t('nav.checkin'), LucideIcons.clipboardCheck),
      _Tab('/dashboard/chat', i18n.t('nav.chat'), LucideIcons.messageCircle),
      _Tab('/dashboard/analyze', analyzeLabel, LucideIcons.scan),
      _Tab('/dashboard/themes', i18n.t('nav.theme'), LucideIcons.palette),
      _Tab('/dashboard/profile', i18n.t('nav.profile'), LucideIcons.userRound),
    ];
    final active = tabs.where((t) => path == t.id).firstOrNull?.id ??
        tabs.where((t) => t.id != '/dashboard' && path.startsWith(t.id)).firstOrNull?.id;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .95),
            border: Border(top: BorderSide(color: Tw.gray200.withValues(alpha: .6))),
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
                      for (final tab in tabs)
                        Expanded(
                          child: _TabButton(
                            tab: tab,
                            active: active == tab.id,
                            color: theme.primary,
                            lightColor: theme.primaryLight,
                            onTap: () {
                              if (tab.id == '/dashboard/checkin' && user != null && !isRoutineTrackingAccepted(user.id)) {
                                context.go('/dashboard', extra: const {'flashNeedAccept': true});
                                return;
                              }
                              context.go(tab.id);
                            },
                          ),
                        ),
                    ],
                  ),
                ),
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
    required this.active,
    required this.color,
    required this.lightColor,
    required this.onTap,
  });

  final _Tab tab;
  final bool active;
  final Color color;
  final Color lightColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: AnimatedScale(
        scale: active ? 1.05 : 1,
        duration: const Duration(milliseconds: 150),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: active ? lightColor : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                boxShadow: active ? const [BoxShadow(color: Color(0x0D000000), blurRadius: 2, offset: Offset(0, 1))] : null,
              ),
              child: Icon(tab.icon, size: 20, color: active ? color : Tw.gray400),
            ),
            const SizedBox(height: 2),
            // Web'de etiket tam görünür ("Yeniden analiz"); dar sekmede kesmek yerine sığdır.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(tab.label, maxLines: 1, style: tx(10, w: 5, c: active ? color : Tw.gray400)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
