import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/consent_recovery.dart';
import '../core/demo_user.dart';
import '../core/user_snapshot.dart';
import 'auth_controller.dart';

/// Açılış senkronu (`docs/MOBIL-API.md` → "Açılış akışı"): oturum açılınca `GET /me/snapshot`
/// ile profil, yürürlükteki rutin, bugünün ilerlemesi ve rıza durumu tek çağrıda alınır.
/// Rıza eksikse yapay zekâ uçları 403 döneceği için kullanıcı baştan onay kutusuna alınır.
class HomeSyncController extends ChangeNotifier {
  HomeSyncController(this._auth) {
    _auth.addListener(_onAuth);
    consentChanges.addListener(_onConsentChanged);
    _onAuth();
  }

  final AuthController _auth;

  UserSnapshot? snapshot;

  String? _uid;
  Future<UserSnapshot?>? _inflight;
  int _generation = 0;
  bool _refreshAgain = false;
  bool _disposed = false;

  String? get _currentUserId {
    final id = _auth.user?.id;
    return (id == null || id.isEmpty || id == demoUserId) ? null : id;
  }

  void _onAuth() {
    // Giriş/kayıt ekranı rıza kaydını bitirmeden yüklenirse rıza kutusu boşuna açılır.
    if (_auth.authFlowInProgress) return;
    final next = _currentUserId;
    if (next == _uid) return;
    _uid = next;
    _generation++;
    _inflight = null;
    _refreshAgain = false;
    snapshot = null;
    _notify();
    if (next != null) unawaited(refresh());
  }

  void _onConsentChanged() {
    if (_uid == null) return;
    // Yükleme sürerken izin değiştiyse o yanıt eskidir: bitince bir kez daha çek.
    if (_inflight != null) {
      _refreshAgain = true;
      return;
    }
    unawaited(refresh());
  }

  /// Paketi sunucudan yeniden okur; sürmekte olan bir istek varsa onu paylaşır.
  /// Başarısızlıkta null döner (eldeki eski paket `snapshot`ta kalır).
  Future<UserSnapshot?> refresh() {
    final uid = _uid;
    if (uid == null) return Future.value(null);
    return _inflight ??= _load(uid, _generation);
  }

  Future<UserSnapshot?> _load(String uid, int generation) async {
    UserSnapshot? result;
    try {
      result = await fetchMeSnapshot(uid);
    } catch (_) {
      /* çevrimdışı: panel yerel kopyayla açılır */
    }
    if (_disposed || generation != _generation) return null;
    _inflight = null;
    final stale = _refreshAgain;
    _refreshAgain = false;
    if (result != null) {
      snapshot = result;
      if (!stale && result.synced && !result.consent.complete) requestConsentRecovery();
    }
    _notify();
    if (stale) unawaited(refresh());
    return result;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _auth.removeListener(_onAuth);
    consentChanges.removeListener(_onConsentChanged);
    super.dispose();
  }
}
