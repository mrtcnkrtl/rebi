import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/demo_user.dart';
import '../core/device_registration.dart';
import '../core/i18n.dart';
import '../core/notification_ports.dart';
import '../core/notification_prefs.dart';
import '../core/reminder_schedule.dart';
import '../core/reminder_text.dart';
import '../core/today_plan.dart';
import 'auth_controller.dart';

/// Hatırlatma bildirimleri (`docs/MOBIL-API.md` → "Bildirimler").
///
/// İki yol vardır ve aynı anda çalışmaz (aynı hatırlatıcı iki kez gelmesin):
/// - **Sunucu push'u:** cihaz FCM anahtarıyla `/devices/register`a kaydolur; sunucuda FCM açıksa
///   (`push_configured`) hatırlatıcıları sunucu gönderir.
/// - **Yerel bildirim:** sunucuda FCM yoksa (ya da Firebase bu derlemede kapalıysa) bugünün kalan
///   hatırlatıcıları ve yarının koşulsuz olanları telefona kurulur. Plan her değiştiğinde yeniden kurulur.
///
/// Bildirimler kullanıcı kendisi açana kadar kapalıdır.
class NotificationsController extends ChangeNotifier {
  NotificationsController(
    this._auth, {
    required this._notifier,
    this._push = const NoPushClient(),
    Future<String?> Function()? appVersion,
    String Function()? platform,
    DateTime Function()? clock,
  })  : _appVersion = appVersion ?? (() async => null),
        _platform = platform ?? (() => defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android'),
        _clock = clock ?? DateTime.now {
    _auth.addListener(_onAuth);
    _subs.add(_notifier.taps.listen(_open));
    _subs.add(_push.opened.listen(_open));
    _subs.add(_push.tokenRefreshes.listen((_) => unawaited(_register())));
    _onAuth();
    unawaited(_openFromLaunch());
  }

  final AuthController _auth;
  final ReminderNotifier _notifier;
  final PushClient _push;
  final Future<String?> Function() _appVersion;
  final String Function() _platform;
  final DateTime Function() _clock;
  final List<StreamSubscription<String>> _subs = [];

  /// Bildirime dokunulunca açılacak ekran; uygulama dinler, gidince null yapar.
  final ValueNotifier<String?> openRoute = ValueNotifier<String?>(null);

  String? _uid;
  String? _token;
  TodayPlan? _plan;
  String? _lastSignature;
  Future<void> _serial = Future.value();
  bool _disposed = false;

  /// Sunucu bu cihaza push gönderiyor: yerel bildirim kurulmaz.
  bool pushActive = false;

  /// Kullanıcı açmak istedi ama işletim sistemi izni vermedi (ya da sonradan kapattı).
  bool permissionBlocked = false;

  bool get supported => _notifier.supported;

  bool get enabled => notificationsEnabledFor(_uid) == true;

  /// Bugün paneldeki "bildirimleri aç" önerisi gösterilsin mi.
  bool get promptVisible =>
      supported && _uid != null && notificationsEnabledFor(_uid) == null && !notificationPromptDismissed(_uid);

  void _onAuth() {
    final id = _auth.user?.id;
    final next = (id == null || id.isEmpty || id == demoUserId) ? null : id;
    if (next == _uid) return;
    _uid = next;
    _token = null;
    _plan = null;
    _lastSignature = null;
    pushActive = false;
    permissionBlocked = false;
    if (next == null) {
      // Başka hesap açılınca önceki kullanıcının hatırlatmaları gelmesin.
      unawaited(_serialize(_notifier.cancelAll));
    } else if (enabled) {
      unawaited(_register());
    }
    _notify();
  }

  /// Bildirimleri açar: izin ister, cihazı kaydeder, hatırlatmaları kurar. Dönüş: izin verildi mi.
  Future<bool> enable() async {
    final uid = _uid;
    if (uid == null || !supported) return false;
    final granted = await _notifier.requestPermission();
    if (_disposed || uid != _uid) return false;
    if (granted && _push.available) await _push.requestPermission();
    permissionBlocked = !granted;
    if (!granted) {
      // Bir kez sorduk; üstüne gitme. Profil ekranında telefon ayarı ipucu görünür.
      await dismissNotificationPrompt(uid);
      _notify();
      return false;
    }
    await setNotificationsEnabled(uid, true);
    _notify();
    await _register();
    await _applySchedule();
    return true;
  }

  /// Bildirimleri kapatır; sunucuya `push_enabled: false` bildirilir, yerel bildirimler silinir.
  Future<void> disable() async {
    final uid = _uid;
    if (uid == null) return;
    await setNotificationsEnabled(uid, false);
    pushActive = false;
    _lastSignature = null;
    _notify();
    await _serialize(_notifier.cancelAll);
    await _register();
  }

  Future<void> dismissPrompt() async {
    final uid = _uid;
    if (uid == null) return;
    await dismissNotificationPrompt(uid);
    _notify();
  }

  /// Panelin güncel planını bildirir; yerel bildirimler buna göre yeniden kurulur.
  void syncReminders(TodayPlan? plan) {
    _plan = plan;
    unawaited(_applySchedule());
  }

  /// Çıkıştan hemen önce: yerel bildirimleri siler ve cihazı sunucudan kaldırır.
  /// Oturum kapanınca kimlik doğrulama gittiği için sonrasında yapılamaz.
  Future<void> prepareSignOut() async {
    final uid = _uid;
    final token = _token ?? (_push.available ? await _push.token() : null);
    _lastSignature = null;
    await _serialize(_notifier.cancelAll);
    if (uid != null && token != null) {
      try {
        await unregisterDevice(userId: uid, token: token).timeout(const Duration(seconds: 3));
      } catch (_) {
        /* ağ yok: sunucu geçersiz anahtarı kendi temizler */
      }
    }
  }

  Future<void> _register() async {
    final uid = _uid;
    if (uid == null || !_push.available) return;
    // Hiç seçim yapılmamışsa cihaz kaydedilmez; kullanıcı açınca ya da kapatınca kaydedilir.
    final choice = notificationsEnabledFor(uid);
    if (choice == null) return;
    try {
      final token = await _push.token();
      if (token == null || _disposed || uid != _uid) return;
      _token = token;
      final registration = await registerDevice(
        userId: uid,
        token: token,
        platform: _platform(),
        utcOffsetMinutes: _clock().timeZoneOffset.inMinutes,
        pushEnabled: choice,
        locale: I18n.instance.lang,
        appVersion: await _appVersion(),
      );
      if (_disposed || uid != _uid) return;
      pushActive = choice && registration != null && registration.pushConfigured && registration.synced;
    } catch (_) {
      pushActive = false;
    }
    _notify();
    await _applySchedule();
  }

  Future<void> _applySchedule() => _serialize(() async {
        final uid = _uid;
        if (uid == null || !supported) return;
        if (!enabled || pushActive) {
          // Kapalıysa ya da sunucu gönderiyorsa yerel bildirim kalmasın (çift bildirim olmaz).
          if (_lastSignature != null) {
            _lastSignature = null;
            await _notifier.cancelAll();
          }
          return;
        }
        final plan = _plan;
        if (plan == null) return;
        final i18n = I18n.instance;
        final items = planNotifications(
          today: plan.reminders,
          now: _clock(),
          textFor: (r) => r.title.isNotEmpty
              ? (title: reminderTitle(i18n, r), body: reminderBody(i18n, r, plan.weather))
              : (title: localReminderTitle(i18n, r.id), body: localReminderBody(i18n, r.id)),
        );
        final signature = '${i18n.lang}\n${scheduleSignature(items)}';
        if (signature == _lastSignature) return;
        if (!await _notifier.hasPermission()) {
          // Kullanıcı izni sistem ayarlarından geri almış.
          if (!permissionBlocked) {
            permissionBlocked = true;
            _notify();
          }
          return;
        }
        if (permissionBlocked) {
          permissionBlocked = false;
          _notify();
        }
        _lastSignature = signature;
        await _notifier.replaceAll(items);
      });

  /// Zamanlama işleri sırayla çalışır: iki eşzamanlı "hepsini sil + kur" birbirini bozmasın.
  Future<void> _serialize(Future<void> Function() job) {
    final next = _serial.then((_) => job()).catchError((Object _) {});
    _serial = next;
    return next;
  }

  Future<void> _openFromLaunch() async {
    try {
      final route = await _notifier.launchRoute() ?? await _push.initialOpened();
      if (route != null) _open(route);
    } catch (_) {
      /* başlatma bilgisi alınamadı: normal açılış */
    }
  }

  void _open(String route) {
    if (!_disposed) openRoute.value = route;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final s in _subs) {
      s.cancel();
    }
    _auth.removeListener(_onAuth);
    openRoute.dispose();
    super.dispose();
  }
}
