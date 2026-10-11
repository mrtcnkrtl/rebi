import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../core/i18n.dart';
import '../core/legal_consent.dart';
import '../state/auth_controller.dart';
import '../ui/components/legal_consent_fields.dart';
import '../ui/tw.dart';
import '../ui/widgets/common.dart';

/// Giriş / kayıt (web: `pages/Auth.jsx`).
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.next});

  /// Başarılı girişten sonra gidilecek yol (`?next=`).
  final String next;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _fullName = TextEditingController();
  String _mode = 'login';
  bool _showPassword = false;
  bool _loading = false;
  String _error = '';
  String _info = '';
  bool _kvkk = false;
  bool _riza = false;
  bool _location = false;
  bool _photo = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _fullName.dispose();
    super.dispose();
  }

  bool get _en => I18n.instance.lang == 'en';

  /// Tarayıcının `required` / `type=email` / `minLength` uyarılarının karşılığı.
  String? _required(String? v) =>
      (v ?? '').trim().isEmpty ? (_en ? 'Please fill out this field.' : 'Lütfen bu alanı doldurun.') : null;

  String? _emailValidator(String? v) {
    final r = _required(v);
    if (r != null) return r;
    final ok = RegExp(r'^[^@\s]+@[^@\s]+$').hasMatch(v!.trim());
    return ok ? null : (_en ? 'Please enter a valid email address.' : 'Lütfen geçerli bir e-posta adresi girin.');
  }

  String? _passwordValidator(String? v) {
    if ((v ?? '').isEmpty) return _required(v);
    if (v!.length < 6) {
      return _en
          ? 'Please use at least 6 characters (you are currently using ${v.length}).'
          : 'Lütfen en az 6 karakter kullanın (şu anda ${v.length} karakter kullanıyorsunuz).';
    }
    return null;
  }

  String _friendlyError(String raw, {required bool network}) {
    final lower = raw.toLowerCase();
    if (network) {
      return 'Sunucuya bağlanılamadı. Kontrol et: internet / VPN bağlantın açık mı; '
          'uygulama doğru Supabase projesine (SUPABASE_URL ve SUPABASE_ANON_KEY) bağlanacak şekilde mi derlendi?';
    }
    if (lower.contains('rate limit') ||
        lower.contains('too many') ||
        lower.contains('exceeded') ||
        lower.contains('quota') ||
        lower.contains('429')) {
      return 'Kısa süre içinde çok fazla deneme yapıldığı için geçici olarak sınır aşıldı. '
          '1-2 dakika bekleyip tekrar dener misin? Devam ederse VPN / kurumsal ağ kullanıyorsan kapatıp dene.';
    }
    return raw.isEmpty ? 'Bir hata oluştu' : raw;
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _error = '';
      _info = '';
    });
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!_kvkk || !_riza) {
      setState(() => _error = I18n.instance.t('auth.legalRequired'));
      return;
    }
    final auth = context.read<AuthController>();
    final router = GoRouter.of(context);
    final consent = ConsentPermissions(ai: true, location: _location, photo: _photo);
    setState(() => _loading = true);
    auth.setAuthFlowInProgress(true);
    try {
      if (_mode == 'login') {
        final r = await auth.signIn(_email.text.trim(), _password.text);
        if (r.error != null) {
          _showError(r.error!, network: r.networkError);
          return;
        }
        if (!await _recordConsent(auth, r.user?.id, consent)) return;
        auth.setAuthFlowInProgress(false);
        router.go(widget.next);
      } else {
        final r = await auth.signUp(_email.text.trim(), _password.text, _fullName.text);
        if (r.error != null) {
          _showError(r.error!, network: r.networkError);
          return;
        }
        if (r.needsEmailConfirmation) {
          if (mounted) {
            setState(() {
              _error = '';
              _mode = 'login';
              _info = 'Kayıt alındı. E-postandaki onay linkine tıkladıktan sonra giriş yapabilirsin. '
                  'Posta gelmediyse spam klasörüne bak.';
            });
          }
          return;
        }
        if (!await _recordConsent(auth, r.user?.id, consent)) return;
        auth.setAuthFlowInProgress(false);
        router.go(widget.next);
      }
    } finally {
      auth.setAuthFlowInProgress(false);
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Rıza kaydı başarısızsa oturumu kapatır (web ile aynı); hatayı ekranda gösterir.
  Future<bool> _recordConsent(AuthController auth, String? userId, ConsentPermissions consent) async {
    try {
      await recordLegalConsent(userId, consent);
      return true;
    } catch (e) {
      await auth.signOut();
      _showError(e.toString().replaceFirst('Exception: ', ''), network: false);
      return false;
    }
  }

  void _showError(String raw, {required bool network}) {
    if (!mounted) return;
    setState(() => _error = _friendlyError(raw, network: network));
  }

  void _switchMode(String mode) => setState(() {
        _mode = mode;
        _error = '';
        _info = '';
      });

  Widget _label(String text) =>
      Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(text, style: tx(14, w: 5, c: Tw.gray700)));

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final login = _mode == 'login';
    final canSubmit = !_loading && _kvkk && _riza;

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Tw.teal50, Colors.white]),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 48, 16, 48),
        child: CenteredBox(
          maxWidth: 448,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Tw.teal500, Tw.teal600],
                    ),
                    boxShadow: [BoxShadow(color: Tw.teal500.withValues(alpha: .2), blurRadius: 25, offset: const Offset(0, 12))],
                  ),
                  child: const Icon(LucideIcons.leaf, size: 32, color: Colors.white),
                ),
              ),
              const SizedBox(height: 16),
              Text(login ? i18n.t('auth.welcome') : i18n.t('auth.createAccount'),
                  textAlign: TextAlign.center, style: tx(24, w: 7)),
              const SizedBox(height: 4),
              Text(login ? i18n.t('auth.loginToAccount') : i18n.t('auth.createFreeAccount'),
                  textAlign: TextAlign.center, style: tx(16, c: Tw.gray500)),
              const SizedBox(height: 32),
              RCard(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_info.isNotEmpty) ...[
                        NoticeBox(
                          text: _info,
                          bg: Tw.teal50,
                          border: Tw.teal100,
                          fg: Tw.teal900,
                          icon: LucideIcons.info,
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (_error.isNotEmpty) ...[
                        NoticeBox(
                          text: _error,
                          bg: Tw.red50,
                          border: Tw.red50,
                          fg: Tw.red600,
                          icon: LucideIcons.circleAlert,
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (!login) ...[
                        _label(i18n.t('auth.fullName')),
                        TextFormField(
                          controller: _fullName,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.name],
                          validator: _required,
                          decoration: inputDecoration(hint: 'Adın Soyadın', prefixIcon: LucideIcons.user),
                        ),
                        const SizedBox(height: 16),
                      ],
                      _label(i18n.t('auth.email')),
                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        autofillHints: const [AutofillHints.email],
                        validator: _emailValidator,
                        decoration: inputDecoration(hint: 'ornek@email.com', prefixIcon: LucideIcons.mail),
                      ),
                      const SizedBox(height: 16),
                      _label(i18n.t('auth.password')),
                      TextFormField(
                        controller: _password,
                        obscureText: !_showPassword,
                        autocorrect: false,
                        enableSuggestions: false,
                        autofillHints: [login ? AutofillHints.password : AutofillHints.newPassword],
                        validator: _passwordValidator,
                        onFieldSubmitted: (_) {
                          if (canSubmit) _submit();
                        },
                        decoration: inputDecoration(
                          hint: '••••••••',
                          prefixIcon: LucideIcons.lock,
                          suffix: IconButton(
                            onPressed: () => setState(() => _showPassword = !_showPassword),
                            icon: Icon(_showPassword ? LucideIcons.eyeOff : LucideIcons.eye, size: 20, color: Tw.gray400),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      LegalConsentFields(
                        kvkk: _kvkk,
                        riza: _riza,
                        location: _location,
                        photo: _photo,
                        onKvkk: (v) => setState(() => _kvkk = v),
                        onRiza: (v) => setState(() => _riza = v),
                        onLocation: (v) => setState(() => _location = v),
                        onPhoto: (v) => setState(() => _photo = v),
                      ),
                      const SizedBox(height: 24),
                      PrimaryButton(
                        onPressed: canSubmit ? _submit : null,
                        loading: _loading,
                        label: login ? i18n.t('auth.login') : i18n.t('auth.signup'),
                        trailingIcon: LucideIcons.arrowRight,
                      ),
                      const SizedBox(height: 24),
                      Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(login ? i18n.t('auth.haveNoAccount') : i18n.t('auth.haveAccount'),
                              style: tx(14, c: Tw.gray500)),
                          const SizedBox(width: 4),
                          TextLink(
                            login ? i18n.t('auth.signup') : i18n.t('auth.login'),
                            onTap: () => _switchMode(login ? 'signup' : 'login'),
                            style: tx(14, w: 6, c: Tw.teal600),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
