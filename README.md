# Rebi - Holistic Skincare AI Platform

Rebi, AI destekli kişiselleştirilmiş cilt bakım rutinleri sunan bir platformdur.

## 🏗️ Mimari

```
Frontend (React/Vite) → Backend (FastAPI) → Supabase → Gemini AI
```

### Bileşenler

- **Frontend**: React + Vite + TailwindCSS
- **Backend**: FastAPI + Python
- **Database**: Supabase (PostgreSQL + pgvector)
- **AI**: Google Gemini 2.0 Flash + Embedding
- **Storage**: Supabase Storage (fotoğraflar için)

## 🚀 Hızlı Başlangıç

### Ön Gereksinimler

- Python 3.11+
- Node.js 20+
- Supabase hesabı
- Google Gemini API key

### 1. Backend Kurulumu

```bash
cd backend
python3 -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate
pip install -r requirements.txt
```

Environment değişkenlerini ayarlayın:

```bash
cp .env.example .env
# .env dosyasını düzenleyin
```

Gerekli değişkenler:
- `SUPABASE_URL`
- `SUPABASE_SERVICE_KEY`
- `GEMINI_API_KEY`
- `OPENWEATHER_API_KEY` (opsiyonel)

Backend'i başlatın:

```bash
uvicorn main:app --reload
```

**API dokümantasyonu (mobil / entegrasyon):** çalışırken [http://localhost:8000/docs](http://localhost:8000/docs) veya `GET /openapi.json`.

**Üretim dağıtım özeti:** [docs/DEPLOY.md](docs/DEPLOY.md)

**rebiovil.com (Docker + nginx):** [docs/REBIOVIL-YAYIN.md](docs/REBIOVIL-YAYIN.md) — kökte `docker-compose.yml`.

**Sıfırdan yayın (adım adım Türkçe):** [docs/REBIOVIL-SIFIRDAN.md](docs/REBIOVIL-SIFIRDAN.md) · **Hostinger VPS:** [docs/REBIOVIL-HOSTINGER.md](docs/REBIOVIL-HOSTINGER.md)

**Backend otomatik test (hızlı):**

```bash
cd backend && source venv/bin/activate && pip install -r requirements.txt && pytest tests/ -m "not slow"
```

### 2. Frontend Kurulumu

```bash
cd frontend
npm install
```

Environment değişkenlerini ayarlayın:

```bash
cp .env.example .env
# .env dosyasını düzenleyin
```

Gerekli değişkenler:
- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_ANON_KEY`
- `VITE_API_URL`

Frontend'i başlatın:

```bash
npm run dev
```

### 3. Veritabanı Kurulumu

Supabase Dashboard → SQL Editor'de `database/schema.sql` dosyasını çalıştırın.

### 4. Veri Yükleme (Opsiyonel)

Bilgi tabanına veri yüklemek için:

```bash
cd backend
python ingest.py  # Excel dosyaları
python ingest_pdf_smart.py  # PDF dosyaları
```

Duplike verileri temizlemek için:

```bash
python cleanup_duplicates.py
```

## 📁 Proje Yapısı

```
rebi/
├── backend/
│   ├── main.py              # FastAPI ana dosyası
│   ├── flow_engine.py       # Deterministik rutin motoru
│   ├── knowledge_router.py   # Metadata-bazlı bilgi sorgulama
│   ├── rag_service.py       # AI polish servisi
│   ├── weather_service.py   # Hava durumu servisi
│   ├── config.py            # Konfigürasyon
│   ├── ingest.py            # Veri yükleme scripti
│   └── cleanup_duplicates.py # Duplike temizleme
├── frontend/
│   ├── src/
│   │   ├── pages/           # Sayfa bileşenleri
│   │   ├── context/         # React context'ler
│   │   └── App.jsx          # Ana uygulama
│   └── package.json
├── database/
│   └── schema.sql           # Veritabanı şeması
├── docker-compose.yml       # Docker Compose yapılandırması
└── README.md
```

## 🧪 Test

### Backend API Testleri

```bash
cd backend
python test_api.py
```

### Manuel Test

1. Backend health check:
   ```bash
   curl http://localhost:8000/health
   ```

2. Frontend erişimi:
   ```
   http://localhost:5173
   ```

## 🐳 Docker ile Çalıştırma

```bash
docker-compose up --build
```

Backend: http://localhost:8000
Frontend: http://localhost:5173

## 📦 Deployment

Detaylı deployment rehberi için [DEPLOY.md](DEPLOY.md) dosyasına bakın.

### Hızlı Deployment

**Backend (Railway/Render):**
- Dockerfile kullanarak deploy edin
- Environment değişkenlerini ayarlayın

**Frontend (Vercel/Netlify):**
- Build komutu: `npm run build`
- Output directory: `dist`

## 🔧 Yapılandırma

### Supabase Storage

Fotoğraf yükleme için Supabase Storage bucket'ı oluşturun. Detaylar için [SETUP_STORAGE.md](SETUP_STORAGE.md) dosyasına bakın.

### Environment Variables

Backend `.env`:
```env
SUPABASE_URL=https://xxx.supabase.co
SUPABASE_SERVICE_KEY=xxx
GEMINI_API_KEY=xxx
OPENWEATHER_API_KEY=xxx  # Opsiyonel
```

Frontend `.env`:
```env
VITE_SUPABASE_URL=https://xxx.supabase.co
VITE_SUPABASE_ANON_KEY=xxx
VITE_API_URL=http://localhost:8000
```

## 📊 API Endpoints

- `GET /health` - Sağlık kontrolü
- `POST /generate_routine` - Rutin üretme
- `POST /chat` - AI sohbet
- `POST /chat_assessment` - Değerlendirme sohbeti
- `POST /daily_checkin` - Günlük check-in
- `POST /upload_photo` - Fotoğraf yükleme

## 🐛 Sorun Giderme

### Backend çalışmıyor
- Python versiyonunu kontrol edin (3.11+)
- Virtual environment aktif mi?
- `.env` dosyası doğru mu?

### Frontend çalışmıyor
- Node.js versiyonunu kontrol edin (20+)
- `npm install` çalıştırıldı mı?
- `.env` dosyası var mı?

### Veritabanı bağlantı hatası
- Supabase URL ve key'leri kontrol edin
- Supabase Dashboard'da bağlantıyı test edin

## 📝 Lisans

Bu proje özel bir projedir.

## 🤝 Katkıda Bulunma

1. Fork edin
2. Feature branch oluşturun (`git checkout -b feature/amazing-feature`)
3. Commit edin (`git commit -m 'Add amazing feature'`)
4. Push edin (`git push origin feature/amazing-feature`)
5. Pull Request açın

## 📞 Destek

Sorularınız için issue açabilirsiniz.
