import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

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
/// Kipler: `login`, `signup`, `verify` (kayıttan sonra e-postadaki 6 haneli kodu yaz), `forgot` (sıfırlama bağlantısı
/// iste) ve `reset` (bağlantıyla gelince yeni parola; kip `AuthController.recoveryPending` ile belirlenir, kullanıcı
/// seçemez).
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.next, this.startInSignup = false});

  /// Başarılı girişten sonra gidilecek yol (`?next=`).
  final String next;

  /// Karşılamadaki ana eylemden gelindiğinde kayıt modunda açılır (`?mode=signup`).
  final bool startInSignup;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _password2 = TextEditingController();
  final _fullName = TextEditingController();
  final _code = TextEditingController();
  late String _mode = widget.startInSignup ? 'signup' : 'login';
  bool _showPassword = false;
  bool _loading = false;
  bool _resending = false;

  /// Supabase aynı kullanıcıya dakikada bir onay e-postası gönderir; yeniden gönder düğmesi o kadar bekletilir.
  static const _resendCooldown = Duration(seconds: 60);
  Timer? _cooldownTimer;
  int _cooldownLeft = 0;

  /// Kod ekranındayken uygulamaya dönülünce yapılan sessiz girişin çakışmaması ve sık denenmemesi için.
  bool _autoSigningIn = false;
  DateTime? _lastAutoSignIn;

  /// Onay e-postasını yeniden gönderme bağlantısı görünsün mü (onaysız giriş, geçersiz bağlantı; kod ekranında her zaman var).
  bool _canResend = false;
  String _error = '';
  String _info = '';
  bool _kvkk = false;
  bool _riza = false;
  bool _location = false;
  bool _photo = false;
  int _shake = 0;

  /// Ekran klavyesi açık mı: açıkken sabit alt şerit gizlenir. `MediaQuery` bu bilgiyi gövdede (Scaffold klavye
  /// boşluğunu düşer) vermez ve `View.of` yeniden çizim tetiklemez; bu yüzden pencere metrikleri dinlenir.
  bool _keyboardOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeMetrics() {
    if (!mounted) return;
    final open = View.of(context).viewInsets.bottom > 0;
    if (open != _keyboardOpen) setState(() => _keyboardOpen = open);
  }

  /// Kod ekranındayken kullanıcı e-postadaki düğmeyle (tarayıcıda) onaylayıp uygulamaya dönmüş olabilir: elde
  /// tutulan e-posta + parolayla girişi sessizce dener, onaylandıysa içeri alır.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _continueAfterConfirm(silent: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cooldownTimer?.cancel();
    _email.dispose();
    _password.dispose();
    _password2.dispose();
    _fullName.dispose();
    _code.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _cooldownLeft = _resendCooldown.inSeconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _cooldownLeft = _cooldownLeft > 0 ? _cooldownLeft - 1 : 0);
      if (_cooldownLeft == 0) t.cancel();
    });
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

  String? _codeValidator(String? v) => RegExp(r'^\d{6}$').hasMatch((v ?? '').trim()) ? null : _t('mobileAuth.verifyCodeShort');

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
      case AuthErrorKind.codeInvalid:
        return _t('mobileAuth.errCodeInvalid');
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
    if (_mode == 'verify') return _submitVerify(auth, router);
    // KVKK ve açık rıza yalnızca kayıtta alınır; girişte kutu da, onay şartı da yoktur.
    if (_mode == 'signup' && (!_kvkk || !_riza)) {
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
        await _continueSignedIn(auth, router);
      } else {
        final r = await auth.signUp(_email.text.trim(), _password.text, _fullName.text, consent: consent);
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
          // Onay e-postası (6 haneli kod + düğme) yola çıktı: kullanıcı kodu bu ekranda yazar.
          if (mounted) {
            setState(() {
              _error = '';
              _mode = 'verify';
              _info = _t('mobileAuth.signupSent');
              _canResend = false;
              _code.clear();
            });
            _startCooldown();
          }
          return;
        }
        // E-posta onayı kapalıysa oturum hemen açılır: kayıttaki rıza şimdi kayda geçer.
        await _continueSignedIn(auth, router);
      }
    } finally {
      auth.setAuthFlowInProgress(false);
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Kayıtta verilen rıza ilk oturum açılışında yazılır (bkz. [AuthController.consentSync]). Hata girişi engellemez:
  /// yazılamazsa panel açılır ve açılış paketi eksik rızayı görüp rıza kutusunu gösterir. Uzun beklemeyi keser.
  Future<void> _waitConsentSync(AuthController auth) =>
      auth.consentSync.timeout(const Duration(seconds: 15), onTimeout: () {});

  /// Oturum açıldıktan sonra (şifreyle giriş, kodla onay, e-posta onaylıysa kayıt): rıza yazılır, panele geçilir.
  Future<void> _continueSignedIn(AuthController auth, GoRouter router) async {
    await _waitConsentSync(auth);
    auth.setAuthFlowInProgress(false);
    router.go(widget.next);
  }

  /// E-postadaki 6 haneli kodla hesabı onaylar; başarılıysa oturum açılır ve panele geçilir.
  Future<void> _submitVerify(AuthController auth, GoRouter router) async {
    setState(() => _loading = true);
    auth.setAuthFlowInProgress(true);
    try {
      final r = await auth.verifySignupCode(_email.text.trim(), _code.text.trim());
      if (r.error != null) {
        // Supabase yanlış kodu da süresi dolmuş bağlantıyla aynı `otp_expired` koduyla bildirir.
        _showAuthError(r.error!, r.kind == AuthErrorKind.linkInvalid ? AuthErrorKind.codeInvalid : r.kind);
        return;
      }
      _code.clear();
      await _continueSignedIn(auth, router);
    } finally {
      auth.setAuthFlowInProgress(false);
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Kullanıcı e-postadaki düğmeyle (tarayıcıda) ya da başka cihazdan onayladıysa, kod ekranında tutulan e-posta +
  /// parolayla giriş yapar. [silent]: uygulamaya dönünce kendiliğinden dener, başarısızlıkta hiçbir şey göstermez;
  /// değilse ("Onayladım, devam et") sonucu açıkça gösterir.
  Future<void> _continueAfterConfirm({required bool silent}) async {
    if (!mounted || _mode != 'verify' || _loading || _autoSigningIn) return;
    final email = _email.text.trim();
    if (_password.text.isEmpty || _emailValidator(email) != null) {
      // Parola elde yok (onay e-postası girişten yeniden istendi): giriş formuna dön, e-posta dolu kalsın.
      if (!silent) _switchMode('login');
      return;
    }
    final now = DateTime.now();
    if (silent && _lastAutoSignIn != null && now.difference(_lastAutoSignIn!) < const Duration(seconds: 5)) return;
    _lastAutoSignIn = now;
    final auth = context.read<AuthController>();
    final router = GoRouter.of(context);
    _autoSigningIn = true;
    if (!silent) setState(() => _loading = true);
    auth.setAuthFlowInProgress(true);
    try {
      final r = await auth.signIn(email, _password.text);
      if (r.error == null) {
        _code.clear();
        await _continueSignedIn(auth, router);
      } else if (!silent) {
        _showAuthError(r.error!, r.kind);
      }
    } finally {
      _autoSigningIn = false;
      auth.setAuthFlowInProgress(false);
      if (mounted && !silent) setState(() => _loading = false);
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
      // Yeni e-postada yeni kod var (eskisi geçersiz): kullanıcı kodu yazabilsin diye kod ekranına geçilir.
      setState(() {
        _info = _t('mobileAuth.resendSent');
        _canResend = false;
        if (_mode != 'verify') {
          _mode = 'verify';
          _code.clear();
        }
      });
      _startCooldown();
    } else {
      _showAuthError(r.error!, r.kind, offerResend: _mode != 'verify');
      if (r.kind == AuthErrorKind.rateLimited) _startCooldown();
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
    final verify = mode == 'verify';
    final forgot = mode == 'forgot';
    final reset = mode == 'reset';
    // Yasal metinler ve onay kutuları yalnızca kayıt ekranında; giriş ve diğer kiplerde yoktur.
    final withLegal = signup;
    final canSwitch = login || signup;
    final canSubmit = !_loading && (!withLegal || (_kvkk && _riza));
    // Üst sahne her iki temada koyu orman yeşili (karşılamayla aynı): durum çubuğu simgeleri açık, alt çubuk panelin rengindedir.
    final overlay = SystemUiOverlayStyle.light.copyWith(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Brand.paper,
      systemNavigationBarIconBrightness: Brand.dark ? Brightness.light : Brightness.dark,
    );
    final title = switch (mode) {
      'signup' => i18n.t('auth.createAccount'),
      'verify' => i18n.t('mobileAuth.verifyTitle'),
      'forgot' => i18n.t('mobileAuth.forgotTitle'),
      'reset' => i18n.t('mobileAuth.resetTitle'),
      _ => i18n.t('auth.welcome'),
    };
    final subtitle = switch (mode) {
      'signup' => i18n.t('auth.createFreeAccount'),
      'verify' => i18n.t('mobileAuth.verifySubtitle', {'email': _email.text.trim()}),
      'forgot' => i18n.t('mobileAuth.forgotSubtitle'),
      'reset' => i18n.t('mobileAuth.resetSubtitle'),
      _ => i18n.t('auth.loginToAccount'),
    };
    final submitLabel = switch (mode) {
      'signup' => i18n.t('auth.signup'),
      'verify' => i18n.t('mobileAuth.verifySubmit'),
      'forgot' => i18n.t('mobileAuth.forgotSend'),
      'reset' => i18n.t('mobileAuth.resetSave'),
      _ => i18n.t('auth.login'),
    };

    final footer = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (canSwitch)
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
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.shieldCheck, size: 14, color: Brand.inkSoft),
            const SizedBox(width: 6),
            Flexible(child: Text(i18n.t('mobileAuth.trust'), textAlign: TextAlign.center, style: tx(12, c: Brand.inkSoft))),
          ],
        ),
      ],
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: ColoredBox(
        // Köşeleri yuvarlak panelin arkasında görünen zemin: üst sahneyle aynı orman yeşili.
        color: Brand.forest,
        child: Column(
          children: [
            Expanded(
              child: CustomScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                physics: const ClampingScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: _AuthStage(modeKey: mode, compact: signup || verify, title: title, subtitle: subtitle, onBack: () => context.go('/')),
                  ),
                  SliverToBoxAdapter(
                    child: Reveal(
                      delay: const Duration(milliseconds: 120),
                      duration: const Duration(milliseconds: 720),
                      offset: const Offset(0, 90),
                      // Krem panel + altına 2 px taşan zemin: alttaki dolgu şeridiyle kesirli piksel sınırında arkadaki orman
                      // yeşili ince bir çizgi gibi sızmasın.
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned(
                            left: 0,
                            right: 0,
                            top: 0,
                            bottom: -2,
                            child: DecoratedBox(
                              decoration: BoxDecoration(color: Brand.paper, borderRadius: const BorderRadius.vertical(top: Radius.circular(32))),
                            ),
                          ),
                          Align(
                            alignment: Alignment.topCenter,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 480),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(26, 30, 26, 22),
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
                                                  icon: LucideIcons.user,
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
                                        if (verify) ...[
                                          Reveal(
                                            delay: const Duration(milliseconds: 200),
                                            duration: const Duration(milliseconds: 600),
                                            offset: const Offset(0, 16),
                                            child: _AuthField(
                                              label: i18n.t('mobileAuth.verifyCodeLabel'),
                                              controller: _code,
                                              keyboardType: TextInputType.number,
                                              textInputAction: TextInputAction.done,
                                              autocorrect: false,
                                              enableSuggestions: false,
                                              autofillHints: const [AutofillHints.oneTimeCode],
                                              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                                              textAlign: TextAlign.center,
                                              textStyle: tx(28, w: 7, c: Brand.ink, ls: 9),
                                              validator: _codeValidator,
                                              onChanged: (v) {
                                                // Altı hane tamamlanınca (elle ya da yapıştırarak) kendiliğinden gönderilir.
                                                if (v.length == 6 && canSubmit) _submit();
                                              },
                                              onSubmitted: (_) {
                                                if (canSubmit) _submit();
                                              },
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 4),
                                            child: Text(i18n.t('mobileAuth.verifyHint'), style: tx(12.5, c: Brand.inkSoft, h: snug)),
                                          ),
                                        ],
                                        if (!reset && !verify) ...[
                                          Reveal(
                                            delay: const Duration(milliseconds: 260),
                                            duration: const Duration(milliseconds: 600),
                                            offset: const Offset(0, 16),
                                            child: _AuthField(
                                              label: i18n.t('auth.email'),
                                              icon: LucideIcons.mail,
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
                                          ),
                                          const SizedBox(height: 14),
                                        ],
                                        if (!forgot && !verify) ...[
                                          Reveal(
                                            delay: const Duration(milliseconds: 340),
                                            duration: const Duration(milliseconds: 600),
                                            offset: const Offset(0, 16),
                                            child: _AuthField(
                                              label: reset ? i18n.t('mobileAuth.resetNewPassword') : i18n.t('auth.password'),
                                              icon: LucideIcons.lock,
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
                                            icon: LucideIcons.lock,
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
                                          const SizedBox(height: 20),
                                        ],
                                        Reveal(
                                          delay: const Duration(milliseconds: 420),
                                          duration: const Duration(milliseconds: 600),
                                          offset: const Offset(0, 16),
                                          child: BrandButton(
                                            key: const Key('auth-submit'),
                                            onPressed: canSubmit ? _submit : null,
                                            loading: _loading,
                                            label: submitLabel,
                                            trailingIcon: LucideIcons.arrowRight,
                                          ),
                                        ),
                                        if (verify) ...[
                                          const SizedBox(height: 6),
                                          _TextAction(
                                            key: const Key('auth-verify-continue'),
                                            label: i18n.t('mobileAuth.verifyContinue'),
                                            onTap: _loading ? null : () => _continueAfterConfirm(silent: false),
                                          ),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: _TextAction(
                                                  key: const Key('auth-resend'),
                                                  label: _cooldownLeft > 0
                                                      ? i18n.t('mobileAuth.resendWait', {'s': _cooldownLeft})
                                                      : i18n.t('mobileAuth.verifyResend'),
                                                  busy: _resending,
                                                  onTap: (_resending || _cooldownLeft > 0) ? null : _resend,
                                                ),
                                              ),
                                              Expanded(
                                                child: _TextAction(
                                                  key: const Key('auth-verify-change'),
                                                  label: i18n.t('mobileAuth.verifyChangeEmail'),
                                                  onTap: () => _switchMode('signup'),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
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
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Panelin altını doldurur: içerik kısaysa krem zemin sabit alt şeride kadar uzanır.
                  SliverFillRemaining(hasScrollBody: false, child: ColoredBox(color: Brand.paper)),
                ],
              ),
            ),
            // Sabit alt şerit: giriş ↔ kayıt bağlantısı ve güven notu. Klavye açılınca yer açmak için gizlenir.
            ColoredBox(
              color: Brand.paper,
              child: AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: _keyboardOpen
                    ? const SizedBox(width: double.infinity)
                    : Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 480),
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(26, 4, 26, 12 + MediaQuery.paddingOf(context).bottom),
                            child: footer,
                          ),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Üst sahne: derin orman yeşili zemin, krem Fraunces başlık ve sağ üstte çok silik dev "R" monogramı.
/// Monogram sayfa açılırken kendini çizer (tek, sakin hareket); mod değişince yalnızca başlık yumuşakça değişir.
class _AuthStage extends StatelessWidget {
  const _AuthStage({required this.modeKey, required this.compact, required this.title, required this.subtitle, required this.onBack});

  final String modeKey;

  /// Kayıt formu uzundur: sahne kısa kalır. Diğer kiplerde ekran yüksekliğinin ~%40'ına uzar, başlık alta oturur.
  final bool compact;
  final String title;
  final String subtitle;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    // Doğal yükseklik: durum çubuğu + üst çubuk (60) + boşluk + başlık bloğu (~75) + alt pay. Fazlası başlığın üstüne eklenir.
    final natural = top + 60 + 22 + 75 + 52;
    final extra = compact ? 0.0 : (MediaQuery.sizeOf(context).height * .40 - natural).clamp(0.0, 150.0);
    return Stack(
      children: [
        const Positioned(right: -90, top: -20, child: _RWatermark(size: 300)),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: top),
            Reveal(offset: Offset.zero, child: PublicTopBar(onBack: onBack, onDark: true)),
            AnimatedPadding(
              duration: const Duration(milliseconds: 360),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.fromLTRB(26, 22 + extra, 26, 52),
              child: AnimatedSize(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topLeft,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  layoutBuilder: (current, previous) => Stack(alignment: Alignment.topLeft, children: [...previous, ?current]),
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(position: Tween<Offset>(begin: const Offset(0, .14), end: Offset.zero).animate(anim), child: child),
                  ),
                  child: Column(
                    key: ValueKey(modeKey),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: Brand.serif(38, ls: -1.2, h: 1.05, color: Brand.cream)),
                      const SizedBox(height: 10),
                      Text(subtitle, style: tx(16.5, c: Brand.cream.withValues(alpha: .74), h: 1.45)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Dev, çok silik "R": sayfa açılırken harf çizilir, sonra köşedeki parıltı belirir. Tek katman saydamlık
/// (üst üste binen çizgiler koyulaşmasın diye) ve süsleme olduğu için ekran okuyuculardan gizli.
class _RWatermark extends StatefulWidget {
  const _RWatermark({required this.size});

  final double size;

  @override
  State<_RWatermark> createState() => _RWatermarkState();
}

class _RWatermarkState extends State<_RWatermark> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (reduceMotion(context)) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: IgnorePointer(
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final draw = Curves.easeInOutCubic.transform(Interval(.05, .78).transform(_c.value));
              final spark = Curves.easeOutBack.transform(Interval(.74, 1).transform(_c.value));
              return Opacity(
                opacity: .075,
                child: CustomPaint(
                  size: Size.square(widget.size),
                  painter: BrandGlyphPainter(draw, spark, color: Brand.cream),
                ),
              );
            },
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
    // Kapalı (ör. yeniden gönderme bekleme süresinde) eylem soluk görünür; yükleniyorsa normal kalır.
    final dim = onTap == null && !busy;
    return Semantics(
      button: true,
      enabled: !dim,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Opacity(
              opacity: dim ? .5 : 1,
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
      ),
    );
  }
}

/// Yüzen etiketli, yumuşak çerçeveli alan; odaklanınca çerçeve koyulaşır.
class _AuthField extends StatelessWidget {
  const _AuthField({
    required this.label,
    this.icon,
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
    this.onChanged,
    this.inputFormatters,
    this.textAlign = TextAlign.start,
    this.textStyle,
  });

  final String label;

  /// Yoksa alanın başında simge bulunmaz (ortalanmış kod alanı).
  final IconData? icon;
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
  final ValueChanged<String>? onChanged;
  final List<TextInputFormatter>? inputFormatters;
  final TextAlign textAlign;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border(Color c, [double w = 1.2]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
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
      onChanged: onChanged,
      inputFormatters: inputFormatters,
      textAlign: textAlign,
      cursorColor: Brand.teal,
      style: textStyle ?? tx(16.5, w: 5, c: Brand.ink),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: tx(15.5, c: Brand.inkSoft),
        floatingLabelStyle: tx(14, w: 6, c: Brand.ink),
        floatingLabelAlignment: icon == null ? FloatingLabelAlignment.center : null,
        filled: true,
        fillColor: Brand.surface,
        contentPadding: EdgeInsets.symmetric(horizontal: icon == null ? 16 : 4, vertical: icon == null ? 17 : 19),
        prefixIcon: icon == null
            ? null
            : Padding(padding: const EdgeInsetsDirectional.only(start: 16, end: 10), child: Icon(icon, size: 19, color: Brand.inkSoft)),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        suffixIcon: suffix,
        errorStyle: tx(12, w: 5, c: Tw.red600),
        enabledBorder: border(Brand.ink.withValues(alpha: .12)),
        focusedBorder: border(Brand.ink, 1.6),
        errorBorder: border(Tw.red500),
        focusedErrorBorder: border(Tw.red500, 1.7),
        border: border(Brand.ink.withValues(alpha: .12)),
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
