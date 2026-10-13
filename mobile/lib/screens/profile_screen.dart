import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/api.dart';
import '../core/checkin_stats.dart';
import '../core/demo_user.dart';
import '../core/i18n.dart';
import '../core/privacy_preferences.dart';
import '../core/privacy_storage.dart';
import '../core/routine_tracking.dart';
import '../core/subscription.dart';
import '../core/user_profile.dart';
import '../state/auth_controller.dart';
import '../state/theme_controller.dart';
import '../ui/components/notification_widgets.dart';
import '../ui/components/profile_details_card.dart';
import '../ui/tw.dart';
import '../ui/widgets/common.dart';

const accountDeletePhrase = 'HESABIMI_SIL';

String _formatJoined(String? iso) {
  if (iso == null || iso.isEmpty) return '—';
  try {
    return DateFormat.yMMMMd('tr').format(DateTime.parse(iso).toLocal());
  } catch (_) {
    return '—';
  }
}

final _imageExt = RegExp(r'\.(jpe?g|png|webp|gif|heic|avif)$', caseSensitive: false);

class _Photo {
  const _Photo(this.name, this.path, this.url, this.createdAt);

  final String name;
  final String path;
  final String url;
  final String? createdAt;
}

/// Profil (web: `pages/Profile.jsx`).
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _displayName = TextEditingController();
  (String, String) _profileMsg = ('', '');
  bool _profileSaving = false;

  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();
  (String, String) _pwdMsg = ('', '');
  bool _pwdSaving = false;

  List<_Photo> _photos = [];
  bool _photosLoading = true;
  String _photosError = '';

  final _deletePhrase = TextEditingController();
  bool _deleteBusy = false;
  (String, String) _deleteMsg = ('', '');

  bool _locationPermission = false;
  bool _photoPermission = false;
  bool _privacySaving = false;
  String _privacyMsg = '';

  late final TapGestureRecognizer _quickUploadTap = TapGestureRecognizer()
    ..onTap = () => context.push('/dashboard/analyze?photo=1');
  late final TapGestureRecognizer _fullAnalyzeTap = TapGestureRecognizer()..onTap = () => context.go('/dashboard/analyze');

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
    _newPassword.addListener(() => setState(() {}));
    _deletePhrase.addListener(() => setState(() {}));
    final uid = context.read<AuthController>().user?.id;
    if (uid != null && uid != demoUserId) {
      getPrivacyPreferences(uid).then((data) {
        if (!mounted) return;
        setState(() {
          _locationPermission = data['location_processing_allowed'] == true;
          _photoPermission = data['photo_processing_allowed'] == true;
        });
      }).catchError((_) {
        if (mounted) setState(() => _privacyMsg = 'Gizlilik tercihleri yüklenemedi.');
      });
    }
    // Eski kayıtlarda acceptedAt yoktu; profil açılınca bir kez tamamlanır.
    if (uid != null && isRoutineTrackingAccepted(uid)) {
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
    _loadPhotos();
  }

  @override
  void dispose() {
    _auth.removeListener(_syncName);
    _displayName.dispose();
    _newPassword.dispose();
    _confirmPassword.dispose();
    _deletePhrase.dispose();
    _quickUploadTap.dispose();
    _fullAnalyzeTap.dispose();
    super.dispose();
  }

  Future<void> _loadPhotos() async {
    final client = supabase;
    final uid = context.read<AuthController>().user?.id;
    if (client == null || uid == null) {
      setState(() {
        _photos = [];
        _photosLoading = false;
      });
      return;
    }
    setState(() {
      _photosLoading = true;
      _photosError = '';
    });
    try {
      final bucket = client.storage.from('skin-photos');
      List<FileObject> list;
      try {
        list = await bucket.list(
          path: uid,
          searchOptions: const SearchOptions(limit: 100, offset: 0, sortBy: SortBy(column: 'created_at', order: 'desc')),
        );
      } catch (_) {
        list = await bucket.list(path: uid, searchOptions: const SearchOptions(limit: 100, offset: 0));
      }
      final files = list.where((f) => f.name.isNotEmpty && !f.name.startsWith('.') && _imageExt.hasMatch(f.name));
      final withUrls = await Future.wait(files.map((f) async {
        final path = '$uid/${f.name}';
        var url = '';
        try {
          url = await bucket.createSignedUrl(path, 900);
        } catch (_) {
          url = '';
        }
        return _Photo(f.name, path, url, f.createdAt);
      }));
      int ts(_Photo p) => p.createdAt == null ? 0 : (DateTime.tryParse(p.createdAt!)?.millisecondsSinceEpoch ?? 0);
      final sorted = withUrls.toList()
        ..sort((a, b) {
          final d = ts(b) - ts(a);
          return d != 0 ? d : b.name.compareTo(a.name);
        });
      if (mounted) setState(() => _photos = sorted);
    } catch (e) {
      if (mounted) {
        setState(() {
          _photosError = e is StorageException ? e.message : 'Fotoğraflar yüklenemedi.';
          _photos = [];
        });
      }
    } finally {
      if (mounted) setState(() => _photosLoading = false);
    }
  }

  Future<void> _saveProfile() async {
    final client = supabase;
    if (client == null) return;
    final auth = context.read<AuthController>();
    setState(() {
      _profileMsg = ('', '');
      _profileSaving = true;
    });
    try {
      final trimmed = _displayName.text.trim();
      await client.auth.updateUser(UserAttributes(data: {'full_name': trimmed.isEmpty ? null : trimmed}));
      await auth.refreshUser();
      // Sunucudaki profil kaydındaki ad da güncellensin (en iyi çaba; ad zaten oturumda güncellendi).
      final uid = auth.user?.id;
      if (uid != null && uid != demoUserId && trimmed.isNotEmpty) {
        try {
          await updateMyProfile(uid, ProfileUpdate(fullName: trimmed));
        } catch (_) {
          /* çevrimdışı: bir sonraki analizde sunucu adı yine yazar */
        }
      }
      if (mounted) setState(() => _profileMsg = ('ok', 'Bilgilerin güncellendi.'));
    } on AuthException catch (e) {
      if (mounted) setState(() => _profileMsg = ('err', e.message.isEmpty ? 'Kaydedilemedi.' : e.message));
    } catch (_) {
      if (mounted) setState(() => _profileMsg = ('err', 'Kaydedilemedi.'));
    } finally {
      if (mounted) setState(() => _profileSaving = false);
    }
  }

  Future<void> _changePassword() async {
    setState(() => _pwdMsg = ('', ''));
    if (_newPassword.text.length < 6) {
      setState(() => _pwdMsg = ('err', 'Şifre en az 6 karakter olmalı.'));
      return;
    }
    if (_newPassword.text != _confirmPassword.text) {
      setState(() => _pwdMsg = ('err', 'Şifreler eşleşmiyor.'));
      return;
    }
    final client = supabase;
    if (client == null) return;
    setState(() => _pwdSaving = true);
    try {
      await client.auth.updateUser(UserAttributes(password: _newPassword.text));
      _newPassword.clear();
      _confirmPassword.clear();
      if (mounted) setState(() => _pwdMsg = ('ok', 'Şifren güncellendi.'));
    } on AuthException catch (e) {
      if (mounted) setState(() => _pwdMsg = ('err', e.message.isEmpty ? 'Şifre değiştirilemedi.' : e.message));
    } catch (_) {
      if (mounted) setState(() => _pwdMsg = ('err', 'Şifre değiştirilemedi.'));
    } finally {
      if (mounted) setState(() => _pwdSaving = false);
    }
  }

  Future<void> _deleteAccount() async {
    final auth = context.read<AuthController>();
    final router = GoRouter.of(context);
    final uid = auth.user?.id;
    setState(() => _deleteMsg = ('', ''));
    if (uid == null) return;
    if (_deletePhrase.text.trim() != accountDeletePhrase) {
      setState(() => _deleteMsg = ('err', 'Kalıcı silmek için kutuya tam olarak $accountDeletePhrase yazmalısın.'));
      return;
    }
    setState(() => _deleteBusy = true);
    try {
      final res = await apiPost('/account/delete', {'user_id': uid, 'confirm_text': accountDeletePhrase});
      if (!res.ok) throw Exception(detailOr(res.data, 'İstek başarısız'));
      _deletePhrase.clear();
      await clearUserLocalData(uid);
      await auth.signOut();
      router.go('/');
    } catch (e) {
      final m = e.toString().replaceFirst('Exception: ', '');
      if (mounted) setState(() => _deleteMsg = ('err', m.isEmpty ? 'Hesap silinemedi.' : m));
    } finally {
      if (mounted) setState(() => _deleteBusy = false);
    }
  }

  Future<void> _savePrivacy() async {
    final uid = context.read<AuthController>().user?.id;
    if (uid == null) return;
    setState(() {
      _privacySaving = true;
      _privacyMsg = '';
    });
    try {
      await updatePrivacyPreferences(uid, location: _locationPermission, photo: _photoPermission);
      if (mounted) setState(() => _privacyMsg = 'Gizlilik tercihlerin kaydedildi.');
    } catch (e) {
      final m = e.toString().replaceFirst('Exception: ', '');
      if (mounted) setState(() => _privacyMsg = m.isEmpty ? 'Gizlilik tercihleri kaydedilemedi.' : m);
    } finally {
      if (mounted) setState(() => _privacySaving = false);
    }
  }

  Widget _sectionTitle(IconData icon, Color color, String text, {Color? textColor}) => Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: tx(14, w: 7, c: textColor ?? Tw.gray800))),
        ],
      );

  Widget _checkboxRow(bool value, ValueChanged<bool> onChanged, String label) => InkWell(
        onTap: () => onChanged(!value),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: Checkbox(
                value: value,
                onChanged: (v) => onChanged(v ?? false),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: tx(14, c: Tw.gray700))),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final theme = context.watch<ThemeController>().theme;
    final user = context.watch<AuthController>().user;
    final uid = user?.id;
    final plus = userHasRebiPlus(user);
    final stats = uid != null ? getProfileRoutineStats(uid) : null;
    const gap = SizedBox(height: 24);

    if (supabase == null) {
      return ThemedBackground(
        theme: theme,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('Supabase yapılandırılmamış; profil ve fotoğraflar kullanılamıyor.',
                textAlign: TextAlign.center, style: tx(14, c: Tw.gray600)),
          ),
        ),
      );
    }

    final linkStyle = tx(14, w: 6, c: Tw.sky950.withValues(alpha: .9)).copyWith(decoration: TextDecoration.underline);

    return ThemedPage(
      theme: theme,
      padding: const EdgeInsets.fromLTRB(16, 32, 16, 48),
      children: [
        Row(
          children: [
            GradientIconBox(icon: LucideIcons.user, from: theme.accent, to: theme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(i18n.t('profile.title'), style: tx(20, w: 7)),
                  Text(i18n.t('profile.subtitle'), style: tx(14, c: Tw.gray500)),
                ],
              ),
            ),
          ],
        ),
        gap,
        RCard(
          padding: const EdgeInsets.all(16),
          borderColor: theme.primaryLight,
          color: Color.alphaBlend(Tw.sky50.withValues(alpha: .6), Tw.surface),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(padding: EdgeInsets.only(top: 2), child: Icon(LucideIcons.info, size: 20, color: Tw.sky700)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(text: 'Rebi', style: tx(14, w: 7, c: Tw.sky950)),
                        const TextSpan(text: ' verilerini güvenle saklar. Yeni cilt fotoğrafını '),
                        TextSpan(text: i18n.t('profile.quickUpload'), style: linkStyle, recognizer: _quickUploadTap),
                        const TextSpan(text: ' ile ekleyebilir veya tam '),
                        TextSpan(text: i18n.t('profile.fullAnalyze'), style: linkStyle, recognizer: _fullAnalyzeTap),
                        const TextSpan(text: 'na gidebilirsin. Aşağıda yüklediğin görseller listelenir.'),
                      ]),
                      style: tx(14, c: Tw.sky950.withValues(alpha: .9), h: relaxed),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Şifre değişikliği e-posta ile giriş yaptığın hesaplar içindir. Sosyal giriş kullanıyorsan şifre bu ekrandan değişmez.',
                      style: tx(12, c: Tw.sky900.withValues(alpha: .8)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        gap,
        RCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionTitle(LucideIcons.shield, theme.primary, i18n.t('profile.accountSummary')),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(LucideIcons.mail, size: 16, color: Tw.gray400),
                  const SizedBox(width: 8),
                  Expanded(child: Text(user?.email ?? '—', style: tx(14, c: Tw.gray700))),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(LucideIcons.calendar, size: 16, color: Tw.gray400),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(i18n.t('profile.membership', {'date': _formatJoined(user?.createdAt)}),
                        style: tx(14, c: Tw.gray700)),
                  ),
                ],
              ),
              if (plus) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: Tw.amber50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Tw.amber200),
                    ),
                    child: Text(i18n.t('profile.plusActive'), style: tx(12, w: 6, c: Tw.amber800)),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (stats?.hasAcceptedRoutine ?? false) ...[gap, _statsCard(i18n, theme, stats!)],
        gap,
        RCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionTitle(LucideIcons.user, theme.primary, 'Görünen ad'),
              const SizedBox(height: 12),
              TextField(
                controller: _displayName,
                maxLength: 120,
                textCapitalization: TextCapitalization.words,
                decoration: inputDecoration(hint: 'Adın soyadın').copyWith(counterText: ''),
                onSubmitted: (_) => _saveProfile(),
              ),
              if (_profileMsg.$2.isNotEmpty) ...[
                const SizedBox(height: 12),
                StatusLine(ok: _profileMsg.$1 == 'ok', text: _profileMsg.$2),
              ],
              const SizedBox(height: 12),
              PrimaryButton(
                onPressed: _profileSaving ? null : _saveProfile,
                loading: _profileSaving,
                color: theme.primary,
                fontSize: 14,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                label: 'Bilgileri kaydet',
              ),
            ],
          ),
        ),
        gap,
        RCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionTitle(LucideIcons.lock, theme.primary, 'Şifre değiştir'),
              const SizedBox(height: 12),
              TextField(
                controller: _newPassword,
                obscureText: true,
                autofillHints: const [AutofillHints.newPassword],
                decoration: inputDecoration(hint: 'Yeni şifre (en az 6 karakter)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _confirmPassword,
                obscureText: true,
                autofillHints: const [AutofillHints.newPassword],
                decoration: inputDecoration(hint: 'Yeni şifre tekrar'),
                onSubmitted: (_) => _changePassword(),
              ),
              if (_pwdMsg.$2.isNotEmpty) ...[
                const SizedBox(height: 12),
                StatusLine(ok: _pwdMsg.$1 == 'ok', text: _pwdMsg.$2),
              ],
              const SizedBox(height: 12),
              SecondaryButton(
                onPressed: _pwdSaving || _newPassword.text.isEmpty ? null : _changePassword,
                loading: _pwdSaving,
                borderColor: theme.primaryLight,
                textColor: theme.primary,
                fontSize: 14,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                label: 'Şifreyi güncelle',
              ),
            ],
          ),
        ),
        gap,
        RCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionTitle(LucideIcons.shield, theme.primary, i18n.t('legal.kvkkTitle')),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                children: [
                  TextLink(i18n.t('legal.kvkkTitle'), onTap: () => context.push('/kvkk'), style: tx(12, w: 6, c: Tw.teal700)),
                  TextLink(i18n.t('legal.rizaTitle'), onTap: () => context.push('/riza'), style: tx(12, w: 6, c: Tw.teal700)),
                ],
              ),
            ],
          ),
        ),
        if (uid != null && uid != demoUserId) ...[
          gap,
          ProfileDetailsCard(theme: theme),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: TextLink(
              i18n.t('mobileProfile.historyLink'),
              onTap: () => context.push('/dashboard/history'),
              style: tx(14, w: 6, c: theme.primary),
            ),
          ),
          gap,
          NotificationSettingsCard(theme: theme),
          gap,
          ReminderSettingsLink(theme: theme),
          gap,
          RCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _sectionTitle(LucideIcons.shield, theme.primary, 'Gizlilik izinleri'),
                const SizedBox(height: 12),
                Text(
                  'Rutin ve sohbet için yapay zekâ işlemesi A3 Biyoteknoloji tarafından yapılır; ayrıntı KVKK ve açık rıza '
                  'metinlerindedir. Konum ve fotoğraf izinlerini istediğin zaman değiştirebilirsin.',
                  style: tx(12, c: Tw.gray500),
                ),
                const SizedBox(height: 12),
                const AiDisclaimer(),
                const SizedBox(height: 12),
                _checkboxRow(_locationPermission, (v) => setState(() => _locationPermission = v),
                    'Hava/UV için kesin konum aktarımı'),
                const SizedBox(height: 12),
                _checkboxRow(_photoPermission, (v) => setState(() => _photoPermission = v),
                    'Private alanda cilt fotoğrafı saklama'),
                if (_privacyMsg.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(_privacyMsg, style: tx(12, c: Tw.gray600)),
                ],
                const SizedBox(height: 12),
                SecondaryButton(
                  onPressed: _privacySaving ? null : _savePrivacy,
                  loading: _privacySaving,
                  fontSize: 14,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                  label: 'İzinleri kaydet',
                ),
              ],
            ),
          ),
          gap,
          _deleteCard(),
        ],
        gap,
        _photosCard(i18n, theme),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextLink('Rebi Plus', onTap: () => context.go('/dashboard/subscribe'), style: tx(12, w: 6, c: theme.primary)),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('·', style: tx(12, c: Tw.gray300))),
            TextLink('Temalar', onTap: () => context.go('/dashboard/themes'), style: tx(12, c: Tw.gray600)),
          ],
        ),
      ],
    );
  }

  Widget _statsCard(I18n i18n, RebiTheme theme, ProfileRoutineStats s) {
    Widget tile(String value, String label, Color color) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Tw.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Tw.gray100),
            ),
            child: Column(
              children: [
                Text(value, style: tx(24, w: 7, c: color).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                const SizedBox(height: 2),
                Text(label, textAlign: TextAlign.center, style: tx(10, w: 5, c: Tw.gray500)),
              ],
            ),
          ),
        );

    Widget smallLink(String label, VoidCallback onTap, Color border, Color color) => Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: border)),
              child: Text(label, style: tx(12, w: 6, c: color)),
            ),
          ),
        );

    return RCard(
      padding: const EdgeInsets.all(16),
      borderColor: theme.primaryLight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle(LucideIcons.target, theme.primary, i18n.t('profile.routineSummaryTitle')),
          const SizedBox(height: 12),
          Text(
            'Günlük check-in yaptıkça seri ve sadakat burada güncellenir. Hedef: üst üste $routineStreakGoalDays gün check-in alışkanlığı.',
            style: tx(11, c: Tw.gray500, h: relaxed),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              tile('${s.streak}', i18n.t('profile.streak'), theme.primary),
              const SizedBox(width: 8),
              tile('${s.totalCheckIns}', i18n.t('profile.totalCheckins'), Tw.gray800),
            ],
          ),
          if (s.appliedRatePercent != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Tw.gray50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Tw.gray100),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.clipboardCheck, size: 16, color: Tw.gray500),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(i18n.t('profile.adherence'), style: tx(12, w: 6, c: Tw.gray800)),
                        Text.rich(
                          TextSpan(children: [
                            const TextSpan(text: 'Check-in kayıtlarında rutini uyguladım dediğin günler: '),
                            TextSpan(text: '${s.appliedRatePercent}%', style: tx(11, w: 7, c: Tw.gray800)),
                          ]),
                          style: tx(11, c: Tw.gray500),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Hedef seri ($routineStreakGoalDays gün)', style: tx(10, c: Tw.gray500)),
              Text('${s.goalProgress}%', style: tx(10, c: Tw.gray500)),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: Container(
              height: 8,
              color: Tw.gray100,
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: s.goalProgress / 100,
                child: Container(decoration: BoxDecoration(color: theme.primary, borderRadius: BorderRadius.circular(999))),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (s.daysSinceAccept != null)
            Text.rich(
              TextSpan(children: [
                const TextSpan(text: 'Rutin yolculuğun: '),
                TextSpan(text: '${s.daysSinceAccept} gün', style: tx(11, w: 7, c: Tw.gray800)),
                const TextSpan(text: ' (kabul tarihinden)'),
              ]),
              textAlign: TextAlign.center,
              style: tx(11, c: Tw.gray500),
            )
          else
            Text('Rutin kabul tarihi bir sonraki güncellemeden itibaren otomatik kaydedilir.',
                textAlign: TextAlign.center, style: tx(11, c: Tw.gray400)),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              smallLink('Check-in yap', () => context.go('/dashboard/checkin'), theme.primaryLight, theme.primary),
              smallLink('Fotoğraf ekle', () => context.push('/dashboard/analyze?photo=1'), Tw.gray200, Tw.gray700),
            ],
          ),
        ],
      ),
    );
  }

  Widget _deleteCard() {
    final phraseOk = _deletePhrase.text.trim() == accountDeletePhrase;
    return RCard(
      padding: const EdgeInsets.all(16),
      borderColor: Tw.red200,
      color: Color.alphaBlend(Tw.red50.withValues(alpha: .4), Tw.surface),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle(LucideIcons.trash2, Tw.red900, 'Hesabı kalıcı olarak sil', textColor: Tw.red900),
          const SizedBox(height: 12),
          Text(
            'Profil, rutinler, günlük kayıtlar ve analiz verilerin veritabanından silinir. Cilt fotoğrafların depodan kaldırılır. '
            'Bu işlem geri alınamaz; Rebi Plus veya başka üyelik bilgisi ayrıca faturalandırma sisteminde kalıyorsa oradan da '
            'iptal etmen gerekebilir.',
            style: tx(12, c: Tw.red900.withValues(alpha: .85), h: relaxed),
          ),
          const SizedBox(height: 12),
          Text.rich(
            TextSpan(children: [
              const TextSpan(text: 'Onay için tam yaz: '),
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(color: Tw.surface.withValues(alpha: .8), borderRadius: BorderRadius.circular(4)),
                  child: Text(accountDeletePhrase, style: tx(12, w: 6, c: Tw.red950).copyWith(fontFamily: 'monospace')),
                ),
              ),
            ]),
            style: tx(12, w: 6, c: Tw.red950.withValues(alpha: .9)),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _deletePhrase,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.characters,
            style: tx(14).copyWith(fontFamily: 'monospace'),
            decoration: inputDecoration(hint: accountDeletePhrase),
          ),
          if (_deleteMsg.$2.isNotEmpty) ...[
            const SizedBox(height: 12),
            StatusLine(ok: _deleteMsg.$1 == 'ok', text: _deleteMsg.$2, errorColor: Tw.red700),
          ],
          const SizedBox(height: 12),
          Opacity(
            opacity: _deleteBusy || !phraseOk ? .5 : 1,
            child: Material(
              color: Tw.surface,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _deleteBusy || !phraseOk ? null : _deleteAccount,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Tw.red600, width: 2),
                  ),
                  child: Center(
                    child: _deleteBusy
                        ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Tw.red700))
                        : Text('Hesabımı kalıcı sil', style: tx(14, w: 6, c: Tw.red700)),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _photosCard(I18n i18n, RebiTheme theme) {
    Widget body;
    if (_photosLoading) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(child: SizedBox(width: 32, height: 32, child: CircularProgressIndicator(color: theme.primary))),
      );
    } else if (_photosError.isNotEmpty) {
      body = Row(
        children: [
          Icon(LucideIcons.circleAlert, size: 16, color: Tw.red600),
          const SizedBox(width: 8),
          Expanded(child: Text(_photosError, style: tx(14, c: Tw.red600))),
        ],
      );
    } else if (_photos.isEmpty) {
      body = RCard(
        dashed: true,
        borderColor: Tw.gray200,
        color: Tw.surface.withValues(alpha: .5),
        radius: 16,
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
        child: Column(
          children: [
            Icon(LucideIcons.image, size: 40, color: Tw.gray300),
            const SizedBox(height: 8),
            Text('Henüz kayıtlı fotoğraf yok.', style: tx(14, c: Tw.gray600)),
            const SizedBox(height: 12),
            TextLink(i18n.t('analyze.quickPhotoUpload'),
                onTap: () => context.push('/dashboard/analyze?photo=1'), style: tx(14, w: 6, c: theme.primary)),
          ],
        ),
      );
    } else {
      body = Column(
        children: [
          for (final p in _photos) ...[
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Tw.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Tw.gray100),
                boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 2, offset: Offset(0, 1))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (p.url.isNotEmpty)
                    Image.network(
                      p.url,
                      height: 192,
                      fit: BoxFit.cover,
                      errorBuilder: (c, e, s) => Container(height: 192, color: Tw.gray100),
                      loadingBuilder: (c, child, prog) => prog == null ? child : Container(height: 192, color: Tw.gray100),
                    )
                  else
                    SizedBox(
                      height: 128,
                      child: Center(child: Text('Önizleme yok', style: tx(14, c: Tw.gray400))),
                    ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(border: Border(top: BorderSide(color: Tw.gray50))),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(p.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: tx(12, c: Tw.gray500).copyWith(fontFamily: 'monospace')),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          p.createdAt != null
                              ? DateFormat('dd.MM.yyyy HH:mm:ss').format(DateTime.parse(p.createdAt!).toLocal())
                              : '—',
                          style: tx(12, c: Tw.gray500),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
        ],
      );
    }

    return RCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: _sectionTitle(LucideIcons.camera, theme.primary, i18n.t('profile.photosTitle'))),
              TextLink(i18n.t('profile.refresh'), onTap: _loadPhotos, style: tx(12, w: 6, c: theme.primary)),
            ],
          ),
          const SizedBox(height: 12),
          Text('Analizde yüklediğin görseller burada tarih sırasıyla listelenir (sunucudaki dosya tarihine göre).',
              style: tx(12, c: Tw.gray500)),
          const SizedBox(height: 12),
          body,
        ],
      ),
    );
  }
}
