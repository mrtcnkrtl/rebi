/// Derleme anında verilen ortam değerleri (`--dart-define-from-file=env/dev.json`).
/// Web karşılığı: `frontend/.env` içindeki `VITE_*` değişkenleri.
class Env {
  Env._();

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Web `VITE_API_URL`. Boşsa canlı API kullanılır (webdeki `${origin}/api` karşılığı).
  static const _apiUrlRaw = String.fromEnvironment('API_URL');

  /// Web `VITE_REBI_PLUS_CHECKOUT_URL`.
  static const rebiPlusCheckoutUrl = String.fromEnvironment('REBI_PLUS_CHECKOUT_URL');

  /// Firebase proje dosyaları (`google-services.json`, `GoogleService-Info.plist`) eklendiğinde
  /// `true` verilir; sunucudan push almak için gerekir. Kapalıyken yerel bildirim kullanılır.
  static const firebaseEnabled = bool.fromEnvironment('FIREBASE_ENABLED');

  static const productionApiUrl = 'https://rebiovil.com/api';

  static bool get supabaseConfigured => supabaseUrl.trim().isNotEmpty;

  static String get apiUrl {
    final raw = _apiUrlRaw.trim().replaceAll(RegExp(r'/$'), '');
    return raw.isEmpty ? productionApiUrl : raw;
  }
}
