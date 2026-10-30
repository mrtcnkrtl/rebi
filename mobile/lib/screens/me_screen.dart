import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../core/i18n.dart';
import '../core/subscription.dart';
import '../state/auth_controller.dart';
import '../state/theme_controller.dart';
import '../ui/brand/palette.dart';
import '../ui/components/appearance_card.dart';
import '../ui/components/language_sheet.dart';
import '../ui/shell/app_shell.dart';
import '../ui/shell/page_stage.dart';
import '../ui/tw.dart';
import '../ui/widgets/app_sheet.dart';
import '../ui/widgets/common.dart';
import '../ui/widgets/menu_list.dart';
import 'today/today_widgets.dart';

/// "Ben" sekmesi: hesap özeti ve ayarlara giden menü. Üst sahne (avatar, ad, e-posta) diğer ekranlarla aynı dildedir;
/// eylemler tek yüzeyli gruplar halinde, ilgili olanlar bir arada durur.
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

    return StagePage(
      theme: theme,
      badge: plus ? _PlusBadge(label: i18n.t('mobileMe.plusBadge')) : null,
      title: name,
      subtitle: user?.email,
      leading: _Avatar(name: name),
      bottomPadding: 32,
      children: [
        MenuGroup(rows: [
          MenuRow(
            icon: LucideIcons.shield,
            color: theme.primary,
            title: i18n.t('mobileMe.account.title'),
            hint: i18n.t('mobileMe.account.hint'),
            onTap: () => context.go('/dashboard/account'),
          ),
          MenuRow(
            icon: LucideIcons.bellRing,
            color: theme.primary,
            title: i18n.t('mobileReminders.open'),
            hint: i18n.t('mobileReminders.openHint'),
            onTap: () => context.go('/dashboard/reminders'),
          ),
          MenuRow(
            icon: LucideIcons.packageCheck,
            color: theme.primary,
            title: i18n.t('mobileShelf.title'),
            hint: i18n.t('mobileMe.shelf.hint'),
            onTap: () => context.go('/dashboard/shelf'),
          ),
          MenuRow(
            icon: LucideIcons.scan,
            color: theme.primary,
            title: i18n.t('mobileMe.reanalyze.title'),
            hint: i18n.t('mobileMe.reanalyze.hint'),
            onTap: () => context.go('/dashboard/analyze'),
          ),
        ]),
        const SizedBox(height: 28),
        AppearanceCard(theme: theme),
        const SizedBox(height: 10),
        MenuGroup(rows: [
          MenuRow(
            icon: LucideIcons.palette,
            color: Tw.purple600,
            title: i18n.t('mobileMe.themes.title'),
            hint: i18n.t('mobileMe.themes.hint'),
            onTap: () => context.go('/dashboard/themes'),
          ),
        ]),
        const SizedBox(height: 28),
        SectionLabel(i18n.t('mobileMe.groups.more')),
        MenuGroup(rows: [
          if (plus || plusPurchasable)
            MenuRow(
              icon: LucideIcons.crown,
              color: Tw.amber600,
              title: i18n.t('mobileMe.plus.title'),
              hint: i18n.t(plus ? 'mobileMe.plus.active' : 'mobileMe.plus.hint'),
              onTap: () => context.go('/dashboard/subscribe'),
            ),
          MenuRow(
            icon: LucideIcons.languages,
            color: theme.primary,
            title: i18n.t('lang.label'),
            hint: languageLabels[i18n.lang] ?? i18n.lang,
            onTap: () => showLanguageSheet(context),
          ),
        ]),
        const SizedBox(height: 28),
        SecondaryButton(
          onPressed: () => _confirmSignOut(context),
          borderColor: Tw.red200,
          textColor: Tw.readable(Tw.red600),
          icon: LucideIcons.logOut,
          fontSize: 15,
          label: i18n.t('mobileMe.logout'),
        ),
      ],
    );
  }
}

/// Çıkış, yanlışlıkla dokunmaya karşı bir onay sayfasından geçer (çıkış bildirimleri ve cihaz kaydını da siler).
Future<void> _confirmSignOut(BuildContext context) async {
  final i18n = I18n.instance;
  final confirmed = await AppSheet.show<bool>(
    context,
    title: i18n.t('mobileMe.logoutConfirm.title'),
    subtitle: i18n.t('mobileMe.logoutConfirm.body'),
    body: (ctx) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PrimaryButton(
          color: Tw.fillWithWhiteText(Tw.red600),
          icon: LucideIcons.logOut,
          label: i18n.t('mobileMe.logoutConfirm.confirm'),
          onPressed: () => Navigator.of(ctx).pop(true),
        ),
        const SizedBox(height: 10),
        SecondaryButton(onPressed: () => Navigator.of(ctx).pop(false), label: i18n.t('mobileMe.logoutConfirm.cancel')),
      ],
    ),
  );
  if (confirmed == true && context.mounted) await signOutAndGoHome(context);
}

/// Plus hesabının küçük hapı: krem çerçeveli, taç simgeli (renk yok; sahne sakin kalır).
class _PlusBadge extends StatelessWidget {
  const _PlusBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Brand.cream.withValues(alpha: .4)),
        color: Brand.cream.withValues(alpha: .08),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.crown, size: 13, color: Brand.cream),
          const SizedBox(width: 6),
          Text(label, style: tx(12, w: 7, c: Brand.cream)),
        ],
      ),
    );
  }
}

/// Sahnedeki avatar: krem çerçeveli, içinde Fraunces baş harf (düz dolgu yok; sahnenin derin tonu görünür kalır).
class _Avatar extends StatelessWidget {
  const _Avatar({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    return ExcludeSemantics(
      child: Container(
        width: 68,
        height: 68,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Brand.cream.withValues(alpha: .1),
          border: Border.all(color: Brand.cream.withValues(alpha: .34), width: 1.4),
        ),
        child: Text(initial, style: Brand.serif(32, color: Brand.cream, h: 1, ls: 0)),
      ),
    );
  }
}
