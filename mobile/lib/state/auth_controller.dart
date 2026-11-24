import 'dart:async';

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env.dart';
import '../core/api.dart';
import '../core/auth_errors.dart';
import '../core/legal_consent.dart';
import '../core/native_apple_sign_in.dart';
import '../core/native_google_sign_in.dart';

/// Parola sıfırlama, Google girişi (ve eski e-posta onayı) dönüşlerinin uygulamayı açtığı adres (Android `intent-filter`,
/// iOS `CFBundleURLTypes`). Supabase panelinde Authentication → URL Configuration → Redirect URLs listesinde
/// de bulunmalıdır; yoksa Supabase bağlantıyı Site URL'ye (web) yönlendirir ve uygulama açılmaz.
/// Yeni onay e-postası bu adresi kullanmaz: 6 haneli kod uygulamada yazılır, düğme web onay sayfasına gider
/// (docs/MOBIL-GIRIS-SUPABASE.md §1.1).
const authCallbackUrl = 'com.rebiovil.rebi://auth-callback';

/// "Google ile devam et" gösterilsin mi. Android'de yerel hesap seçicisi, iOS'ta Supabase'in tarayıcıdaki OAuth
/// akışı kullanılır. iOS'ta App Store kuralı 4.8 gereği yanında "Apple ile devam et" de vardır
/// ([appleSignInAvailable]); üçüncü taraf girişi sunan uygulamadan Apple ile girişi de istenir.
bool get googleSignInAvailable =>
    debugGoogleSignInAvailable ??
    (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS));

/// "Apple ile devam et" gösterilsin mi. Yalnız Apple platformlarında: Apple'ın yerel giriş sayfası (ASAuthorization)
/// yalnızca orada vardır ve App Store kuralı 4.8 de yalnızca Apple platformları için geçerlidir.
bool get appleSignInAvailable =>
    debugAppleSignInAvailable ??
    (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS));

/// Testlerde platformdan bağımsız açıp kapatmak için.
@visibleForTesting
bool? debugGoogleSignInAvailable;

/// Testlerde platformdan bağımsız açıp kapatmak için.
@visibleForTesting
bool? debugAppleSignInAvailable;

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

/// Supabase panelinde Google sağlayıcısı kapalıyken `signInWithGoogle` bu hatayla döner (tarayıcı açılmaz).
const googleProviderDisabledError = 'Google provider is not enabled';

/// Supabase panelinde Apple sağlayıcısı kapalıyken `signInWithApple` bu hatayla döner (Apple sayfası açılmaz).
const appleProviderDisabledError = 'Apple provider is not enabled';

/// Yerel Google hesap seçicisi kapatıldı.
const googleCanceledError = 'Google sign-in canceled';

/// Apple'ın giriş sayfası kapatıldı.
const appleCanceledError = 'Apple sign-in canceled';

/// Supabase'in herkese açık `/auth/v1/settings` yanıtına göre [provider] (`google`, `apple`…) açık mı.
/// `false` yalnızca sunucu açıkça "kapalı" dediğinde döner; ağ hatası/zaman aşımında `null` (deneme engellenmez).
Future<bool?> fetchProviderEnabled(String provider, {http.Client? client, String? baseUrl}) async {
  final base = (baseUrl ?? Env.supabaseUrl).trim();
  if (base.isEmpty) return null;
  final c = client ?? http.Client();
  try {
    final res = await c
        .get(Uri.parse('$base/auth/v1/settings'), headers: {'apikey': Env.supabaseAnonKey})
        .timeout(const Duration(seconds: 6));
    if (res.statusCode != 200) return null;
    final body = jsonDecode(res.body);
    final value = body is Map ? (body['external'] is Map ? body['external'][provider] : null) : null;
    return value is bool ? value : null;
  } catch (_) {
    return null;
  } finally {
    if (client == null) c.close();
  }
}

/// [fetchProviderEnabled] ile aynı; Google için kısa yol.
Future<bool?> fetchGoogleProviderEnabled({http.Client? client, String? baseUrl}) =>
    fetchProviderEnabled('google', client: client, baseUrl: baseUrl);

/// Webdeki "Failed to fetch" karşılığı: sunucuya hiç ulaşılamadı.
bool _isNetwork(Object e) => e is AuthRetryableFetchException || isNetworkError(e);

AuthErrorKind _kindOf(Object e, String message, bool network) {
  if (message == supabaseNotConfiguredError) return AuthErrorKind.notConfigured;
  if (message.contains(googleProviderDisabledError) || message.contains(appleProviderDisabledError)) {
    return AuthErrorKind.providerDisabled;
  }
  if (message.contains(googleCanceledError) || message.contains(appleCanceledError)) return AuthErrorKind.canceled;
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

  /// Kodla parola sıfırlama sürerken (ve hemen ardından) gelen "parola kurtarma" olayı yok sayılır.
  DateTime? _codeResetUntil;
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
    // Kodla sıfırlamada doğrulama da "parola kurtarma" olayı yayar; parola o akışta zaten yazıldığı için olay
    // (geç gelse bile) kullanıcıyı yeniden "yeni parola" ekranına düşürmemeli.
    final codeReset = _codeResetUntil != null && DateTime.now().isBefore(_codeResetUntil!);
    final recovery = data.event == AuthChangeEvent.passwordRecovery && !codeReset;
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

  /// Onay e-postasındaki 6 haneli kodla hesabı onaylar ve oturumu açar. Kod, bağlantı tarayıcılarının (Gmail,
  /// antivirüs) tüketebildiği tek kullanımlık bağlantının aksine kullanıcı yazana kadar kullanılmaz; başka
  /// cihazdaki e-postadan da çalışır. Başarılıysa SDK `signedIn` olayını yayar (rıza eşitlemesi buradan başlar).
  Future<SignInResult> verifySignupCode(String email, String code) async {
    final client = supabase;
    if (client == null) return const SignInResult(error: supabaseNotConfiguredError, kind: AuthErrorKind.notConfigured);
    try {
      final res = await client.auth.verifyOTP(type: OtpType.signup, email: email, token: code);
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

  /// Yerel Google hesap seçicisi (testlerde sahtelenir).
  @visibleForTesting
  NativeGoogleSignIn nativeGoogle = NativeGoogleSignIn();

  /// Apple'ın yerel giriş sayfası (testlerde sahtelenir).
  @visibleForTesting
  NativeAppleSignIn nativeApple = NativeAppleSignIn();

  /// Google hesabıyla giriş ya da kayıt (aynı düğme). Önce Android'in yerel hesap seçicisi denenir: ekranın altında
  /// açılır ve uygulama adını ("Rebi") gösterir; seçilen hesabın kimlik belgesiyle Supabase oturumu hemen açılır
  /// (`signedIn` olayı). Yerel yol kullanılamazsa (Play hizmetleri yok, Android client'ı/SHA-1 tanımsız) tarayıcıdaki
  /// Supabase OAuth akışına düşülür: oturum [authCallbackUrl] derin bağlantısıyla döner; sonuç yalnızca tarayıcının
  /// açılıp açılmadığını söyler. Google'dan gelen e-posta doğrulanmıştır (onay kodu gerekmez); KVKK / açık rıza
  /// kaydı yoksa açılış paketi rıza kutusunu gösterir.
  /// Supabase'de Google sağlayıcısı kapalıysa hiçbir şey açılmaz ([googleProviderDisabledError]); yoksa kullanıcı
  /// tarayıcıda ham `{"error_code":"validation_failed","msg":"Unsupported provider…"}` sayfasında kalırdı.
  Future<AuthActionResult> signInWithGoogle() => _action((auth) async {
        if (await fetchGoogleProviderEnabled() == false) throw StateError(googleProviderDisabledError);
        if (nativeGoogle.available) {
          final r = await nativeGoogle.obtainIdToken();
          switch (r) {
            case NativeGoogleToken(:final idToken):
              await auth.signInWithIdToken(provider: OAuthProvider.google, idToken: idToken);
              return;
            case NativeGoogleCanceled():
              throw StateError(googleCanceledError);
            case NativeGoogleUnavailable(:final reason):
              debugPrint('Yerel Google girişi kullanılamadı ($reason); tarayıcı akışına geçiliyor.');
          }
        }
        final opened = await auth.signInWithOAuth(
          OAuthProvider.google,
          redirectTo: authCallbackUrl,
          // Telefonda birden çok Google hesabı varsa hangisiyle girileceği her seferinde sorulur.
          queryParams: const {'prompt': 'select_account'},
        );
        if (!opened) throw StateError('browser');
      });

  /// Apple hesabıyla giriş ya da kayıt (aynı düğme). Apple'ın kendi sayfası uygulamanın İÇİNDE açılır: tarayıcıya
  /// çıkılmaz, kullanıcı Face ID / parolasıyla onaylar ve adını paylaşmayı ya da "adresimi gizle"yi seçer.
  /// Alınan kimlik belgesi (+ ham nonce) `signInWithIdToken` ile Supabase'e verilir; oturum hemen açılır
  /// (`signedIn` olayı). Apple'dan gelen e-posta doğrulanmıştır, onay kodu gerekmez; KVKK / açık rıza kaydı yoksa
  /// açılış paketi rıza kutusunu gösterir.
  /// Supabase'de Apple sağlayıcısı kapalıysa hiçbir şey açılmaz ([appleProviderDisabledError]).
  Future<AuthActionResult> signInWithApple() => _action((auth) async {
        if (await fetchProviderEnabled('apple') == false) throw StateError(appleProviderDisabledError);
        final r = await nativeApple.obtainCredential();
        switch (r) {
          case NativeAppleCredential(:final idToken, :final rawNonce, :final fullName):
            final res = await auth.signInWithIdToken(
              provider: OAuthProvider.apple,
              idToken: idToken,
              nonce: rawNonce,
            );
            await _saveAppleFullName(auth, res.user, fullName);
            return;
          case NativeAppleCanceled():
            throw StateError(appleCanceledError);
          case NativeAppleUnavailable(:final reason):
            // Yetki eksik, iOS 13 öncesi, iCloud hesabı yok… Google ya da e-posta yolu açık kalır.
            throw StateError('Apple sign-in unavailable: $reason');
        }
      });

  /// Apple adı yalnızca kullanıcının uygulamaya **ilk** izin verdiği girişte gelir. Kullanıcı bilgisinde `full_name`
  /// yoksa bir kez yazılır (profil ve rutin metinleri bu adı kullanır); yazılamazsa giriş bozulmaz.
  Future<void> _saveAppleFullName(GoTrueClient auth, User? u, String? fullName) async {
    if (u == null || fullName == null || fullName.trim().isEmpty) return;
    final current = u.userMetadata?['full_name'];
    if (current is String && current.trim().isNotEmpty) return;
    try {
      await auth.updateUser(UserAttributes(data: {'full_name': fullName.trim()}));
    } catch (_) {
      /* ad sonradan Ben → Profil'den yazılabilir */
    }
  }

  /// Onay e-postasını (yeni kod + düğme) yeniden gönderir; önceki e-postadaki kod ve bağlantı geçersiz olur.
  Future<AuthActionResult> resendConfirmation(String email) =>
      _action((auth) => auth.resend(type: OtpType.signup, email: email, emailRedirectTo: authCallbackUrl));

  /// Parola sıfırlama bağlantısı gönderir. Supabase adresin kayıtlı olup olmadığını belli etmez.
  Future<AuthActionResult> sendPasswordReset(String email) =>
      _action((auth) => auth.resetPasswordForEmail(email, redirectTo: authCallbackUrl));

  /// Sıfırlama e-postasındaki 6 haneli kodla yeni parolayı kaydeder (bağlantı tarayıcılarının tüketebildiği tek
  /// kullanımlık bağlantı yerine). Önce kod doğrulanır (bu, kullanıcı için oturum açar), sonra parola güncellenir.
  /// [verified] false ise kod yanlış/süresi dolmuş; true ama sonuç hatalıysa oturum açıktır ve parola reddedilmiştir
  /// (ör. zayıf ya da sızdırılmış): ekran "yeni parola belirle" kipine geçer, kullanıcı başka parola dener.
  Future<({AuthActionResult result, bool verified})> resetPasswordWithCode(String email, String code, String password) async {
    _codeResetUntil = DateTime.now().add(const Duration(seconds: 15));
    setAuthFlowInProgress(true);
    try {
      final verify = await _action((auth) => auth.verifyOTP(type: OtpType.recovery, email: email, token: code));
      if (!verify.ok) return (result: verify, verified: false);
      final update = await _action((auth) async {
        await auth.updateUser(UserAttributes(password: password));
      });
      recoveryPending = !update.ok;
      notifyListeners();
      return (result: update, verified: true);
    } finally {
      setAuthFlowInProgress(false);
    }
  }

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
    await nativeGoogle.signOut();
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
