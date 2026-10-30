import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/api.dart';
import '../../core/demo_user.dart';
import '../../core/i18n.dart';
import '../../core/user_profile.dart';
import '../../state/auth_controller.dart';
import '../../state/theme_controller.dart';
import '../../ui/widgets/common.dart';
import 'account_parts.dart';

/// Görünen ad: oturumdaki `full_name` ve (varsa) sunucudaki profil kaydı birlikte güncellenir.
class AccountNameCard extends StatefulWidget {
  const AccountNameCard({super.key, required this.theme});

  final RebiTheme theme;

  @override
  State<AccountNameCard> createState() => _AccountNameCardState();
}

class _AccountNameCardState extends State<AccountNameCard> {
  final _displayName = TextEditingController();
  (String, String) _msg = ('', '');
  bool _saving = false;
  String? _lastName;
  late final AuthController _auth = context.read<AuthController>();

  /// Görünen ad, oturumdaki `full_name` değişince güncellenir.
  void _syncName() {
    final name = (_auth.user?.userMetadata?['full_name'] ?? '').toString();
    if (name == _lastName) return;
    _lastName = name;
    _displayName.text = name;
  }

  @override
  void initState() {
    super.initState();
    _auth.addListener(_syncName);
    _syncName();
  }

  @override
  void dispose() {
    _auth.removeListener(_syncName);
    _displayName.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final client = supabase;
    if (client == null) return;
    final i18n = I18n.instance;
    setState(() {
      _msg = ('', '');
      _saving = true;
    });
    try {
      final trimmed = _displayName.text.trim();
      await client.auth.updateUser(UserAttributes(data: {'full_name': trimmed.isEmpty ? null : trimmed}));
      await _auth.refreshUser();
      // Sunucudaki profil kaydındaki ad da güncellensin (en iyi çaba; ad zaten oturumda güncellendi).
      final uid = _auth.user?.id;
      if (uid != null && uid != demoUserId && trimmed.isNotEmpty) {
        try {
          await updateMyProfile(uid, ProfileUpdate(fullName: trimmed));
        } catch (_) {
          /* çevrimdışı: bir sonraki analizde sunucu adı yine yazar */
        }
      }
      if (mounted) setState(() => _msg = ('ok', i18n.t('mobileAccount.name.saved')));
    } on AuthException catch (e) {
      if (mounted) setState(() => _msg = ('err', e.message.isEmpty ? i18n.t('mobileAccount.name.failed') : e.message));
    } catch (_) {
      if (mounted) setState(() => _msg = ('err', i18n.t('mobileAccount.name.failed')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    return RCard(
      padding: const EdgeInsets.all(18),
      radius: 24,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccountSectionTitle(icon: LucideIcons.user, color: widget.theme.fg, text: i18n.t('mobileAccount.name.title')),
          const SizedBox(height: 14),
          TextField(
            controller: _displayName,
            maxLength: 120,
            textCapitalization: TextCapitalization.words,
            decoration: inputDecoration(hint: i18n.t('mobileAccount.name.hint')).copyWith(counterText: ''),
            onSubmitted: (_) => _save(),
          ),
          if (_msg.$2.isNotEmpty) ...[
            const SizedBox(height: 12),
            StatusLine(ok: _msg.$1 == 'ok', text: _msg.$2),
          ],
          const SizedBox(height: 14),
          PrimaryButton(
            onPressed: _saving ? null : _save,
            loading: _saving,
            color: widget.theme.primary,
            fontSize: 15,
            label: i18n.t('mobileAccount.name.save'),
          ),
        ],
      ),
    );
  }
}
