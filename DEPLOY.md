# Rebiovil.com Deploy Rehberi

Bu rehber, Rebi uygulamasını rebiovil.com üzerine deploy etmek için gerekli adımları içerir.

## Ön Hazırlık

### 1. Environment Variables Hazırlığı

**Backend için (.env):**
```bash
cd backend
cp .env.example .env
```

`.env` dosyasını düzenleyin:
```env
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_KEY=your-anon-key
SUPABASE_SERVICE_KEY=your-service-role-key
OPENAI_API_KEY=sk-your-openai-key
OPENWEATHER_API_KEY=your-openweather-key
```

**Frontend için (.env):**
```bash
cd frontend
cp .env.example .env
```

`.env` dosyasını düzenleyin (production URL'leri ile):
```env
VITE_SUPABASE_URL=https://your-project.supabase.co
VITE_SUPABASE_ANON_KEY=your-anon-key
VITE_API_URL=https://api.rebiovil.com  # Backend API URL'i
```

## Deploy Senaryoları

### Senaryo 1: Docker Compose ile Deploy (VPS/Cloud Server)

Eğer rebiovil.com bir VPS veya cloud server üzerinde çalışıyorsa:

#### Adımlar:

1. **Sunucuya bağlanın:**
```bash
ssh user@rebiovil.com
```

2. **Projeyi sunucuya yükleyin:**
```bash
# Git ile (önerilen)
git clone <your-repo-url> /var/www/rebi
cd /var/www/rebi

# Veya FTP/SFTP ile dosyaları yükleyin
```

3. **Docker ve Docker Compose kurulumu:**
```bash
# Docker kurulumu (eğer yoksa)
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh

# Docker Compose kurulumu
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
```

4. **Environment dosyalarını oluşturun:**
```bash
cd /var/www/rebi
cp backend/.env.example backend/.env
cp frontend/.env.example frontend/.env
# Dosyaları düzenleyin ve gerçek değerleri girin
nano backend/.env
nano frontend/.env
```

5. **Uygulamayı başlatın:**
```bash
docker-compose up -d --build
```

6. **Nginx Reverse Proxy Kurulumu (Önerilen):**

`/etc/nginx/sites-available/rebiovil.com` dosyası oluşturun:
```nginx
# Frontend
server {
    listen 80;
    server_name rebiovil.com www.rebiovil.com;

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }
}

# Backend API
server {
    listen 80;
    server_name api.rebiovil.com;

    location / {
        proxy_pass http://localhost:8000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }
}
```

Nginx'i aktif edin:
```bash
sudo ln -s /etc/nginx/sites-available/rebiovil.com /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

7. **SSL Sertifikası (Let's Encrypt):**
```bash
sudo apt install certbot python3-certbot-nginx
sudo certbot --nginx -d rebiovil.com -d www.rebiovil.com -d api.rebiovil.com
```

### Senaryo 2: Ayrı Deploy (Frontend Static + Backend API)

#### Frontend (Static Build)

1. **Production build oluşturun:**
```bash
cd frontend
npm install
npm run build
```

2. **Build dosyalarını sunucuya yükleyin:**
```bash
# dist klasörünü FTP/SFTP ile yükleyin veya:
scp -r dist/* user@rebiovil.com:/var/www/html/
```

3. **Nginx konfigürasyonu:**
```nginx
server {
    listen 80;
    server_name rebiovil.com www.rebiovil.com;
    root /var/www/html;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }
}
```

#### Backend (FastAPI)

1. **Sunucuya Python ve bağımlılıkları kurun:**
```bash
ssh user@rebiovil.com
cd /var/www/rebi-backend
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

2. **Systemd service oluşturun:**

`/etc/systemd/system/rebi-backend.service`:
```ini
[Unit]
Description=Rebi Backend API
After=network.target

[Service]
User=www-data
WorkingDirectory=/var/www/rebi-backend
Environment="PATH=/var/www/rebi-backend/venv/bin"
ExecStart=/var/www/rebi-backend/venv/bin/uvicorn main:app --host 0.0.0.0 --port 8000
Restart=always

[Install]
WantedBy=multi-user.target
```

Servisi başlatın:
```bash
sudo systemctl daemon-reload
sudo systemctl enable rebi-backend
sudo systemctl start rebi-backend
```

### Senaryo 3: Platform-Specific Deploy

#### Railway.app

1. Railway hesabı oluşturun
2. GitHub repo'yu bağlayın
3. `railway.json` oluşturun:
```json
{
  "build": {
    "builder": "DOCKERFILE",
    "dockerfilePath": "backend/Dockerfile"
  },
  "deploy": {
    "startCommand": "uvicorn main:app --host 0.0.0.0 --port $PORT",
    "restartPolicyType": "ON_FAILURE",
    "restartPolicyMaxRetries": 10
  }
}
```

#### Render.com

1. Render hesabı oluşturun
2. New Web Service → GitHub repo seçin
3. Build Command: `cd backend && pip install -r requirements.txt`
4. Start Command: `cd backend && uvicorn main:app --host 0.0.0.0 --port $PORT`

#### Heroku

1. Heroku CLI kurun
2. `Procfile` oluşturun:
```
web: cd backend && uvicorn main:app --host 0.0.0.0 --port $PORT
```
3. Deploy:
```bash
heroku create rebi-backend
git push heroku main
```

## Post-Deploy Kontrolleri

1. **Backend sağlık kontrolü:**
```bash
curl https://api.rebiovil.com/health
```

2. **Frontend erişim kontrolü:**
```bash
curl https://rebiovil.com
```

3. **Log kontrolü:**
```bash
# Docker ile
docker-compose logs -f

# Systemd ile
sudo journalctl -u rebi-backend -f
```

## Güncelleme İşlemi

```bash
# Git ile
git pull origin main
docker-compose up -d --build

# Veya manuel
docker-compose restart
```

## Sorun Giderme

### Port çakışması
```bash
# Kullanılan portları kontrol edin
sudo netstat -tulpn | grep :8000
sudo netstat -tulpn | grep :3000
```

### Environment variables kontrolü
```bash
# Docker ile
docker-compose exec backend env
docker-compose exec frontend env
```

### Database bağlantı sorunu
- Supabase URL ve key'lerin doğru olduğundan emin olun
- Supabase dashboard'dan connection test edin

## Güvenlik Notları

1. ✅ `.env` dosyalarını `.gitignore`'a ekleyin
2. ✅ Production'da `SUPABASE_SERVICE_KEY` kullanın (anon key değil)
3. ✅ CORS ayarlarını production domain'lerine göre güncelleyin
4. ✅ SSL sertifikası kullanın (HTTPS zorunlu)
5. ✅ API rate limiting ekleyin

## Destek

Sorun yaşarsanız:
- Backend logs: `docker-compose logs backend`
- Frontend logs: `docker-compose logs frontend`
- Database: Supabase dashboard
