import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../core/i18n.dart';
import '../core/subscription.dart';
import '../state/auth_controller.dart';
import '../state/theme_controller.dart';
import '../ui/components/appearance_card.dart';
import '../ui/shell/app_shell.dart';
import '../ui/tw.dart';
import '../ui/widgets/common.dart';
import 'today/today_widgets.dart';

/// "Ben" sekmesi: hesap özeti ve ayarlara giden menü. Hamburger menüsünün yerini alır.
class MeScreen extends StatelessWidget {
  const MeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final theme = context.watch<ThemeController>().theme;
    final user = context.watch<AuthController>().user;
    final plus = userHasRebiPlus(user);
    final fullName = '${user?.userMetadata?['full_name'] ?? ''}'.trim();
    final name = fullName.isNotEmpty ? fullName : (user?.email?.split('@').first ?? i18n.t('mobileMe.noName'));

    return ThemedPage(
      theme: theme,
      maxWidth: 672,
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
      children: [
        _Header(name: name, email: user?.email ?? '', plus: plus, theme: theme),
        const SizedBox(height: 24),
        _GroupTitle(i18n.t('mobileMe.groups.account')),
        _MenuRow(
          icon: LucideIcons.shield,
          color: theme.primary,
          title: i18n.t('mobileMe.account.title'),
          hint: i18n.t('mobileMe.account.hint'),
          onTap: () => context.go('/dashboard/account'),
        ),
        const SizedBox(height: 10),
        _MenuRow(
          icon: LucideIcons.bellRing,
          color: theme.primary,
          title: i18n.t('mobileReminders.open'),
          hint: i18n.t('mobileReminders.openHint'),
          onTap: () => context.go('/dashboard/reminders'),
        ),
        const SizedBox(height: 10),
        _MenuRow(
          icon: LucideIcons.scan,
          color: theme.primary,
          title: i18n.t('mobileMe.reanalyze.title'),
          hint: i18n.t('mobileMe.reanalyze.hint'),
          onTap: () => context.go('/dashboard/analyze'),
        ),
        const SizedBox(height: 24),
        _GroupTitle(i18n.t('mobileMe.groups.look')),
        AppearanceCard(theme: theme),
        const SizedBox(height: 10),
        _MenuRow(
          icon: LucideIcons.palette,
          color: const Color(0xFF7C3AED),
          title: i18n.t('mobileMe.themes.title'),
          hint: i18n.t('mobileMe.themes.hint'),
          onTap: () => context.go('/dashboard/themes'),
        ),
        const SizedBox(height: 24),
        _GroupTitle(i18n.t('mobileMe.groups.more')),
        _MenuRow(
          icon: LucideIcons.crown,
          color: Tw.amber600,
          title: i18n.t('mobileMe.plus.title'),
          hint: i18n.t(plus ? 'mobileMe.plus.active' : 'mobileMe.plus.hint'),
          onTap: () => context.go('/dashboard/subscribe'),
        ),
        const SizedBox(height: 10),
        RCard(
          padding: const EdgeInsets.all(14),
          radius: 20,
          child: const Align(alignment: Alignment.centerLeft, child: LanguageSelect()),
        ),
        const SizedBox(height: 24),
        SecondaryButton(
          onPressed: () => signOutAndGoHome(context),
          borderColor: Tw.red200,
          textColor: Tw.red600,
          icon: LucideIcons.logOut,
          fontSize: 15,
          label: i18n.t('mobileMe.logout'),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.name, required this.email, required this.plus, required this.theme});

  final String name;
  final String email;
  final bool plus;
  final RebiTheme theme;

  @override
  Widget build(BuildContext context) {
    final i18n = I18n.instance;
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    return Row(
      children: [
        Container(
          width: 64,
          height: 64,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [theme.accent, theme.primary]),
            boxShadow: [BoxShadow(color: theme.primary.withValues(alpha: .25), blurRadius: 14, offset: const Offset(0, 6))],
          ),
          child: Text(initial, style: tx(26, w: 8, c: Colors.white)),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(22, w: 8, h: tight))),
                if (plus) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: Tw.amber100, borderRadius: BorderRadius.circular(999)),
                    child: Text(i18n.t('mobileMe.plusBadge'), style: tx(10, w: 8, c: Tw.amber900)),
                  ),
                ],
              ]),
              if (email.isNotEmpty) Text(email, maxLines: 1, overflow: TextOverflow.ellipsis, style: tx(13, c: Tw.gray500)),
            ],
          ),
        ),
      ],
    );
  }
}

class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.only(left: 4, bottom: 8), child: Text(text.toUpperCase(), style: tx(11, w: 7, c: Tw.gray500, ls: .6)));
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.color, required this.title, required this.hint, required this.onTap});

  final IconData icon;
  final Color color;
  final String title;
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: title,
      child: RCard(
        padding: const EdgeInsets.all(14),
        radius: 20,
        onTap: onTap,
        child: Row(
          children: [
            TodayIconBadge(icon: icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: tx(14, w: 7, c: Tw.gray800)),
                  const SizedBox(height: 2),
                  Text(hint, style: tx(12, c: Tw.gray500, h: snug)),
                ],
              ),
            ),
            Icon(LucideIcons.chevronRight, size: 18, color: Tw.gray400),
          ],
        ),
      ),
    );
  }
}
