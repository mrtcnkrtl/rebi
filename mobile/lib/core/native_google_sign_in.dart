import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../config/env.dart';

/// Yerel Google hesap seçicisinin (Android Credential Manager) sonucu.
sealed class NativeGoogleResult {
  const NativeGoogleResult();
}

/// Hesap seçildi; Google'ın imzaladığı kimlik belgesi Supabase'e `signInWithIdToken` ile verilir.
class NativeGoogleToken extends NativeGoogleResult {
  const NativeGoogleToken(this.idToken);
  final String idToken;
}

/// Kullanıcı hesap seçicisini kapattı: hata gösterilmez.
class NativeGoogleCanceled extends NativeGoogleResult {
  const NativeGoogleCanceled();
}

/// Yerel akış bu cihazda/derlemede çalışmıyor (Google Play hizmetleri yok, Android client'ı / SHA-1 tanımsız…):
/// tarayıcıdaki Supabase OAuth akışına düşülür.
class NativeGoogleUnavailable extends NativeGoogleResult {
  const NativeGoogleUnavailable(this.reason);
  final String reason;
}

/// "Google ile devam et"in yerel yolu. Tarayıcı akışında Google hesap seçme ekranı Supabase'in adresini
/// (`<proje>.supabase.co`) gösterir; yerel seçicide ise Google Cloud onay ekranındaki uygulama adı ("Rebi") görünür.
/// Belgenin alıcısı (aud) Web client'tır ([Env.googleWebClientId]); Supabase'in Google ayarındaki Client IDs listesinde
/// bulunmalıdır. Android client'ı (paket adı + imza SHA-1'i) yalnızca uygulamanın kimliğini Google'a kanıtlar.
class NativeGoogleSignIn {
  NativeGoogleSignIn({GoogleSignIn? signIn}) : _signIn = signIn ?? GoogleSignIn.instance;

  final GoogleSignIn _signIn;
  Future<void>? _init;

  /// Yalnız Android (iOS'ta Google düğmesi gizli; web ayrı yoldan gider) ve Web client kimliği verilmişse.
  bool get available =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android && Env.googleWebClientId.trim().isNotEmpty;

  Future<NativeGoogleResult> obtainIdToken() async {
    if (!available) return const NativeGoogleUnavailable('platform');
    try {
      await (_init ??= _signIn.initialize(serverClientId: Env.googleWebClientId.trim()));
      if (!_signIn.supportsAuthenticate()) return const NativeGoogleUnavailable('authenticate');
      final account = await _signIn.authenticate(scopeHint: const ['email', 'profile']);
      final token = account.authentication.idToken;
      if (token == null || token.isEmpty) return const NativeGoogleUnavailable('no-id-token');
      return NativeGoogleToken(token);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return const NativeGoogleCanceled();
      // interrupted / uiUnavailable / clientConfigurationError / providerConfigurationError / unknownError:
      // tarayıcı akışı hâlâ çalışır, kullanıcı yarı yolda kalmasın.
      _init = null;
      return NativeGoogleUnavailable('${e.code.name}: ${e.description ?? ''}');
    } on PlatformException catch (e) {
      _init = null;
      return NativeGoogleUnavailable('platform: ${e.code}');
    } on MissingPluginException {
      return const NativeGoogleUnavailable('plugin');
    }
  }

  /// Çıkışta seçili Google hesabını da unutturur (sonraki girişte hesap yeniden sorulur). Hata yutulur.
  Future<void> signOut() async {
    if (!available || _init == null) return;
    try {
      await _signIn.signOut();
    } catch (_) {}
  }
}
