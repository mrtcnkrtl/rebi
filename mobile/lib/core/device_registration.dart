import 'api.dart';

/// `POST /devices/register` yanıtı.
class DeviceRegistration {
  const DeviceRegistration({required this.pushConfigured, required this.synced});

  /// Sunucuda FCM yapılandırması açık: hatırlatıcıları sunucu gönderir, yerel bildirim kurulmaz.
  final bool pushConfigured;

  /// Kullanıcı verisi sunucuda tutuluyor (demo / veritabanı yokken false).
  final bool synced;
}

/// Cihazı bildirimler için kaydeder (`docs/MOBIL-API.md` → "Cihaz kaydı"). Hatırlatıcı saatleri
/// yerel olduğundan [utcOffsetMinutes] zorunludur. Uygulama her açılışta çağırmalıdır.
/// Başarısızlıkta null döner.
Future<DeviceRegistration?> registerDevice({
  required String userId,
  required String token,
  required String platform,
  required int utcOffsetMinutes,
  required bool pushEnabled,
  String? locale,
  String? appVersion,
}) async {
  final res = await apiPost('/devices/register', {
    'user_id': userId,
    'token': token,
    'platform': platform,
    'utc_offset_minutes': utcOffsetMinutes,
    if (locale != null && locale.isNotEmpty) 'locale': locale,
    if (appVersion != null && appVersion.isNotEmpty) 'app_version': appVersion,
    'push_enabled': pushEnabled,
  });
  if (!res.ok) return null;
  return DeviceRegistration(
    pushConfigured: res.data['push_configured'] == true,
    synced: res.data['synced'] != false,
  );
}

/// Çıkışta veya cihaz kaydı kaldırılırken. Dönüş: sunucu kabul etti mi.
Future<bool> unregisterDevice({required String userId, required String token}) async {
  final res = await apiDelete('/devices/register', query: {'user_id': userId, 'token': token});
  return res.ok;
}
