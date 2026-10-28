import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

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

/// Giriş / kayıt (web: `pages/Auth.jsx`).
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
  final _fullName = TextEditingController();
  late String _mode = widget.startInSignup ? 'signup' : 'login';
  bool _showPassword = false;
  bool _loading = false;
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
    if (raw == supabaseNotConfiguredError) {
      return I18n.instance.t('mobileMisc.authNotConfigured');
    }
    final lower = raw.toLowerCase();
    if (network) {
      return I18n.instance.t('mobileMisc.authNetwork');
    }
    if (lower.contains('rate limit') ||
        lower.contains('too many') ||
        lower.contains('exceeded') ||
        lower.contains('quota') ||
        lower.contains('429')) {
      return I18n.instance.t('mobileMisc.authRateLimit');
    }
    return raw.isEmpty ? I18n.instance.t('mobileMisc.genericError') : raw;
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _error = '';
      _info = '';
    });
    if (!(_formKey.currentState?.validate() ?? false)) {
      setState(() => _shake++);
      return;
    }
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
              _info = I18n.instance.t('mobileMisc.signupConfirm');
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
    setState(() {
      _error = _friendlyError(raw, network: network);
      _shake++;
    });
  }

  void _switchMode(String mode) => setState(() {
        _mode = mode;
        _error = '';
        _info = '';
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
    final login = _mode == 'login';
    final canSubmit = !_loading && _kvkk && _riza;
    final overlay = (Brand.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Brand.paper,
      systemNavigationBarIconBrightness: Brand.dark ? Brightness.light : Brightness.dark,
    );

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
                          key: ValueKey(_mode),
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(login ? i18n.t('auth.welcome') : i18n.t('auth.createAccount'), style: Brand.serif(38, ls: -1.2, h: 1.05)),
                            const SizedBox(height: 10),
                            Text(login ? i18n.t('auth.loginToAccount') : i18n.t('auth.createFreeAccount'), style: tx(16.5, c: Brand.inkSoft, h: 1.45)),
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
                                      if (!login) ...[
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
                                _AuthField(
                                  label: i18n.t('auth.email'),
                                  controller: _email,
                                  keyboardType: TextInputType.emailAddress,
                                  textInputAction: TextInputAction.next,
                                  autocorrect: false,
                                  autofillHints: const [AutofillHints.email],
                                  validator: _emailValidator,
                                ),
                                const SizedBox(height: 14),
                                _AuthField(
                                  label: i18n.t('auth.password'),
                                  controller: _password,
                                  obscure: !_showPassword,
                                  autocorrect: false,
                                  enableSuggestions: false,
                                  autofillHints: [login ? AutofillHints.password : AutofillHints.newPassword],
                                  validator: _passwordValidator,
                                  onSubmitted: (_) {
                                    if (canSubmit) _submit();
                                  },
                                  suffix: IconButton(
                                    tooltip: i18n.t(_showPassword ? 'mobileAuth.hidePassword' : 'mobileAuth.showPassword'),
                                    onPressed: () => setState(() => _showPassword = !_showPassword),
                                    icon: Icon(_showPassword ? LucideIcons.eyeOff : LucideIcons.eye, size: 20, color: Brand.inkSoft),
                                  ),
                                ),
                                AnimatedSize(
                                  duration: const Duration(milliseconds: 240),
                                  curve: Curves.easeOutCubic,
                                  alignment: Alignment.topCenter,
                                  child: login
                                      ? const SizedBox(width: double.infinity)
                                      : Padding(
                                          padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
                                          child: ValueListenableBuilder<TextEditingValue>(
                                            valueListenable: _password,
                                            builder: (context, value, _) => _StrengthMeter(level: _strength(value.text)),
                                          ),
                                        ),
                                ),
                                const SizedBox(height: 22),
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
                                BrandButton(
                                  key: const Key('auth-submit'),
                                  onPressed: canSubmit ? _submit : null,
                                  loading: _loading,
                                  label: login ? i18n.t('auth.login') : i18n.t('auth.signup'),
                                  trailingIcon: LucideIcons.arrowRight,
                                ),
                                AnimatedSize(
                                  duration: const Duration(milliseconds: 220),
                                  alignment: Alignment.topCenter,
                                  child: (_kvkk && _riza)
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
