import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:rebi/core/native_apple_sign_in.dart';
import 'package:sign_in_with_apple_platform_interface/sign_in_with_apple_platform_interface.dart';

/// Apple'ın ASAuthorization sayfası yerine geçen sahte platform: [result] dönülür ya da [error] fırlatılır.
class _FakePlatform extends SignInWithApplePlatform with MockPlatformInterfaceMixin {
  AuthorizationCredentialAppleID? result;
  Object? error;

  /// İsteğe geçirilen değerler (nonce'un özetlenmiş hâlde gittiğini doğrulamak için).
  String? lastNonce;
  List<AppleIDAuthorizationScopes>? lastScopes;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<AuthorizationCredentialAppleID> getAppleIDCredential({
    required List<AppleIDAuthorizationScopes> scopes,
    WebAuthenticationOptions? webAuthenticationOptions,
    String? nonce,
    String? state,
  }) async {
    lastNonce = nonce;
    lastScopes = scopes;
    if (error != null) throw error!;
    return result!;
  }
}

AuthorizationCredentialAppleID _credential({
  String? identityToken = 'apple-id-token',
  String? givenName,
  String? familyName,
  String? email,
}) =>
    AuthorizationCredentialAppleID(
      userIdentifier: '001',
      givenName: givenName,
      familyName: familyName,
      email: email,
      authorizationCode: 'code',
      identityToken: identityToken,
      state: null,
    );

void main() {
  late _FakePlatform platform;
  setUp(() => SignInWithApplePlatform.instance = platform = _FakePlatform());

  // Test platformu Android'dir; Apple yolu yalnız iOS/macOS'ta çalıştığı için nonce'u sabitleyip
  // `obtainCredential`'ı doğrudan sınarız. Platform kapısı ayrı bir testte.
  NativeAppleSignIn signIn({String nonce = 'sabit-nonce'}) => NativeAppleSignIn(nonceSource: () => nonce);

  test('Android/web\'de Apple yolu kapalıdır', () {
    expect(NativeAppleSignIn().available, isFalse, reason: 'test platformu Android');
    expect(NativeAppleSignIn().obtainCredential(), completion(isA<NativeAppleUnavailable>()));
  });

  group('Apple platformu (yol açıkken)', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('ham nonce Supabase\'e, SHA-256 özeti Apple\'a gider; ad ve e-posta okunur', () async {
      platform.result = _credential(givenName: 'Ayşe', familyName: 'Yılmaz', email: 'a@b.com');
      final r = await signIn().obtainCredential();
      final c = r as NativeAppleCredential;
      expect(c.idToken, 'apple-id-token');
      expect(c.rawNonce, 'sabit-nonce');
      expect(c.fullName, 'Ayşe Yılmaz');
      expect(c.email, 'a@b.com');
      expect(platform.lastNonce, sha256.convert(utf8.encode('sabit-nonce')).toString());
      expect(platform.lastNonce, isNot('sabit-nonce'), reason: 'Apple\'a yalnız özet gider');
      expect(platform.lastScopes, containsAll(AppleIDAuthorizationScopes.values));
    });

    test('her denemede yeni nonce üretilir', () async {
      platform.result = _credential();
      final nonces = <String>{};
      for (var i = 0; i < 3; i++) {
        nonces.add(((await NativeAppleSignIn().obtainCredential()) as NativeAppleCredential).rawNonce);
      }
      expect(nonces, hasLength(3));
      expect(nonces.every((n) => n.length >= 16), isTrue);
    });

    test('kullanıcı adını paylaşmazsa ad boş kalır (sunucuda ezilmesin)', () async {
      platform.result = _credential(givenName: '', familyName: null);
      expect(((await signIn().obtainCredential()) as NativeAppleCredential).fullName, isNull);
    });

    test('yalnız ad verilirse tek parça kullanılır', () async {
      platform.result = _credential(givenName: 'Ayşe');
      expect(((await signIn().obtainCredential()) as NativeAppleCredential).fullName, 'Ayşe');
    });

    test('sayfa kapatılırsa vazgeçildi sayılır', () async {
      platform.error = const SignInWithAppleAuthorizationException(
        code: AuthorizationErrorCode.canceled,
        message: 'canceled',
      );
      expect(await signIn().obtainCredential(), isA<NativeAppleCanceled>());
    });

    test('yetki (entitlement) eksikse kullanılamaz döner, çökme olmaz', () async {
      platform.error = const SignInWithAppleAuthorizationException(
        code: AuthorizationErrorCode.unknown,
        message: 'authorization attempt failed',
      );
      final r = await signIn().obtainCredential();
      expect(r, isA<NativeAppleUnavailable>().having((u) => u.reason, 'reason', contains('unknown')));
    });

    test('iOS 13 öncesi: desteklenmiyor', () async {
      platform.error = const SignInWithAppleNotSupportedException(message: 'iOS 13+');
      expect(await signIn().obtainCredential(), isA<NativeAppleUnavailable>());
    });

    test('kimlik belgesi gelmezse kullanılamaz döner (Supabase\'e boş belge gitmez)', () async {
      platform.result = _credential(identityToken: null);
      expect(await signIn().obtainCredential(), isA<NativeAppleUnavailable>());
      platform.result = _credential(identityToken: '');
      expect(await signIn().obtainCredential(), isA<NativeAppleUnavailable>());
    });

    test('eklenti/platform hatası yutulur', () async {
      platform.error = PlatformException(code: 'x');
      expect(await signIn().obtainCredential(), isA<NativeAppleUnavailable>());
      platform.error = MissingPluginException();
      expect(await signIn().obtainCredential(), isA<NativeAppleUnavailable>());
    });
  });
}
