# Mobil abonelik (App Store / Google Play, RevenueCat) ve reklamlar

## Paketler

| Kademe (entitlement) | Günlük Rebi AI sorusu | Tema | Reklam |
|---|---|---|---|
| Ücretsiz | `FREE_CHAT_DAILY_LIMIT` (6) | 4 ücretsiz renk | AdMob banner (Bugün + Geçmiş sayfa sonu) |
| `plus` | 50 | + premium renkler | yok |
| `pro` | 80 | + premium renkler | yok |
| `max` | 120 | + premium renkler | yok |

Her kademe için aylık ve yıllık ürün. Fiyatlar (TRY): Plus 179,99 / 1.799,99 · Pro 229,99 / 2.299,99 · Max 269,99 / 2.699,99 (aylık / yıllık). Günlük sınırlar sunucuda `REBI_TIER_DAILY_LIMITS=plus:50,pro:80,max:120`.
Uygulamadaki tanıtım metni için `mobile/lib/core/subscription.dart > storeTierDailyLimits` (ikisi aynı tutulmalı).

Elle verilmiş eski Plus hesapları (`rebi_plus: true`, `subscription_tier`, `REBI_PLUS_USER_IDS`) aynen çalışır;
sınırsız eski Plus, mağaza kademesinden önceliklidir.

## Nasıl çalışır

1. Uygulama RevenueCat'e Supabase kullanıcı kimliğiyle girer (`Purchases.logIn(auth.users.id)`).
2. Satın alma / yenileme / iptal / iade → RevenueCat `POST https://rebiovil.com/api/webhooks/revenuecat`.
   Satın alma ve geri yükleme sonrası uygulama ayrıca `POST /api/subscription/sync` çağırır.
3. Sunucu olay içeriğine güvenmez: RevenueCat REST API'den güncel hakları okur, en üst etkin kademeyi
   Supabase `auth.users.app_metadata.rebi_store = {tier, expires_at_ms, product_id, store}` alanına yazar.
4. Uygulama oturumu yeniler; kademe JWT ile gelir. Sunucu her istekte `expires_at_ms`'i kontrol eder
   (10 dk yenileme toleransı), yani süre dolunca token'ın yenilenmesi beklenmez.
5. Sohbet kotası: ücretsiz ve ücretli günlük kota aynı günlük sayaçtır; gün içinde paket yükselten kullanıcının
   o güne kadar kullandığı hak yeni sınırdan düşülür. Yanıt `usage_kind: "plan_daily"`.

Veritabanı migration'ı yok; yalnızca `app_metadata` kullanılır.

## Yapılacaklar (panel işleri)

### Durum (2026-11-16)

| Panel | Yapıldı | Kalan |
|---|---|---|
| AdMob | Rebi (Android) `ca-app-pub-2703087426574328~7153628835`, banner `/9835632496`; Rebi (iOS) `~1869512566`, banner `/8522550820`; AB onay mesajı ("İzin vermiyorum" açık) ve IDFA açıklayıcısı (en + tr) yayında; `frontend/public/app-ads.txt` | Uygulamalar mağazada yayınlanınca AdMob'da mağazaya bağla |
| RevenueCat | Entitlement'lar `plus`, `pro`, `max`; iOS uygulaması "Rebi iOS" (In-App Purchase anahtarı geçerli); 6 App Store ürünü entitlement'lara bağlı; `default` offering, 6 paket (`plus_monthly` … `max_yearly`) | Apple bildirim adresinin App Store Connect'e girilmesi, webhook, sunucu anahtarları, iOS SDK anahtarı (`REVENUECAT_APPLE_KEY`), Android uygulaması |
| App Store Connect | Grup `rebiovil_premium_monthly` (ID 21930885, görünen ad "Rebi Abonelik" / "Rebi Subscription"); 6 ürün (`rebi_{max,pro,plus}_{monthly,yearly}`), TRY fiyatları, tr + en adlar, 175 ülke; yıllıklar "1 Year Upfront". Ücretli Uygulamalar sözleşmesi, banka, vergi aktif | In-App Purchase anahtarı (.p8) → RevenueCat; her ürüne inceleme ekran görüntüsü (abonelik ekranı); ilk abonelikler yeni bir uygulama sürümüyle birlikte incelemeye gönderilmeli |
| Play Console | 1.2.0 (15) faturalandırma izinli sürüm Dahili test kanalında (test kullanıcısı yok); abonelikler `rebi_plus`, `rebi_pro`, `rebi_max`, her birinde etkin `monthly` ve `yearly` temel planı. Türkiye fiyatı App Store ile aynı (KDV dahil), diğer ülkeler Play'in otomatik çevirisi | RevenueCat hizmet hesabı (JSON) ve Android uygulaması, anlık bildirimler (Pub/Sub), lisans test kullanıcıları, reklam/veri güvenliği beyanları |


### App Store Connect
1. Uygulama > Abonelikler > tek bir **abonelik grubu** ("Rebi"), içinde 6 ürün. Grup içi sıra (üstten alta):
   Max, Pro, Plus — böylece yükseltme/düşürme Apple tarafından yönetilir.
   Önerilen ürün kimlikleri: `rebi_plus_monthly`, `rebi_plus_yearly`, `rebi_pro_monthly`, `rebi_pro_yearly`,
   `rebi_max_monthly`, `rebi_max_yearly`.
2. Her ürüne fiyat, yerelleştirilmiş ad/açıklama ve inceleme ekran görüntüsü.
3. Users and Access > Integrations > **In-App Purchase** anahtarı (.p8) oluştur → RevenueCat'e yükle.
4. App Store Server Notifications V2 URL'si olarak RevenueCat'in verdiği adresi gir.
5. Ücretli Uygulamalar sözleşmesi + banka/vergi bilgileri tamamlanmış olmalı (yoksa ürünler yüklenmez).
6. App Privacy: "Identifiers > Device ID" (reklam), "Usage Data > Advertising", "Purchases" eklenmeli;
   ATT kullanıldığı için "Used for Tracking" işaretlenmeli.

### Google Play Console
1. Para kazanma > Abonelikler: 3 abonelik (`rebi_plus`, `rebi_pro`, `rebi_max`), her birinde
   `monthly` ve `yearly` temel planı. Fiyat girerken ondalık ayırıcı virgül olmalı ("179,99"); nokta binlik sayılıyor.
   "Set prices" ile girilen fiyat KDV hariç kabul ediliyor, Türkiye satırı ayrıca KDV dahil tutara düzeltilmeli.
2. Google Cloud'da hizmet hesabı → Play Console'da finans izinleri → JSON anahtarı RevenueCat'e.
3. Real-time developer notifications (Pub/Sub) RevenueCat'in yönergesiyle bağlanır.
4. Veri güvenliği formu: reklam kimliği + satın alma geçmişi; "Reklam içerir" işaretlenmeli.

### RevenueCat
1. Proje + iOS ve Android uygulamaları (paket adı `com.rebiovil.mobile`).
2. **Entitlements**: `plus`, `pro`, `max` (bu adlar koddadır, değiştirilmemeli). Her ürünü kendi kademesine bağla.
3. **Offering** `default` (current) içinde 6 paket; paket kimlikleri `plus_monthly`, `plus_yearly`, `pro_monthly`,
   `pro_yearly`, `max_monthly`, `max_yearly` (uygulama kademe/dönemi bu adlardan okur).
4. Integrations > Webhooks: URL `https://rebiovil.com/api/webhooks/revenuecat`, Authorization header'a uzun rastgele
   bir değer → sunucuda `REVENUECAT_WEBHOOK_AUTH`.
5. API keys: Secret key (v1) → sunucuda `REVENUECAT_SECRET_API_KEY`; Public SDK key'ler → mobil env.

### AdMob
1. iOS ve Android uygulamaları ekle, birer **banner** reklam birimi oluştur.
2. Privacy & messaging: AB/İngiltere için **GDPR mesajı** ve iOS için **IDFA açıklama mesajı** yayınla
   (uygulama UMP ile bunları gösterir).
3. Uygulama kimlikleri:
   - iOS: `mobile/ios/Flutter/AdMob.xcconfig` > `ADMOB_APP_ID_IOS` (Rebi iOS kimliği yazılı).
   - Android: `build.gradle.kts` varsayılanı Rebi Android kimliği; `-PADMOB_APP_ID_ANDROID` ile değiştirilebilir.
4. `mobile/ios/Runner/Info.plist > SKAdNetworkItems` listesini Google'ın güncel listesiyle tamamla
   (şu an yalnızca Google'ın kendi kimliği var; reklam geliri için diğer ağlar da eklenmeli).
5. `app-ads.txt`: `frontend/public/app-ads.txt` (deploy sonrası rebiovil.com/app-ads.txt). Mağaza kayıtlarındaki geliştirici web sitesi rebiovil.com olmalı.

## Ortam değişkenleri

Sunucu (`deploy/.env.api` / `backend/.env`):

```
REVENUECAT_SECRET_API_KEY=sk_...
REVENUECAT_WEBHOOK_AUTH=<uzun rastgele değer>
REBI_TIER_DAILY_LIMITS=plus:50,pro:80,max:120
```

Mobil (`mobile/env/prod.json`):

```
"REVENUECAT_APPLE_KEY": "appl_...",
"REVENUECAT_GOOGLE_KEY": "goog_...",
"ADMOB_BANNER_IOS": "ca-app-pub-.../...",
"ADMOB_BANNER_ANDROID": "ca-app-pub-.../..."
```

Anahtar boşsa ilgili özellik kapalı kalır: RevenueCat anahtarı yoksa abonelik sayfası eski davranışına döner,
banner kimliği yoksa reklam yüklenmez ve onay/ATT sorulmaz.

## Test

- iOS: Xcode StoreKit Configuration ya da TestFlight'ta sandbox hesabı. Android: Play Console'da lisans test
  kullanıcısı + dahili test kanalı.
- AdMob'da geliştirirken Google'ın test birim kimlikleri kullanılmalı (iOS `ca-app-pub-3940256099942544/2435281174`,
  Android `ca-app-pub-3940256099942544/9214589741`); gerçek reklama kendi cihazından tıklamak hesabı askıya aldırabilir.
- Sunucu tarafı: `backend/tests/test_store_subscription.py`; mobil: `mobile/test/subscription_test.dart`.
