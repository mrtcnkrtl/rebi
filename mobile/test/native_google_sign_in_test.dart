import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:rebi/core/native_google_sign_in.dart';

/// Android Credential Manager yerine geçen sahte platform: [result] dönülür ya da [error] fırlatılır.
class _FakePlatform extends GoogleSignInPlatform with MockPlatformInterfaceMixin {
  AuthenticationResults? result;
  GoogleSignInException? error;
  InitParameters? lastInit;
  int inits = 0;

  @override
  Future<void> init(InitParameters params) async {
    lastInit = params;
    inits++;
  }

  @override
  bool supportsAuthenticate() => true;

  @override
  Future<AuthenticationResults> authenticate(AuthenticateParameters params) async {
    if (error != null) throw error!;
    return result!;
  }

  @override
  Future<AuthenticationResults?>? attemptLightweightAuthentication(AttemptLightweightAuthenticationParameters params) =>
      null;

  @override
  bool authorizationRequiresUserInteraction() => false;

  @override
  Future<ClientAuthorizationTokenData?> clientAuthorizationTokensForScopes(ClientAuthorizationTokensForScopesParameters params) async =>
      null;

  @override
  Future<ServerAuthorizationTokenData?> serverAuthorizationTokensForScopes(ServerAuthorizationTokensForScopesParameters params) async =>
      null;

  @override
  Future<void> signOut(SignOutParams params) async {}

  @override
  Future<void> disconnect(DisconnectParams params) async {}
}

void main() {
  late _FakePlatform platform;
  setUp(() => GoogleSignInPlatform.instance = platform = _FakePlatform());

  AuthenticationResults ok(String? token) => AuthenticationResults(
        user: const GoogleSignInUserData(email: 'a@b.com', id: '1'),
        authenticationTokens: AuthenticationTokenData(idToken: token),
      );

  test('hesap seçilince Web client için kimlik belgesi döner; başlatma bir kez yapılır', () async {
    platform.result = ok('id-token');
    final g = NativeGoogleSignIn();
    expect(g.available, isTrue, reason: 'test platformu Android');
    final r = await g.obtainIdToken();
    expect(r, isA<NativeGoogleToken>().having((t) => t.idToken, 'idToken', 'id-token'));
    expect(platform.lastInit!.serverClientId, endsWith('.apps.googleusercontent.com'));
    await g.obtainIdToken();
    expect(platform.inits, 1);
  });

  test('seçici kapatılırsa vazgeçildi sayılır', () async {
    platform.error = const GoogleSignInException(code: GoogleSignInExceptionCode.canceled);
    expect(await NativeGoogleSignIn().obtainIdToken(), isA<NativeGoogleCanceled>());
  });

  test('yapılandırma hatası (SHA-1 / Android client yok) tarayıcı akışına düşürür ve yeniden başlatmaya izin verir', () async {
    platform.error = const GoogleSignInException(code: GoogleSignInExceptionCode.clientConfigurationError, description: 'x');
    final g = NativeGoogleSignIn();
    expect(await g.obtainIdToken(), isA<NativeGoogleUnavailable>());
    platform
      ..error = null
      ..result = ok('t2');
    expect(await g.obtainIdToken(), isA<NativeGoogleToken>());
    expect(platform.inits, 2);
  });

  test('kimlik belgesi gelmezse tarayıcı akışına düşülür', () async {
    platform.result = ok(null);
    expect(await NativeGoogleSignIn().obtainIdToken(), isA<NativeGoogleUnavailable>());
  });
}
