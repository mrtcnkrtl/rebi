# Reklam kampanyası öncesi kontrol listesi

Hedef: kampanyanın ilk haftasında 1.000–5.000 yeni kullanıcı. Kod tarafındaki ölçek işleri yapıldı (aşağıda "Kodda
yapılanlar"). Bu sayfadaki **"Senin yapacakların"** kodla çözülemez: panel ayarı, plan yükseltmesi ya da sunucuda
komut gerektirir. Sıra önemlidir; ilk üç madde yapılmadan kampanya başlatılmamalı.

Canlı durum (2026-11-13, `https://rebiovil.com/api/health`): `redis: ok`, `db_integrity: ok`, `db_schema: ok`,
**`push: off`** (sunucuda bildirim anahtarı yok), **`retention: no_pg_cron`** (eski veri temizliği çalışmıyor).

## Senin yapacakların

### 1. E-posta (SMTP) — KRİTİK, kampanyayı en çok bu durdurur

Supabase'in yerleşik e-posta servisi saatte yalnızca birkaç e-posta gönderir ve yalnızca test içindir. Kendi SMTP'n
yoksa yeni kullanıcıların çoğu onay kodunu hiç almaz ve kayıt yarıda kalır.

1. Bir e-posta servisi aç (Resend, Brevo veya Postmark; üçünün de ücretsiz/ucuz başlangıç katmanı var) ve
   `rebiovil.com` alan adını doğrula (servis DNS'e SPF/DKIM kayıtları eklemeni ister; bunlar olmadan e-postalar spama düşer).
2. Supabase → **Authentication → Emails → SMTP Settings** → servisin verdiği host/port/kullanıcı/parolayı gir,
   gönderen: `Rebi <no-reply@rebiovil.com>`.
3. Supabase → **Authentication → Rate Limits** → "emails sent per hour" değerini yükselt (özel SMTP'den sonra
   varsayılan saatte 30 civarıdır; kampanya için en az **300**). "Sign-ups and sign-ins per 5 minutes per IP" değerini
   de düşük bırakma: mobil operatörler binlerce kullanıcıyı aynı IP'nin arkasına koyar (CGNAT).
4. Kontrol: ekip dışı bir adresle kayıt ol; kod 1 dakika içinde gelmeli. Ayrıntı: `docs/MOBIL-GIRIS-SUPABASE.md` §2.2–2.3.

### 2. Supabase planı: Free → Pro

Free plan kampanya için dar: veritabanı 500 MB, aylık egress birkaç GB, günlük yedek yok, bağlantı sınırları düşük.
Pro (aylık ~25 USD) bunları birkaç kat genişletir ve günlük yedek getirir. **Settings → Billing**'den yükselt.
Yükseltmeden sonra **Reports → Database**'de bağlantı sayısına ve CPU'ya göz at.

### 3. Yapay zekâ (Gemini) maliyeti ve kotası

- Google AI Studio / Cloud'da **ücretli katmanın** açık olduğunu doğrula (ücretsiz katmanın dakikalık istek sınırı
  birkaç düzine kullanıcıda dolar; kullanıcı sohbette "yanıt veremedim" görür).
- Google Cloud → Billing → **Budgets & alerts**: aylık bütçe + %50/%90 e-posta uyarısı.
- Günlük tavan: sunucuda `deploy/.env.api` içine `GEMINI_DAILY_BUDGET_USD=20` (örnek değer; mesaj başı ~0,002 USD →
  günde ~10.000 mesaj). Dolunca sohbet çökmez, bilgi tabanı özetine düşer.

### 4. Bildirimler ve veri temizliği (sunucuda)

- `push: off` → `deploy/.env.api`'ye `FCM_SERVICE_ACCOUNT_JSON` ve `PUSH_DISPATCH_SECRET` ekle (adımlar:
  `docs/MOBIL-CANLIYA-ALMA.md` "Push'u açınca"). Bu olmadan hatırlatıcılar telefona gitmez.
- `retention: no_pg_cron` → ya Supabase → Database → Extensions'tan **pg_cron**'u aç, ya da `deploy/.env.api`'ye
  `RETENTION_PURGE_DAILY=1` yaz (push-cron günde bir temizlik yapar). Kullanıcı sayısı artınca `daily_events` büyür.
- Değişiklikten sonra: `docker compose -f docker-compose.yml -f docker-compose.https.yml up -d`.

### 5. Sunucu boyutu ve işçi sayısı

- Hostinger panelinde VPS'in çekirdek/RAM değerine bak (ya da sunucuda `nproc` ve `free -m`).
- API varsayılan olarak **2 işçiyle** açılır (bir işçi ~180 MB). Sunucu 4+ çekirdek / 8 GB ise repo kökündeki `.env`'e
  `WEB_CONCURRENCY=4` yaz ve canlı yük testinde (madde 6) iyileştiğini gör. 1 çekirdekli sunucuda 2'de kal.
- 2 GB'tan az RAM varsa kampanyadan önce bir üst plana geç.

### 6. Canlı yük testi (düşük trafikli bir saatte)

Komutlar ve sonuçların okunuşu: `docs/YUK-TESTI.md`. Hedef: 50 sanal kullanıcıda `SONUÇ: GEÇTİ`
(5.000 kayıtlı kullanıcının tepe saatinin ~10 katı yük). Bitince mutlaka `cleanup --yes`.

### 7. Kesinti izleme

[UptimeRobot](https://uptimerobot.com) (ücretsiz) ya da benzeri bir servisle `https://rebiovil.com/api/health`'i 1-5
dakikada bir yoklat, düşerse e-posta/SMS gelsin. Uç 200 ve `"status":"ok"` dönmeli.

### 8. Kampanya süresince

- **Tepe saatlerde deploy etme.** Her deploy API'yi ~30-40 sn yeniden başlatır. Bu sırada mobil uygulama olayları
  kuyrukta tutar ve kaybolmaz, ama açılış ekranı "sunucu yanıt vermiyor" diyebilir.
- Günde bir kez: `/health`, Supabase Reports, Google Cloud faturası, `docker stats --no-stream`, `df -h`.

## Kodda yapılanlar (2026-11-13)

| Ne | Neden |
|---|---|
| API çok işçili (`WEB_CONCURRENCY`, varsayılan 2) | Python tek süreçte tek çekirdek kullanır; yerel ölçümde aynı yükte istek/sn 425→603, p95 ~400→~85 ms |
| Açılış migration'ları Postgres danışma kilidiyle | Birden çok işçi aynı anda açılınca migration'lar yarışmasın |
| Push imleci, son tur özeti ve "tek tur" kilidi Redis'te (`shared_state.py`) | Cron isteği hangi işçiye düşerse düşsün tur kaldığı yerden sürer; iki tur aynı anda çalışmaz |
| Postgres bağlantı havuzu (`psycopg_pool`) | Bilgi tabanı sorgularında her seferinde yeni TLS bağlantısı (~100-300 ms) yerine açık bağlantı; toplam bütçe işçilere bölünür |
| `prepare_threshold=0` → `None` | 0 her sorguyu hazırlar (pooler'da hata); None kapatır |
| nginx: IP başına kenar hız sınırı, gzip, gerçek upstream keepalive, API kapalıyken JSON 503, `resolve` | Sel koruması, mobil veride 3-5 kat küçük JSON, ara sıra 502'lerin önlenmesi, deploy sonrası eski IP'ye gidilmemesi |
| Deploy'da `nginx -t` + reload, CI'da canlı imajla `nginx -t` | Ayar dosyası konteynere bağlı olduğu için değişiklikler eskiden devreye girmiyordu; bozuk ayar sunucuya ulaşmaz |
| Docker log rotasyonu (servis başına 5×20 MB) | Sınırsız günlük yoğun trafikte diski doldurup sunucuyu durdurur |
| Düzgün kapanma (uvicorn 25 sn, Docker 30 sn) | Deploy sırasında süren sohbet istekleri kesilmesin |
