import 'package:flutter/material.dart' show AppLifecycleState, Checkbox, Key, TextFormField;
import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/core/auth_errors.dart';
import 'package:rebi/core/legal_consent.dart';
import 'package:rebi/state/auth_controller.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'helpers/app_harness.dart';

/// Giriş / kayıt / e-posta onayı / parola sıfırlama: Supabase ile uygulama arasındaki kopuk uçlar.
/// Supabase'e gerçek istek yoktur; `AuthController` sahtelenir, Supabase olaylarını işleyen gerçek kod ise
/// `debugEmit*` kancalarıyla çalıştırılır.
class FakeAuth extends AuthController {
  SignInResult signInResult = const SignInResult(error: 'Invalid login credentials', kind: AuthErrorKind.invalidCredentials);
  SignUpResult signUpResult = const SignUpResult(needsEmailConfirmation: true);
  AuthActionResult resendResult = const AuthActionResult();
  SignInResult verifyResult = const SignInResult(error: 'Token has expired or is invalid', kind: AuthErrorKind.linkInvalid);
  AuthActionResult resetResult = const AuthActionResult();
  AuthActionResult updateResult = const AuthActionResult();
  final calls = <String>[];

  /// Son `signUp` çağrısıyla gelen rıza seçimleri.
  ConsentPermissions? lastConsent;

  @override
  Future<SignInResult> signIn(String email, String password) async {
    calls.add('signIn $email');
    final u = signInResult.user;
    // Gerçek SDK gibi: giriş başarılıysa `signedIn` olayı yayılır (rıza eşitlemesi buradan başlar).
    if (u != null) debugEmitAuthState(AuthState(AuthChangeEvent.signedIn, Session(accessToken: 'tok', tokenType: 'bearer', user: u)));
    return signInResult;
  }

  @override
  Future<SignUpResult> signUp(String email, String password, String fullName, {ConsentPermissions? consent}) async {
    calls.add('signUp $email $fullName');
    lastConsent = consent;
    return signUpResult;
  }

  @override
  Future<SignInResult> verifySignupCode(String email, String code) async {
    calls.add('verify $email $code');
    final u = verifyResult.user;
    // Gerçek SDK gibi: kod doğruysa oturum açılır ve `signedIn` olayı yayılır.
    if (u != null) debugEmitAuthState(AuthState(AuthChangeEvent.signedIn, Session(accessToken: 'tok', tokenType: 'bearer', user: u)));
    return verifyResult;
  }

  @override
  Future<AuthActionResult> resendConfirmation(String email) async {
    calls.add('resend $email');
    return resendResult;
  }

  @override
  Future<AuthActionResult> sendPasswordReset(String email) async {
    calls.add('reset $email');
    return resetResult;
  }

  @override
  Future<AuthActionResult> updatePassword(String password) async {
    calls.add('update $password');
    if (updateResult.ok) {
      recoveryPending = false;
      notifyListeners();
    }
    return updateResult;
  }

  @override
  Future<void> signOut() async {
    calls.add('signOut');
    user = null;
    recoveryPending = false;
    notifyListeners();
  }
}

User _user({List<UserIdentity>? identities}) => User(
      id: 'u1',
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: '2026-10-20T10:00:00Z',
      email: 'ayse@ornek.com',
      identities: identities,
    );

const _identity = UserIdentity(
  id: 'i1',
  userId: 'u1',
  identityData: {},
  identityId: 'i1',
  provider: 'email',
  createdAt: '2026-10-20T10:00:00Z',
  lastSignInAt: '2026-10-20T10:00:00Z',
);

Session _session() => Session(accessToken: 'tok', tokenType: 'bearer', user: _user(identities: const [_identity]));

Future<void> _acceptLegal(WidgetTester tester) async {
  final boxes = find.byType(Checkbox);
  await tapFinder(tester, boxes.at(0));
  await tapFinder(tester, boxes.at(1));
}

Future<void> _submit(WidgetTester tester) => tapFinder(tester, find.byKey(const Key('auth-submit')).first);

Future<void> _fillLogin(WidgetTester tester, {String email = 'ayse@ornek.com', String password = 'parola123'}) async {
  await tester.enterText(find.byType(TextFormField).at(0), email);
  await tester.enterText(find.byType(TextFormField).at(1), password);
  await settle(tester, 4);
}

/// Uygulamayı arka plana atıp geri getirir (geçerli yaşam döngüsü geçişleriyle: e-posta uygulamasına gidip dönmek).
void _backgroundAndResume(WidgetTester tester) {
  for (final s in const [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(s);
  }
}

void main() {
  group('hata sınıflandırma', () {
    test('Supabase hata kodları ve eski İngilizce mesajlar doğru türe düşer', () {
      AuthErrorKind k(String m, {String? code, bool net = false}) => classifyAuthError(m, code: code, network: net);
      expect(k('x', code: 'invalid_credentials'), AuthErrorKind.invalidCredentials);
      expect(k('Invalid login credentials'), AuthErrorKind.invalidCredentials);
      expect(k('x', code: 'email_not_confirmed'), AuthErrorKind.emailNotConfirmed);
      expect(k('Email not confirmed'), AuthErrorKind.emailNotConfirmed);
      expect(k('x', code: 'user_already_exists'), AuthErrorKind.alreadyRegistered);
      expect(k('x', code: 'email_exists'), AuthErrorKind.alreadyRegistered);
      expect(k('User already registered'), AuthErrorKind.alreadyRegistered);
      expect(k('x', code: 'weak_password'), AuthErrorKind.weakPassword);
      expect(k('Password should be at least 6 characters'), AuthErrorKind.weakPassword);
      expect(k('x', code: 'same_password'), AuthErrorKind.samePassword);
      expect(k('x', code: 'over_email_send_rate_limit'), AuthErrorKind.rateLimited);
      expect(k('email rate limit exceeded'), AuthErrorKind.rateLimited);
      expect(k('Email link is invalid or has expired'), AuthErrorKind.linkInvalid);
      expect(k('x', code: 'otp_expired'), AuthErrorKind.linkInvalid);
      expect(k('Error sending confirmation email'), AuthErrorKind.emailSendFailed);
      expect(k('anything', net: true), AuthErrorKind.network);
      expect(k('bilinmeyen bir şey'), AuthErrorKind.other);
    });

    test('kayıtlı adresle kayıt: Supabase hata vermez, kimliksiz kullanıcı döner', () {
      final existing = signUpResultFromResponse(AuthResponse(user: _user(identities: const [])));
      expect(existing.alreadyRegistered, isTrue);
      expect(existing.needsEmailConfirmation, isFalse, reason: 'e-posta gitmedi: "onay e-postası gönderdik" denmemeli');

      final fresh = signUpResultFromResponse(AuthResponse(user: _user(identities: const [_identity])));
      expect(fresh.alreadyRegistered, isFalse);
      expect(fresh.needsEmailConfirmation, isTrue);

      final confirmed = signUpResultFromResponse(AuthResponse(user: _user(identities: const [_identity]), session: _session()));
      expect(confirmed.needsEmailConfirmation, isFalse);
      expect(confirmed.alreadyRegistered, isFalse);
    });
  });

  group('oturum olayları', () {
    test('parola sıfırlama olayı bekleyen sıfırlamayı açar, çıkış kapatır', () {
      final auth = AuthController();
      addTearDown(auth.dispose);
      auth.debugEmitAuthState(AuthState(AuthChangeEvent.passwordRecovery, _session()));
      expect(auth.recoveryPending, isTrue);
      expect(auth.user?.id, 'u1');
      auth.debugEmitAuthState(const AuthState(AuthChangeEvent.signedOut, null));
      expect(auth.recoveryPending, isFalse);
      expect(auth.user, isNull);
    });

    test('geçersiz bağlantı hatası yakalanır ve bir kez saklanır; oturum açıksa yok sayılır', () {
      final auth = AuthController();
      addTearDown(auth.dispose);
      auth.debugEmitStreamError(const AuthException('Email link is invalid or has expired', code: 'otp_expired'));
      expect(auth.linkError, isNotNull);
      auth.clearLinkError();
      expect(auth.linkError, isNull);

      auth.debugSetUser(_user());
      auth.debugEmitStreamError(const AuthException('eski bağlantı'));
      expect(auth.linkError, isNull);
    });
  });

  group('giriş ekranı', () {
    testWidgets('yasal metin ve onay kutusu yok; yalnız e-posta + parola ile gönderilebilir', (tester) async {
      final fake = FakeAuth();
      await pumpApp(tester, location: '/auth', loggedIn: false, authController: fake);
      expect(find.byType(Checkbox), findsNothing);
      expect(find.text(tr('auth.legalRequired')), findsNothing);
      expect(find.textContaining(tr('auth.kvkkLink')), findsNothing);
      await _fillLogin(tester);
      await _submit(tester);
      expect(fake.calls, ['signIn ayse@ornek.com'], reason: 'onay kutusu şartı olmadan gönderilir');
    });

    testWidgets('yanlış parola: ham İngilizce mesaj yerine anlaşılır cümle', (tester) async {
      final fake = FakeAuth();
      await pumpApp(tester, location: '/auth', loggedIn: false, authController: fake);
      await _fillLogin(tester);
      await _submit(tester);
      expect(find.text(tr('mobileAuth.errInvalidCredentials')), findsOneWidget);
      expect(find.text('Invalid login credentials'), findsNothing);
      expect(find.byKey(const Key('auth-resend')), findsNothing);
    });

    testWidgets('e-posta onaysız: açıklama + onay e-postasını tekrar gönder çalışır', (tester) async {
      final fake = FakeAuth()
        ..signInResult = const SignInResult(error: 'Email not confirmed', kind: AuthErrorKind.emailNotConfirmed);
      await pumpApp(tester, location: '/auth', loggedIn: false, authController: fake);
      await _fillLogin(tester);
      await _submit(tester);
      expect(find.text(tr('mobileAuth.errEmailNotConfirmed')), findsOneWidget);

      await tapFinder(tester, find.byKey(const Key('auth-resend')));
      expect(fake.calls, contains('resend ayse@ornek.com'));
      expect(find.text(tr('mobileAuth.resendSent')), findsOneWidget);
      expect(find.text(tr('mobileAuth.verifyTitle')), findsOneWidget, reason: 'yeni e-postadaki kod yazılabilsin diye kod ekranına geçilir');
    });

    testWidgets('sunucuya ulaşılamazsa ağ mesajı gösterilir', (tester) async {
      final fake = FakeAuth()..signInResult = const SignInResult(error: 'SocketException', kind: AuthErrorKind.network, networkError: true);
      await pumpApp(tester, location: '/auth', loggedIn: false, authController: fake);
      await _fillLogin(tester);
      await _submit(tester);
      expect(find.text(tr('mobileAuth.errNetwork')), findsOneWidget);
    });

    testWidgets('rızası zaten kayıtlı kullanıcı: rıza yazılmaz, panele geçilir', (tester) async {
      final fake = FakeAuth()..signInResult = SignInResult(user: fakeUser());
      final h = await pumpApp(tester, location: '/auth', loggedIn: false, authController: fake);
      await _fillLogin(tester);
      await _submit(tester);
      await settle(tester, 6);
      expect(h.backend.calls('/legal-consent/status'), isEmpty, reason: 'kayıtta bekleyen rıza yok: sunucuya sorulmaz');
      expect(h.backend.calls('/legal-consent/accept'), isEmpty);
      expect(h.router.routeInformationProvider.value.uri.path, '/dashboard');
    });
  });

  group('kayıttaki rızanın ilk girişte kayda geçmesi', () {
    User pendingUser({bool location = false, bool photo = false}) => User(
          id: testUserId,
          appMetadata: const {},
          userMetadata: {
            'full_name': 'Ayşe Test',
            'legal_consent': legalConsentMetadata(ConsentPermissions(ai: true, location: location, photo: photo)),
          },
          aud: 'authenticated',
          createdAt: '2026-10-20T10:00:00Z',
          email: 'ayse@ornek.com',
        );

    testWidgets('girişte bekleyen rıza sunucuya yazılır (kutu sormadan) ve panele geçilir', (tester) async {
      final fake = FakeAuth()..signInResult = SignInResult(user: pendingUser(location: true));
      final h = await pumpApp(tester, location: '/auth', loggedIn: false, authController: fake);
      await _fillLogin(tester);
      await _submit(tester);
      await settle(tester, 8);
      final body = h.backend.bodyOf('/legal-consent/accept');
      expect(body['user_id'], testUserId);
      expect(body['kvkk_accepted'], true);
      expect(body['explicit_consent_accepted'], true);
      expect(body['ai_processing_accepted'], true);
      expect(body['location_processing_accepted'], true, reason: 'kayıt formundaki seçim taşınır');
      expect(body['photo_processing_accepted'], false);
      expect(h.router.routeInformationProvider.value.uri.path, '/dashboard');
      expect(find.text(tr('common.consentRecoveryTitle')), findsNothing, reason: 'rıza kutusu açılmaz');
    });

    testWidgets('sunucuda zaten kayıt varsa üzerine yazılmaz (sonradan değiştirilen izinler korunur)', (tester) async {
      final backend = FakeBackend()..consentRecordedOnServer = true;
      final fake = FakeAuth()..signInResult = SignInResult(user: pendingUser(location: true));
      final h = await pumpApp(tester, location: '/auth', loggedIn: false, authController: fake, backend: backend);
      await _fillLogin(tester);
      await _submit(tester);
      await settle(tester, 8);
      expect(h.backend.calls('/legal-consent/status'), isNotEmpty);
      expect(h.backend.calls('/legal-consent/accept'), isEmpty);
      expect(h.router.routeInformationProvider.value.uri.path, '/dashboard');
    });

    testWidgets('rıza yazılamazsa giriş engellenmez: panel açılır, rıza kutusu yedek olur', (tester) async {
      final backend = FakeBackend()
        ..consentStatusFails = 500
        ..consentMissing = true
        ..snapshot = {
          ...FakeBackend().snapshot,
          'consent': {'legal_version': 'v2', 'legal_accepted': false, 'ai_processing_allowed': false},
        };
      final fake = FakeAuth()..signInResult = SignInResult(user: pendingUser());
      final h = await pumpApp(tester, location: '/auth', loggedIn: false, authController: fake, backend: backend);
      await _fillLogin(tester);
      await _submit(tester);
      await settle(tester, 8);
      expect(h.backend.calls('/legal-consent/accept'), isEmpty);
      expect(h.router.routeInformationProvider.value.uri.path, '/dashboard', reason: 'rıza hatası girişi kilitlemez');
      expect(find.text(tr('common.consentRecoveryTitle')), findsOneWidget, reason: 'yazılamayan rıza, rıza kutusuyla yeniden alınır');
    });

    testWidgets('e-posta onayı bağlantısıyla (ekransız) girişte de rıza yazılır', (tester) async {
      final fake = FakeAuth();
      final h = await pumpApp(tester, location: '/', loggedIn: false, authController: fake);
      // Bağlantı uygulamayı açınca SDK oturumu kurar ve `signedIn` yayar.
      fake.debugEmitAuthState(AuthState(AuthChangeEvent.signedIn, Session(accessToken: 'tok', tokenType: 'bearer', user: pendingUser(photo: true))));
      expect(fake.authFlowInProgress, isTrue, reason: 'rıza yazılırken açılış senkronu ve yönlendirme bekler');
      await fake.consentSync;
      await settle(tester, 6);
      expect(fake.authFlowInProgress, isFalse);
      final body = h.backend.bodyOf('/legal-consent/accept');
      expect(body['user_id'], testUserId);
      expect(body['photo_processing_accepted'], true);
    });
  });

  group('rıza yardımcıları', () {
    test('kayıt seçimleri metadata\'ya konur ve geri okunur', () {
      final meta = legalConsentMetadata(const ConsentPermissions(ai: true, location: true, photo: false));
      expect(meta['version'], legalConsentVersion);
      final back = pendingConsentFromMetadata({'legal_consent': meta})!;
      expect(back.ai, isTrue);
      expect(back.location, isTrue);
      expect(back.photo, isFalse);
    });

    test('eksik, eski sürüm ya da onaysız metadata bekleyen rıza sayılmaz', () {
      Map<String, dynamic> m(Map<String, dynamic> over) => {'legal_consent': {...legalConsentMetadata(const ConsentPermissions(ai: true)), ...over}};
      expect(pendingConsentFromMetadata(null), isNull);
      expect(pendingConsentFromMetadata(const {}), isNull);
      expect(pendingConsentFromMetadata({'legal_consent': 'x'}), isNull);
      expect(pendingConsentFromMetadata(m({'version': 'v1'})), isNull, reason: 'eski metin sürümü: yeniden onay gerekir');
      expect(pendingConsentFromMetadata(m({'kvkk': false})), isNull);
      expect(pendingConsentFromMetadata(m({'riza': false})), isNull);
      expect(pendingConsentFromMetadata(m({'ai': false})), isNull);
    });
  });

  group('kayıt', () {
    Future<void> openSignup(WidgetTester tester, FakeAuth fake) async {
      await pumpApp(tester, location: '/auth?mode=signup', loggedIn: false, authController: fake);
      await tester.enterText(find.byType(TextFormField).at(0), 'Ayşe Test');
      await tester.enterText(find.byType(TextFormField).at(1), 'ayse@ornek.com');
      await tester.enterText(find.byType(TextFormField).at(2), 'parola123');
      await settle(tester, 4);
      await _acceptLegal(tester);
      await _submit(tester);
    }

    testWidgets('e-posta onayı gerekiyorsa kod ekranına geçer: kod alanı, bilgi ve (beklemeli) tekrar gönderme', (tester) async {
      final fake = FakeAuth()..signUpResult = const SignUpResult(needsEmailConfirmation: true);
      await openSignup(tester, fake);
      expect(fake.calls, contains('signUp ayse@ornek.com Ayşe Test'));
      expect(fake.lastConsent?.ai, isTrue, reason: 'kayıttaki rıza, oturum açılınca yazılmak üzere gönderilir');
      expect(fake.lastConsent?.location, isFalse);
      expect(find.text(tr('mobileAuth.verifyTitle')), findsOneWidget, reason: 'kod ekranına geçmeli');
      expect(find.text(tr('mobileAuth.verifySubtitle', {'email': 'ayse@ornek.com'})), findsOneWidget);
      expect(find.text(tr('mobileAuth.signupSent')), findsOneWidget);
      expect(find.byType(TextFormField), findsOneWidget, reason: 'yalnız kod alanı; e-posta ve parola alanları gizli');
      expect(find.byKey(const Key('auth-resend')), findsOneWidget);
      await tapFinder(tester, find.byKey(const Key('auth-resend')));
      expect(fake.calls.where((c) => c.startsWith('resend')), isEmpty, reason: 'e-posta az önce gitti: bekleme süresinde tekrar gönderilmez');
    });

    testWidgets('kayıtlı adresle kayıt: "e-posta gönderdik" denmez, girişe ve sıfırlamaya yönlendirir', (tester) async {
      final fake = FakeAuth()..signUpResult = const SignUpResult(alreadyRegistered: true, kind: AuthErrorKind.alreadyRegistered);
      await openSignup(tester, fake);
      expect(find.text(tr('mobileAuth.errAlreadyRegistered')), findsOneWidget);
      expect(find.text(tr('mobileAuth.signupSent')), findsNothing);
      expect(find.text(tr('auth.welcome')), findsOneWidget);
      expect(find.byKey(const Key('auth-resend')), findsNothing, reason: 'gönderilmiş bir onay e-postası yok');
      expect(find.byKey(const Key('auth-forgot')), findsOneWidget);
    });

    testWidgets('zayıf parola ve e-posta gönderilemedi hataları anlaşılır gösterilir', (tester) async {
      final fake = FakeAuth()..signUpResult = const SignUpResult(error: 'Password should be at least 6 characters', kind: AuthErrorKind.weakPassword);
      await openSignup(tester, fake);
      expect(find.text(tr('mobileAuth.errWeakPassword')), findsOneWidget);
    });
  });

  group('e-posta onay kodu', () {
    /// Kayıt formunu doldurup gönderir; onay gerektiği için kod ekranında kalır.
    Future<(Harness, FakeAuth)> openVerify(WidgetTester tester, {FakeAuth? auth}) async {
      final fake = auth ?? FakeAuth();
      final h = await pumpApp(tester, location: '/auth?mode=signup', loggedIn: false, authController: fake);
      await tester.enterText(find.byType(TextFormField).at(0), 'Ayşe Test');
      await tester.enterText(find.byType(TextFormField).at(1), 'ayse@ornek.com');
      await tester.enterText(find.byType(TextFormField).at(2), 'parola123');
      await settle(tester, 4);
      await _acceptLegal(tester);
      await _submit(tester);
      expect(find.text(tr('mobileAuth.verifyTitle')), findsOneWidget);
      return (h, fake);
    }

    Future<void> enterCode(WidgetTester tester, String code) async {
      await tester.enterText(find.byType(TextFormField).first, code);
      await settle(tester, 6);
    }

    testWidgets('altı hane tamamlanınca kendiliğinden gönderilir; oturum açılır, kayıttaki rıza yazılır, panele geçilir', (tester) async {
      final user = User(
        id: testUserId,
        appMetadata: const {},
        userMetadata: {'full_name': 'Ayşe Test', 'legal_consent': legalConsentMetadata(const ConsentPermissions(ai: true, location: true))},
        aud: 'authenticated',
        createdAt: '2026-10-20T10:00:00Z',
        email: 'ayse@ornek.com',
      );
      final (h, fake) = await openVerify(tester, auth: FakeAuth()..verifyResult = SignInResult(user: user));
      await enterCode(tester, '482913');
      await settle(tester, 6);
      expect(fake.calls, contains('verify ayse@ornek.com 482913'), reason: 'altıncı hane girilince gönder düğmesine basmadan gider');
      expect(h.backend.bodyOf('/legal-consent/accept')['location_processing_accepted'], true, reason: 'kayıttaki seçim ilk oturumda yazılır');
      expect(h.router.routeInformationProvider.value.uri.path, '/dashboard');
    });

    testWidgets('yanlış ya da süresi dolmuş kod: anlaşılır mesaj, ekranda kalır, yeniden denenebilir', (tester) async {
      final (h, fake) = await openVerify(tester);
      await enterCode(tester, '000000');
      expect(find.text(tr('mobileAuth.errCodeInvalid')), findsOneWidget);
      expect(find.text('Token has expired or is invalid'), findsNothing, reason: 'ham İngilizce mesaj gösterilmez');
      expect(find.text(tr('mobileAuth.verifyTitle')), findsOneWidget);
      expect(h.router.routeInformationProvider.value.uri.path, '/auth');

      fake.verifyResult = SignInResult(user: fakeUser());
      await enterCode(tester, '111111');
      await settle(tester, 6);
      expect(h.router.routeInformationProvider.value.uri.path, '/dashboard');
    });

    testWidgets('eksik kod gönderilmez', (tester) async {
      final (_, fake) = await openVerify(tester);
      await enterCode(tester, '123');
      await _submit(tester);
      expect(find.text(tr('mobileAuth.verifyCodeShort')), findsOneWidget);
      expect(fake.calls.where((c) => c.startsWith('verify')), isEmpty);
      await enterCode(tester, '12ab34');
      expect((tester.widget(find.byType(TextFormField).first) as TextFormField).controller?.text, '1234', reason: 'yalnız rakam kabul edilir');
    });

    testWidgets('tekrar gönder bekleme süresi bitince açılır ve yeni kodu bildirir', (tester) async {
      final (_, fake) = await openVerify(tester);
      await tapFinder(tester, find.byKey(const Key('auth-resend')));
      expect(fake.calls.where((c) => c.startsWith('resend')), isEmpty);

      await tester.pump(const Duration(seconds: 61));
      await tapFinder(tester, find.byKey(const Key('auth-resend')));
      expect(fake.calls, contains('resend ayse@ornek.com'));
      expect(find.text(tr('mobileAuth.resendSent')), findsOneWidget);

      await tapFinder(tester, find.byKey(const Key('auth-resend')));
      expect(fake.calls.where((c) => c.startsWith('resend')).length, 1, reason: 'yeni gönderimle bekleme süresi yeniden başlar');
    });

    testWidgets('"Onayladım, devam et": onaylandıysa içeri alır', (tester) async {
      final (h, fake) = await openVerify(tester);
      fake.signInResult = SignInResult(user: fakeUser());
      await tapFinder(tester, find.byKey(const Key('auth-verify-continue')));
      await settle(tester, 6);
      expect(fake.calls, contains('signIn ayse@ornek.com'), reason: 'kayıtta yazılan e-posta + parola kullanılır');
      expect(h.router.routeInformationProvider.value.uri.path, '/dashboard');
    });

    testWidgets('"Onayladım, devam et": henüz onaylanmadıysa nedenini söyler ve kod ekranında bırakır', (tester) async {
      final (h, fake) = await openVerify(tester);
      fake.signInResult = const SignInResult(error: 'Email not confirmed', kind: AuthErrorKind.emailNotConfirmed);
      await tapFinder(tester, find.byKey(const Key('auth-verify-continue')));
      expect(find.text(tr('mobileAuth.errEmailNotConfirmed')), findsOneWidget);
      expect(find.text(tr('mobileAuth.verifyTitle')), findsOneWidget);
      expect(h.router.routeInformationProvider.value.uri.path, '/auth');
    });

    testWidgets('e-postadaki düğmeyle onaylayıp uygulamaya dönünce kendiliğinden giriş yapılır', (tester) async {
      final (h, fake) = await openVerify(tester);
      fake.signInResult = SignInResult(user: fakeUser());
      _backgroundAndResume(tester);
      await settle(tester, 8);
      expect(fake.calls, contains('signIn ayse@ornek.com'));
      expect(h.router.routeInformationProvider.value.uri.path, '/dashboard');
    });

    testWidgets('uygulamaya dönünce hesap henüz onaylı değilse sessiz kalır (hata göstermez)', (tester) async {
      final (h, fake) = await openVerify(tester);
      fake.signInResult = const SignInResult(error: 'Email not confirmed', kind: AuthErrorKind.emailNotConfirmed);
      _backgroundAndResume(tester);
      await settle(tester, 8);
      expect(fake.calls, contains('signIn ayse@ornek.com'));
      expect(find.text(tr('mobileAuth.errEmailNotConfirmed')), findsNothing);
      expect(find.text(tr('mobileAuth.verifyTitle')), findsOneWidget);
      expect(h.router.routeInformationProvider.value.uri.path, '/auth');
    });

    testWidgets('e-posta adresini değiştir: kayıt formuna döner, yazılanlar korunur', (tester) async {
      await openVerify(tester);
      await tapFinder(tester, find.byKey(const Key('auth-verify-change')));
      expect(find.text(tr('auth.createAccount')), findsOneWidget);
      expect(find.text('ayse@ornek.com'), findsOneWidget);
      expect(find.text('Ayşe Test'), findsOneWidget);
    });

    test('Supabase ayarsızken kodla onay "ayarlanmamış" döner (çökmez)', () async {
      final auth = AuthController();
      addTearDown(auth.dispose);
      final r = await auth.verifySignupCode('ayse@ornek.com', '123456');
      expect(r.kind, AuthErrorKind.notConfigured);
      expect(r.user, isNull);
    });
  });

  group('parolamı unuttum', () {
    testWidgets('giriş ekranından açılır; yalnız e-posta ister, rıza kutusu yok; bağlantı gönderilir', (tester) async {
      final fake = FakeAuth();
      await pumpApp(tester, location: '/auth', loggedIn: false, authController: fake);
      await tapFinder(tester, find.byKey(const Key('auth-forgot')));
      expect(find.text(tr('mobileAuth.forgotTitle')), findsOneWidget);
      expect(find.byType(TextFormField), findsOneWidget);
      expect(find.byType(Checkbox), findsNothing);

      await _submit(tester);
      expect(find.text('Lütfen bu alanı doldurun.'), findsOneWidget, reason: 'boş e-posta ile gönderilemez');
      expect(fake.calls, isEmpty);

      await tester.enterText(find.byType(TextFormField).first, 'ayse@ornek.com');
      await settle(tester, 4);
      await _submit(tester);
      expect(fake.calls, ['reset ayse@ornek.com']);
      expect(find.text(tr('mobileAuth.forgotSent')), findsOneWidget);

      await tapFinder(tester, find.byKey(const Key('auth-back-login')));
      expect(find.text(tr('auth.welcome')), findsOneWidget);
    });

    testWidgets('e-posta gönderilemezse hata gösterilir', (tester) async {
      final fake = FakeAuth()..resetResult = const AuthActionResult(error: 'Error sending recovery email', kind: AuthErrorKind.emailSendFailed);
      await pumpApp(tester, location: '/auth', loggedIn: false, authController: fake);
      await tapFinder(tester, find.byKey(const Key('auth-forgot')));
      await tester.enterText(find.byType(TextFormField).first, 'ayse@ornek.com');
      await settle(tester, 4);
      await _submit(tester);
      expect(find.text(tr('mobileAuth.errEmailSend')), findsOneWidget);
    });
  });

  group('sıfırlama bağlantısıyla yeni parola', () {
    Future<(Harness, FakeAuth)> openReset(WidgetTester tester) async {
      final fake = FakeAuth();
      final h = await pumpApp(tester, location: '/auth', loggedIn: false, authController: fake);
      // Bağlantı uygulamayı açınca supabase_flutter oturumu kurar ve bu olayı yayar.
      fake.debugEmitAuthState(AuthState(AuthChangeEvent.passwordRecovery, _session()));
      await settle(tester, 6);
      return (h, fake);
    }

    testWidgets('oturum açılsa da panele geçilmez; yeni parola ekranı çıkar', (tester) async {
      final (h, _) = await openReset(tester);
      expect(find.text(tr('mobileAuth.resetTitle')), findsOneWidget);
      expect(find.byType(TextFormField), findsNWidgets(2));
      expect(find.byType(Checkbox), findsNothing);

      h.router.go('/dashboard');
      await settle(tester, 6);
      expect(h.router.routeInformationProvider.value.uri.path, '/auth', reason: 'yeni parola belirlenmeden uygulamaya geçilemez');
    });

    testWidgets('parolalar uyuşmazsa kaydedilmez, uyuşunca kaydedilir ve panele geçilir', (tester) async {
      final (h, fake) = await openReset(tester);
      await tester.enterText(find.byType(TextFormField).at(0), 'yeniparola1');
      await tester.enterText(find.byType(TextFormField).at(1), 'baskaparola2');
      await settle(tester, 4);
      await _submit(tester);
      expect(find.text(tr('mobileAuth.resetMismatch')), findsOneWidget);
      expect(fake.calls.where((c) => c.startsWith('update')), isEmpty);

      await tester.enterText(find.byType(TextFormField).at(1), 'yeniparola1');
      await settle(tester, 4);
      await _submit(tester);
      await settle(tester, 6);
      expect(fake.calls, contains('update yeniparola1'));
      expect(h.router.routeInformationProvider.value.uri.path, '/dashboard');
    });

    testWidgets('vazgeçilirse oturum kapanır ve giriş ekranına dönülür', (tester) async {
      final (h, fake) = await openReset(tester);
      await tapFinder(tester, find.byKey(const Key('auth-cancel-reset')));
      await settle(tester, 6);
      expect(fake.calls, contains('signOut'));
      expect(find.text(tr('auth.welcome')), findsOneWidget);
      expect(h.router.routeInformationProvider.value.uri.path, '/auth');
    });
  });

  group('geçersiz e-posta bağlantısı', () {
    testWidgets('süresi dolmuş bağlantı giriş ekranında nedeniyle gösterilir (çökmez)', (tester) async {
      final fake = FakeAuth();
      final h = await pumpApp(tester, location: '/', loggedIn: false, authController: fake);
      fake.debugEmitStreamError(const AuthException('Email link is invalid or has expired', code: 'otp_expired'));
      await settle(tester, 8);
      expect(h.router.routeInformationProvider.value.uri.path, '/auth');
      expect(find.text(tr('mobileAuth.errLinkInvalid')), findsOneWidget);
      expect(fake.linkError, isNull, reason: 'bir kez gösterilip temizlenir');
      expect(find.byKey(const Key('auth-resend')), findsOneWidget);
    });
  });
}
