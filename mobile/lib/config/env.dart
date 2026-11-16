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

  /// RevenueCat herkese açık SDK anahtarları (`appl_…` / `goog_…`). Boşsa uygulama içi satın alma kapalıdır.
  static const revenueCatAppleKey = String.fromEnvironment('REVENUECAT_APPLE_KEY');
  static const revenueCatGoogleKey = String.fromEnvironment('REVENUECAT_GOOGLE_KEY');

  /// AdMob banner birim kimlikleri (`ca-app-pub-…/…`). Boşsa reklam gösterilmez. Uygulama kimlikleri
  /// `Info.plist` (GADApplicationIdentifier) ve `AndroidManifest.xml` içindedir.
  static const admobBannerIos = String.fromEnvironment('ADMOB_BANNER_IOS');
  static const admobBannerAndroid = String.fromEnvironment('ADMOB_BANNER_ANDROID');

  /// Firebase proje dosyaları (`google-services.json`, `GoogleService-Info.plist`) eklendiğinde
  /// `true` verilir; sunucudan push almak için gerekir. Kapalıyken yerel bildirim kullanılır.
  static const firebaseEnabled = bool.fromEnvironment('FIREBASE_ENABLED');

  /// Beta sürüm: girişteki "BETA" etiketi ve ilk açılıştaki "hata çıkabilir" uyarısı. Beta bitince derlemeye
  /// `--dart-define=REBI_BETA=false` verilir (kod değişmez).
  static const betaBuild = bool.fromEnvironment('REBI_BETA', defaultValue: true);

  static const productionApiUrl = 'https://rebiovil.com/api';

  /// Destek e-postası ve sayfası (mağazalardaki destek URL'si de bu sayfadır; web: `pages/Support.jsx`).
  static const supportEmail = 'mertkartal48.mck@gmail.com';
  static const supportPageUrl = 'https://rebiovil.com/destek';

  static bool get supabaseConfigured => supabaseUrl.trim().isNotEmpty;

  static String get apiUrl {
    final raw = _apiUrlRaw.trim().replaceAll(RegExp(r'/$'), '');
    return raw.isEmpty ? productionApiUrl : raw;
  }
}
