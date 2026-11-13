import 'api.dart';

/// `POST /devices/register` yanıtı.
class DeviceRegistration {
  const DeviceRegistration({required this.pushConfigured, required this.synced, this.dispatchAlive = true});

  /// Sunucuda FCM yapılandırması açık.
  final bool pushConfigured;

  /// Sunucunun push dağıtıcısı yakın zamanda çalıştı. FCM açık **ve** dağıtıcı canlıysa hatırlatıcıları sunucu
  /// gönderir ve yerel bildirim kurulmaz; dağıtıcı sustuysa (cron durmuş) hatırlatma kaybolmasın diye yerel
  /// bildirim kurulur. Alanı bilmeyen eski sunucuda true sayılır (eski davranış).
  final bool dispatchAlive;

  /// Kullanıcı verisi sunucuda tutuluyor (demo / veritabanı yokken false).
  final bool synced;
}

/// Cihazı bildirimler için kaydeder (`docs/MOBIL-API.md` → "Cihaz kaydı"). Hatırlatıcı saatleri
/// yerel olduğundan [utcOffsetMinutes] zorunludur. Uygulama açılışta, saat dilimi değişince ve uzun aradan
/// sonra öne gelince çağırır (`NotificationsController.onAppResumed`).
/// Başarısızlıkta null döner.
Future<DeviceRegistration?> registerDevice({
  required String userId,
  required String token,
  required String platform,
  required int utcOffsetMinutes,
  required bool pushEnabled,
  String? locale,
  String? appVersion,
  bool actionsSupported = false,
}) async {
  final res = await apiPost('/devices/register', {
    'user_id': userId,
    'token': token,
    'platform': platform,
    'utc_offset_minutes': utcOffsetMinutes,
    if (locale != null && locale.isNotEmpty) 'locale': locale,
    if (appVersion != null && appVersion.isNotEmpty) 'app_version': appVersion,
    'push_enabled': pushEnabled,
    'actions_supported': actionsSupported,
  });
  if (!res.ok) return null;
  return DeviceRegistration(
    pushConfigured: res.data['push_configured'] == true,
    synced: res.data['synced'] != false,
    dispatchAlive: res.data['dispatch_alive'] != false,
  );
}

/// Çıkışta veya cihaz kaydı kaldırılırken. Dönüş: sunucu kabul etti mi.
Future<bool> unregisterDevice({required String userId, required String token}) async {
  final res = await apiDelete('/devices/register', query: {'user_id': userId, 'token': token});
  return res.ok;
}
