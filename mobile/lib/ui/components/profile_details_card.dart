import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/demo_user.dart';
import '../../core/i18n.dart';
import '../../core/user_profile.dart';
import '../../state/auth_controller.dart';
import '../../state/theme_controller.dart';
import '../tw.dart';
import '../widgets/common.dart';
import 'skin_type_visual.dart';

/// Profilde cilt tipi, yaş, cinsiyet ve şehir (`GET` / `PATCH /me/profile`).
/// Analiz sihirbazı aynı kaydı yazar; buradan değişiklik yapılınca bir sonraki panel açılışında
/// havaya göre öneriler yeni cilt tipine göre gelir.
class ProfileDetailsCard extends StatefulWidget {
  const ProfileDetailsCard({super.key, required this.theme});

  final RebiTheme theme;

  @override
  State<ProfileDetailsCard> createState() => _ProfileDetailsCardState();
}

class _ProfileDetailsCardState extends State<ProfileDetailsCard> {
  final _age = TextEditingController();
  final _city = TextEditingController();
  String _skinType = '';
  String _gender = '';

  UserProfile? _loaded;
  bool _loading = true;
  bool _loadFailed = false;
  bool _saving = false;
  bool _ageTouched = false;
  (String, String) _msg = ('', '');

  late final String? _uid = context.read<AuthController>().user?.id;

  @override
  void initState() {
    super.initState();
    _age.addListener(() => setState(() => _ageTouched = true));
    _load();
  }

  @override
  void dispose() {
    _age.dispose();
    _city.dispose();
    super.dispose();
  }

  void _apply(UserProfile p) {
    _loaded = p;
    _skinType = UserProfile.skinTypes.contains(p.skinType) ? p.skinType! : '';
    _gender = UserProfile.genders.contains(p.gender) ? p.gender! : '';
    _age.text = p.age?.toString() ?? '';
    _city.text = p.city ?? '';
    _ageTouched = false;
  }

  Future<void> _load() async {
    final uid = _uid;
    if (uid == null || uid == demoUserId) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    UserProfile? profile;
    try {
      profile = await fetchMyProfile(uid);
    } catch (_) {
      profile = null;
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (profile == null) {
        _loadFailed = true;
      } else {
        _apply(profile);
      }
    });
  }

  Future<void> _save() async {
    final uid = _uid;
    final base = _loaded;
    if (uid == null || base == null || _saving) return;
    final i18n = I18n.instance;
    if (isInvalidAge(_age.text)) {
      setState(() => _msg = ('err', i18n.t('mobileProfile.ageInvalid')));
      return;
    }
    final ageText = _age.text.trim();
    final city = _city.text.trim();
    // Yalnızca değişen alanlar gönderilir; sunucu `null`ı "dokunma" sayar.
    final update = ProfileUpdate(
      skinType: _skinType.isNotEmpty && _skinType != base.skinType ? _skinType : null,
      age: ageText.isNotEmpty && int.parse(ageText) != base.age ? int.parse(ageText) : null,
      gender: _gender.isNotEmpty && _gender != base.gender ? _gender : null,
      city: city != (base.city ?? '') ? city : null,
    );
    if (update.isEmpty) {
      setState(() => _msg = ('ok', i18n.t('mobileProfile.nothingChanged')));
      return;
    }
    setState(() {
      _saving = true;
      _msg = ('', '');
    });
    final result = await updateMyProfile(uid, update);
    if (!mounted) return;
    setState(() {
      _saving = false;
      final saved = result.profile;
      if (saved == null) {
        _msg = ('err', result.networkError ? i18n.t('mobileProfile.saveFailed') : (result.error ?? i18n.t('mobileProfile.saveFailed')));
      } else if (!saved.synced) {
        _msg = ('err', i18n.t('mobileProfile.notSynced'));
      } else {
        _apply(saved);
        _msg = ('ok', i18n.t('mobileProfile.saved'));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final theme = widget.theme;
    final pack = Pack(i18n.analyzeWizardPack.cast<String, dynamic>());
    final ageError = _ageTouched && isInvalidAge(_age.text);

    Widget label(String text) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(text, style: tx(14, w: 5, c: Tw.gray700)),
        );

    return RCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Icon(LucideIcons.sparkles, size: 16, color: theme.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(i18n.t('mobileProfile.title'), style: tx(14, w: 7, c: Tw.gray800))),
          ]),
          const SizedBox(height: 8),
          Text(i18n.t('mobileProfile.intro'), style: tx(12, c: Tw.gray500, h: relaxed)),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Center(child: RingSpinner(size: 28, stroke: 3)))
          else if (_loadFailed)
            Row(children: [
              Icon(LucideIcons.wifiOff, size: 16, color: Tw.amber600),
              const SizedBox(width: 8),
              Expanded(child: Text(i18n.t('mobileProfile.loadFailed'), style: tx(12, c: Tw.amber900))),
              TextLink(i18n.t('mobileProfile.retry'), onTap: _load, style: tx(12, w: 6, c: theme.primary)),
            ])
          else if (_loaded == null)
            const SizedBox.shrink()
          else ...[
            label(i18n.t('mobileProfile.skinType')),
            SkinTypeVisual(value: _skinType, onChanged: (v) => setState(() => _skinType = v)),
            const SizedBox(height: 16),
            label(i18n.t('mobileProfile.age')),
            TextField(
              controller: _age,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: 3,
              decoration: inputDecoration(
                hint: i18n.t('mobileProfile.agePlaceholder'),
                borderColor: ageError ? Tw.red500 : Tw.gray200,
              ).copyWith(counterText: ''),
            ),
            if (ageError) ...[
              const SizedBox(height: 6),
              Text(i18n.t('mobileProfile.ageInvalid'), style: tx(12, c: Tw.red600)),
            ],
            const SizedBox(height: 16),
            label(i18n.t('mobileProfile.gender')),
            Row(children: [
              for (final g in UserProfile.genders) ...[
                if (g != UserProfile.genders.first) const SizedBox(width: 6),
                Expanded(
                  child: ChoiceChipBox(
                    label: pack.or('gender.$g', g),
                    selected: _gender == g,
                    radius: 12,
                    center: true,
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 2),
                    onTap: () => setState(() => _gender = g),
                  ),
                ),
              ],
            ]),
            const SizedBox(height: 16),
            label(i18n.t('mobileProfile.city')),
            TextField(
              controller: _city,
              maxLength: 80,
              textCapitalization: TextCapitalization.words,
              decoration: inputDecoration(hint: i18n.t('mobileProfile.cityPlaceholder')).copyWith(counterText: ''),
              onSubmitted: (_) => _save(),
            ),
            if (!_loaded!.synced) ...[
              const SizedBox(height: 12),
              NoticeBox(
                text: i18n.t('mobileProfile.notSynced'),
                bg: Tw.amber50,
                border: Tw.amber200,
                fg: Tw.amber900,
                icon: LucideIcons.info,
                fontSize: 12,
              ),
            ],
            if (_msg.$2.isNotEmpty) ...[
              const SizedBox(height: 12),
              StatusLine(ok: _msg.$1 == 'ok', text: _msg.$2),
            ],
            const SizedBox(height: 12),
            PrimaryButton(
              onPressed: _saving ? null : _save,
              loading: _saving,
              color: theme.primary,
              fontSize: 14,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              label: i18n.t('mobileProfile.save'),
            ),
          ],
        ],
      ),
    );
  }
}
