import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

typedef Coordinates = ({double lat, double lon});
typedef LocationLookup = Future<Coordinates?> Function();

/// Konum izni **sorulmadan**, yalnızca zaten verilmişse konumu okur. Panel her açıldığında
/// izin penceresi çıkmasın diye; izin analiz sihirbazındaki konum adımında istenir.
/// Hava durumu için yaklaşık konum yeter: koordinatlar ~1 km'ye yuvarlanır.
Future<Coordinates?> _lookupGrantedLocation() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    final permission = await Geolocator.checkPermission();
    if (permission != LocationPermission.whileInUse && permission != LocationPermission.always) return null;
    final position = await Geolocator.getLastKnownPosition() ??
        await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 8)),
        );
    return (lat: roundCoordinate(position.latitude), lon: roundCoordinate(position.longitude));
  } catch (_) {
    return null;
  }
}

/// Hava durumu için ~1 km yeter; sunucuya kesin konum gitmesin diye iki ondalığa yuvarlanır.
double roundCoordinate(double v) => (v * 100).roundToDouble() / 100;

LocationLookup _lookup = _lookupGrantedLocation;

// async: sahte bir arama `Future<Koordinat>` döndürse bile çağıran `Future<Koordinat?>` görür (zaman aşımı `null` verebilsin).
Future<Coordinates?> lookupDeviceLocation() async => _lookup();

/// Testlerde gerçek konum eklentisi yerine sabit koordinat vermek için.
@visibleForTesting
set deviceLocationLookup(LocationLookup lookup) => _lookup = lookup;

@visibleForTesting
void resetDeviceLocationLookup() => _lookup = _lookupGrantedLocation;

/// Konum izninin şu anki durumu (sormadan okunur).
enum LocationAccess {
  /// İzin verilmiş.
  granted,

  /// Henüz sorulmamış ya da bir kez reddedilmiş: sistem penceresi yine açılabilir.
  askable,

  /// Kalıcı reddedilmiş (telefon ayarlarından açılır).
  blocked,

  /// Cihazın konum servisi kapalı ya da okunamadı.
  off,
}

Future<LocationAccess> _readAccess() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return LocationAccess.off;
    return switch (await Geolocator.checkPermission()) {
      LocationPermission.whileInUse || LocationPermission.always => LocationAccess.granted,
      LocationPermission.deniedForever => LocationAccess.blocked,
      _ => LocationAccess.askable,
    };
  } catch (_) {
    return LocationAccess.off;
  }
}

Future<LocationAccess> _askAccess() async {
  try {
    final permission = await Geolocator.requestPermission();
    return switch (permission) {
      LocationPermission.whileInUse || LocationPermission.always => LocationAccess.granted,
      LocationPermission.deniedForever => LocationAccess.blocked,
      _ => LocationAccess.askable,
    };
  } catch (_) {
    return LocationAccess.off;
  }
}

Future<LocationAccess> Function() _access = _readAccess;
Future<LocationAccess> Function() _request = _askAccess;

/// Konum izni durumu; **sorulmaz**.
Future<LocationAccess> locationAccess() => _access();

/// Sistem konum izni penceresini açar (kullanıcı "Konumu aç" dediğinde).
Future<LocationAccess> requestLocationAccess() => _request();

/// Testlerde gerçek konum eklentisi yerine sabit durum vermek için.
@visibleForTesting
void setLocationAccess({Future<LocationAccess> Function()? read, Future<LocationAccess> Function()? request}) {
  if (read != null) _access = read;
  if (request != null) _request = request;
}

@visibleForTesting
void resetLocationAccess() {
  _access = _readAccess;
  _request = _askAccess;
}
