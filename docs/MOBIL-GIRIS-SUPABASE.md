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
| 5 | Süresi dolmuş / posta tarayıcısının önceden açtığı bağlantı | Supabase bu hatayı oturum akışına hata olarak yollar; dinleyici yoktu → **yakalanmamış hata** | Hata yakalanır, giriş ekranında nedeniyle gösterilir (+ tekrar gönder) |
| 6 | Supabase hataları ham İngilizce (`Invalid login credentials`, `User already registered`…) | Türkçe kullanıcıya İngilizce cümle | Hata kodu/mesajı türe çevrilir; TR/EN cümleler (`mobileAuth.err*`) |
| 7 | Rıza kaydı sırasında ağ kesilirse `SocketException: …` metni gösteriliyordu | Teknik metin | "Sunucuya bağlanılamadı…" mesajı |

Testler: `mobile/test/auth_flow_test.dart` (17 test: hata sınıflandırma, kayıtlı e-posta, onaysız giriş, tekrar gönder,
parolamı unuttum, sıfırlama oturumu, geçersiz bağlantı). Supabase'e gerçek istek atılmaz.

## 2. SENİN yapman gerekenler (Supabase paneli)

Bunlar kodla yapılamaz; yapılmazsa 3. ve 4. maddeler **çalışmaz** (bağlantı eskisi gibi web sitesine düşer).

### 2.1 Redirect URL ekle (zorunlu)

Supabase Dashboard → **Authentication → URL Configuration → Redirect URLs → Add URL**:

```
com.rebiovil.rebi://auth-callback
```

Mevcut `https://rebiovil.com/**` ve `https://www.rebiovil.com/**` satırları **kalsın** (web onlara bağlı).
**Site URL** (`https://rebiovil.com`) değişmez. Adres listede yoksa Supabase bağlantıyı sessizce Site URL'ye
yönlendirir: kayıt onayı web'e düşer (eskisi gibi), **parola sıfırlama ise çıkmaza girer** (web'de yeni parola ekranı yok).

### 2.2 E-posta gönderimi (SMTP) — canlıya çıkmadan önce kontrol et

Supabase'in yerleşik e-posta servisi yalnızca test içindir: saatte çok az e-posta yollar ve (yeni projelerde)
**yalnızca proje ekibinin adreslerine** gönderir. Gerçek kullanıcılara onay / sıfırlama e-postası gitmesi için
**Authentication → Emails → SMTP Settings**'ten kendi SMTP'ni (Resend, Brevo, Postmark, Gmail Workspace…) tanımla.

Kontrol: panelde ekip dışı yeni bir adresle (kendi ikinci adresin) kayıt ol; onay e-postası dakikalar içinde gelmeli.
Gelmiyorsa uygulamada "Şu an e-posta gönderilemedi" ya da "Kısa sürede çok fazla deneme" mesajını görürsün.

### 2.3 E-posta şablonları (isteğe bağlı ama önerilir)

**Authentication → Emails → Templates** altında "Confirm signup" ve "Reset password" metinlerini Türkçeleştir.
`{{ .ConfirmationURL }}` bağlantısını **silme**; uygulama o bağlantıyla açılır.

## 3. Telefonda doğrulama (cihaz testi)

`MOBIL-CIHAZ-TESTI.md` §1'e ek olarak, 2.1 yapıldıktan sonra:

| # | Adım | Beklenen |
| --- | --- | --- |
| A1 | Yeni bir e-postayla kayıt ol | "Kayıt alındı…" bildirimi; giriş kipine döner; **Onay e-postasını tekrar gönder** görünür |
| A2 | Telefondaki e-postadan onay bağlantısına dokun | **Uygulama açılır** ve içeride olursun (Gmail'in iç tarayıcısı açmazsa "Tarayıcıda aç" de) |
| A3 | Aynı e-postayla tekrar kayıt ol | "Bu e-posta ile zaten bir hesap var…" (e-posta gelmez) |
| A4 | Onaylamadan giriş yapmayı dene | "Bu e-posta henüz onaylanmamış…" + tekrar gönder |
| A5 | Giriş ekranı → **Parolamı unuttum** → e-posta | "Bu adres kayıtlıysa bağlantı gönderdik" |
| A6 | Sıfırlama e-postasındaki bağlantıya dokun | Uygulama açılır, **Yeni parola belirle** ekranı; kaydedince panele geçer |
| A7 | Aynı bağlantıya ikinci kez dokun | "Bağlantı geçersiz ya da süresi dolmuş…" (çökme yok) |
| A8 | Yeni parolayla çıkış yapıp giriş | Girer |

## 4. Bilinen sınırlar

- **iOS** derin bağlantı ayarı (`Info.plist`) eklendi ama Mac olmadığı için hiç çalıştırılmadı; TestFlight'ta doğrula.
- Bağlantı **başka cihazda** (ör. bilgisayardaki e-posta) açılırsa uygulama açılmaz; e-posta yine de onaylanmış olur,
  telefonda elle giriş yapılır. Parola sıfırlama bağlantısı ise **kayıt/istek yapılan aynı telefonda** açılmalıdır (PKCE).
- Web (`frontend/`) bu işte değiştirilmedi: web'de hâlâ "parolamı unuttum" yok. İstersen ayrıca eklenir.
- Parola en az 6 karakter (Supabase varsayılanı). Daha sıkı kural için panelde **Authentication → Policies**.
