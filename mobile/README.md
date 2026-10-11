# Rebi Mobil (Flutter)

Web uygulamasının (`frontend/`, React) iOS ve Android karşılığı. Aynı FastAPI backend'i
(`backend/`) ve aynı Supabase projesini kullanır; hesap, rutin, sohbet geçmişi ve rıza
kayıtları iki platform arasında ortaktır.

## Kurulum

Gereksinimler: Flutter 3.47+, Xcode (iOS), Android Studio + Android SDK (Android).

```bash
cd mobile
flutter pub get
cp env/example.json env/dev.json   # değerleri doldurun
flutter run --dart-define-from-file=env/dev.json
```

`env/*.json` dosyaları git'e girmez (yalnızca `env/example.json`).

| Anahtar | Web karşılığı | Not |
| --- | --- | --- |
| `SUPABASE_URL` | `VITE_SUPABASE_URL` | Boşsa giriş/profil/fotoğraf devre dışı (web ile aynı davranış) |
| `SUPABASE_ANON_KEY` | `VITE_SUPABASE_ANON_KEY` | |
| `API_URL` | `VITE_API_URL` | Boşsa `https://rebiovil.com/api` |
| `REBI_PLUS_CHECKOUT_URL` | `VITE_REBI_PLUS_CHECKOUT_URL` | Abonelik ödeme bağlantısı |

Yerel backend'e bağlanırken: iOS simülatöründe `http://127.0.0.1:8000`, Android
emülatöründe `http://10.0.2.2:8000`. Düz HTTP yalnızca yerel ağ (iOS) ve debug derlemesi
(Android) için açıktır.

## Test

```bash
flutter analyze
flutter test
```

- `test/routine_logic_test.dart` — panelin rutin hesapları, gerçek bir `/generate_routine`
  yanıtı üzerinde (`test/fixtures/`).
- `test/screens_test.dart` — gerçek yönlendirme + ekranlarla kullanıcı akışları (analiz
  sihirbazı, rutin kabulü, check-in, sohbet/kota, rıza kurtarma, tema kilidi) ve küçük
  telefon / tablet boyutlarında taşma kontrolü. API çağrıları sahte istemciyle yakalanır ve
  gövdelerin web ile aynı alanları taşıdığı doğrulanır.
- `test/web_sync_test.dart` — çeviri dosyaları ve KVKK/açık rıza metinleri web ile birebir aynı mı.

## Web ile ortak içerik

- **Çeviriler:** tek kaynak `frontend/src/locales`. Web'de metin değişince
  `tool/sync_locales.sh` çalıştırın; fark kalırsa `web_sync_test` kırılır.
- **KVKK / açık rıza metinleri:** `frontend/src/lib/legalTexts.js` ↔ `lib/core/legal_texts.dart`.
  İkisini birlikte güncelleyin; test farkı yakalar.
- **Tema tanımları:** `frontend/src/context/ThemeContext.jsx` ↔ `lib/state/theme_controller.dart`.

## Yapı

| Web (`frontend/src`) | Mobil (`mobile/lib`) |
| --- | --- |
| `App.jsx` (rotalar, `ProtectedRoute`) | `router.dart` (go_router, `redirect`) |
| `components/Navbar`, `BottomNav`, modallar | `ui/shell/app_shell.dart`, `ui/components/modals.dart` |
| `context/AuthContext` | `state/auth_controller.dart` |
| `context/ThemeContext` (+ `ThemePremiumGate`) | `state/theme_controller.dart` |
| `i18n.js`, `lib/localePacks.js` | `core/i18n.dart` |
| `lib/*.js` (apiAuth, apiErrors, routineTracking, checkinStats, legalConsent…) | `core/*.dart` (aynı adlar) |
| `pages/Dashboard.jsx` içindeki saf hesaplar | `core/routine_logic.dart` |
| `pages/*.jsx` | `screens/*.dart` |
| `localStorage` | `shared_preferences` (`core/local_store.dart`, anahtar adları aynı) |
| Tailwind sınıfları (`card`, `btn-primary`…) | `ui/tw.dart`, `ui/widgets/common.dart` |

Cihazda tutulan veriler (rutin kabulü, check-in serisi, sohbet önbelleği) web'deki
`localStorage` anahtarlarıyla aynı adları kullanır; hesap silmede `core/privacy_storage.dart`
hepsini temizler.

## Bilinçli platform farkları

İşlev kaybı yoktur; aşağıdakiler mobil kullanıma uyarlamadır:

- **Kamera:** web'deki "web kamerası" düğmesi masaüstü içindir; mobilde ön/arka kamera ve
  galeri vardır. Fotoğraflar JPEG (%92) olarak, çözünürlük korunarak yüklenir.
- **Açılış:** oturum açıksa uygulama doğrudan panelde açılır; tanıtım sayfasına logodan gidilir.
- **Giriş:** rıza kaydı başarısız olursa hata giriş ekranında gösterilir (web'de oturum açılır
  açılmaz sayfa değiştiği için mesaj görünmüyordu).
- **Sohbet:** web'deki köşe kota sayacı ve sol çekmece yalnızca geniş ekranda (tablet) gösterilir;
  telefonda kota rozeti başlıkta zaten vardır (web'in mobil görünümüyle aynı).
- **Gün içi kayıtlar:** `docs/MOBIL-API.md` sözleşmesine uygun olarak `source: "mobile"`, yerel
  saat dilimli `timestamp` ve tekrar denemelerde çift sayımı önleyen `client_event_id` gönderilir.
- **Android geri tuşu:** alt sekmelerden birindeyken panele döner, panelde uygulamadan çıkar.

## Uygulama kimliği ve yayın

- Paket / bundle kimliği: `com.rebiovil.rebi`, görünen ad: `Rebi`.
- İkonlar web'deki marka görselinden üretilir: `dart run flutter_launcher_icons`.
- Android release imzası henüz tanımlı değil (`android/app/build.gradle.kts` debug anahtarıyla
  imzalar); mağazaya çıkmadan önce yükleme anahtarı eklenmeli.
- Push bildirimleri (FCM) backend'de hazır (`/devices/register`, `docs/MOBIL-API.md`); mobilde
  Firebase kurulumu sonraki geliştirme adımıdır.
