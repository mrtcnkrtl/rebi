import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/ai_sharing.dart';
import '../../core/demo_user.dart';
import '../../core/i18n.dart';
import '../../core/privacy_preferences.dart';
import '../../state/auth_controller.dart';
import '../../state/theme_controller.dart';
import '../../ui/components/modals.dart';
import '../../ui/tw.dart';
import '../../ui/widgets/common.dart';
import 'account_parts.dart';

/// Gizlilik izinleri: yapay zekâ (Google Gemini) ile veri paylaşımı (cihazda tutulur, geri alınabilir), konum ve fotoğraf
/// saklama tercihleri (sunucuya yazılır) + KVKK / açık rıza metinlerine bağlantılar.
class AccountPrivacyCard extends StatefulWidget {
  const AccountPrivacyCard({super.key, required this.theme});

  final RebiTheme theme;

  @override
  State<AccountPrivacyCard> createState() => _AccountPrivacyCardState();
}

class _AccountPrivacyCardState extends State<AccountPrivacyCard> {
  bool _ai = false;
  bool _location = false;
  bool _photo = false;
  bool _saving = false;
  String _msg = '';

  @override
  void initState() {
    super.initState();
    _ai = hasAiSharingConsent(context.read<AuthController>().user?.id ?? demoUserId);
    final uid = context.read<AuthController>().user?.id;
    if (uid == null) return;
    getPrivacyPreferences(uid).then((data) {
      if (!mounted) return;
      setState(() {
        _location = data['location_processing_allowed'] == true;
        _photo = data['photo_processing_allowed'] == true;
      });
    }).catchError((_) {
      if (mounted) setState(() => _msg = I18n.instance.t('mobileAccount.privacy.loadFailed'));
    });
  }

  Future<void> _save() async {
    final uid = context.read<AuthController>().user?.id;
    if (uid == null) return;
    final i18n = I18n.instance;
    setState(() {
      _saving = true;
      _msg = '';
    });
    try {
      await setAiSharingConsent(uid, _ai);
      await updatePrivacyPreferences(uid, location: _location, photo: _photo);
      if (mounted) setState(() => _msg = i18n.t('mobileAccount.privacy.saved'));
    } catch (e) {
      final m = e.toString().replaceFirst('Exception: ', '');
      if (mounted) setState(() => _msg = m.isEmpty ? i18n.t('mobileAccount.privacy.failed') : m);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// "Neler paylaşılıyor?": izin ekranının aynısı; oradan "İzin ver" denirse kutu işaretlenir (kaydet ile kalıcı olur).
  Future<void> _showAiDetails() async {
    if (await showAiSharingDialog(context) && mounted) setState(() => _ai = true);
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
          AccountSectionTitle(icon: LucideIcons.shield, color: theme.fg, text: i18n.t('mobileAccount.privacy.title')),
          const SizedBox(height: 8),
          Text(i18n.t('mobileAccount.privacy.body'), style: tx(12.5, c: Tw.gray600, h: relaxed)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            children: [
              TextLink(i18n.t('legal.kvkkTitle'), onTap: () => context.push('/kvkk'), style: tx(13, w: 6, c: Tw.teal700), underline: true),
              TextLink(i18n.t('legal.rizaTitle'), onTap: () => context.push('/riza'), style: tx(13, w: 6, c: Tw.teal700), underline: true),
            ],
          ),
          const SizedBox(height: 8),
          const AiDisclaimer(),
          const SizedBox(height: 10),
          AccountCheckboxRow(value: _ai, onChanged: (v) => setState(() => _ai = v), label: i18n.t('mobileAccount.privacy.aiSharing')),
          Padding(
            padding: const EdgeInsets.only(left: 36, bottom: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextLink(
                i18n.t('mobileAccount.privacy.aiSharingDetails'),
                onTap: _showAiDetails,
                style: tx(12.5, w: 6, c: Tw.teal700),
                underline: true,
              ),
            ),
          ),
          AccountCheckboxRow(value: _location, onChanged: (v) => setState(() => _location = v), label: i18n.t('mobileAccount.privacy.location')),
          const SizedBox(height: 4),
          AccountCheckboxRow(value: _photo, onChanged: (v) => setState(() => _photo = v), label: i18n.t('mobileAccount.privacy.photo')),
          if (_msg.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(_msg, style: tx(12.5, c: Tw.gray600, h: snug)),
          ],
          const SizedBox(height: 14),
          SecondaryButton(
            onPressed: _saving ? null : _save,
            loading: _saving,
            fontSize: 15,
            label: i18n.t('mobileAccount.privacy.save'),
          ),
        ],
      ),
    );
  }
}
