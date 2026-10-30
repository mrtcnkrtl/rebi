import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/checkin_stats.dart';
import '../core/demo_user.dart';
import '../core/i18n.dart';
import '../core/routine_tracking.dart';
import '../core/subscription.dart';
import '../state/auth_controller.dart';
import '../state/theme_controller.dart';
import '../ui/components/profile_details_card.dart';
import '../ui/shell/page_stage.dart';
import '../ui/tw.dart';
import '../ui/widgets/common.dart';
import 'account/delete_card.dart';
import 'account/name_card.dart';
import 'account/password_card.dart';
import 'account/photos_card.dart';
import 'account/privacy_card.dart';
import 'account/routine_stats_card.dart';
import 'account/summary_card.dart';

export 'account/delete_card.dart' show accountDeletePhrase, typedDeletePhrase;

/// Testlerde hesap ekranını Supabase yapılandırması olmadan açmak için (null: gerçek duruma bak).
@visibleForTesting
bool? debugAccountAvailable;

/// Hesap ve gizlilik (web: `pages/Profile.jsx`). Ekran yalnızca bir kompozisyondur: her bölüm kendi durumunu taşıyan ayrı bir
/// kart (`screens/account/`). Sıra: özet → rutin özeti → cilt profili → ad → şifre → gizlilik → fotoğraflar → hesabı sil (en sonda).
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  @override
  void initState() {
    super.initState();
    _backfillAcceptedAt();
  }

  /// Eski kayıtlarda acceptedAt yoktu; profil açılınca bir kez tamamlanır.
  void _backfillAcceptedAt() {
    final uid = context.read<AuthController>().user?.id;
    if (uid == null || !isRoutineTrackingAccepted(uid)) return;
    final s = getRoutineSnapshot(uid);
    final r = s?['routine'];
    if (s != null && s['acceptedAt'] == null && r is List && r.isNotEmpty) {
      saveRoutineSnapshot(uid, {
        'acceptedAt': s['updatedAt'] is num ? s['updatedAt'] : DateTime.now().millisecondsSinceEpoch,
      }).then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final theme = context.watch<ThemeController>().theme;
    final user = context.watch<AuthController>().user;
    final uid = user?.id;
    final real = uid != null && uid != demoUserId;
    final stats = uid != null ? getProfileRoutineStats(uid) : null;
    const gap = SizedBox(height: 16);

    if (!(debugAccountAvailable ?? supabase != null)) {
      return ThemedBackground(
        theme: theme,
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(i18n.t('mobileAccount.unavailable'), textAlign: TextAlign.center, style: tx(14, c: Tw.gray600)),
            ),
          ),
        ),
      );
    }

    return StagePage(
      theme: theme,
      title: i18n.t('profile.title'),
      subtitle: i18n.t('profile.subtitle'),
      backTo: '/dashboard/profile',
      maxWidth: 512,
      bottomPadding: 48,
      children: [
        AccountSummaryCard(theme: theme, email: user?.email, createdAt: user?.createdAt, plus: userHasRebiPlus(user)),
        if (stats?.hasAcceptedRoutine ?? false) ...[gap, AccountRoutineStatsCard(theme: theme, stats: stats!)],
        if (real) ...[gap, ProfileDetailsCard(theme: theme)],
        gap,
        AccountNameCard(theme: theme),
        gap,
        AccountPasswordCard(theme: theme),
        if (real) ...[gap, AccountPrivacyCard(theme: theme)],
        gap,
        AccountPhotosCard(theme: theme),
        if (real) ...[const SizedBox(height: 28), const AccountDeleteCard()],
      ],
    );
  }
}
