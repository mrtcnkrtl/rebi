import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../core/api.dart' show isNetworkError;
import '../core/auth_errors.dart';
import '../core/i18n.dart';
import '../core/legal_consent.dart';
import '../state/auth_controller.dart';
import '../ui/brand/brand_button.dart';
import '../ui/brand/brand_mark.dart';
import '../ui/brand/motion.dart';
import '../ui/brand/palette.dart';
import '../ui/brand/public_top_bar.dart';
import '../ui/components/legal_consent_fields.dart';
import '../ui/tw.dart';
import '../ui/widgets/common.dart';

/// Giriş / kayıt / parola sıfırlama (web: `pages/Auth.jsx`; sıfırlama yalnızca mobilde).
///
/// Kipler: `login`, `signup`, `forgot` (sıfırlama bağlantısı iste) ve `reset` (bağlantıyla gelince yeni parola;
/// kip `AuthController.recoveryPending` ile belirlenir, kullanıcı seçemez).
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.next, this.startInSignup = false});

  /// Başarılı girişten sonra gidilecek yol (`?next=`).
  final String next;

  /// Karşılamadaki ana eylemden gelindiğinde kayıt modunda açılır (`?mode=signup`).
  final bool startInSignup;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _password2 = TextEditingController();
  final _fullName = TextEditingController();
  late String _mode = widget.startInSignup ? 'signup' : 'login';
  bool _showPassword = false;
  bool _loading = false;
  bool _resending = false;

  /// Onay e-postasını yeniden gönderme bağlantısı görünsün mü (onaysız giriş, kayıt sonrası, geçersiz bağlantı).
  bool _canResend = false;
  String _error = '';
  String _info = '';
  bool _kvkk = false;
  bool _riza = false;
  bool _location = false;
  bool _photo = false;
  int _shake = 0;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _password2.dispose();
    _fullName.dispose();
    super.dispose();
  }

  bool get _en => I18n.instance.lang == 'en';

  String _t(String key) => I18n.instance.t(key);

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

  String? _confirmValidator(String? v) {
    if ((v ?? '').isEmpty) return _required(v);
    return v == _password.text ? null : _t('mobileAuth.resetMismatch');
  }

  /// Supabase hata türünü kullanıcının dilinde bir cümleye çevirir; tanınmayan hatada sunucunun mesajı gösterilir.
  String _errorText(AuthErrorKind kind, String raw) {
    switch (kind) {
      case AuthErrorKind.notConfigured:
        return 'Giriş şu an yapılamıyor: uygulama Supabase ayarları olmadan başlatılmış. '
            'Geliştirme sırasında "main.dart (dev)" ayarıyla ya da '
            '`flutter run --dart-define-from-file=env/dev.json` ile çalıştır.';
      case AuthErrorKind.network:
        return _t('mobileAuth.errNetwork');
      case AuthErrorKind.invalidCredentials:
        return _t('mobileAuth.errInvalidCredentials');
      case AuthErrorKind.emailNotConfirmed:
        return _t('mobileAuth.errEmailNotConfirmed');
      case AuthErrorKind.alreadyRegistered:
        return _t('mobileAuth.errAlreadyRegistered');
      case AuthErrorKind.weakPassword:
        return _t('mobileAuth.errWeakPassword');
      case AuthErrorKind.samePassword:
        return _t('mobileAuth.errSamePassword');
      case AuthErrorKind.rateLimited:
        return _t('mobileAuth.errRateLimited');
      case AuthErrorKind.emailSendFailed:
        return _t('mobileAuth.errEmailSend');
      case AuthErrorKind.linkInvalid:
        return _t('mobileAuth.errLinkInvalid');
      case AuthErrorKind.other:
        return raw.isEmpty ? (_en ? 'Something went wrong.' : 'Bir hata oluştu') : raw;
    }
  }

  void _showAuthError(String raw, AuthErrorKind kind, {bool offerResend = false}) {
    if (!mounted) return;
    setState(() {
      _error = _errorText(kind, raw);
      _info = '';
      _canResend = offerResend;
      _shake++;
    });
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _error = '';
      _info = '';
      _canResend = false;
    });
    if (!(_formKey.currentState?.validate() ?? false)) {
      setState(() => _shake++);
      return;
    }
    final auth = context.read<AuthController>();
    final router = GoRouter.of(context);
    if (auth.recoveryPending) return _submitReset(auth, router);
    if (_mode == 'forgot') return _submitForgot(auth);
    if (!_kvkk || !_riza) {
      setState(() => _error = I18n.instance.t('auth.legalRequired'));
      return;
    }
    final consent = ConsentPermissions(ai: true, location: _location, photo: _photo);
    setState(() => _loading = true);
    auth.setAuthFlowInProgress(true);
    try {
      if (_mode == 'login') {
        final r = await auth.signIn(_email.text.trim(), _password.text);
        if (r.error != null) {
          _showAuthError(r.error!, r.kind, offerResend: r.kind == AuthErrorKind.emailNotConfirmed);
          return;
        }
        if (!await _recordConsent(auth, r.user?.id, consent)) return;
        auth.setAuthFlowInProgress(false);
        router.go(widget.next);
      } else {
        final r = await auth.signUp(_email.text.trim(), _password.text, _fullName.text);
        if (r.error != null) {
          _showAuthError(r.error!, r.kind);
          return;
        }
        if (r.alreadyRegistered) {
          // Supabase kayıtlı adrese e-posta göndermez: kullanıcıyı giriş yapmaya ve gerekirse sıfırlamaya yönlendir.
          if (mounted) {
            setState(() {
              _error = '';
              _mode = 'login';
              _info = _t('mobileAuth.errAlreadyRegistered');
            });
          }
          return;
        }
        if (r.needsEmailConfirmation) {
          if (mounted) {
            setState(() {
              _error = '';
              _mode = 'login';
              _info = _t('mobileAuth.signupSent');
              _canResend = true;
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
      if (isNetworkError(e)) {
        _showAuthError('', AuthErrorKind.network);
      } else {
        _showAuthError(e.toString().replaceFirst('Exception: ', ''), AuthErrorKind.other);
      }
      return false;
    }
  }

  Future<void> _submitForgot(AuthController auth) async {
    setState(() => _loading = true);
    try {
      final r = await auth.sendPasswordReset(_email.text.trim());
      if (!mounted) return;
      if (!r.ok) {
        _showAuthError(r.error!, r.kind);
        return;
      }
      setState(() => _info = _t('mobileAuth.forgotSent'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submitReset(AuthController auth, GoRouter router) async {
    setState(() => _loading = true);
    try {
      final r = await auth.updatePassword(_password.text);
      if (!r.ok) {
        _showAuthError(r.error!, r.kind);
        return;
      }
      _password.clear();
      _password2.clear();
      router.go(widget.next);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Sıfırlamadan vazgeçilirse bağlantının açtığı oturum kapatılır.
  Future<void> _cancelReset() async {
    await context.read<AuthController>().signOut();
    if (!mounted) return;
    setState(() {
      _mode = 'login';
      _error = '';
      _info = '';
      _password.clear();
      _password2.clear();
    });
  }

  Future<void> _resend() async {
    final email = _email.text.trim();
    if (_emailValidator(email) != null) {
      setState(() {
        _info = '';
        _error = _t('mobileAuth.needEmailFirst');
        _shake++;
      });
      return;
    }
    final auth = context.read<AuthController>();
    setState(() {
      _resending = true;
      _error = '';
      _info = '';
    });
    final r = await auth.resendConfirmation(email);
    if (!mounted) return;
    setState(() => _resending = false);
    if (r.ok) {
      setState(() => _info = _t('mobileAuth.resendSent'));
    } else {
      _showAuthError(r.error!, r.kind, offerResend: true);
    }
  }

  /// Geçersiz/süresi dolmuş e-posta bağlantısının nedenini bir kez gösterir.
  void _consumeLinkError() {
    if (!mounted) return;
    final auth = context.read<AuthController>();
    if (auth.linkError == null) return;
    auth.clearLinkError();
    _showAuthError('', AuthErrorKind.linkInvalid, offerResend: true);
  }

  void _switchMode(String mode) => setState(() {
        _mode = mode;
        _error = '';
        _info = '';
        _canResend = false;
      });

  /// 0–4 arası parola gücü (uzunluk, harf büyüklüğü, rakam + sembol).
  static int _strength(String v) {
    if (v.isEmpty) return 0;
    var s = 0;
    if (v.length >= 6) s++;
    if (v.length >= 10) s++;
    if (RegExp(r'[A-Z]').hasMatch(v) && RegExp(r'[a-z]').hasMatch(v)) s++;
    if (RegExp(r'\d').hasMatch(v) && RegExp(r'[^A-Za-z0-9]').hasMatch(v)) s++;
    return s.clamp(1, 4);
  }

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final auth = context.watch<AuthController>();
    if (auth.linkError != null) WidgetsBinding.instance.addPostFrameCallback((_) => _consumeLinkError());
    final mode = auth.recoveryPending ? 'reset' : _mode;
    final login = mode == 'login';
    final signup = mode == 'signup';
    final forgot = mode == 'forgot';
    final reset = mode == 'reset';
    final withLegal = login || signup;
    final canSubmit = !_loading && (!withLegal || (_kvkk && _riza));
    final overlay = (Brand.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Brand.paper,
      systemNavigationBarIconBrightness: Brand.dark ? Brightness.light : Brightness.dark,
    );
    final title = switch (mode) {
      'signup' => i18n.t('auth.createAccount'),
      'forgot' => i18n.t('mobileAuth.forgotTitle'),
      'reset' => i18n.t('mobileAuth.resetTitle'),
      _ => i18n.t('auth.welcome'),
    };
    final subtitle = switch (mode) {
      'signup' => i18n.t('auth.createFreeAccount'),
      'forgot' => i18n.t('mobileAuth.forgotSubtitle'),
      'reset' => i18n.t('mobileAuth.resetSubtitle'),
      _ => i18n.t('auth.loginToAccount'),
    };
    final submitLabel = switch (mode) {
      'signup' => i18n.t('auth.signup'),
      'forgot' => i18n.t('mobileAuth.forgotSend'),
      'reset' => i18n.t('mobileAuth.resetSave'),
      _ => i18n.t('auth.login'),
    };

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: ColoredBox(
        color: Brand.paper,
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          physics: const ClampingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: MediaQuery.paddingOf(context).top),
              PublicTopBar(onBack: () => context.go('/')),
              CenteredBox(
                maxWidth: 480,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(26, 22, 26, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Reveal(offset: Offset(0, 12), child: Align(alignment: Alignment.centerLeft, child: BrandMark(size: 54))),
                      const SizedBox(height: 24),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 280),
                        layoutBuilder: (current, previous) => Stack(alignment: Alignment.topLeft, children: [...previous, ?current]),
                        transitionBuilder: (child, anim) => FadeTransition(
                          opacity: anim,
                          child: SlideTransition(position: Tween<Offset>(begin: const Offset(0, .12), end: Offset.zero).animate(anim), child: child),
                        ),
                        child: Column(
                          key: ValueKey(mode),
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: Brand.serif(38, ls: -1.2, h: 1.05)),
                            const SizedBox(height: 10),
                            Text(subtitle, style: tx(16.5, c: Brand.inkSoft, h: 1.45)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 30),
                      Reveal(
                        delay: const Duration(milliseconds: 100),
                        offset: const Offset(0, 22),
                        child: Shake(
                          trigger: _shake,
                          child: Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                AnimatedSize(
                                  duration: const Duration(milliseconds: 240),
                                  curve: Curves.easeOutCubic,
                                  alignment: Alignment.topCenter,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      if (_info.isNotEmpty) ...[
                                        NoticeBox(text: _info, bg: Tw.teal50, border: Tw.teal100, fg: Tw.teal900, icon: LucideIcons.info, radius: 16),
                                        const SizedBox(height: 16),
                                      ],
                                      if (_error.isNotEmpty) ...[
                                        NoticeBox(text: _error, bg: Tw.red50, border: Tw.red200, fg: Tw.red700, icon: LucideIcons.circleAlert, radius: 16),
                                        const SizedBox(height: 16),
                                      ],
                                      if (_canResend && login) ...[
                                        _TextAction(
                                          key: const Key('auth-resend'),
                                          label: i18n.t('mobileAuth.resendConfirmation'),
                                          busy: _resending,
                                          onTap: _resending ? null : _resend,
                                        ),
                                        const SizedBox(height: 8),
                                      ],
                                      if (signup) ...[
                                        _AuthField(
                                          label: i18n.t('auth.fullName'),
                                          controller: _fullName,
                                          textCapitalization: TextCapitalization.words,
                                          textInputAction: TextInputAction.next,
                                          autofillHints: const [AutofillHints.name],
                                          validator: _required,
                                        ),
                                        const SizedBox(height: 14),
                                      ],
                                    ],
                                  ),
                                ),
                                if (!reset) ...[
                                  _AuthField(
                                    label: i18n.t('auth.email'),
                                    controller: _email,
                                    keyboardType: TextInputType.emailAddress,
                                    textInputAction: forgot ? TextInputAction.done : TextInputAction.next,
                                    autocorrect: false,
                                    autofillHints: const [AutofillHints.email],
                                    validator: _emailValidator,
                                    onSubmitted: forgot
                                        ? (_) {
                                            if (canSubmit) _submit();
                                          }
                                        : null,
                                  ),
                                  const SizedBox(height: 14),
                                ],
                                if (!forgot) ...[
                                  _AuthField(
                                    label: reset ? i18n.t('mobileAuth.resetNewPassword') : i18n.t('auth.password'),
                                    controller: _password,
                                    obscure: !_showPassword,
                                    autocorrect: false,
                                    enableSuggestions: false,
                                    textInputAction: reset ? TextInputAction.next : null,
                                    autofillHints: [login ? AutofillHints.password : AutofillHints.newPassword],
                                    validator: _passwordValidator,
                                    onSubmitted: reset
                                        ? null
                                        : (_) {
                                            if (canSubmit) _submit();
                                          },
                                    suffix: IconButton(
                                      tooltip: i18n.t(_showPassword ? 'mobileAuth.hidePassword' : 'mobileAuth.showPassword'),
                                      onPressed: () => setState(() => _showPassword = !_showPassword),
                                      icon: Icon(_showPassword ? LucideIcons.eyeOff : LucideIcons.eye, size: 20, color: Brand.inkSoft),
                                    ),
                                  ),
                                ],
                                AnimatedSize(
                                  duration: const Duration(milliseconds: 240),
                                  curve: Curves.easeOutCubic,
                                  alignment: Alignment.topCenter,
                                  child: (signup || reset)
                                      ? Padding(
                                          padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
                                          child: ValueListenableBuilder<TextEditingValue>(
                                            valueListenable: _password,
                                            builder: (context, value, _) => _StrengthMeter(level: _strength(value.text)),
                                          ),
                                        )
                                      : const SizedBox(width: double.infinity),
                                ),
                                if (reset) ...[
                                  const SizedBox(height: 14),
                                  _AuthField(
                                    label: i18n.t('mobileAuth.resetConfirmPassword'),
                                    controller: _password2,
                                    obscure: !_showPassword,
                                    autocorrect: false,
                                    enableSuggestions: false,
                                    autofillHints: const [AutofillHints.newPassword],
                                    validator: _confirmValidator,
                                    onSubmitted: (_) {
                                      if (canSubmit) _submit();
                                    },
                                  ),
                                ],
                                if (login)
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: _TextAction(
                                      key: const Key('auth-forgot'),
                                      label: i18n.t('mobileAuth.forgotPassword'),
                                      onTap: () => _switchMode('forgot'),
                                    ),
                                  ),
                                SizedBox(height: login ? 10 : 22),
                                if (withLegal) ...[
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
                                ],
                                BrandButton(
                                  key: const Key('auth-submit'),
                                  onPressed: canSubmit ? _submit : null,
                                  loading: _loading,
                                  label: submitLabel,
                                  trailingIcon: LucideIcons.arrowRight,
                                ),
                                AnimatedSize(
                                  duration: const Duration(milliseconds: 220),
                                  alignment: Alignment.topCenter,
                                  child: (!withLegal || (_kvkk && _riza))
                                      ? const SizedBox(width: double.infinity)
                                      : Padding(
                                          padding: const EdgeInsets.only(top: 12),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Padding(padding: const EdgeInsets.only(top: 1), child: Icon(LucideIcons.info, size: 14, color: Brand.inkSoft)),
                                              const SizedBox(width: 6),
                                              Flexible(child: Text(i18n.t('auth.legalRequired'), textAlign: TextAlign.center, style: tx(12, c: Brand.inkSoft, h: snug))),
                                            ],
                                          ),
                                        ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      if (withLegal)
                        Center(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _switchMode(login ? 'signup' : 'login'),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Wrap(
                                alignment: WrapAlignment.center,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 6,
                                children: [
                                  Text(login ? i18n.t('auth.haveNoAccount') : i18n.t('auth.haveAccount'), style: tx(14.5, c: Brand.inkSoft)),
                                  BrandLinkText(login ? i18n.t('auth.signup') : i18n.t('auth.login')),
                                ],
                              ),
                            ),
                          ),
                        )
                      else
                        Center(
                          child: _TextAction(
                            key: Key(reset ? 'auth-cancel-reset' : 'auth-back-login'),
                            label: reset ? i18n.t('mobileAuth.resetCancel') : i18n.t('mobileAuth.backToLogin'),
                            onTap: reset ? _cancelReset : () => _switchMode('login'),
                          ),
                        ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(LucideIcons.shieldCheck, size: 14, color: Brand.inkSoft),
                          const SizedBox(width: 6),
                          Flexible(child: Text(i18n.t('mobileAuth.trust'), textAlign: TextAlign.center, style: tx(12, c: Brand.inkSoft))),
                        ],
                      ),
                      SizedBox(height: 28 + MediaQuery.paddingOf(context).bottom),
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

/// Altı çizili metin eylemi (parolamı unuttum, tekrar gönder…); dokunma alanı en az 48 dp.
class _TextAction extends StatelessWidget {
  const _TextAction({super.key, required this.label, required this.onTap, this.busy = false});

  final String label;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (busy) ...[
                  SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Brand.ink)),
                  const SizedBox(width: 8),
                ],
                Flexible(child: BrandLinkText(label, size: 14)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Yüzen etiketli, yumuşak çerçeveli alan; odaklanınca çerçeve koyulaşır.
class _AuthField extends StatelessWidget {
  const _AuthField({
    required this.label,
    required this.controller,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.autofillHints,
    this.validator,
    this.obscure = false,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.suffix,
    this.onSubmitted,
  });

  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final Iterable<String>? autofillHints;
  final FormFieldValidator<String>? validator;
  final bool obscure;
  final bool autocorrect;
  final bool enableSuggestions;
  final Widget? suffix;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border(Color c, [double w = 1.3]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: c, width: w),
        );
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      textCapitalization: textCapitalization,
      autofillHints: autofillHints,
      validator: validator,
      obscureText: obscure,
      autocorrect: autocorrect,
      enableSuggestions: enableSuggestions,
      onFieldSubmitted: onSubmitted,
      cursorColor: Brand.teal,
      style: tx(16.5, w: 5, c: Brand.ink),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: tx(15.5, c: Brand.inkSoft),
        floatingLabelStyle: tx(14, w: 6, c: Brand.ink),
        filled: true,
        fillColor: Brand.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 19),
        suffixIcon: suffix,
        errorStyle: tx(12, w: 5, c: Tw.red600),
        enabledBorder: border(Brand.ink.withValues(alpha: .16)),
        focusedBorder: border(Brand.ink, 1.7),
        errorBorder: border(Tw.red500),
        focusedErrorBorder: border(Tw.red500, 1.7),
        border: border(Brand.ink.withValues(alpha: .16)),
      ),
    );
  }
}

/// Parola gücü: dört parçalı ince çubuk ve kısa bir etiket; boşken kural ipucu gösterilir.
class _StrengthMeter extends StatelessWidget {
  const _StrengthMeter({required this.level});

  final int level;

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    if (level == 0) {
      return Text(i18n.t('mobileAuth.strengthHint'), style: tx(12, c: Brand.inkSoft, h: snug));
    }
    final colors = [Tw.red500, Tw.amber500, Tw.teal500, Tw.emerald500];
    final labels = ['mobileAuth.strengthWeak', 'mobileAuth.strengthFair', 'mobileAuth.strengthFair', 'mobileAuth.strengthStrong'];
    final color = colors[level - 1];
    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              for (var i = 0; i < 4; i++)
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    height: 4,
                    margin: EdgeInsets.only(right: i < 3 ? 5 : 0),
                    decoration: BoxDecoration(color: i < level ? color : Brand.inkFaint, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(i18n.t(labels[level - 1]), style: tx(12, w: 7, c: color)),
      ],
    );
  }
}
