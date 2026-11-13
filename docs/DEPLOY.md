# Rebi — üretim dağıtım özeti

Bu liste yeni ortam açarken veya gözden geçirirken kullanılır. Ayrıntılı env açıklamaları için `backend/.env.example` dosyasına bakın.

## 1. Supabase

- [ ] Proje oluşturuldu; **URL**, **anon** ve **service_role** anahtarları kayıtlı.
- [ ] Tek yetkili kaynak olan `supabase/migrations/` sırasıyla uygulandı. Backend DB bağlantısı varsa checksum’lı migration takibini otomatik yapar.
- [ ] `database/` altındaki eski SQL dosyaları üretime uygulanmadı; yalnızca tarihsel referanstır.
- [ ] Tablolar: `profiles`, `assessments`, `routines`, `daily_logs`, `daily_events`, `knowledge_base` (+ gerekli indeksler).
- [ ] RLS politikaları üretim beklentisiyle uyumlu; `knowledge_base` ve `skin-photos` storage politikaları uygulandı.
- [ ] `skin-photos` bucket private; yalnızca sahibinin klasörüne erişen RLS ve signed URL akışı etkin.
- [ ] Şema değişikliğinden sonra gerekirse **API → Reload schema cache**.

## 2a. rebiovil.com (Docker)

Tek sunucu için hazır `docker-compose.yml` ve adım adım Türkçe rehber: **[REBIOVIL-YAYIN.md](./REBIOVIL-YAYIN.md)**. Sıfırdan, tek tek: **[REBIOVIL-SIFIRDAN.md](./REBIOVIL-SIFIRDAN.md)**. Hostinger VPS: **[REBIOVIL-HOSTINGER.md](./REBIOVIL-HOSTINGER.md)**. Push ile otomatik deploy: **[GITHUB-ACTIONS-DEPLOY.md](./GITHUB-ACTIONS-DEPLOY.md)**.

## 2. Backend (FastAPI)

- [ ] `SUPABASE_URL`, `SUPABASE_SERVICE_KEY` (sunucuda asla istemciye sızdırılmaz).
- [ ] `GEMINI_API_KEY`, `OPENWEATHER_API_KEY` (opsiyonel).
- [ ] `CORS_ORIGINS`: üretim web origin’leri (virgülle).
- [ ] **JWT (zorunlu):** `SUPABASE_JWT_SECRET` tanımlı; eksikse `/health` 503 verir.
- [ ] `API_ALLOW_INSECURE_AUTH=0`; `API_JWT_BYPASS_USER_IDS` üretimde boş.
- [ ] `API_DEMO_USER_IDS`: demo kullanıcıların DB yazımını atlar; üretimde boş veya kaldırılmalı.
- [ ] **Rate limit ve sohbet kotası:** `docker-compose.yml` içindeki `redis` servisi (yalnızca iç ağ, AOF açık) bu sayaçları
      tutar; `api` servisine `REDIS_URL` compose'dan verilir. Böylece deploy/yeniden başlatma kotaları sıfırlamaz ve çok
      işçiye geçilebilir. Redis kapanırsa API çalışmaya devam eder: sayaçlar o süre süreç içine düşer (kota gevşer) ve
      `GET /health` içinde `"redis": "down"` görünür. `REDIS_URL` yoksa her şey bellekte kalır (`"redis": "off"`).
      Not: son push turu özeti ve devam imleci hâlâ süreç içidir; birden çok işçiye geçmeden önce bunlar da Redis'e taşınmalı.
- [ ] Süreç yöneticisi: `uvicorn main:app --host 0.0.0.0 --port 8000` veya benzeri; reverse proxy arkasında TLS.
- [ ] Sağlık: `GET /health` (`jwt_auth`, `rate_limit_backend`, `supabase`).
- [ ] **Veritabanı öz-denetimi:** `GET /health` içinde `db_integrity` (`ok` | `slow` | `degraded` | `unknown`) eksik indeks/fonksiyonu
      ve retention zamanlayıcısını (`retention`: `pg_cron` | `no_cron_job` | `no_pg_cron`) gösterir; adlar yalnızca günlüktedir.
      `degraded` ise veri güvenliği riski vardır (ör. olay idempotansı indeksi yok): `scripts/db_checks.sql` ile bakıp ilgili
      migration'ı çalıştırın. Retention `no_pg_cron` ise pg_cron'u açın ya da `RETENTION_PURGE_DAILY=1` verin.
- [ ] **Retention güvenlik ağı:** `RETENTION_PURGE_DAILY=1` iken push-cron günde bir `POST /maintenance/purge` çağırır
      (dağıtım anahtarıyla korunur; pg_cron aktifse atlar). İlk temizlikten önce `scripts/db_checks.sql` bölüm 6 ile silinecek
      satır sayısına bakın; sayı büyükse ilk temizliği SQL Editor'da elle çalıştırın.
- [ ] **Hava sağlayıcısı hacmi:** her sağlayıcı çağrısı `weather_call provider=… ok=… ms=…` satırı yazar
      (`docker compose logs api | grep -c weather_call`). Open-Meteo ücretsiz API ticari kullanıma kapalıdır; Standard plan ayda 1 milyon çağrıdır.
      Veri CC BY 4.0 lisanslıdır: uygulamada ve web panelinde "Hava verisi: Open-Meteo.com" atfı gösterilir.
- [ ] **Gemini günlük bütçe kesicisi:** `GEMINI_DAILY_BUDGET_USD` tanımlıysa tahmini günlük harcama bu değere ulaşınca yeni
      Gemini çağrıları durur ve sohbet bilgi tabanı özetine düşer (`gemini_budget` günlük satırları: %80 uyarısı ve "DOLDU").
- [ ] **Yük testi:** `docs/YUK-TESTI.md`.
- [ ] **Token harcaması:** her Gemini çağrısı günlüğe `gemini_usage label=… in=… out=… cost_usd=…` satırı yazar
      (`docker compose logs api | grep gemini_usage`). Etiket çağrı yerini gösterir (`chat_slots`, `chat_compose`,
      `routine_polish`, `checkin_note` …). Zaman aşımı/hata: `gemini_error label=… kind=…`.

## 3. Frontend

- [ ] `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`, `VITE_API_URL` üretim değerleri.
- [ ] `npm run build` ile statik çıktı; CDN veya static host + API CORS uyumu.

## 4. Güvenlik ve gözlemlenebilirlik

- [ ] Service role yalnızca backend ortamında.
- [ ] 429 / 401 / 403 logları veya metrikleri (opsiyonel APM).
- [ ] Gemini kota uyarıları (`ai_polish_note` ile kullanıcıya da iletilir).

## 5. Testler

Hızlı (CI):

```bash
cd backend && source venv/bin/activate && pytest tests/ -m "not slow"
```

Tam zincir (bilgi tabanı + Gemini; daha uzun sürebilir):

```bash
cd backend && pytest tests/
```

Mevcut adaptif motor testi:

```bash
cd backend && python test_adaptive.py
```

## 6. Mobil / harici istemci

- OpenAPI şema: `https://<API_HOST>/openapi.json`
- Swagger UI: `https://<API_HOST>/docs`
- Tüm korumalı uçlar için `user_id` gövde veya sorguda; JWT açıksa `Authorization: Bearer <access_token>` ve `sub == user_id`.
