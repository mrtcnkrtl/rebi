import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/device_location.dart';
import '../core/i18n.dart';
import '../core/weather_location.dart';

/// Şehir aramasının durumu.
enum PlaceSearchPhase { idle, searching, results, empty, failed }

/// "Hava için yer" sayfasının mantığı: telefonun konumunu kullan ya da bir şehir ara ve seç. Her ikisinde de seçim
/// sunucuya (profile) kaydedilir ve [onChanged] ile Bugün planı yeni yerle yeniden okunur.
class WeatherPlaceController extends ChangeNotifier {
  WeatherPlaceController({
    required this.userId,
    required this.consentAllowed,
    required this.onChanged,
    this.debounce = const Duration(milliseconds: 450),
  }) : pref = weatherPlacePref(userId);

  final String userId;

  /// Gizlilik onayında konum işlemeye izin verilmiş mi; verilmediyse ne konum ne şehir sunucuya gönderilebilir.
  final bool consentAllowed;

  /// Yer değişince çağrılır (Bugün planı yenilenir).
  final Future<void> Function() onChanged;
  final Duration debounce;

  WeatherPlacePref pref;
  LocationAccess access = LocationAccess.askable;

  /// Konum alınıyor ya da seçim kaydediliyor.
  bool busy = false;

  /// Telefon konumu alınamadı: nedeni (ayar düğmesi buna göre) ve ekrana yazılacak sebep anahtarı.
  LocationFailure? deviceFailure;

  String query = '';
  List<Place> results = const [];
  PlaceSearchPhase phase = PlaceSearchPhase.idle;

  /// Arama ya da kaydetme hatası (yerelleştirilmiş cümle).
  String? error;

  Timer? _timer;
  int _version = 0;
  bool _disposed = false;

  /// Telefonun konum izni durumunu (sormadan) okur.
  Future<void> init() async {
    access = await locationAccess();
    _notify();
  }

  /// Yazı değiştikçe (kısa bir bekleyişten sonra) arar; iki harften kısa yazı aramaz.
  void setQuery(String text) {
    query = text;
    error = null;
    _timer?.cancel();
    final q = text.trim();
    if (q.length < 2) {
      _version++;
      results = const [];
      phase = PlaceSearchPhase.idle;
      _notify();
      return;
    }
    phase = PlaceSearchPhase.searching;
    _notify();
    _timer = Timer(debounce, () => unawaited(_search(q)));
  }

  Future<void> _search(String q) async {
    final version = ++_version;
    final found = await searchPlaces(userId, q);
    if (_disposed || version != _version) return;
    if (found.error != null) {
      results = const [];
      error = found.error;
      phase = PlaceSearchPhase.failed;
    } else {
      results = found.places;
      phase = found.places.isEmpty ? PlaceSearchPhase.empty : PlaceSearchPhase.results;
    }
    _notify();
  }

  /// Bir şehri seçer: sunucuya kaydeder, bu cihazda "seçilen şehir" olarak işaretler, planı yeniler. Başarılıysa true.
  Future<bool> choose(Place place) async {
    if (busy) return false;
    busy = true;
    error = null;
    _notify();
    final saved = await saveWeatherLocation(userId, lat: place.lat, lon: place.lon, city: place.name);
    if (!saved.saved) {
      busy = false;
      error = saved.error ?? _generic();
      _notify();
      return false;
    }
    await setManualWeatherPlace(userId, place);
    pref = WeatherPlacePref.manual(place.name);
    await onChanged();
    busy = false;
    _notify();
    return true;
  }

  /// Telefonun konumunu kullanır (gerekirse izin ister). Başarılıysa true; değilse [deviceFailure] nedeni söyler.
  Future<bool> useDevice() async {
    if (busy) return false;
    busy = true;
    deviceFailure = null;
    error = null;
    _notify();
    final outcome = await acquireDeviceLocation();
    final at = outcome.at;
    if (at == null) {
      deviceFailure = outcome.failure ?? LocationFailure.timeout;
      access = await locationAccess();
      busy = false;
      _notify();
      return false;
    }
    await useDeviceWeatherPlace(userId);
    pref = const WeatherPlacePref.device();
    final saved = await saveWeatherLocation(userId, lat: at.lat, lon: at.lon);
    if (saved.saved) await markDeviceLocationSaved(userId, at);
    await onChanged();
    busy = false;
    _notify();
    return true;
  }

  /// Konum hatasının düzeldiği telefon ayarını açar (konum servisi / uygulama izni).
  Future<void> openSettings() async {
    final failure = deviceFailure;
    if (failure == null) return;
    await openLocationSettingsFor(failure);
  }

  /// Henüz denemeden, izin durumundan bilinen engel için ilgili ayarı açar (izin kalıcı reddedilmiş / konum servisi kapalı).
  Future<void> openSettingsFromAccess() async {
    final failure = switch (access) {
      LocationAccess.blocked => LocationFailure.blocked,
      LocationAccess.off => LocationFailure.serviceOff,
      _ => null,
    };
    if (failure != null) await openLocationSettingsFor(failure);
  }

  String _generic() => I18n.instance.t('mobileWeatherPlace.saveFailed', const {}, 'Konum kaydedilemedi. Tekrar dene.');

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
