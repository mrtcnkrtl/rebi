# Rebi — üretim dağıtım özeti

Bu liste yeni ortam açarken veya gözden geçirirken kullanılır. Ayrıntılı env açıklamaları için `backend/.env.example` dosyasına bakın.

## 1. Supabase

- [ ] Proje oluşturuldu; **URL**, **anon** ve **service_role** anahtarları kayıtlı.
- [ ] `database/schema.sql` veya `database/migrations/` sırasıyla SQL Editor’de uygulandı (veya `scripts/apply_supabase_migration.py`).
- [ ] Tablolar: `profiles`, `assessments`, `routines`, `daily_logs`, `daily_events`, `knowledge_base` (+ gerekli indeksler).
- [ ] RLS politikaları üretim beklentisiyle uyumlu; `knowledge_base` ve `skin-photos` storage politikaları uygulandı.
- [ ] `skin-photos` bucket oluşturuldu; public okuma / authenticated yükleme kuralları tanımlı.
- [ ] Şema değişikliğinden sonra gerekirse **API → Reload schema cache**.

## 2a. rebiovil.com (Docker)

Tek sunucu için hazır `docker-compose.yml` ve adım adım Türkçe rehber: **[REBIOVIL-YAYIN.md](./REBIOVIL-YAYIN.md)**. Sıfırdan, tek tek: **[REBIOVIL-SIFIRDAN.md](./REBIOVIL-SIFIRDAN.md)**. Hostinger VPS: **[REBIOVIL-HOSTINGER.md](./REBIOVIL-HOSTINGER.md)**. Push ile otomatik deploy: **[GITHUB-ACTIONS-DEPLOY.md](./GITHUB-ACTIONS-DEPLOY.md)**.

## 2. Backend (FastAPI)

- [ ] `SUPABASE_URL`, `SUPABASE_SERVICE_KEY` (sunucuda asla istemciye sızdırılmaz).
- [ ] `GEMINI_API_KEY`, `OPENWEATHER_API_KEY` (opsiyonel).
- [ ] `CORS_ORIGINS`: üretim web origin’leri (virgülle).
- [ ] **JWT (önerilir):** `SUPABASE_JWT_SECRET` (Dashboard → Settings → API). Açıkken mobil/web `Authorization: Bearer` göndermeli.
- [ ] `API_JWT_BYPASS_USER_IDS`: üretimde genelde **boş**; sadece iç test için sınırlı id’ler.
- [ ] `API_DEMO_USER_IDS`: demo kullanıcıların DB yazımını atlar; üretimde boş veya kaldırılmalı.
- [ ] **Rate limit:** çok süreç için `REDIS_URL`; yoksa bellek içi (tek worker).
- [ ] Süreç yöneticisi: `uvicorn main:app --host 0.0.0.0 --port 8000` veya benzeri; reverse proxy arkasında TLS.
- [ ] Sağlık: `GET /health` (`jwt_auth`, `rate_limit_backend`, `supabase`).

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
