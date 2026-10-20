import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/api.dart';
import '../core/auth_errors.dart';
import '../core/legal_consent.dart';

/// E-posta onayı ve parola sıfırlama bağlantılarının uygulamayı açtığı adres (Android `intent-filter`,
/// iOS `CFBundleURLTypes`). Supabase panelinde Authentication → URL Configuration → Redirect URLs listesinde
/// de bulunmalıdır; yoksa Supabase bağlantıyı Site URL'ye (web) yönlendirir ve uygulama açılmaz.
const authCallbackUrl = 'com.rebiovil.rebi://auth-callback';

class SignUpResult {
  const SignUpResult({
    this.user,
    this.error,
    this.kind = AuthErrorKind.other,
    this.networkError = false,
    this.needsEmailConfirmation = false,
    this.alreadyRegistered = false,
  });

  final User? user;
  final String? error;
  final AuthErrorKind kind;
  final bool networkError;
  final bool needsEmailConfirmation;

  /// E-posta onayı açıkken kayıtlı bir adresle kayıt denendi: Supabase hata vermez, e-posta da göndermez.
  final bool alreadyRegistered;
}

class SignInResult {
  const SignInResult({this.user, this.error, this.kind = AuthErrorKind.other, this.networkError = false});

  final User? user;
  final String? error;
  final AuthErrorKind kind;
  final bool networkError;
}

/// Sonuç dönmeyen Supabase işlemleri (onay e-postasını yeniden gönder, sıfırlama bağlantısı, yeni parola).
class AuthActionResult {
  const AuthActionResult({this.error, this.kind = AuthErrorKind.other, this.networkError = false});

  final String? error;
  final AuthErrorKind kind;
  final bool networkError;

  bool get ok => error == null;
}

/// Uygulama `SUPABASE_URL` olmadan derlendiğinde giriş/kayıt bu hatayla döner.
const supabaseNotConfiguredError = 'Supabase not configured';

/// Webdeki "Failed to fetch" karşılığı: sunucuya hiç ulaşılamadı.
bool _isNetwork(Object e) => e is AuthRetryableFetchException || isNetworkError(e);

AuthErrorKind _kindOf(Object e, String message, bool network) {
  if (message == supabaseNotConfiguredError) return AuthErrorKind.notConfigured;
  return classifyAuthError(message, code: e is AuthException ? e.code : null, network: network);
}

/// Kayıt yanıtını sonuca çevirir. Supabase, e-posta onayı AÇIKKEN kayıtlı bir adresle yeniden kayıtta hata
/// vermez: kimliksiz (`identities: []`) sahte bir kullanıcı döner ve onay e-postası GÖNDERİLMEZ. Bunu
/// "onay e-postası yolladık" diye göstermek kullanıcıyı çıkmaza sokar.
@visibleForTesting
SignUpResult signUpResultFromResponse(AuthResponse res) {
  final user = res.user;
  final noSession = user != null && res.session == null;
  if (noSession && (user.identities?.isEmpty ?? false)) {
    return const SignUpResult(alreadyRegistered: true, kind: AuthErrorKind.alreadyRegistered);
  }
  return SignUpResult(user: user, needsEmailConfirmation: noSession);
}

/// Web `AuthContext` karşılığı: oturum durumu + giriş/kayıt/çıkış (+ onay e-postası ve parola sıfırlama).
class AuthController extends ChangeNotifier {
  AuthController() {
    final client = supabase;
    if (client == null) {
      loading = false;
      return;
    }
    // supabase_flutter, `initialize` sırasında kayıtlı oturumu zaten geri yükledi.
    user = client.auth.currentSession?.user;
    loading = false;
    _sub = client.auth.onAuthStateChange.listen(_onAuthState, onError: _onAuthStreamError);
  }

  User? user;
  bool loading = true;
  StreamSubscription<AuthState>? _sub;

  /// Giriş/kayıt ekranı rıza kaydını tamamlayana kadar yönlendirme yapılmaz.
  /// Web'de oturum açılır açılmaz `/auth` sayfası söküldüğü için rıza hatası
  /// kullanıcıya gösterilemiyordu; mobilde ekran işini bitirene kadar beklenir.
  bool authFlowInProgress = false;

  /// Parola sıfırlama bağlantısıyla gelindi: yeni parola belirlenene kadar uygulamanın geri kalanına geçilmez.
  bool recoveryPending = false;

  /// Açılan e-posta bağlantısı geçersiz/süresi dolmuşsa (ör. posta tarayıcısı bağlantıyı önceden açtı) giriş
  /// ekranı bunu bir kez gösterir.
  String? linkError;

  bool _disposed = false;
  Future<void> _consentSync = Future.value();

  /// Oturum açılınca kayıt sırasında verilen rızanın sunucuya yazılması (yoksa hemen biten bir Future).
  /// Giriş ekranı bunu bekleyip panele öyle geçer; e-posta bağlantısıyla girişte aynı iş arka planda yürür.
  Future<void> get consentSync => _consentSync;

  void setAuthFlowInProgress(bool v) {
    if (authFlowInProgress == v) return;
    authFlowInProgress = v;
    notifyListeners();
  }

  /// Kayıtta verilen rıza bu oturumun kullanıcı bilgisinde bekliyorsa yazılır. Bitene kadar açılış senkronu ve
  /// giriş yönlendirmesi bekletilir; yoksa rıza kutusu boşuna açılır.
  void _startConsentSync(User u) {
    if (pendingConsentFromMetadata(u.userMetadata) == null) return;
    authFlowInProgress = true;
    _consentSync = syncPendingLegalConsent(u).whenComplete(() {
      if (_disposed) return;
      authFlowInProgress = false;
      notifyListeners();
    });
  }

  void _onAuthState(AuthState data) {
    final next = data.session?.user;
    if (data.event == AuthChangeEvent.signedIn && next != null && next.id != user?.id) _startConsentSync(next);
    final recovery = data.event == AuthChangeEvent.passwordRecovery;
    var changed = false;
    if (recovery && !recoveryPending) {
      recoveryPending = true;
      changed = true;
    }
    if (next == null && recoveryPending) {
      // Sıfırlama oturumu kapandı (çıkış / süre bitti): bekleyen sıfırlama da biter.
      recoveryPending = false;
      changed = true;
    }
    if (!changed && next?.id == user?.id && identical(next, user)) return;
    user = next;
    notifyListeners();
  }

  /// Bağlantı hatası (`otp_expired` vb.) akışa hata olarak düşer; dinleyici olmazsa yakalanmamış hata olurdu.
  void _onAuthStreamError(Object error, [StackTrace? stack]) {
    if (user != null) return;
    final raw = error is AuthException ? error.message : error.toString();
    linkError = raw.isEmpty ? 'link' : raw;
    notifyListeners();
  }

  /// Hata bir kez gösterildikten sonra temizlenir.
  void clearLinkError() {
    if (linkError == null) return;
    linkError = null;
    notifyListeners();
  }

  /// [consent]: kayıt formundaki KVKK/açık rıza seçimleri; kullanıcı bilgisine konur ve ilk oturum açılışında
  /// sunucuya yazılır (e-posta onayı beklenirken oturum olmadığı için hemen yazılamaz).
  Future<SignUpResult> signUp(String email, String password, String fullName, {ConsentPermissions? consent}) async {
    final client = supabase;
    if (client == null) return const SignUpResult(error: supabaseNotConfiguredError, kind: AuthErrorKind.notConfigured);
    try {
      final res = await client.auth.signUp(
        email: email,
        password: password,
        data: {'full_name': fullName, if (consent != null) 'legal_consent': legalConsentMetadata(consent)},
        emailRedirectTo: authCallbackUrl,
      );
      return signUpResultFromResponse(res);
    } on AuthException catch (e) {
      final network = _isNetwork(e);
      return SignUpResult(error: e.message, networkError: network, kind: _kindOf(e, e.message, network));
    } catch (e) {
      final network = _isNetwork(e);
      return SignUpResult(error: e.toString(), networkError: network, kind: _kindOf(e, e.toString(), network));
    }
  }

  Future<SignInResult> signIn(String email, String password) async {
    final client = supabase;
    if (client == null) return const SignInResult(error: supabaseNotConfiguredError, kind: AuthErrorKind.notConfigured);
    try {
      final res = await client.auth.signInWithPassword(email: email, password: password);
      return SignInResult(user: res.user);
    } on AuthException catch (e) {
      final network = _isNetwork(e);
      return SignInResult(error: e.message, networkError: network, kind: _kindOf(e, e.message, network));
    } catch (e) {
      final network = _isNetwork(e);
      return SignInResult(error: e.toString(), networkError: network, kind: _kindOf(e, e.toString(), network));
    }
  }

  Future<AuthActionResult> _action(Future<void> Function(GoTrueClient auth) run) async {
    final client = supabase;
    if (client == null) return const AuthActionResult(error: supabaseNotConfiguredError, kind: AuthErrorKind.notConfigured);
    try {
      await run(client.auth);
      return const AuthActionResult();
    } on AuthException catch (e) {
      final network = _isNetwork(e);
      return AuthActionResult(error: e.message, networkError: network, kind: _kindOf(e, e.message, network));
    } catch (e) {
      final network = _isNetwork(e);
      return AuthActionResult(error: e.toString(), networkError: network, kind: _kindOf(e, e.toString(), network));
    }
  }

  /// Onay e-postasını yeniden gönderir (posta gelmediyse ya da bağlantının süresi dolduysa).
  Future<AuthActionResult> resendConfirmation(String email) =>
      _action((auth) => auth.resend(type: OtpType.signup, email: email, emailRedirectTo: authCallbackUrl));

  /// Parola sıfırlama bağlantısı gönderir. Supabase adresin kayıtlı olup olmadığını belli etmez.
  Future<AuthActionResult> sendPasswordReset(String email) =>
      _action((auth) => auth.resetPasswordForEmail(email, redirectTo: authCallbackUrl));

  /// Sıfırlama bağlantısıyla açılan oturumda yeni parolayı kaydeder; başarılıysa uygulamaya geçilir.
  Future<AuthActionResult> updatePassword(String password) async {
    final r = await _action((auth) async {
      await auth.updateUser(UserAttributes(password: password));
    });
    if (r.ok) {
      recoveryPending = false;
      notifyListeners();
    }
    return r;
  }

  Future<void> signOut() async {
    final client = supabase;
    if (client == null) return;
    try {
      await client.auth.signOut();
    } catch (_) {
      /* ağ yoksa yerel oturum yine silinir */
    }
    user = null;
    recoveryPending = false;
    notifyListeners();
  }

  /// Testlerde oturumu Supabase olmadan değiştirmek için.
  @visibleForTesting
  void debugSetUser(User? next) {
    user = next;
    notifyListeners();
  }

  /// Testlerde Supabase akışından gelen olayı gerçek işleyiciye vermek için.
  @visibleForTesting
  void debugEmitAuthState(AuthState data) => _onAuthState(data);

  /// Testlerde Supabase akışından gelen hatayı (geçersiz bağlantı vb.) gerçek işleyiciye vermek için.
  @visibleForTesting
  void debugEmitStreamError(Object error) => _onAuthStreamError(error);

  Future<void> refreshUser() async {
    final client = supabase;
    if (client == null) return;
    user = client.auth.currentSession?.user ?? client.auth.currentUser;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    super.dispose();
  }
}
