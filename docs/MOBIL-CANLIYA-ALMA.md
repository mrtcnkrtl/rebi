# Mobil backend'ini canlıya alma (flutter-mobile → main)

> **Durum (2026-10-19):** birleşme **yapıldı** (`main` = Faz F sonu, fast-forward) ve dağıtım başarılı; canlı `/health` `db_schema: ok`,
> `/me/reminder-settings` 401 (yeni uç canlıda). **Kalan, sende:** "Push'u açınca" bölümündeki VPS anahtarları, duman testi (adım 5) ve
> web'i bir kez elle açmak (adım 6). Aşağısı, aynı işi yeniden yapman gerekirse (örn. yeni backend değişikliği) sırayı korur.

`main`'e her push; backend testleri → frontend lint/build → VPS'te `docker compose up -d --build` çalıştırır
(`.github/workflows/deploy-rebiovil.yml`). Bu yüzden `flutter-mobile`'i birleştirmek **canlıyı değiştirir**.
Aşağıdaki sıra bunu güvenli yapar. Web (`frontend/`) bu dalda değişmedi; web için ek bir adım yok.

## Birleşmeyle canlıya giden ne?

- **Backend**: `/today/plan` (hatırlatıcı ayarı, yerel gün, adım ilerlemesi), yeni `/me/reminder-settings`,
  sohbet için bugünün özeti, su düzeltme (negatif ml), blok yeniden açma, güvenilir push dağıtımı,
  düzeltilmiş hava önbelleği, hesap silmede eksik tablo toleransı.
- **Yeni migration**: `supabase/migrations/20261013120000_reminder_settings.sql` (yeni tablo; mevcut tabloya dokunmaz).
- **Yeni servis**: `push-cron` (5 dk'da bir `/push/dispatch`). `PUSH_DISPATCH_SECRET` tanımlı değilse boşta bekler.
- Mobil kodu (`mobile/`) sunucuya gitmez; uygulama mağazaya ayrıca çıkar.

Web'in kullandığı uçların istek/yanıt biçimleri korunur (`backend/tests/test_web_compat.py` bunu sabitler);
yeni alanlar yalnızca ekleniyor.

## Önce: canlı durumu oku (salt okunur)

```bash
curl -s https://rebiovil.com/api/health
```

2026-10-15'te: `status: ok`, `db_schema: ok`, `push: off`, `push_dispatch` anahtarı **yok** (eski sürüm),
`GET /me/reminder-settings` → **404** (yeni uç yok).

- `db_schema: ok` → sunucu açılışta `supabase/migrations/*.sql` dosyalarını kendisi uygular (DB bağlantısı tanımlı).
  Migration'ı elle çalıştırmana gerek yok.
- `db_schema: skipped` görürsen DB bağlantısı yoktur: birleştirmeden **önce** migration'ı elle uygula:
  `python3 scripts/apply_supabase_migration.py supabase/migrations/20261013120000_reminder_settings.sql`
  (Supabase access token gerekir; dosya tekrar çalıştırılabilir, `if not exists` kullanır).

## Adımlar

1. **VPS'te `deploy/.env.api`'ye push anahtarını ekle** (şimdilik sadece bu; Firebase gelince FCM de eklenir):
   ```bash
   openssl rand -hex 32     # çıkan değeri PUSH_DISPATCH_SECRET= satırına yaz
   ```
   Boş bırakırsan `push-cron` kapalı bekler, başka hiçbir şey etkilenmez. Push'un gerçekten çalışması için
   ayrıca `FCM_SERVICE_ACCOUNT_JSON` (Firebase servis hesabı) gerekir.
2. **PR aç** (`flutter-mobile` → `main`), CI'ın (backend 306 test, frontend lint+build, mobil analiz+test+derleme) yeşil olduğunu gör.
3. **Birleştir.** GitHub Actions dağıtımı başlatır; `docker compose ps` ile `api` ve `push-cron` konteynerlerinin `healthy` olmasını bekle.
4. **Doğrula:**
   ```bash
   curl -s https://rebiovil.com/api/health        # db_schema: ok, push_dispatch anahtarı var
   curl -s -o /dev/null -w "%{http_code}\n" "https://rebiovil.com/api/me/reminder-settings?user_id=x"   # artık 401 (404 değil)
   ```
5. **Duman testi** — özel bir TEST hesabıyla (müşteri hesabıyla değil):
   ```bash
   export REBI_SMOKE_TOKEN='<test hesabının access_token değeri>'
   python3 scripts/smoke_mobile_api.py --api https://rebiovil.com/api --write
   ```
   Tüm satırlar GEÇTİ olmalı. `--write` o hesaba +10/−10 ml'lik iki su olayı bırakır.
6. **Web'i bir kez elle aç** (giriş, rutin, check-in, sohbet) — uçlar korunuyor ama son bakış senin.

## Sorun olursa geri alma

`main`'de birleşme commit'ini `git revert -m 1 <sha>` ile geri al ve push et; dağıtım eski sürüme döner.
Migration yeni bir tablo ekliyor ve eski kod onu kullanmıyor; tabloyu silmeye gerek yok, veri kaybı olmaz.
Hesap silme, tablo hiç olmasa bile çalışmaya devam eder.

## Push'u açınca (Firebase dosyaları geldikten sonra)

1. `deploy/.env.api`: `FCM_SERVICE_ACCOUNT_JSON` ve `PUSH_DISPATCH_SECRET` dolu olsun, `docker compose up -d`.
2. `/health` → `push: configured`; `push-cron` 5 dakika içinde ilk turu çalıştırır ve `push_dispatch.at` dolar.
3. `docker compose logs -f push-cron` satırı: `kullanıcı=… hatırlatıcı=… bildirim=… başarısız=…`.
   `başarısız` sürekli sıfırdan büyükse FCM'e ulaşılamıyordur (anahtar/proje kimliği).
4. Çift bildirim önlemi hazır (Faz E4): mobil, `/devices/register` yanıtındaki `dispatch_alive` true iken yerel bildirimleri kaldırır, false iken
   yeniden kurar. Doğrulama: `docs/MOBIL-BILDIRIM-TEST.md` §5.
