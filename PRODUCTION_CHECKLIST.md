# Rebi - Production Yayına Alma Checklist

Bu doküman, Rebi projesini production'a çıkarmadan önce yapılması gerekenleri listeler.

## ✅ Tamamlanan İşlemler

### 1. Duplike Veri Temizliği
- ✅ `cleanup_duplicates.py` scripti oluşturuldu
- ⚠️  **Yapılacak**: Script'i çalıştırarak metadata'siz eski kayıtları temizleyin
  ```bash
  cd backend
  python cleanup_duplicates.py
  ```

### 2. Backend Hazırlığı
- ✅ Backend kodları kontrol edildi
- ✅ Environment değişkenleri ayarlandı
- ✅ Logging mekanizması mevcut
- ✅ Hata yönetimi iyileştirildi
- ⚠️  **Yapılacak**: Backend'i test edin
  ```bash
  cd backend
  source venv/bin/activate
  uvicorn main:app --reload
  # Başka terminalde:
  python test_api.py
  ```

### 3. Frontend Hazırlığı
- ✅ Frontend kodları kontrol edildi
- ✅ Environment değişkenleri ayarlandı
- ✅ node_modules kurulu
- ⚠️  **Yapılacak**: Frontend'i test edin
  ```bash
  cd frontend
  npm run dev
  # Tarayıcıda http://localhost:5173 açın
  ```

### 4. Deployment Dosyaları
- ✅ `backend/Dockerfile` oluşturuldu
- ✅ `frontend/Dockerfile` oluşturuldu
- ✅ `docker-compose.yml` oluşturuldu
- ✅ `DEPLOY.md` güncellendi

### 5. Supabase Storage
- ✅ `SETUP_STORAGE.md` dokümantasyonu oluşturuldu
- ⚠️  **Yapılacak**: Supabase Dashboard'dan `skin-photos` bucket'ını oluşturun
  - Detaylar için `SETUP_STORAGE.md` dosyasına bakın

### 6. Dokümantasyon
- ✅ `README.md` oluşturuldu
- ✅ `DEPLOY.md` mevcut
- ✅ `SETUP_STORAGE.md` oluşturuldu
- ✅ `PRODUCTION_CHECKLIST.md` (bu dosya)

## 🔴 Kritik Yapılacaklar

### 1. Veritabanı Temizliği
```bash
cd backend
source venv/bin/activate
python cleanup_duplicates.py
```

### 2. Supabase Storage Kurulumu
1. Supabase Dashboard → Storage
2. `skin-photos` bucket'ını oluşturun
3. RLS politikalarını ayarlayın
4. Detaylar: `SETUP_STORAGE.md`

### 3. Environment Variables Kontrolü

**Backend (.env):**
- [ ] `SUPABASE_URL` ✅
- [ ] `SUPABASE_SERVICE_KEY` ✅
- [ ] `GEMINI_API_KEY` ✅
- [ ] `OPENWEATHER_API_KEY` (opsiyonel, fallback var)

**Frontend (.env):**
- [ ] `VITE_SUPABASE_URL` ✅
- [ ] `VITE_SUPABASE_ANON_KEY` ✅
- [ ] `VITE_API_URL` ✅ (production'da güncellenmeli)

### 4. Production Environment Variables

Production'da şunları güncelleyin:

**Backend:**
```env
CORS_ORIGINS=https://rebiovil.com,https://www.rebiovil.com
```

**Frontend:**
```env
VITE_API_URL=https://api.rebiovil.com
```

### 5. Test Senaryoları

#### Backend Testleri
```bash
cd backend
python test_api.py
```

Beklenen sonuçlar:
- ✅ Health check başarılı
- ✅ Generate routine çalışıyor
- ✅ Chat endpoint çalışıyor

#### Frontend Testleri
1. Landing page açılıyor mu?
2. Auth sayfası çalışıyor mu?
3. Dashboard yükleniyor mu?
4. Analyze wizard çalışıyor mu?

#### End-to-End Test
1. Yeni kullanıcı kaydı
2. Cilt analizi yapma
3. Rutin üretme
4. Fotoğraf yükleme
5. Chat özelliği

### 6. Güvenlik Kontrolleri

- [ ] `.env` dosyaları `.gitignore`'da mı?
- [ ] Production'da `SUPABASE_SERVICE_KEY` kullanılıyor mu? (anon key değil)
- [ ] CORS ayarları production domain'lerine göre güncellendi mi?
- [ ] SSL sertifikası kuruldu mu? (HTTPS zorunlu)
- [ ] API rate limiting eklendi mi? (opsiyonel ama önerilir)

### 7. Performance Optimizasyonları

- [ ] Frontend build optimize edildi mi?
  ```bash
  cd frontend
  npm run build
  # dist klasörü boyutunu kontrol edin
  ```
- [ ] Backend'de gerekli indexler var mı?
  - Supabase Dashboard → Database → Indexes kontrol edin
- [ ] Image optimization yapıldı mı?

### 8. Monitoring ve Logging

- [ ] Backend logları görüntülenebiliyor mu?
- [ ] Error tracking kuruldu mu? (Sentry, vb.)
- [ ] Analytics entegrasyonu var mı? (Google Analytics, vb.)

## 🚀 Deployment Adımları

### Senaryo 1: Docker Compose (VPS)

```bash
# 1. Projeyi sunucuya yükleyin
git clone <repo-url> /var/www/rebi
cd /var/www/rebi

# 2. Environment dosyalarını ayarlayın
cp backend/.env.example backend/.env
cp frontend/.env.example frontend/.env
# Dosyaları düzenleyin

# 3. Docker Compose ile başlatın
docker-compose up -d --build

# 4. Logları kontrol edin
docker-compose logs -f
```

### Senaryo 2: Ayrı Deploy

**Backend (Railway/Render):**
1. GitHub repo'yu bağlayın
2. Build command: `cd backend && pip install -r requirements.txt`
3. Start command: `cd backend && uvicorn main:app --host 0.0.0.0 --port $PORT`
4. Environment variables'ı ayarlayın

**Frontend (Vercel/Netlify):**
1. GitHub repo'yu bağlayın
2. Build command: `cd frontend && npm install && npm run build`
3. Output directory: `frontend/dist`
4. Environment variables'ı ayarlayın

## 📋 Post-Deployment Kontrolleri

### 1. Health Checks
```bash
# Backend
curl https://api.rebiovil.com/health

# Frontend
curl https://rebiovil.com
```

### 2. API Endpoint Testleri
```bash
# Backend test scripti ile
cd backend
python test_api.py
# BASE_URL'i production URL'ine güncelleyin
```

### 3. Frontend Fonksiyonellik
- [ ] Sayfalar yükleniyor mu?
- [ ] API çağrıları çalışıyor mu?
- [ ] Fotoğraf yükleme çalışıyor mu?
- [ ] Chat özelliği çalışıyor mu?

### 4. Database Bağlantısı
- [ ] Supabase bağlantısı çalışıyor mu?
- [ ] RLS politikaları doğru mu?
- [ ] Storage bucket erişilebilir mi?

## 🐛 Bilinen Sorunlar ve Çözümler

### Sorun: Backend çalışmıyor
**Çözüm:**
- Python versiyonunu kontrol edin (3.11+ önerilir)
- Virtual environment aktif mi?
- `.env` dosyası doğru mu?
- Port 8000 kullanımda mı?

### Sorun: Frontend API çağrıları başarısız
**Çözüm:**
- `VITE_API_URL` doğru mu?
- CORS ayarları kontrol edin
- Backend çalışıyor mu?

### Sorun: Fotoğraf yükleme çalışmıyor
**Çözüm:**
- Supabase Storage bucket oluşturuldu mu?
- RLS politikaları ayarlandı mı?
- Bucket public mi?

## 📞 Destek

Sorun yaşarsanız:
1. Logları kontrol edin
2. Environment variables'ı kontrol edin
3. Supabase Dashboard'da bağlantıyı test edin
4. Issue açın veya dokümantasyonu kontrol edin

## ✅ Final Checklist

Production'a çıkmadan önce:

- [ ] Tüm testler başarılı
- [ ] Environment variables ayarlandı
- [ ] Supabase Storage kuruldu
- [ ] Duplike veriler temizlendi
- [ ] SSL sertifikası kuruldu
- [ ] CORS ayarları güncellendi
- [ ] Monitoring kuruldu
- [ ] Backup stratejisi belirlendi
- [ ] Dokümantasyon güncel

---

**Son Güncelleme**: 2026-02-19
**Durum**: Hazırlık tamamlandı, production deployment bekleniyor
