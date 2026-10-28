import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/daily_tracking.dart';
import '../core/demo_user.dart';
import '../core/device_registration.dart';
import '../core/i18n.dart';
import '../core/notification_actions.dart';
import '../core/notification_ports.dart';
import '../core/notification_prefs.dart';
import '../core/reminder_schedule.dart';
import '../core/reminder_text.dart';
import '../core/silence_budget.dart';
import '../core/today_plan.dart';
import 'auth_controller.dart';

/// Cihaz kaydı bu kadar süre yenilenmediyse uygulama öne gelince yenilenir (saat farkı, push durumu taze kalsın).
const reRegisterAfter = Duration(hours: 12);

/// "Test bildirimi" düğmesinin sonucu.
enum TestNotificationResult { scheduled, blocked, unavailable }

/// Hatırlatma bildirimleri (`docs/MOBIL-API.md` → "Bildirimler").
///
/// İki yol vardır ve aynı anda çalışmaz (aynı hatırlatıcı iki kez gelmesin):
/// - **Sunucu push'u:** cihaz FCM anahtarıyla `/devices/register`a kaydolur; sunucuda FCM açıksa
///   (`push_configured`) **ve** push dağıtıcısı yakın zamanda çalıştıysa (`dispatch_alive`) hatırlatıcıları
///   sunucu gönderir.
/// - **Yerel bildirim:** sunucuda FCM yoksa, dağıtıcı sustuysa ya da Firebase bu derlemede kapalıysa bugünün
///   kalan hatırlatıcıları ve sonraki birkaç günün koşulsuz olanları telefona kurulur. Plan her değiştiğinde
///   (iş kaydedilince, ayar değişince, uygulama öne gelince) yeniden kurulur.
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
    int Function()? utcOffsetMinutes,
  })  : _appVersion = appVersion ?? (() async => null),
        _platform = platform ?? (() => defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android'),
        _clock = clock ?? DateTime.now,
        _utcOffsetOverride = utcOffsetMinutes {
    _auth.addListener(_onAuth);
    _subs.add(_notifier.taps.listen(_open));
    _subs.add(_notifier.actions.listen((tap) => unawaited(_onAction(tap))));
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
  final int Function()? _utcOffsetOverride;
  final List<StreamSubscription<Object?>> _subs = [];
  final StreamController<String> _recorded = StreamController<String>.broadcast();

  /// Cihazın şu anki UTC farkı (dakika). Yolculukta ve yaz saati geçişinde değişir.
  int get _utcOffset => _utcOffsetOverride?.call() ?? _clock().timeZoneOffset.inMinutes;

  /// Bildirimdeki düğmeyle bir olay kaydedildi (olay tipi). Panel planını yeniden okur.
  Stream<String> get recordedActions => _recorded.stream;

  /// Bildirime dokunulunca açılacak ekran; uygulama dinler, gidince null yapar.
  final ValueNotifier<String?> openRoute = ValueNotifier<String?>(null);

  String? _uid;
  String? _token;
  TodayPlan? _plan;
  String? _lastSignature;
  Future<void> _serial = Future.value();
  bool _disposed = false;
  DateTime? _registeredAt;
  int? _registeredOffset;

  /// Sunucuda FCM açık ama push dağıtıcısı çalışmıyor: hatırlatmalar yerelden kurulur, uygulama öne gelince
  /// dağıtıcının dirilip dirilmediğine yeniden bakılır.
  bool _pushIdle = false;

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
    _registeredAt = null;
    _registeredOffset = null;
    _pushIdle = false;
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

  /// Uygulama öne geldi: izin geri alındı mı, saat dilimi değişti mi, sunucu push durumu ne, hangi bildirimler
  /// kurulu? Telefon uyurken değişen her şey burada yakalanır; plan [syncReminders] ile tazelenir.
  Future<void> onAppResumed() async {
    final uid = _uid;
    if (uid == null || !supported || _disposed) return;
    if (enabled) await _recheckPermission();
    if (_disposed || uid != _uid) return;
    if (_push.available && notificationsEnabledFor(uid) != null && _needsRegistration()) {
      await _register();
    } else {
      await _applySchedule();
    }
  }

  bool _needsRegistration() {
    final at = _registeredAt;
    if (at == null || _registeredOffset != _utcOffset) return true;
    return _pushIdle || _clock().difference(at) >= reRegisterAfter;
  }

  /// Sistem ayarlarından izin geri alındıysa (ya da geri verildiyse) durumu yansıtır.
  Future<void> _recheckPermission() async {
    final granted = await _notifier.hasPermission();
    if (_disposed) return;
    if (granted == !permissionBlocked) return;
    permissionBlocked = !granted;
    // İzin yokken kurulan liste boşa gider: geri gelince baştan kurulsun.
    _lastSignature = null;
    _notify();
  }

  /// "Test bildirimi": [ReminderNotifier.scheduleTest] ile 1 dakika sonra bir bildirim kurar. Uygulamayı kapatıp
  /// beklemek, bu telefonun (pil tasarrufu dahil) bildirimleri gerçekten iletip iletmediğini gösterir.
  Future<TestNotificationResult> sendTestNotification() async {
    if (!supported) return TestNotificationResult.unavailable;
    if (!await _notifier.hasPermission()) {
      permissionBlocked = true;
      _notify();
      return TestNotificationResult.blocked;
    }
    final i18n = I18n.instance;
    final ok = await _notifier.scheduleTest(
      title: i18n.t('mobileNotifications.test.notificationTitle'),
      body: i18n.t('mobileNotifications.test.notificationBody'),
    );
    return ok ? TestNotificationResult.scheduled : TestNotificationResult.unavailable;
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
      final offset = _utcOffset;
      final registration = await registerDevice(
        userId: uid,
        token: token,
        platform: _platform(),
        utcOffsetMinutes: offset,
        pushEnabled: choice,
        locale: I18n.instance.lang,
        appVersion: await _appVersion(),
      );
      if (_disposed || uid != _uid) return;
      final serverPush = choice && registration != null && registration.pushConfigured && registration.synced;
      final alive = registration?.dispatchAlive ?? false;
      // FCM açık olsa da dağıtıcı çalışmıyorsa kimse hatırlatma göndermez: yerel bildirime düşülür.
      _pushIdle = serverPush && !alive;
      pushActive = serverPush && alive;
      if (registration != null) {
        _registeredAt = _clock();
        _registeredOffset = offset;
      }
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
        final now = _clock();
        final items = planNotifications(
          today: remindersFor(plan),
          now: now,
          settings: plan.settings,
          userId: uid,
          textFor: (r) => r.title.isNotEmpty
              ? (title: reminderTitle(i18n, r), body: reminderBody(i18n, r, plan.weather, waterTarget: plan.waterTarget))
              : (title: localReminderTitle(i18n, r.id), body: localReminderBody(i18n, r.id, waterTarget: plan.waterTarget)),
          actionsFor: (r) => [
            for (final a in notificationQuickActions(r.id))
              NotificationActionSpec(notificationActionId(r.id, a), i18n.t('mobileToday.actions.${a.labelKey}')),
          ],
        );
        final signature = '${i18n.lang}\n${scheduleSignature(items)}';
        if (signature == _lastSignature) return;
        if (!await _notifier.hasPermission()) {
          // Kullanıcı izni sistem ayarlarından geri almış.
          _lastSignature = null;
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
        try {
          await _notifier.replaceAll(items);
          _lastSignature = signature;
        } on ScheduleIncomplete {
          // Bazı bildirimler kurulamadı: aynı liste bir sonraki senkronda yeniden denensin.
          _lastSignature = null;
          return;
        }
        try {
          await SilenceBudget.fromPlan(uid, plan, now).save();
        } catch (_) {
          /* özet yazılamadı: uygulama kapalıyken düğme basılınca kalan bildirimler susmaz, başka bir şey olmaz */
        }
      });

  /// Zamanlama işleri sırayla çalışır: iki eşzamanlı "hepsini sil + kur" birbirini bozmasın.
  Future<void> _serialize(Future<void> Function() job) {
    final next = _serial.then((_) => job()).catchError((Object _) {});
    _serial = next;
    return next;
  }

  /// Bildirimdeki düğmeye uygulama çalışırken dokunuldu: olay gönderilir (olmazsa kuyruğa alınır).
  /// Başka bir hesap için kurulmuş bildirimin düğmesi yok sayılır.
  Future<void> _onAction(NotificationActionTap tap) async {
    final uid = _uid;
    if (uid == null || tap.userId != uid || _disposed) return;
    final action = resolveNotificationAction(tap.reminderId, tap.actionId);
    final type = action?.type;
    if (action == null || type == null) return;
    final result = await ingestDailyTrackingEvent(uid, type, action.payload);
    if (_disposed || uid != _uid || result.skipped || !result.ok) return;
    // Akıllı susma: yapılan iş hemen plana işlenir; hedefi dolan su / bitirilen rutin için kalan
    // bildirimler geri alınır. Panel de planını yeniden okur ([recordedActions]).
    final plan = _plan;
    if (plan != null) {
      _plan = plan.withProgress(plan.progress.withEvent(type, action.payload));
      unawaited(_applySchedule());
    }
    if (!_recorded.isClosed) _recorded.add(type);
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
    unawaited(_recorded.close());
    openRoute.dispose();
    super.dispose();
  }
}
