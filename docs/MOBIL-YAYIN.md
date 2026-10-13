# Rebi mobil: mağazaya yayın rehberi

Kod tarafı hazır, geriye hesap / anahtar / karar gerektiren adımlar kaldı. Bu belge neyin hazır olduğunu,
neyin kimden beklendiğini ve mağaza formlarının taslak cevaplarını toplar. Metinler **taslaktır**: gönderimden önce
sorumlu kişi (ve KVKK danışmanı) okuyup onaylamalıdır.

## 1. Durum özeti

| Konu | Durum |
| --- | --- |
| Paket / bundle kimliği `com.rebiovil.rebi`, iOS takımı `6LVDQJ9UMA` | hazır |
| Android release imzalama (`android/key.properties`) | **kod hazır, anahtar sizde yok** (bölüm 3) |
| Android release derlemesi (R8 + kaynak küçültme, bildirim simgesi korunuyor) | derleme geçiyor (AAB 59,8 MB, 3 ABI; Play cihaza özel daha küçük parça verir); cihazda çalıştırılmadı |
| iOS gizlilik bildirimi (`ios/Runner/PrivacyInfo.xcprivacy`) | hazır, Mac'te derlenmedi (CI derler, bölüm 4) |
| Hata raporlama noktası (`core/crash_reporter.dart`) | hazır, **servis seçilmedi** (bölüm 5) |
| Firebase push | kod hazır, **`google-services.json` / `GoogleService-Info.plist` bekleniyor** |
| Rebi Plus satışı | **ödeme altyapısı yok, karar gerekiyor** (bölüm 6) |
| Mağaza görselleri | **gerçek cihazdan çekilmeli** (bölüm 10) |
| Gerçek cihazda doğrulama | **yapılmadı**: bu geliştirme makinesinde emülatör açılmıyor (bölüm 11) |

## 2. Sürüm numarası

`pubspec.yaml` → `version: 1.0.0+1`. `+` öncesi mağazada görünen sürüm, sonrası derleme numarasıdır
(Android `versionCode`, iOS `CFBundleVersion`). **Her mağaza yüklemesinde derleme numarası artmalıdır**
(`1.0.0+2`, `1.0.1+3`…). Aynı numarayı iki kez yükleyemezsiniz.

## 3. Android (Google Play)

1. **Yükleme anahtarı oluşturun** (bir kez):
   ```bash
   keytool -genkey -v -keystore android/app/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```
2. `android/key.properties.example` dosyasını `android/key.properties` olarak kopyalayıp doldurun. Hem `.jks`
   hem `key.properties` `.gitignore`'dadır; **repoya girmez**. Anahtarı ve parolayı güvenli yerde yedekleyin.
3. Play Console'da uygulamayı oluştururken **"Play Uygulama İmzalama"yı** kabul edin (önerilen). Sizin anahtarınız
   yalnızca yükleme anahtarı olur; kaybolursa Google üzerinden sıfırlanabilir.
4. Ortam dosyası: `cp env/example.json env/prod.json`, değerleri doldurun (`SUPABASE_URL`, `SUPABASE_ANON_KEY`;
   `API_URL` boş kalırsa `https://rebiovil.com/api`). `REBI_PLUS_CHECKOUT_URL` kararınıza göre (bölüm 6).
5. Derleyin:
   ```bash
   tool/build_release.sh android
   ```
   Betik ortam dosyasını doğrular (şablon değeri, yerel adres, http reddedilir), `android/key.properties` yoksa
   **debug anahtarıyla sessizce imzalamak yerine durur**, sonra `build/app/outputs/bundle/release/app-release.aab`
   üretir. Çıktıyı Play Console → Test → Dahili test'e yükleyin.
6. Hedef API seviyesi ve minimum sürüm Flutter'ın varsayılanlarındandır; Play Console uyarırsa Flutter'ı yükseltin.

Android tarafında yapılan sertleştirme: yedekleme kapalı (`allowBackup=false`; oturum ve sağlık verisi bulut
yedeğine gitmez), düz HTTP yalnızca debug derlemesinde, bildirim küçük simgesi tek renkli (`ic_stat_rebi`) ve
kaynak küçültmeden korunuyor (`res/raw/keep.xml`; yoksa release'te bildirimler sessizce görünmeyebilir).
Zamanlanmış bildirimler **tam zamanlı alarm izni istemez** (`inexactAllowWhileIdle`): hatırlatmalar saat
pencerelerinde birkaç dakika kayabilir, Play'in alarm izni politikasına takılmaz.

## 4. iOS (App Store)

Yalnızca Mac + Xcode'da derlenir. Bu repoda iOS hiç derlenmemişti; `Mobile CI` artık her push'ta bir macOS
işinde `flutter build ios --no-codesign` çalıştırır (proje dosyası, Pod çözümü ve `PrivacyInfo.xcprivacy`
paketlemesi doğrulanır).

1. Apple Developer hesabında uygulama kimliği `com.rebiovil.rebi` kayıtlı olmalı; App Store Connect'te uygulama
   kaydı açılmalı.
2. Xcode → Runner → Signing & Capabilities: takım `6LVDQJ9UMA` zaten ayarlı; otomatik imzalama önerilir.
3. `tool/build_release.sh ios` → `build/ios/ipa/*.ipa`; Xcode Organizer ya da Transporter ile yükleyin,
   TestFlight'ta deneyin.
4. **Push açılacaksa:** Xcode'da "Push Notifications" ve "Background Modes → Remote notifications" yeteneklerini
   ekleyin (otomatik `Runner.entitlements` üretir), APNs anahtarını (.p8) Firebase'e yükleyin,
   `GoogleService-Info.plist`'i `ios/Runner` içine ekleyip `FIREBASE_ENABLED=true` verin. Yetenek eklenmeden
   `aps-environment` yazmayın: imzalama profili uyuşmayıp derleme bozulur. Yerel bildirimler bunlar olmadan çalışır.
5. `PrivacyInfo.xcprivacy` toplanan veri türlerini bildirir (bölüm 8); App Store Connect "Uygulama Gizliliği"
   anketiyle **aynı** olmalı. Uygulama izleme (tracking) yapmaz, reklam kimliği kullanmaz.
6. Uygulama iPhone + iPad için işaretli (`TARGETED_DEVICE_FAMILY = 1,2`): iPad ekran görüntüleri de gerekir.
   Yalnızca iPhone isterseniz `1` yapın.

## 5. Hata raporlama

`lib/core/crash_reporter.dart`: tüm çizim ve yakalanmamış asenkron hatalar `CrashReporting.report` üzerinden
geçer (60 sn içinde aynı hata tek sayılır, ileti 300 / yığın 4000 karaktere kısaltılır, **kullanıcı kimliği ya da
istek gövdesi eklenmez**). Şu an yalnızca konsola yazar, çünkü servis seçimi sizin kararınız:

| Seçenek | Artı | Eksi |
| --- | --- | --- |
| Firebase Crashlytics | Firebase zaten kuruluyor (push), ücretsiz | Google'a ek veri aktarımı; Gradle / Xcode betiği (dSYM) kurulumu |
| Sentry | Hesap + DSN yeter, Firebase'den bağımsız, hata gruplama iyi | Ücretsiz katman sınırlı; yeni bağımlılık |

Seçince: ilgili paketi ekleyin, `CrashReporter` arayüzünü uygulayan bir sınıf yazıp `main()` içinde
`CrashReporting.reporter = ...` atayın (yaklaşık 20 satır). Hata raporlama **kişisel veri işlemesi sayılabilir**:
KVKK aydınlatma metnine ve mağaza beyanlarına ("Crash logs / Diagnostics") eklenmeli.

## 6. Rebi Plus ödemesi: karar gerekiyor

Bugün hiçbir yerde Plus satılmıyor: backend'de ödeme kodu yok, Plus hakkı Supabase `app_metadata`'ya elle
yazılıyor, abonelik ekranındaki bağlantı `REBI_PLUS_CHECKOUT_URL` boş olduğundan çıkmıyor. Mağaza kuralları:

- **iOS (App Store 3.1.1):** uygulama içinde açılan dijital özellikler (sınırsız sohbet, premium temalar) için
  uygulama içi satın alma (IAP) zorunlu; harici ödeme bağlantısı yönlendirmesi reddedilir (ABD mağazası gibi
  bölgesel istisnalar vardır, güncel kuralı kontrol edin).
- **Google Play:** dijital ürünler için Play Faturalandırma zorunlu (bölgesel kullanıcı seçimi programları hariç).

| Seçenek | Ne yapılır | Süre / risk |
| --- | --- | --- |
| **A. v1'de Plus'ı mağazada satmayın (önerilen)** | Abonelik ekranındaki geliştirici notu kalkar; ücretsiz kota bitince "yarın yenilenir" gibi nötr mesaj; satın alma yönlendirmesi yok | Birkaç saat. Mevcut durumdan gelir kaybı yok (zaten satılmıyor). Elle Plus verilmiş hesaplar çalışmaya devam eder |
| B. IAP (RevenueCat ya da `in_app_purchase`) | Ürünler iki mağazada tanımlanır, makbuz doğrulaması + webhook ile backend `app_metadata` günceller | 1–2 hafta + mağaza ürün onayı. Kalıcı çözüm; v1.1 için |
| C. Harici ödeme (Stripe / iyzico) bağlantısı | Mevcut `REBI_PLUS_CHECKOUT_URL` | iOS / Play incelemesinde ret riski yüksek |

Not: `tool/build_release.sh`, `REBI_PLUS_CHECKOUT_URL` doluysa uyarır.

## 7. Mağaza metinleri (taslak)

Sınırlar: Play başlık 30, kısa açıklama 80, tam açıklama 4000; App Store ad 30, alt başlık 30, anahtar
kelimeler 100 karakter.

**Türkçe**

- Ad: `Rebi: Cilt Bakım Asistanı`
- Alt başlık (iOS): `Kişisel cilt bakım rutini`
- Kısa açıklama (Play): `Yapay zekâ ile kişisel cilt rutini, günlük takip ve zamanında hatırlatmalar.`
- Anahtar kelimeler (iOS): `cilt bakımı,cilt rutini,yüz bakımı,güneş kremi,SPF,nemlendirici,su takibi,cilt analizi,dermokozmetik`
- Açıklama:

  > Rebi, cildini tanıyan ve her gün yanında olan bakım asistanındır.
  >
  > • Kişisel rutin: cilt tipini ve sorunlarını anlat, isteğe bağlı fotoğraf ekle; sabah ve akşam rutinin hazır olsun.
  > • Bugün ekranı: rutinini adım adım işaretle, "yaptım" de, biten ürünü tek dokunuşla bildir.
  > • Günlük takip: su, makyaj ve nasıl temizlediğin, beslenme, güneş kremi yenileme.
  > • Havaya göre öneri: UV ve sıcaklığa göre güneş kremi, nemlendirici ve dudak balsamı hatırlatması.
  > • Hatırlatıcılar: uyanma ve uyku saatine göre saat aralıklarıyla; bildirimden tek dokunuşla "+250 ml su" ya da "yaptım".
  > • Günlük check-in: uyku, stres ve cilt hissine göre rutinin güncellenir.
  > • Rebi sohbet: bugünkü durumunu bilen yapay zekâ ile cilt bakımı sorularını sor.
  > • Geçmiş: su, uyku, stres ve rutin grafikleri; haftalık özet.
  >
  > Gizlilik: verilerini sen yönetirsin; konum ve fotoğraf isteğe bağlıdır, hesabını uygulama içinden silebilirsin.
  >
  > Önemli: Rebi tıbbi tanı koymaz, tedavi önermez. Öneriler genel cilt bakımı bilgisidir. Ciddi ya da süren cilt
  > sorunlarında bir dermatoloğa danış.

**English**

- Name: `Rebi: Skincare Assistant`
- Subtitle (iOS): `Your personal skincare routine`
- Short description (Play): `AI-guided skincare routine, daily tracking and well-timed reminders.`
- Keywords (iOS): `skincare,skin routine,face care,sunscreen,SPF,moisturizer,water tracker,skin analysis,dermocosmetic`
- Description: yukarıdaki Türkçe metnin çevirisi (özellik listesi aynı; "Rebi does not diagnose or treat medical
  conditions. See a dermatologist for persistent or serious skin problems." cümlesi **zorunlu**).

Tıbbi iddialardan kaçının ("tedavi eder", "teşhis koyar", "akneyi yok eder" yazmayın): App Store 1.4.1 ve Play
sağlık politikası bunları sıkı denetler.

## 8. Gizlilik beyanları

Uygulamanın topladığı veriler (koddan çıkarıldı; `PrivacyInfo.xcprivacy` ile aynı). Hepsi hesaba bağlı, yalnızca
uygulama işlevi için, izleme / reklam yok:

| Veri | App Store türü | Play Data Safety türü | Zorunlu mu |
| --- | --- | --- | --- |
| E-posta | Contact Info → Email Address | Personal info → Email address | evet (kayıt) |
| Ad soyad | Contact Info → Name | Personal info → Name | evet (kayıt) |
| Kullanıcı kimliği | Identifiers → User ID | Personal info → User IDs | evet |
| Yaklaşık konum (~1 km'ye yuvarlanır; hava/UV için) | Location → Coarse Location | Location → Approximate location | hayır |
| Cilt fotoğrafı | User Content → Photos or Videos | Photos and videos → Photos | hayır |
| Cilt tipi / sorunlar, uyku, stres, su, beslenme, makyaj, check-in | Health & Fitness → Health | Health and fitness → Health info | kısmen |
| Yaş, cinsiyet, şehir | Other Data Types | Personal info → Other info | hayır |
| Sohbet mesajları | User Content → Other User Content | Messages → Other in-app messages | hayır |
| Bildirim cihaz kimliği (push) | Identifiers → Device ID | Device or other IDs | hayır |

- **Aktarım şifreli** (HTTPS). **Silme:** uygulama içinde Ben → "Hesap ve gizlilik" → "Hesabı kalıcı olarak sil" (`/account/delete`; profil, rutin,
  check-in, rıza kaydı, fotoğraflar kalıcı silinir).
- **Veri işleyiciler** (mağaza formunda "üçüncü taraflarla paylaşım" sorusu için hukuki görüşle netleştirin): Supabase
  (kimlik, veritabanı, fotoğraf deposu), Google Gemini (yapay zekâ yanıtları: sohbet / rutin metni ve fotoğraf
  değerlendirmesi), hava durumu sağlayıcısı (yalnızca yuvarlanmış koordinat). Bunlar kullanıcı adına işleme yapan
  hizmet sağlayıcılarıdır; Play, bu tür aktarımı "paylaşım" saymayabilir, ancak bunu siz onaylayın.
- **Gerekenler (sizde):** (a) **Gizlilik politikası URL'si**: web'de `https://rebiovil.com/kvkk` (aydınlatma metni)
  var; mağazalar ayrıca bir "gizlilik politikası" sayfası ister, bu sayfa yeterliyse onu girin. (b) Play için **web'de
  veri silme talebi sayfası / e-postası** ("hesap silme URL'si"): şu an yalnızca uygulama içi silme var. (c) Destek
  e-postası / URL'si.
- Yapay zekâ: kullanıcı verisinin yapay zekâ hizmetine gönderileceği açıkça bildirilmeli ve izin alınmalı. Uygulama
  bunu zaten yapıyor (KVKK + açık rıza + yapay zekâ işleme onayı olmadan sohbet / rutin 403 döner).
- Yaş derecelendirmesi: sağlık / sohbet içerikli; App Store anketinde "Tıbbi/tedavi bilgisi" için "seyrek / hafif",
  kullanıcı içeriği için "yok" önerilir. Çocuklara yönelik değildir.

## 9. İnceleme (review) notları

Mağaza incelemecisine verilecek not (gönderim formundaki "Notes for review" alanı):

1. **Demo hesabı** (zorunlu): e-posta + parola, rıza adımları tamamlanmış, bir rutini olan bir hesap. İncelemeci
   kayıt olurken e-posta onayı bekleyemez; onaylı hesap verin. (App Store 2.1)
2. Giriş yalnızca e-posta + parola (üçüncü taraf girişi yok, "Apple ile giriş" gerekmez).
3. Konum izni isteğe bağlı: yalnızca hava / UV'ye göre öneri için, yaklaşık konum. Kamera / fotoğraf: cilt fotoğrafı için,
   isteğe bağlı. Bildirimler: kullanıcı hatırlatma saatlerini ayarlar.
4. Yapay zekâ: rutin ve sohbet yapay zekâ ile üretilir, tıbbi tanı değildir; uygulama içinde açıklama gösterilir.
5. Hesap silme yeri: Ben → "Hesap ve gizlilik" → "Hesabı kalıcı olarak sil".
6. Ücretli abonelik bu sürümde sunulmuyor (bölüm 6, seçenek A) ya da IAP ile sunuluyor.

## 10. Mağaza görselleri

Gerçek cihazdan (ya da simülatörden) çekin; test çıktıları farklı yazı tipiyle çizildiği için mağazada kullanılmaz.
Boyutları gönderimde güncel gereksinimle doğrulayın:

- **App Store:** iPhone 6,9" (1320×2868) en az 3 görsel; iPad 13" (2064×2752) iPad destekleniyorsa.
- **Google Play:** telefon ekran görüntüsü en az 2 (9:16, kenar 320–3840 px); öne çıkan görsel 1024×500; ikon 512×512.
- Çekilecek ekranlar: Bugün (rutin + su kartı), Rutin, Rebi sohbet (öneri çipleriyle), Geçmiş (grafikler), Check-in,
  Hatırlatıcılar, karanlık mod örneği. Kişisel veri göstermeyen, doldurulmuş bir demo hesabı kullanın.
- Uygulama ikonu `assets/icon/icon.png` (`dart run flutter_launcher_icons`; iOS ikonunda alfa kanalı otomatik silinir).

## 11. Gönderimden önce cihazda doğrulama

Aşağıdakiler yalnızca otomatik testle ve derlemeyle doğrulandı; **gerçek telefonda hiç denenmedi**:

- [ ] Kayıt / giriş / çıkış, rıza adımları, hesap silme
- [ ] Android 13+ bildirim izni isteği; zamanlanmış hatırlatmaların saat pencerelerinde gelmesi; telefon yeniden
      başlayınca geri kurulması; bildirim düğmeleri (+250 ml, Yaptım) uygulama kapalıyken
- [ ] Release derlemesinde (R8) bildirim simgesi, hatırlatma, sohbet, fotoğraf yükleme, konum
- [ ] iOS: bildirim düğmeleri, izin metinleri, karanlık mod, iPad düzeni
- [ ] Çevrimdışı kuyruk: uçak modunda kayıt, bağlantı gelince gönderim
- [ ] Büyük yazı boyutu (%150–200) ve ekran okuyucu (TalkBack / VoiceOver)
- [ ] Yazı tipi: uygulama **Inter'i çalışma anında internetten indirir** (`google_fonts`); ilk açılışta çevrimdışıysa
      sistem yazı tipi görünür ve Google'a bir istek gider (gizlilik açısından beyan edin ya da yazı tipini pakete
      gömün).
