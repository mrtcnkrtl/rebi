# Hostinger Hızlı Başlangıç Rehberi

Bu rehber, Hostinger VPS üzerinde Rebi'yi hızlıca deploy etmek için özet adımları içerir.

## ⚡ Hızlı Kurulum (5 Dakika)

### 1. VPS'e Bağlanın

```bash
ssh root@your-vps-ip
```

### 2. Gerekli Yazılımları Kurun

```bash
# Sistem güncellemesi
sudo apt update && sudo apt upgrade -y

# Python, Node.js, Nginx
sudo apt install -y python3.11 python3.11-venv python3-pip nodejs npm nginx git

# Docker (opsiyonel ama önerilir)
curl -fsSL https://get.docker.com -o get-docker.sh && sudo sh get-docker.sh
```

### 3. Projeyi Yükleyin

```bash
# Proje klasörü oluştur
sudo mkdir -p /var/www/rebi
cd /var/www/rebi

# Git ile klonlayın veya SFTP ile yükleyin
git clone <your-repo-url> .
```

### 4. Backend'i Kurun

```bash
cd /var/www/rebi/backend
python3.11 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# .env dosyasını oluşturun
cp .env.example .env
nano .env  # Gerekli değerleri girin
```

### 5. Backend Servisini Başlatın

```bash
# Systemd service oluştur
sudo nano /etc/systemd/system/rebi-backend.service
```

İçeriği:
```ini
[Unit]
Description=Rebi Backend API
After=network.target

[Service]
Type=simple
User=www-data
WorkingDirectory=/var/www/rebi/backend
Environment="PATH=/var/www/rebi/backend/venv/bin"
ExecStart=/var/www/rebi/backend/venv/bin/uvicorn main:app --host 0.0.0.0 --port 8000
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

### 6. Frontend'i Build Edin

```bash
cd /var/www/rebi/frontend
npm install

# .env dosyasını oluşturun
cp .env.example .env
nano .env  # API URL'ini güncelleyin

# Build
npm run build

# Dosyaları web root'a kopyalayın
sudo mkdir -p /var/www/html/rebi
sudo cp -r dist/* /var/www/html/rebi/
```

### 7. Nginx Yapılandırması

```bash
# Backend API için
sudo nano /etc/nginx/sites-available/rebi-api
```

İçeriği:
```nginx
server {
    listen 80;
    server_name api.rebiovil.com;
    
    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

```bash
# Frontend için
sudo nano /etc/nginx/sites-available/rebi-frontend
```

İçeriği:
```nginx
server {
    listen 80;
    server_name rebiovil.com www.rebiovil.com;
    root /var/www/html/rebi;
    index index.html;
    
    location / {
        try_files $uri $uri/ /index.html;
    }
}
```

Aktif edin:
```bash
sudo ln -s /etc/nginx/sites-available/rebi-api /etc/nginx/sites-enabled/
sudo ln -s /etc/nginx/sites-available/rebi-frontend /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

### 8. SSL Sertifikası

```bash
sudo apt install -y certbot python3-certbot-nginx
sudo certbot --nginx -d rebiovil.com -d www.rebiovil.com -d api.rebiovil.com
```

### 9. Domain DNS Ayarları

Hostinger hPanel → Domains → DNS Zone Editor:

```
Type    Name    Value              TTL
A       @       YOUR_VPS_IP        3600
A       www     YOUR_VPS_IP         3600
A       api     YOUR_VPS_IP         3600
```

### 10. Firewall

```bash
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
```

## ✅ Test

```bash
# Backend
curl https://api.rebiovil.com/health

# Frontend
# Tarayıcıda https://rebiovil.com açın
```

## 🐳 Docker ile Alternatif (Daha Kolay)

```bash
cd /var/www/rebi
docker-compose up -d --build
```

Sonra Nginx reverse proxy ayarlayın (yukarıdaki adım 7).

## 📞 Sorun mu Var?

Detaylı rehber için `DEPLOY_HOSTINGER.md` dosyasına bakın.
