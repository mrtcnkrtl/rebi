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
- `test/today_plan_test.dart` — `/today/plan` ve `/me/snapshot` yanıtlarının ayrıştırılması, hatırlatıcı
  pencereleri ve hatırlatıcı → olay eşlemesi.
- `test/home_sync_test.dart` — açılış paketi denetleyicisi (oturum, rıza, giriş akışı beklemesi, demo kullanıcı).
- `test/reminder_settings_test.dart`, `test/reminders_screen_test.dart` — hatırlatıcı ayarları: pencere hesabı (sunucuyla aynı),
  yarının bildirimleri, ayar ekranı (saat seçimi, su aralığı, kategori anahtarları, doğrulama, hata durumları).
- `test/notification_actions_test.dart` — bildirim düğmeleri: yük biçimi, hangi hatırlatıcıda hangi düğme, arka planda
  kuyruğa alma, başka izolatın yazdığını yeniden okuma, düğmeye dokunulunca olay gönderme.
- `test/reminder_schedule_test.dart`, `test/notifications_controller_test.dart`, `test/notification_screens_test.dart` —
  hatırlatma zamanlaması, bildirim denetleyicisi (izin, cihaz kaydı, çift bildirim önleme, dokunma yönlendirmesi)
  ve öneri kartı / profil anahtarı. Gerçek bildirim eklentisi yerine sahteleri kullanır.
- `test/profile_history_core_test.dart`, `test/profile_history_screens_test.dart` — profil / geçmiş yanıtlarının
  ayrıştırılması, özet hesabı, profil formu (yalnızca değişen alanlar, doğrulama, hata durumları) ve geçmiş ekranı.
- `test/today_screens_test.dart` — "Bugün" ekranı: şimdi kartı, rutin kontrol listesi (adım, blok, geri al),
  yaptım / ürün bitti çubuğu, makyaj (temizleme yöntemi), beslenme, su ve ürün bitti sayfaları, çevrimdışı
  kuyruk, konum izni, hata durumu, küçük ekran.

## Web ile ortak içerik

- **Çeviriler:** tek kaynak `frontend/src/locales`. Web'de metin değişince
  `tool/sync_locales.sh` çalıştırın; fark kalırsa `web_sync_test` kırılır.
- **KVKK / açık rıza metinleri:** `frontend/src/lib/legalTexts.js` ↔ `lib/core/legal_texts.dart`.
  İkisini birlikte güncelleyin; test farkı yakalar.
- **Tema tanımları:** `frontend/src/context/ThemeContext.jsx` ↔ `lib/state/theme_controller.dart`.
- **Yalnızca mobilde olan metinler:** `assets/mobile_locales/{tr,en}/mobile.json` (`mobileToday.*`).
  Web'de karşılığı yoktur; `tool/sync_locales.sh` bu klasöre dokunmaz, `web_sync_test` karşılaştırmaz.
  Yer tutucu biçimi webdeki gibi `{{ad}}`'dır.

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

## Mobil API entegrasyonu

`docs/MOBIL-API.md` sözleşmesinin uygulama durumu:

| Sözleşme | Durum | Nerede |
| --- | --- | --- |
| `GET /me/snapshot` — açılış paketi (rutin, rıza, ilerleme) | var | `state/home_sync_controller.dart`; panel her açıldığında tazeler |
| Rıza eksikse onay kutusu | var | snapshot `consent` → `core/consent_recovery.dart` |
| `GET /today/plan` — rutin, havaya göre öneri, hatırlatıcı, ilerleme | var | `state/today_plan_controller.dart`, `screens/today/` |
| Canlı hava için `lat`/`lon` | var, izin sorulmaz | `core/device_location.dart` (yalnızca konum izni ve rıza varsa) |
| `POST /daily_tracking/ingest` — su, makyaj, SPF, beslenme, rutin, ürün bitti | var | `core/daily_tracking.dart` |
| Çevrimdışı kuyruk (tekrar deneme) | var | `core/event_outbox.dart` (kalıcı kuyruk), `state/outbox_sync_controller.dart` (ne zaman gönderileceği) |
| `POST /devices/register`, push / yerel bildirim | var; push için Firebase dosyaları gerekir | `state/notifications_controller.dart`, `core/local_notifications.dart`, `core/firebase_push.dart` |
| `GET/PUT /me/reminder-settings` — uyanma / uyku saati, su aralığı, kapatılan kategoriler | var | `core/reminder_settings.dart`, `screens/reminders_screen.dart` (`/dashboard/reminders`; Profil ve Bugün ekranından açılır) |
| `utc_offset_minutes` — "bugün" kullanıcının yerel günü | var | `core/api.dart` (`localUtcOffsetMinutes`); plan, açılış paketi, geçmiş, check-in |
| `GET/PATCH /me/profile` — cilt tipi, yaş, cinsiyet, şehir | var | `core/user_profile.dart`, `ui/components/profile_details_card.dart` (Profil ekranı) |
| `GET /me/history` — geçmiş günler, check-in'ler, son analizler | var | `core/user_history.dart`, `screens/history_screen.dart` (`/dashboard/history`; Profil ve panelden açılır) |

### Bugün ekranı

Kabul edilmiş rutinle açılan panel (`screens/today/`, kayıt mantığı `state/today_actions.dart`) yukarıdan aşağı:

1. **Selamlama + hava şeridi**: günün saatine göre karşılama, canlı hava ve havaya göre öneriler (SPF, nemlendirici,
   dudak balsamı).
2. **Şimdi**: saat penceresi açık hatırlatıcılar, tek dokunuşla eylem. Su kendi kartında gösterilir.
3. **Günün rutini**: sabah / akşam sekmeleri (saat 16'dan sonra akşam öne çıkar), adım adım işaretleme
   (`routine_step`). Son adım işaretlenince blok kendiliğinden tamamlanır (`routine_completed_block`).
4. **Takip kartları**: su (halka, +250 / +500 / başka miktar, yanlışı düzeltme, sonraki hatırlatma saati),
   makyaj (yaptı mı → akşam **nasıl temizlendi**: çift temizlik, temizleyici, su, mendil, temizlemedi),
   beslenme (abur cubur, şekerli, kızartma, süt ürünü, dengeli) ve güneş kremi yenileme.
5. **Sabit alt çubuk**: öne çıkan rutini "yaptım" ve "ürün bitti" (rutindeki bakım ürünlerinden seçilir).

Her kayıt çevrimdışı kuyruktan geçer. Kayıttan sonra ekranın altında onay mesajı çıkar; su, rutin bloğu için
**Geri al** vardır. Adım işaretlerinin sunucuda kalması için backend'de `progress.routine_steps` desteği
(`docs/MOBIL-API.md`) dağıtılmış olmalıdır; eski sunucuda işaretler ekran yenilenince sıfırlanır.

### Çevrimdışı kuyruk

Gün içi kayıtlar önce doğrudan gönderilir. Sunucuya ulaşılamazsa (bağlantı yok, zaman aşımı, 5xx, 429, 401)
olay cihazda kuyruğa alınır ve kullanıcıya "kaydedildi" denir; panelde ilerleme hemen güncellenir ve
"N kayıt gönderilmeyi bekliyor" satırı çıkar. Kuralları:

- Kimlik (`client_event_id`) ve zaman damgası kullanıcı işlemi yaptığı anda üretilir, yeniden denemelerde
  değişmez; sunucu aynı kimliği ikinci kez yazmaz. Bu yüzden "yazıldı ama yanıt gelmedi" durumunda da
  su miktarı iki kez sayılmaz.
- Sunucu olayı gününe, olayın zaman damgasına göre (UTC tarihi) yazar; dünden kalan kayıt dünün özetine girer.
- Gönderim eskiden yeniye sırayla yapılır ve ilk geçici hatada durur. Zamanlayıcı 30 sn → 1 dk → 2 dk → 5 dk
  aralıklarla dener; ayrıca oturum açılınca, uygulama öne gelince ve "Şimdi dene" ile.
- Kalıcı reddedilen (400/403/404/422…) olay kuyruğu tıkamasın diye düşürülür. Kuyruk kullanıcı başınadır;
  en fazla 200 olay, 7 gün ve 30 deneme tutulur. Hesap silinince kuyruk da silinir.
- Bağlantı durumu eklentisi yoktur: gönderim başarısızsa ağ yok sayılır.
- Yalnızca gün içi kayıtlar kuyruğa girer. Check-in ve analiz gibi yapay zekâ çağrıları çevrimdışı çalışmaz.

### Profil ve geçmiş

- **Cilt profilim** (Profil ekranı): cilt tipi, yaş, cinsiyet ve şehir `GET /me/profile` ile yüklenir, `PATCH /me/profile`
  ile kaydedilir. Yalnızca değişen alanlar gönderilir (sunucu `null` alanlara dokunmaz); şehir silinirse boş metin gider.
  Yaş sunucuda 13–100'e sabitlenir; sessizce değişmesin diye istemci baştan uyarır. Cilt tipi, bir sonraki panel
  açılışında havaya göre önerileri ve sohbeti etkiler. Görünen ad kaydedilince sunucudaki profil adı da güncellenir.
- **Geçmişim** (`/dashboard/history`): 7 / 30 / 90 gün; her gün için su, SPF, rutin, makyaj, beslenme, "ürün bitti" ve
  check-in (cilt hissi, uyku, stres, risk), üstte özet ve altta son analizler. Gün içi kayıt ve check-in'i olmayan
  günler listelenmez. Çevrimdışı kuyrukta bekleyen kayıtlar sunucuya ulaşana kadar burada görünmez.

### Bildirimler

Bildirimler kullanıcı panelde ya da Profil'de açana kadar **kapalıdır**. İki yol vardır, aynı anda çalışmaz:

- **Yerel bildirim** (`flutter_local_notifications`): sunucuda FCM yoksa ya da bu derlemede Firebase kapalıysa
  bugünün kalan hatırlatıcıları ve yarının koşulsuz olanları (sabah / akşam rutini, su, makyaj ve beslenme kaydı,
  check-in) telefona kurulur. Plan her değiştiğinde (yeni kayıt, uygulama açılışı) liste baştan kurulur; yapılan iş
  listeden düşer. Tam saatli alarm izni istenmez, bildirim birkaç dakika kayabilir. Havaya bağlı olanlar (SPF, dudak
  balsamı) yalnızca uygulama açıkken bilinen gerçek planla kurulur.
- **Sunucu push'u** (FCM): cihaz `POST /devices/register` ile kaydolur (`utc_offset_minutes`, dil, sürüm,
  `push_enabled`; uygulama her açılışta ve anahtar yenilenince yeniden kaydeder). Yanıttaki `push_configured`
  true ise hatırlatıcıları sunucu gönderir ve yerel bildirimler silinir. Çıkışta cihaz `DELETE /devices/register`
  ile kaldırılır.

Bildirime dokunmak ilgili ekranı açar (`daily_checkin` → check-in, diğerleri → panel); uygulama kapalıyken
bildirimle açıldıysa ilk ekran odur.

**Hatırlatıcı ayarları** (`/dashboard/reminders`): pencereler sabit değildir, kullanıcının gün düzenine göre kurulur.
Uyanma ve uyku saati, su aralığı (1 / 1,5 / 2 / 3 saat) ve kategori anahtarları (rutin, su, makyaj, beslenme, güneş
kremi, dudak balsamı, check-in) `PUT /me/reminder-settings` ile kaydedilir. Pencere hesabı sunucuyla aynıdır
(`core/reminder_settings.dart` ↔ `backend/today_plan.py`); varsayılan düzen (07:30 / 23:00) eski sabit saatleri verir.
Sunucu planı ve push'u bu ayara göre üretir; yerel bildirimlerde yarının hatırlatıcıları da bu pencerelerle kurulur.
Kaydedince plan yeniden alınır ve bildirimler hemen yeniden kurulur.

**Bildirim düğmeleri** (yerel bildirimler): rutin ("Yaptım"), makyaj sorusu ("Evet, yaptım" / "Hayır"), su ("+250 ml" /
"+500 ml"), güneş kremi ve beslenme ("Hayır") bildirimlerinin altında hızlı eylem düğmeleri vardır; ekran ya da seçim
sayfası açan eylemler (check-in, "nasıl temizledin", "evet yedim") bildirime dokunmakla zaten açılır.
- **Android:** düğme uygulamayı açmadan çalışır (`ActionBroadcastReceiver`). Uygulama kapalıysa arka plan izolatında
  oturum olmadığı için olay **gönderilmez, cihazdaki kuyruğa yazılır** (`rebiNotificationBackground`); uygulama öne
  gelince `EventOutbox.reload` ile okunur ve gönderilir. Uygulama çalışıyorsa olay doğrudan gönderilir.
- **iOS:** düğme uygulamayı öne getirir (arka plan izolatı için ek yerel kurulum gerekir, Mac olmadan doğrulanamadı).
- Sunucu push'unda (FCM) düğme yoktur: sistem bildirimine eylem eklemek için veri mesajı + istemci tarafı gösterim
  gerekir.

**Firebase'i açmak** (push için; yerel bildirimler bunsuz da çalışır):

1. Firebase konsolunda Android (`com.rebiovil.rebi`) ve iOS (`com.rebiovil.rebi`) uygulamalarını ekleyin.
2. `google-services.json` → `android/app/`, `GoogleService-Info.plist` → `ios/Runner/` (Xcode'da Runner hedefine ekleyin).
   Android'de dosya varsa Google Services eklentisi kendiliğinden uygulanır, yoksa atlanır.
3. iOS (Mac gerekir): Xcode → Runner → Signing & Capabilities → **Push Notifications** ekleyin; Firebase konsoluna
   bir APNs anahtarı (.p8) yükleyin; `cd ios && pod install` çalıştırıp `Podfile.lock`u commit'leyin.
4. Derlerken `env/dev.json`a `"FIREBASE_ENABLED": true` ekleyin. Bu bayrak olmadan Firebase hiç başlatılmaz
   (iOS'ta plist yokken başlatmak uygulamayı çökertir).
5. Sunucuda `FCM_SERVICE_ACCOUNT_JSON` ve `PUSH_DISPATCH_SECRET` tanımlı olmalı (`docs/MOBIL-API.md`).

Panel açılışta önce `/me/snapshot` ister; alınamazsa rutini doğrudan Supabase'den, o da olmazsa
cihazdaki kopyadan okur. `/today/plan` yüklenemezse panelin geri kalanı çalışmaya devam eder.
Havaya göre öneri metinleri sunucudan Türkçe gelir; İngilizce arayüzde de olduğu gibi gösterilir
(hatırlatıcı başlıkları ise çevrilir).

## Gezinme

Giriş yapmış kullanıcıda üst çubuk ve hamburger menü yoktur; beş sekmeli alt çubuk vardır
(`ui/shell/app_shell.dart`, `AppTab`):

| Sekme | Yol | İçerik |
| --- | --- | --- |
| Bugün | `/dashboard` | günlük takip ekranı; check-in alt sayfası |
| Rutin | `/dashboard/routine` | haftalık plan (gün seçiciyle), ürün listesi; analiz alt sayfası |
| Rebi | `/dashboard/chat` | sohbet |
| Geçmiş | `/dashboard/history` | geçmiş günler |
| Ben | `/dashboard/profile` | hesap özeti, ayar menüsü, görünüm, dil, çıkış |

Sekme köklerinde geri çubuğu yoktur; alt sayfalarda (`/dashboard/checkin`, `/analyze`, `/account`, `/themes`,
`/subscribe`, `/reminders`) üstte "Geri" çubuğu çıkar ve ait olduğu sekmeye döner. Android geri tuşu: alt sayfadan
sekmesine, sekmeden Bugün'e, Bugün'de uygulamadan çıkış. Tanıtım, giriş ve yasal sayfalar (oturum yokken) logo ve
menülü üst çubuğu korur. "Ben" sekmesi eski hamburger menüsünün yerini alır; hesap ve gizlilik ayrıntıları
`/dashboard/account` altındadır.

## Renkler ve karanlık mod

Renkler `ui/tw.dart` içindeki `Tw` alıcılarından okunur ve açık / koyu moda göre değer verir (`Tw.dark`):

- **Tonlar:** 50–300 (açık tint zeminler) koyu modda çok koyu ve sönük olur, 700–950 (koyu metin tonları) açılır,
  400–600 (marka ve vurgu) iki modda da aynı kalır; üstüne beyaz yazı konabilir. Griler elle seçilmiştir.
- **Anlamsal renkler:** `Tw.background` (sayfa), `Tw.surface` (kart), `Tw.surfaceRaised` (alt sayfa, menü),
  `Tw.blueText` (mavi metin). Yeni kodda `Colors.white` yüzey için değil, yalnızca renkli dolgu üstündeki yazı ve
  simge için kullanılır. Her iki modda koyu kalan bölümler (Plus tanıtımı) `Tw.fixed*` sabitlerini kullanır.
- **Kullanıcı temaları** (`rebiThemes`): ana ve vurgu renkleri aynı kalır, açık tint ve koyu tonlar `Tw.adapt` /
  `Tw.adaptText` ile uyarlanır; mod başına bir kez hesaplanır.
- **Mod seçimi:** Ben → Görünüm (Sistem / Açık / Koyu, `rebi-theme-mode`). Uygulama kökü mod değişince alt ağacı
  baştan kurar, böylece `Tw` okuyan her yer yenilenir.
- **Kural:** `const` bir ifadede `Tw` rengi kullanılamaz (alıcılar sabit değildir); sınıf varsayılan parametreleri
  `Color?` olur ve `build` içinde çözülür.
- Testler (`test/dark_mode_test.dart`): metin hiyerarşisi için WCAG AA (4.5:1) kontrast, tüm rotaların koyu modda 390 ve
  320 genişlikte taşmadan çizilmesi, tema ve mod kalıcılığı.

## Cila: yükleme, dokunuş, erişilebilirlik

- **İskelet yükleme** (`ui/widgets/skeleton.dart`): plan ve geçmiş yüklenirken dönen gösterge yerine kart biçiminde
  nabız atan iskelet çıkar; içerik gelince yer değiştirmez. Ekran okuyucuya "Yükleniyor" denir.
- **Dokunsal geri bildirim** (`core/haptics.dart`): kayıt başarılı → hafif, başarısız → orta titreşim; rutin adımı
  işaretlemede seçim titreşimi. Desteklemeyen cihazda sessizce geçilir.
- **Büyük yazı:** sistem yazı boyutu %150 (360 px) ve %200 (320 px) iken ana ekranlar açık ve koyu modda taşmadan çizilir
  (`test/text_scale_test.dart`). Yeni ekranlarda sabit genişlikli `Row` yerine `Expanded` / `Flexible` / `Wrap` kullanın.
- **Henüz yok:** Inter yazı tipi pakete gömülü değil (`google_fonts` çalışma anında indirir; ilk açılış çevrimdışıysa sistem
  yazı tipine düşer).

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
- Push bildirimleri (FCM): uygulama tarafı hazır, Firebase proje dosyaları eklenip `FIREBASE_ENABLED=true`
  verilince açılır (ayrıntı: "Mobil API entegrasyonu → Bildirimler").
