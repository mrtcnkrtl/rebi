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

Future<Coordinates?> lookupDeviceLocation() => _lookup();

/// Testlerde gerçek konum eklentisi yerine sabit koordinat vermek için.
@visibleForTesting
set deviceLocationLookup(LocationLookup lookup) => _lookup = lookup;

@visibleForTesting
void resetDeviceLocationLookup() => _lookup = _lookupGrantedLocation;
