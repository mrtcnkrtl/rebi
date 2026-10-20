import 'package:flutter/material.dart' show Checkbox, Key, TextFormField;
import 'package:flutter_test/flutter_test.dart';
import 'package:rebi/core/auth_errors.dart';
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
  AuthActionResult resetResult = const AuthActionResult();
  AuthActionResult updateResult = const AuthActionResult();
  final calls = <String>[];

  @override
  Future<SignInResult> signIn(String email, String password) async {
    calls.add('signIn $email');
    if (signInResult.user != null) debugSetUser(signInResult.user);
    return signInResult;
  }

  @override
  Future<SignUpResult> signUp(String email, String password, String fullName) async {
    calls.add('signUp $email $fullName');
    return signUpResult;
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
    testWidgets('yanlış parola: ham İngilizce mesaj yerine anlaşılır cümle', (tester) async {
      final fake = FakeAuth();
      await pumpApp(tester, location: '/auth', loggedIn: false, authController: fake);
      await _fillLogin(tester);
      await _acceptLegal(tester);
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
      await _acceptLegal(tester);
      await _submit(tester);
      expect(find.text(tr('mobileAuth.errEmailNotConfirmed')), findsOneWidget);

      await tapFinder(tester, find.byKey(const Key('auth-resend')));
      expect(fake.calls, contains('resend ayse@ornek.com'));
      expect(find.text(tr('mobileAuth.resendSent')), findsOneWidget);
    });

    testWidgets('sunucuya ulaşılamazsa ağ mesajı gösterilir', (tester) async {
      final fake = FakeAuth()..signInResult = const SignInResult(error: 'SocketException', kind: AuthErrorKind.network, networkError: true);
      await pumpApp(tester, location: '/auth', loggedIn: false, authController: fake);
      await _fillLogin(tester);
      await _acceptLegal(tester);
      await _submit(tester);
      expect(find.text(tr('mobileAuth.errNetwork')), findsOneWidget);
    });

    testWidgets('başarılı giriş rıza kaydını backend\'e yazar ve panele geçer', (tester) async {
      final fake = FakeAuth()..signInResult = SignInResult(user: fakeUser());
      final h = await pumpApp(tester, location: '/auth', loggedIn: false, authController: fake);
      await _fillLogin(tester);
      await _acceptLegal(tester);
      await _submit(tester);
      await settle(tester, 6);
      final body = h.backend.bodyOf('/legal-consent/accept');
      expect(body['user_id'], testUserId);
      expect(h.router.routeInformationProvider.value.uri.path, '/dashboard');
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

    testWidgets('e-posta onayı gerekiyorsa girişe döner, bilgi verir ve tekrar gönderme sunar', (tester) async {
      final fake = FakeAuth()..signUpResult = const SignUpResult(needsEmailConfirmation: true);
      await openSignup(tester, fake);
      expect(fake.calls, contains('signUp ayse@ornek.com Ayşe Test'));
      expect(find.text(tr('mobileAuth.signupSent')), findsOneWidget);
      expect(find.text(tr('auth.welcome')), findsOneWidget, reason: 'giriş kipine dönmeli');
      expect(find.byKey(const Key('auth-resend')), findsOneWidget);
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
