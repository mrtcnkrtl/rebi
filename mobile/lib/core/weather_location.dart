import 'api.dart';
import 'device_location.dart';
import 'i18n.dart';
import 'local_store.dart';

/// Hava durumu için bir yer: ad ve ~1 km'ye yuvarlı koordinat (sunucu şehir aramasından gelir).
class Place {
  const Place({required this.name, this.region, this.country, required this.lat, required this.lon});

  factory Place.fromJson(Map<String, dynamic> j) => Place(
        name: '${j['name'] ?? ''}'.trim(),
        region: _text(j['region']),
        country: _text(j['country']),
        lat: (j['lat'] as num).toDouble(),
        lon: (j['lon'] as num).toDouble(),
      );

  final String name;
  final String? region;
  final String? country;
  final double lat;
  final double lon;

  /// "Marmara, Türkiye": bölge ve ülke; bölge adı şehirle aynıysa tekrarlanmaz. Boş olabilir.
  String get detail => [if (region != name) ?region, ?country].join(', ');

  /// "Ankara, Türkiye" ya da "Bursa, Marmara, Türkiye".
  String get label => detail.isEmpty ? name : '$name, $detail';
}

String? _text(Object? v) {
  final s = v?.toString().trim() ?? '';
  return s.isEmpty ? null : s;
}

String _offline() => I18n.instance.t('mobileWeatherPlace.offline', const {}, 'Bağlantı yok. İnternetini kontrol edip tekrar dene.');

/// Şehir araması sonucu: adaylar (boş olabilir: "bulunamadı") ya da kullanıcıya gösterilecek hata.
class PlaceSearch {
  const PlaceSearch({this.places = const [], this.error});

  final List<Place> places;
  final String? error;
}

/// `GET /weather/search`: yazılan ad → şehir adayları (konum işleme izni gerekir).
Future<PlaceSearch> searchPlaces(String userId, String query) async {
  try {
    final res = await apiGet('/weather/search', query: {'user_id': userId, 'q': query.trim(), 'lang': I18n.instance.lang});
    if (!res.ok) return PlaceSearch(error: apiErrorMessage(res));
    final raw = res.data['places'];
    final places = <Place>[];
    if (raw is List) {
      for (final p in raw) {
        if (p is Map) {
          try {
            places.add(Place.fromJson(p.cast<String, dynamic>()));
          } catch (_) {
            /* bozuk aday atlanır */
          }
        }
      }
    }
    return PlaceSearch(places: places);
  } catch (_) {
    return PlaceSearch(error: _offline());
  }
}

class LocationSave {
  const LocationSave({this.saved = false, this.error});

  final bool saved;
  final String? error;
}

/// `PATCH /me/profile` ile hava için konumu kaydeder: sunucu konum gelmeyen isteklerde (ve bildirimlerde) bunu kullanır.
/// [city] verilirse profildeki şehir adı da güncellenir.
Future<LocationSave> saveWeatherLocation(String userId, {required double lat, required double lon, String? city}) async {
  try {
    final res = await apiPatch('/me/profile', {
      'user_id': userId,
      'location_lat': lat,
      'location_lon': lon,
      'city': ?city,
    });
    if (!res.ok) return LocationSave(error: apiErrorMessage(res));
    return LocationSave(saved: res.data['location_saved'] == true);
  } catch (_) {
    return LocationSave(error: _offline());
  }
}

/// Havanın hangi yere göre gösterildiği: telefonun konumu (varsayılan) ya da kullanıcının seçtiği şehir.
/// Seçilen şehir sunucudaki profilde kayıtlıdır; o zaman istekle cihaz konumu gönderilmez (seçim cihazın konumunu ezer).
class WeatherPlacePref {
  const WeatherPlacePref.device()
      : manual = false,
        name = null;
  const WeatherPlacePref.manual(String this.name) : manual = true;

  final bool manual;
  final String? name;
}

String _prefKey(String userId) => 'rebi-weather-place_$userId';
String _savedKey(String userId) => 'rebi-weather-saved_$userId';

WeatherPlacePref weatherPlacePref(String userId) {
  final j = LocalStore.instance.getJson(_prefKey(userId));
  if (j is Map && j['mode'] == 'manual' && '${j['name'] ?? ''}'.trim().isNotEmpty) return WeatherPlacePref.manual('${j['name']}'.trim());
  return const WeatherPlacePref.device();
}

/// Kullanıcı bir şehir seçti (sunucuya kaydedildi). Cihaz konumunun "kayıtlı" işareti geçersiz olur: telefon konumuna
/// dönülürse yeniden kaydedilir.
Future<void> setManualWeatherPlace(String userId, Place place) async {
  await LocalStore.instance.setJson(_prefKey(userId), {'mode': 'manual', 'name': place.name});
  await LocalStore.instance.remove(_savedKey(userId));
}

/// Telefonun konumuna dönüldü.
Future<void> useDeviceWeatherPlace(String userId) async {
  await LocalStore.instance.remove(_prefKey(userId));
  await LocalStore.instance.remove(_savedKey(userId));
}

/// Cihaz konumu sunucuya en son kaydedildiğinde bu kadar uzaktaysa (≈5 km) yeniden kaydedilir. Aynı yerde olan kullanıcı
/// her açılışta profil yazmaz (profil yazımı saatte 30 istekle sınırlıdır).
const _moveThreshold = .05;

bool shouldSaveDeviceLocation(String userId, Coordinates at) {
  final j = LocalStore.instance.getJson(_savedKey(userId));
  if (j is! Map) return true;
  final la = j['lat'], lo = j['lon'];
  if (la is! num || lo is! num) return true;
  return (la - at.lat).abs() >= _moveThreshold || (lo - at.lon).abs() >= _moveThreshold;
}

Future<void> markDeviceLocationSaved(String userId, Coordinates at) =>
    LocalStore.instance.setJson(_savedKey(userId), {'lat': at.lat, 'lon': at.lon});
