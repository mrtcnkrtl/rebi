import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/api.dart';
import '../../core/i18n.dart';
import '../../state/theme_controller.dart';
import '../../ui/tw.dart';
import '../../ui/widgets/common.dart';
import 'account_parts.dart';

/// Şifre değiştirme (yalnız e-postayla giriş yapan hesaplar için; sosyal girişte şifre bu ekrandan değişmez).
class AccountPasswordCard extends StatefulWidget {
  const AccountPasswordCard({super.key, required this.theme});

  final RebiTheme theme;

  @override
  State<AccountPasswordCard> createState() => _AccountPasswordCardState();
}

class _AccountPasswordCardState extends State<AccountPasswordCard> {
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();
  (String, String) _msg = ('', '');
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _newPassword.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _newPassword.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _change() async {
    final i18n = I18n.instance;
    setState(() => _msg = ('', ''));
    if (_newPassword.text.length < 6) {
      setState(() => _msg = ('err', i18n.t('mobileAccount.password.tooShort')));
      return;
    }
    if (_newPassword.text != _confirmPassword.text) {
      setState(() => _msg = ('err', i18n.t('mobileAccount.password.mismatch')));
      return;
    }
    final client = supabase;
    if (client == null) return;
    setState(() => _saving = true);
    try {
      await client.auth.updateUser(UserAttributes(password: _newPassword.text));
      _newPassword.clear();
      _confirmPassword.clear();
      if (mounted) setState(() => _msg = ('ok', i18n.t('mobileAccount.password.updated')));
    } on AuthException catch (e) {
      if (mounted) setState(() => _msg = ('err', e.message.isEmpty ? i18n.t('mobileAccount.password.failed') : e.message));
    } catch (_) {
      if (mounted) setState(() => _msg = ('err', i18n.t('mobileAccount.password.failed')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final theme = widget.theme;
    return RCard(
      padding: const EdgeInsets.all(18),
      radius: 24,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccountSectionTitle(icon: LucideIcons.lock, color: theme.fg, text: i18n.t('mobileAccount.password.title')),
          const SizedBox(height: 6),
          Text(i18n.t('mobileAccount.passwordNote'), style: tx(12.5, c: Tw.gray600, h: relaxed)),
          const SizedBox(height: 14),
          TextField(
            controller: _newPassword,
            obscureText: true,
            autofillHints: const [AutofillHints.newPassword],
            decoration: inputDecoration(hint: i18n.t('mobileAccount.password.hint')),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirmPassword,
            obscureText: true,
            autofillHints: const [AutofillHints.newPassword],
            decoration: inputDecoration(hint: i18n.t('mobileAccount.password.confirm')),
            onSubmitted: (_) => _change(),
          ),
          if (_msg.$2.isNotEmpty) ...[
            const SizedBox(height: 12),
            StatusLine(ok: _msg.$1 == 'ok', text: _msg.$2),
          ],
          const SizedBox(height: 14),
          SecondaryButton(
            onPressed: _saving || _newPassword.text.isEmpty ? null : _change,
            loading: _saving,
            borderColor: theme.primaryLight,
            textColor: theme.fg,
            fontSize: 15,
            label: i18n.t('mobileAccount.password.update'),
          ),
        ],
      ),
    );
  }
}
