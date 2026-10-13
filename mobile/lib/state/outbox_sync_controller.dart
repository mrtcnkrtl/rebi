import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../core/demo_user.dart';
import '../core/event_outbox.dart';
import 'auth_controller.dart';

/// Çevrimdışı olay kuyruğunu ([EventOutbox]) ne zaman göndereceğine karar verir:
/// oturum açılınca, uygulama öne gelince, kullanıcı "şimdi dene" deyince ve bekleyen
/// olay varken artan aralıklarla (30 sn → 1 dk → 2 dk → 5 dk).
/// Bağlantı durumu eklentisi kullanılmaz; gönderim başarısız oluyorsa ağ yoktur.
class OutboxSyncController extends ChangeNotifier with WidgetsBindingObserver {
  OutboxSyncController(
    this._auth, {
    EventOutbox? outbox,
    this.retryDelays = defaultRetryDelays,
  }) : outbox = outbox ?? EventOutbox.instance {
    WidgetsBinding.instance.addObserver(this);
    _auth.addListener(_onAuth);
    this.outbox.addListener(_onOutbox);
    _onAuth();
  }

  static const defaultRetryDelays = [
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 2),
    Duration(minutes: 5),
  ];

  final AuthController _auth;
  final EventOutbox outbox;
  final List<Duration> retryDelays;

  String? _uid;
  Timer? _timer;
  int _failures = 0;
  bool _flushing = false;
  bool _disposed = false;

  /// Oturumdaki kullanıcının gönderilmeyi bekleyen olay sayısı.
  int get pendingCount => _uid == null ? 0 : outbox.pendingCount(_uid!);

  void _onAuth() {
    final id = _auth.user?.id;
    final next = (id == null || id.isEmpty || id == demoUserId) ? null : id;
    if (next == _uid) return;
    _uid = next;
    _failures = 0;
    _timer?.cancel();
    _timer = null;
    _notify();
    if (next != null) unawaited(flushNow());
  }

  void _onOutbox() {
    _notify();
    if (pendingCount == 0) {
      _timer?.cancel();
      _timer = null;
      _failures = 0;
    } else {
      _schedule();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(flushNow());
  }

  /// Bekleyenleri hemen göndermeyi dener. Dönüş: sunucuya ulaşan olay sayısı.
  Future<int> flushNow() async {
    final uid = _uid;
    if (uid == null || _flushing) return 0;
    _timer?.cancel();
    _timer = null;
    if (outbox.pendingCount(uid) == 0) {
      _failures = 0;
      return 0;
    }
    _flushing = true;
    var delivered = 0;
    try {
      delivered = await outbox.flush(uid);
    } finally {
      _flushing = false;
    }
    if (_disposed) return delivered;
    if (_uid == uid && outbox.pendingCount(uid) > 0) {
      _failures++;
      _schedule();
    } else {
      _failures = 0;
    }
    _notify();
    return delivered;
  }

  void _schedule() {
    if (_disposed || _flushing || (_timer?.isActive ?? false) || retryDelays.isEmpty) return;
    final delay = retryDelays[math.min(_failures, retryDelays.length - 1)];
    _timer = Timer(delay, () => unawaited(flushNow()));
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _auth.removeListener(_onAuth);
    outbox.removeListener(_onOutbox);
    super.dispose();
  }
}
