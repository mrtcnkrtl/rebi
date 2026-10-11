import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/api.dart';

class SignUpResult {
  const SignUpResult({this.user, this.error, this.networkError = false, this.needsEmailConfirmation = false});

  final User? user;
  final String? error;
  final bool networkError;
  final bool needsEmailConfirmation;
}

class SignInResult {
  const SignInResult({this.user, this.error, this.networkError = false});

  final User? user;
  final String? error;
  final bool networkError;
}

/// Webdeki "Failed to fetch" karşılığı: sunucuya hiç ulaşılamadı.
bool _isNetwork(Object e) => e is AuthRetryableFetchException || isNetworkError(e);

/// Web `AuthContext` karşılığı: oturum durumu + giriş/kayıt/çıkış.
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
    _sub = client.auth.onAuthStateChange.listen((data) {
      final next = data.session?.user;
      if (next?.id == user?.id && identical(next, user)) return;
      user = next;
      notifyListeners();
    });
  }

  User? user;
  bool loading = true;
  StreamSubscription<AuthState>? _sub;

  /// Giriş/kayıt ekranı rıza kaydını tamamlayana kadar yönlendirme yapılmaz.
  /// Web'de oturum açılır açılmaz `/auth` sayfası söküldüğü için rıza hatası
  /// kullanıcıya gösterilemiyordu; mobilde ekran işini bitirene kadar beklenir.
  bool authFlowInProgress = false;

  void setAuthFlowInProgress(bool v) {
    if (authFlowInProgress == v) return;
    authFlowInProgress = v;
    notifyListeners();
  }

  Future<SignUpResult> signUp(String email, String password, String fullName) async {
    final client = supabase;
    if (client == null) return const SignUpResult(error: 'Supabase not configured');
    try {
      final res = await client.auth.signUp(email: email, password: password, data: {'full_name': fullName});
      final needs = res.user != null && res.session == null;
      return SignUpResult(user: res.user, needsEmailConfirmation: needs);
    } on AuthException catch (e) {
      return SignUpResult(error: e.message, networkError: _isNetwork(e));
    } catch (e) {
      return SignUpResult(error: e.toString(), networkError: _isNetwork(e));
    }
  }

  Future<SignInResult> signIn(String email, String password) async {
    final client = supabase;
    if (client == null) return const SignInResult(error: 'Supabase not configured');
    try {
      final res = await client.auth.signInWithPassword(email: email, password: password);
      return SignInResult(user: res.user);
    } on AuthException catch (e) {
      return SignInResult(error: e.message, networkError: _isNetwork(e));
    } catch (e) {
      return SignInResult(error: e.toString(), networkError: _isNetwork(e));
    }
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
    notifyListeners();
  }

  /// Testlerde oturumu Supabase olmadan değiştirmek için.
  @visibleForTesting
  void debugSetUser(User? next) {
    user = next;
    notifyListeners();
  }

  Future<void> refreshUser() async {
    final client = supabase;
    if (client == null) return;
    user = client.auth.currentSession?.user ?? client.auth.currentUser;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
