import 'dart:async';

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

/// Konum alınamamasının nedeni: kullanıcıya her biri için ayrı, uygulanabilir bir cümle söylenir.
enum LocationFailure {
  /// Telefonun konum servisi (GPS / konum) kapalı.
  serviceOff,

  /// İzin verilmedi (sistem penceresi reddedildi); tekrar sorulabilir.
  denied,

  /// İzin kalıcı reddedilmiş: yalnızca telefon ayarlarından açılır.
  blocked,

  /// Konum belirli süre içinde alınamadı (kapalı alan, zayıf sinyal).
  timeout,
}

typedef LocationOutcome = ({Coordinates? at, LocationFailure? failure});

/// Son bilinen konum bu kadar eskiyse (hava için ~1 km yeter) yeni konum beklenir.
const _freshLastKnown = Duration(hours: 6);

/// Konumu **izin isteyerek** alır (kullanıcı "konumumu paylaş" dediğinde). Önce telefonun son bilinen konumuna bakar
/// (anında ve kapalı alanda da çalışır), yoksa ya da çok eskiyse yeni konum ister. Başarısızlıkta nedeni söyler.
Future<LocationOutcome> _acquireDeviceLocation() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return (at: null, failure: LocationFailure.serviceOff);
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.deniedForever) return (at: null, failure: LocationFailure.blocked);
    if (permission != LocationPermission.whileInUse && permission != LocationPermission.always) {
      return (at: null, failure: LocationFailure.denied);
    }
    Position? last;
    try {
      last = await Geolocator.getLastKnownPosition();
    } catch (_) {
      last = null; // desteklenmeyen platform: yeni konum denenir
    }
    final lastIsFresh = last != null && DateTime.now().difference(last.timestamp) < _freshLastKnown;
    if (last != null && lastIsFresh) return (at: _round(last), failure: null);
    try {
      final now = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 20)),
      );
      return (at: _round(now), failure: null);
    } on TimeoutException {
      // Yeni konum gelmedi: eski ama gerçek bir konum, hiç konumdan iyidir.
      if (last != null) return (at: _round(last), failure: null);
      return (at: null, failure: LocationFailure.timeout);
    }
  } on LocationServiceDisabledException {
    return (at: null, failure: LocationFailure.serviceOff);
  } on PermissionDeniedException {
    return (at: null, failure: LocationFailure.denied);
  } catch (_) {
    return (at: null, failure: LocationFailure.timeout);
  }
}

Coordinates _round(Position p) => (lat: roundCoordinate(p.latitude), lon: roundCoordinate(p.longitude));

Future<LocationOutcome> Function() _acquire = _acquireDeviceLocation;

/// Konumu izin isteyerek alır; sonuç koordinat ya da [LocationFailure] nedenidir.
Future<LocationOutcome> acquireDeviceLocation() => _acquire();

/// Başarısızlığın düzeltildiği telefon ayarı sayfasını açar ([LocationFailure.serviceOff] → konum ayarları,
/// [LocationFailure.blocked] → uygulama ayarları). Açılabildiyse true.
Future<bool> openLocationFixSettings(LocationFailure failure) async {
  try {
    return failure == LocationFailure.serviceOff ? await Geolocator.openLocationSettings() : await Geolocator.openAppSettings();
  } catch (_) {
    return false;
  }
}

Future<bool> Function(LocationFailure) _openSettings = openLocationFixSettings;

/// Ayar sayfasını açar (testte sahtelenebilir).
Future<bool> openLocationSettingsFor(LocationFailure failure) => _openSettings(failure);

/// Testlerde gerçek konum eklentisi yerine sabit sonuç vermek için.
@visibleForTesting
void setDeviceLocationAcquirer({Future<LocationOutcome> Function()? acquire, Future<bool> Function(LocationFailure)? openSettings}) {
  if (acquire != null) _acquire = acquire;
  if (openSettings != null) _openSettings = openSettings;
}

@visibleForTesting
void resetDeviceLocationAcquirer() {
  _acquire = _acquireDeviceLocation;
  _openSettings = openLocationFixSettings;
}

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
