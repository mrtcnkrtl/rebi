import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// Apple'ın yerel giriş sayfasının (ASAuthorization) sonucu.
sealed class NativeAppleResult {
  const NativeAppleResult();
}

/// Giriş tamamlandı. [idToken] Apple'ın imzaladığı kimlik belgesidir; Supabase'e `signInWithIdToken` ile,
/// [rawNonce] ile birlikte verilir (belgenin içindeki `nonce` bunun SHA-256 özetidir, Supabase karşılaştırır).
/// [fullName] yalnızca kullanıcının bu uygulamaya **ilk** izni verdiği anda gelir; sonraki girişlerde `null`'dur,
/// bu yüzden ilk seferde kullanıcı bilgisine yazılır.
class NativeAppleCredential extends NativeAppleResult {
  const NativeAppleCredential({required this.idToken, required this.rawNonce, this.fullName, this.email});

  final String idToken;
  final String rawNonce;
  final String? fullName;

  /// Apple "adresimi gizle"yi seçtiyse `…@privaterelay.appleid.com` olur; yine de gerçek bir adrestir.
  final String? email;
}

/// Kullanıcı Apple sayfasını kapattı: hata gösterilmez.
class NativeAppleCanceled extends NativeAppleResult {
  const NativeAppleCanceled();
}

/// Apple ile giriş bu cihazda/derlemede çalışmıyor (iOS 13 öncesi, yetki (entitlement) eksik, iCloud hesabı yok…).
class NativeAppleUnavailable extends NativeAppleResult {
  const NativeAppleUnavailable(this.reason);
  final String reason;
}

/// "Apple ile devam et"in yerel yolu. Apple'ın kendi sayfası uygulamanın içinde açılır (tarayıcıya çıkılmaz);
/// kullanıcı adını ve e-postasını paylaşmayı ya da "adresimi gizle"yi seçer. Supabase tarafında yalnızca
/// Apple sağlayıcısının açık olması ve Client IDs listesinde paket kimliğinin (`com.rebiovil.mobile`) bulunması
/// yeterlidir: yerel akışta Services ID / gizli anahtar gerekmez (bkz. docs/MOBIL-GIRIS-SUPABASE.md §2.5).
///
/// iOS'ta yetki (`Runner.entitlements` → `com.apple.developer.applesignin`) ve Apple Developer'daki App ID
/// yeteneği şarttır; yoksa Apple `authorization-error/unknown` döner ve düğme çalışmaz.
class NativeAppleSignIn {
  NativeAppleSignIn({@visibleForTesting String Function()? nonceSource}) : _nonce = nonceSource ?? generateNonce;

  final String Function() _nonce;

  /// Yalnız Apple platformları. Android/web'de Apple ile giriş tarayıcı üzerinden yürür; Rebi'de gösterilmez
  /// (oralarda Google ile devam et vardır).
  bool get available =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS);

  Future<NativeAppleResult> obtainCredential() async {
    if (!available) return const NativeAppleUnavailable('platform');
    final rawNonce = _nonce();
    try {
      final c = await SignInWithApple.getAppleIDCredential(
        scopes: const [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
        // Apple belgenin içine özeti koyar; ham değer Supabase'e verilir (yanıt tekrar oynatma saldırısına karşı).
        nonce: sha256.convert(utf8.encode(rawNonce)).toString(),
      );
      final token = c.identityToken;
      if (token == null || token.isEmpty) return const NativeAppleUnavailable('no-identity-token');
      return NativeAppleCredential(idToken: token, rawNonce: rawNonce, fullName: fullNameOf(c), email: c.email);
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) return const NativeAppleCanceled();
      return NativeAppleUnavailable('${e.code.name}: ${e.message}');
    } on SignInWithAppleNotSupportedException catch (e) {
      return NativeAppleUnavailable('not-supported: ${e.message}');
    } on SignInWithAppleException catch (e) {
      return NativeAppleUnavailable('apple: $e');
    } on PlatformException catch (e) {
      return NativeAppleUnavailable('platform: ${e.code}');
    } on MissingPluginException {
      return const NativeAppleUnavailable('plugin');
    }
  }

  /// Apple'ın verdiği ad parçalarını tek satıra çevirir; hiçbiri yoksa `null` (kullanıcı adını paylaşmamayı seçti).
  @visibleForTesting
  static String? fullNameOf(AuthorizationCredentialAppleID c) {
    final parts = [c.givenName, c.familyName]
        .whereType<String>()
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    return parts.isEmpty ? null : parts.join(' ');
  }
}
