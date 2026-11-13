# Mobil giriş / kayıt ↔ Supabase (denetim ve kurulum)

Bu belge, uygulamanın Supabase Auth ile bağlantısının **kodda** ve **Supabase panelinde** ne durumda olduğunu,
2026-10-20'de yapılan denetimin sonuçlarını ve senin yapman gereken panel ayarlarını toplar.

## 1. Zincir ve denetim sonucu

```
Telefon ──(e-posta+parola)──▶ Supabase Auth ──(access token, ES256)──▶ Telefon
Telefon ──(Authorization: Bearer <token>)──▶ FastAPI (rebiovil.com/api) ──(JWKS ile doğrular)──▶ Supabase DB
```

| Halka | Durum | Nasıl bakıldı |
| --- | --- | --- |
| Mobil, web ve sunucu **aynı Supabase projesi** (`eulcargzcatxdbjevkpm`) | ✅ | `mobile/env/dev.json` ile canlı web paketindeki URL/anon anahtarı karşılaştırıldı |
| Supabase Auth ayakta, anon anahtarı geçerli | ✅ | `/auth/v1/health` 200, `/auth/v1/settings` 200 |
| E-posta ile kayıt açık, **e-posta onayı zorunlu** (`mailer_autoconfirm=false`) | ✅ (bilgi) | `/auth/v1/settings` |
| Sunucu token'ı doğruluyor (imza ES256 → JWKS) | ✅ | `/auth/v1/.well-known/jwks.json` ES256 anahtar döndürüyor; `/health` `jwt_auth: on`; korumalı uçlar tokensiz 401 |
| Android **release** derlemesinde internet izni | ✅ | `AndroidManifest.xml` ana dosyasında var (yalnız debug'da olsaydı yayında hiçbir şey bağlanmazdı) |
| Rıza kaydı: giriş sonrası `POST /legal-consent/accept` | ✅ | `test/auth_flow_test.dart` |

### Bulunan ve kapatılan kopukluklar (mobil kodu)

| # | Sorun | Sonuç (önce) | Düzeltme |
| --- | --- | --- | --- |
| 1 | **Kayıtlı e-postayla yeniden kayıt**: e-posta onayı açıkken Supabase hata vermez, e-posta da göndermez | "Onay e-postası gönderdik" diyordu; gelmeyen e-postayı bekleyen kullanıcı çıkmazda kalıyordu | `identities` boşsa "Bu e-posta zaten kayıtlı, giriş yap / parolamı unuttum" gösterilir |
| 2 | **Onaysız e-posta ile giriş** | Ham İngilizce "Email not confirmed", yapacak bir şey yok | Açıklama + **Onay e-postasını tekrar gönder** |
| 3 | **Parola sıfırlama hiç yoktu** (webde de yok) | Parolasını unutan kullanıcı hesabına bir daha giremiyordu | **Parolamı unuttum** → e-postadaki bağlantı uygulamayı açar → **yeni parola belirle** ekranı |
| 4 | Onay bağlantısı uygulamayı değil, **web sitesini** açıyordu | Kullanıcı tarayıcıda kalıyor, uygulamaya elle dönüp giriş yapıyordu | Bağlantı `com.rebiovil.rebi://auth-callback` ile uygulamayı açar ve oturumu kurar (Android/iOS derin bağlantı ayarı eklendi) |
| 5 | Uygulamaya hata parametresiyle dönen bağlantı (`#error=…`) | Hata oturum akışına düşer; dinleyici yoktu → **yakalanmamış hata** | Hata yakalanır, giriş ekranında nedeniyle gösterilir (+ tekrar gönder). **Not:** kullanılmış/süresi dolmuş tek kullanımlık bağlantıda Supabase uygulamaya hiç yönlendirmez, tarayıcıda ham `otp_expired` JSON'u gösterir (bkz. A7); uygulama bunu göremez |
| 6 | Supabase hataları ham İngilizce (`Invalid login credentials`, `User already registered`…) | Türkçe kullanıcıya İngilizce cümle | Hata kodu/mesajı türe çevrilir; TR/EN cümleler (`mobileAuth.err*`) |
| 7 | Rıza kaydı sırasında ağ kesilirse `SocketException: …` metni gösteriliyordu | Teknik metin | "Sunucuya bağlanılamadı…" mesajı |
| 8 | KVKK / açık rıza kutuları **girişte de** zorunluydu ve rıza kaydı girişi engelliyordu (kayıtta e-posta onayı beklenirken oturum olmadığı için rıza ilk girişte yazılıyordu) | Her girişte aynı kutular; rıza yazılamazsa (`Rıza kaydı oluşturulamadı`) kullanıcı **içeri alınmıyordu** | Yasal metinler ve onay kutuları **yalnızca kayıt ekranında**. Kayıttaki seçimler Supabase `user_metadata.legal_consent` içinde taşınır, ilk oturum açılışında (şifreyle giriş ya da e-posta bağlantısı) sunucuya yazılır. Yazılamazsa giriş **engellenmez**; açılış paketi eksik rızayı görüp mevcut "rıza kutusu"nu açar |
| 9 | **Onay bağlantısına dokununca `{"code":403,"error_code":"otp_expired","msg":"Email link is invalid or has expired"}`** (2026-10-28 telefon testi: Gmail → tarayıcı, ham JSON, "verify.json" indirme önerisi) | Kullanıcı hatalı bir şey yapmamıştı. Supabase'in `{{ .ConfirmationURL }}` bağlantısı **tek kullanımlıktır ve ilk GET isteğinde tüketilir**. Gmail / Outlook / antivirüs gibi bağlantı tarayıcıları e-postadaki bağlantıyı kullanıcıdan **önce** açar: hesap o anda onaylanır, kullanıcı tıklayınca "geçersiz" JSON'unu görür. Aynı hata, yeniden gönderilen e-postalarda **eski** e-postanın bağlantısında da çıkar (her yeni e-posta öncekini geçersiz kılar). Uygulama bunu göremez (bkz. #5 / A7) | Bkz. **§1.1**: e-postaya **6 haneli kod** + **rebiovil.com/auth/confirm** düğmesi; sayfa token'a ancak kullanıcı dokununca dokunur; hata sayfaları Türkçe ve "hesabın onaylanmış olabilir, giriş yap" der; uygulamada kod ekranı |

### 1.1 Onay e-postası akışı (2026-10-28, #9'un çözümü)

```
Kayıt ─▶ Supabase e-posta yollar:  [ 6 haneli kod ]  +  [ E-postamı onayla ] düğmesi
  │
  ├─ Kodu uygulamaya yaz ─────────────▶ verifyOTP(signup) ──▶ oturum açık ──▶ panele
  │                                      (bağlantı yok → tarayıcı tüketemez; başka cihazdaki e-postadan da çalışır)
  │
  └─ Düğme ─▶ https://rebiovil.com/auth/confirm?token_hash=…&type=signup
                │   sayfa açılınca HİÇBİR istek atmaz (token tüketilmez)
                └─ "E-postamı onayla"ya dokununca verifyOtp ─▶ "E-postan onaylandı"
                      ├─ Rebi uygulamasını aç ─▶ uygulama kod ekranındaysa girişi kendiliğinden dener
                      │                          (ya da "Onayladım, devam et")
                      └─ Web'de devam et ─▶ /dashboard (web oturumu açık)
```

| Parça | Dosya |
| --- | --- |
| E-posta şablonu (TR, markalı, görselsiz) | `deploy/supabase/email-templates/confirm-signup.html` |
| Web onay sayfası + yardımcıları | `frontend/src/pages/ConfirmEmail.jsx`, `frontend/src/lib/emailConfirm.js`, rota `/auth/confirm` (`App.jsx`), metinler `frontend/src/locales/{tr,en}/common.json` → `authConfirm` |
| Uygulama kod ekranı (`verify` kipi) | `mobile/lib/screens/auth_screen.dart`, `AuthController.verifySignupCode` |
| Testler | `mobile/test/auth_flow_test.dart` (grup "e-posta onay kodu"), `mobile/test/accessibility_test.dart` ("Giriş · e-posta kodu") |

Davranışlar:

- **Kod ekranı**: kayıttan sonra açılır. Altı hane tamamlanınca kendiliğinden gönderilir; yanlış/süresi dolmuş kod anlaşılır cümleyle bildirilir. **Kodu tekrar gönder** Supabase'in dakikada bir sınırına uygun olarak 60 sn bekletilir; yeni e-postadaki kod eskisini geçersiz kılar.
- **Onaysız girişte** "Onay e-postasını tekrar gönder" artık kod ekranına geçirir (yeni kod yazılabilsin diye).
- **Uygulamaya dönünce**: kod ekranındayken kullanıcı e-postadaki düğmeyle onaylayıp döndüyse, ekranda tutulan e-posta + parolayla giriş sessizce denenir (en fazla 5 sn'de bir; hata göstermez). Elle: **Onayladım, devam et**. Parola bellekte yalnızca bu ekran açıkken durur.
- **Web hata sayfası** (`otp_expired`): "Bu bağlantı artık geçerli değil… hesabın aslında onaylanmış olabilir: önce giriş yapmayı dene" + giriş düğmesi + yeni onay e-postası isteme formu. Ham JSON hiçbir yerde görünmez.
- Şablona **kullanıcının girdiği ad eklenmedi** (bilerek): Supabase şablonuna basılan kayıt adı, başkasının adresiyle kayıt olan biri tarafından e-postaya sahte içerik sokmak için kullanılabilir.

### Rıza akışı (kayıt → ilk giriş)

1. **Kayıt ekranı:** KVKK + açık rıza (zorunlu), konum/fotoğraf (isteğe bağlı). Seçimler `signUp(data: {legal_consent: {...}})` ile kullanıcı bilgisine konur.
2. E-posta onayı beklerken oturum yoktur, sunucuya yazılamaz: kayıt "Kayıt alındı…" ile biter.
3. **İlk oturum açılışı** (`signedIn` olayı; şifreyle giriş, e-postadaki kod ya da onay bağlantısı): `syncPendingLegalConsent` önce `GET /legal-consent/status` ile sunucuya bakar;
   kayıt **yoksa** `POST /legal-consent/accept` yazar, **varsa** dokunmaz (kullanıcının sonradan değiştirdiği izinler ezilmesin).
   Bu sırada açılış senkronu ve giriş yönlendirmesi bekler (rıza kutusu boşuna açılmasın).
4. Başarısızlıkta sessizce geçilir; `/me/snapshot` rıza eksikliğini bildirirse mevcut **rıza kutusu** (yasal metin + kutular) açılır. Yapay zekâ uçları rıza olmadan zaten 403 döner.
5. Metin sürümü (`v2`) değişirse metadata'daki eski seçim geçersiz sayılır; kullanıcı rıza kutusuyla yeniden onaylar.

Yasal metinlerin okunabileceği yerler: kayıt ekranındaki bağlantılar, karşılama ekranının altı ve Ben → Hesap ve gizlilik (mağaza kuralları için uygulama içinde erişilebilir kalmalı).

Testler: `mobile/test/auth_flow_test.dart` (34 test: hata sınıflandırma, kayıtlı e-posta, onaysız giriş, tekrar gönder, **e-posta onay kodu**
(otomatik gönderim, yanlış kod, bekleme süresi, "Onayladım", uygulamaya dönünce otomatik giriş), parolamı unuttum,
sıfırlama oturumu, geçersiz bağlantı, girişte rıza kutusu yok, kayıttaki rızanın ilk girişte yazılması). Supabase'e gerçek istek atılmaz.

## 2. SENİN yapman gerekenler (Supabase paneli)

Bunlar kodla yapılamaz; yapılmazsa 3. ve 4. maddeler **çalışmaz** (bağlantı eskisi gibi web sitesine düşer).

### 2.1 Redirect URL ekle (zorunlu)

Supabase Dashboard → **Authentication → URL Configuration → Redirect URLs → Add URL**:

```
com.rebiovil.rebi://auth-callback
```

Bu adres artık yalnızca **parola sıfırlama** için gerekir (kayıt onayı yeni şablonla Supabase yönlendirmesine bağlı değildir, bkz. §2.3).
Mevcut `https://rebiovil.com/**` ve `https://www.rebiovil.com/**` satırları **kalsın** (web onlara bağlı).
**Site URL** (`https://rebiovil.com`) değişmez. Adres listede yoksa Supabase bağlantıyı sessizce Site URL'ye
yönlendirir: kayıt onayı web'e düşer (eskisi gibi), **parola sıfırlama ise çıkmaza girer** (web'de yeni parola ekranı yok).

### 2.2 E-posta gönderimi (SMTP) — canlıya çıkmadan önce kontrol et

Supabase'in yerleşik e-posta servisi yalnızca test içindir: saatte çok az e-posta yollar ve (yeni projelerde)
**yalnızca proje ekibinin adreslerine** gönderir. Gerçek kullanıcılara onay / sıfırlama e-postası gitmesi için
**Authentication → Emails → SMTP Settings**'ten kendi SMTP'ni (Resend, Brevo, Postmark, Gmail Workspace…) tanımla.

Kontrol: panelde ekip dışı yeni bir adresle (kendi ikinci adresin) kayıt ol; onay e-postası dakikalar içinde gelmeli.
Gelmiyorsa uygulamada "Şu an e-posta gönderilemedi" ya da "Kısa sürede çok fazla deneme" mesajını görürsün.

### 2.3 "Confirm signup" e-posta şablonu — ZORUNLU (#9 hatası bunu yapınca kapanır)

**Sıra önemli.** Önce web sayfası canlıya çıkmalı, sonra şablon değişmeli; tersi olursa e-postadaki düğme ana sayfaya düşer.

1. Bu dalı `main`'e birleştirip canlıya al (GitHub Actions `Deploy rebiovil`). Kontrol: tarayıcıda `https://rebiovil.com/auth/confirm` aç →
   **"Bağlantı eksik görünüyor"** sayfası gelmeli (token yok, beklenen sonuç). Ana sayfaya düşüyorsa henüz canlıda değildir.
2. Supabase Dashboard → **Authentication → Emails → Templates → Confirm signup**:
   - **Subject**: `Rebi hesabını onayla` (konuya şablon değişkeni koyma)
   - **Message body**: `deploy/supabase/email-templates/confirm-signup.html` dosyasının **tamamını** yapıştır (kaynak / HTML görünümünde) → **Save**.
   - Şablondaki `{{ .Token }}` (6 haneli kod), `{{ .TokenHash }}` (düğme bağlantısı) ve `{{ .Email }}` değişkenlerini **silme / değiştirme**.
     Düğmenin adresi `https://rebiovil.com` sabittir (Site URL'ye bağlı değildir).
3. **Authentication → Sign In / Providers → Email** (panel sürümüne göre yeri biraz değişebilir): **Email OTP Length = 6** olmalı
   (uygulama tam 6 hane bekler; başka değer kod ekranını bozar), **Email OTP Expiration = 3600** (1 saat; şablondaki "1 saat geçerlidir" cümlesiyle uyumlu).
4. Kontrol: ekip dışı bir adresle yeni kayıt ol → e-posta Türkçe/markalı gelmeli, kodu uygulamaya yazınca içeri girmeli (bkz. §3 A1–A2).

**"Reset password" şablonu henüz değişmedi**: parola sıfırlama e-postası hâlâ Supabase'in tek kullanımlık `{{ .ConfirmationURL }}`
bağlantısını kullanır; aynı bağlantı-tarayıcısı sorununa (A7) açıktır. Aynı kod + sayfa yöntemi sıfırlama için de uygulanabilir (bkz. §4).

## 3. Telefonda doğrulama (cihaz testi)

`MOBIL-CIHAZ-TESTI.md` §1'e ek olarak, 2.1 yapıldıktan sonra:

| # | Adım | Beklenen |
| --- | --- | --- |
| A1 | Yeni bir e-postayla kayıt ol | "Kayıt alındı…" bildirimi; **"E-postanı onayla" kod ekranı** (tek alan: 6 haneli kod); "Tekrar gönder (NN sn)" 60 sn sonra açılır. E-posta **Türkçe, yeşil başlıklı, kodlu** gelir (şablon §2.3 yapıldıysa) |
| A2 | E-postadaki **6 haneli kodu** kod alanına yaz | Altıncı haneyle birlikte kendiliğinden gönderilir; **içeri girersin** (rıza kutusu çıkmaz) |
| A2b | Yeni kayıtta bu kez e-postadaki **"E-postamı onayla"** düğmesine dokun | Tarayıcıda `rebiovil.com/auth/confirm` açılır, **"Hesabını onayla"** + düğme (Gmail'in iç tarayıcısı da olur); dokununca **"E-postan onaylandı"** + "Rebi uygulamasını aç". Uygulamaya dönünce (kod ekranı açıksa) **kendiliğinden içeri girer**; girmezse **Onayladım, devam et** |
| A2c | A2b'deki sayfayı aynı e-postadaki düğmeyle **ikinci kez** aç, "E-postamı onayla"ya dokun | Ham JSON **yok**: "Bu bağlantı artık geçerli değil… hesabın onaylanmış olabilir: giriş yapmayı dene" + Giriş yap + yeni e-posta isteme formu |
| A2d | Kod ekranında yanlış kod yaz (ör. 000000) | "Kod yanlış ya da süresi dolmuş…" mesajı; ekranda kalırsın |
| A3 | Aynı e-postayla tekrar kayıt ol | "Bu e-posta ile zaten bir hesap var…" (e-posta gelmez) |
| A4 | Onaylamadan giriş yapmayı dene | "Bu e-posta henüz onaylanmamış…" + tekrar gönder |
| A5 | Giriş ekranı → **Parolamı unuttum** → e-posta | "Bu adres kayıtlıysa bağlantı gönderdik" |
| A6 | Sıfırlama e-postasındaki bağlantıya dokun | Uygulama açılır, **Yeni parola belirle** ekranı; kaydedince panele geçer |
| A7 | **Parola sıfırlama** bağlantısına ikinci kez dokun (bu e-posta henüz eski yöntemde, bkz. §2.3 sonu) | Tarayıcıda Supabase'in `{"code":403,"error_code":"otp_expired",…}` sayfası açılır (**Supabase kullanılmış/süresi dolmuş bağlantıyı uygulamaya yönlendirmez**, ham JSON gösterir; 2026-10-20 telefon testinde görüldü). Uygulamaya dön: giriş ekranından **tekrar gönder** / **Parolamı unuttum** ile yeni bağlantı iste |
| A8 | Yeni parolayla çıkış yapıp giriş | Girer |
| A9 | Giriş ekranını aç | KVKK / açık rıza metni ve onay kutusu **yok**; yalnız e-posta + parola |
| A10 | A1'deki kayıttan sonra (onay bağlantısına dokunup ya da şifreyle) ilk kez içeri gir | **Rıza kutusu çıkmaz** (kayıtta verilen rıza arka planda yazıldı); Ben → Hesap ve gizlilik'te izinler kayıttaki seçimle aynı |
| A11 | Rıza kaydı sunucuda başarısız olursa (ör. sunucu kapalı) | Giriş **engellenmez**; panel açılır ve rıza kutusu bir kez sorar |

## 4. Bilinen sınırlar

- **iOS** derin bağlantı ayarı (`Info.plist`) eklendi ama Mac olmadığı için hiç çalıştırılmadı; TestFlight'ta doğrula.
- Bağlantı **başka cihazda** (ör. bilgisayardaki e-posta) açılırsa uygulama açılmaz; e-posta yine de onaylanmış olur,
  telefonda elle giriş yapılır. Parola sıfırlama bağlantısı ise **kayıt/istek yapılan aynı telefonda** açılmalıdır (PKCE).
- Web'de "parolamı unuttum" hâlâ yok (`frontend/` yalnızca onay sayfası eklendi). İstersen ayrıca eklenir.
- **Parola sıfırlama e-postası** henüz eski yöntemde (tek kullanımlık Supabase bağlantısı): Gmail/antivirüs bağlantıyı önceden açarsa A7'deki ham JSON çıkabilir.
  Çözüm aynı kalıp: Türkçe şablon + 6 haneli kod + `rebiovil.com/auth/confirm` benzeri bir sayfa; uygulamada "kodu yaz → yeni parola". Henüz yapılmadı.
- Web onay sayfası **canlıya çıkmadan** şablon değiştirilirse e-postadaki düğme ana sayfaya düşer (§2.3 sırası). Kod yöntemi sayfadan bağımsız çalışır.
- "Rebi uygulamasını aç" düğmesi özel şemayı (`com.rebiovil.rebi://`) kullanır; uygulama yüklü değilse ya da iOS'ta TestFlight/mağaza sürümü yoksa
  hiçbir şey olmaz (sayfada "Web'de devam et" yedek olarak durur). Evrensel bağlantı (https://rebiovil.com → uygulama) mağaza sonrası ayrı bir iş.
- Kod ekranındaki otomatik giriş yalnızca ekran **açıkken** çalışır; uygulama kapatılıp yeniden açılırsa normal giriş yapılır (onaylıysa girer; değilse
  "henüz onaylanmamış" + kod ekranına geçiren tekrar gönder).
- Parola en az 6 karakter (Supabase varsayılanı). Daha sıkı kural için panelde **Authentication → Policies**.
