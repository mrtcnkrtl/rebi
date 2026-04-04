# rebiovil.com yayın rehberi

Tek sunucuda: **nginx** statik React + **`/api/*` → FastAPI** (aynı site, CORS sorunu yok). TLS Let’s Encrypt ile.

**Hiç deneyim yoksa önce şunu okuyun:** [REBIOVIL-SIFIRDAN.md](./REBIOVIL-SIFIRDAN.md) (adım adım Türkçe + `deploy/bootstrap-server.sh` ve `deploy/enable-https.sh`).

**Hostinger:** [REBIOVIL-HOSTINGER.md](./REBIOVIL-HOSTINGER.md) — VPS, hPanel firewall/DNS, SSH.

HTTPS için kısayol: sertifika aldıktan sonra `docker compose -f docker-compose.yml -f docker-compose.https.yml up -d --build` (ayrıntı aşağıda ve `enable-https.sh` içinde).

## Ön koşullar

- Ubuntu 22.04/24.04 LTS (veya benzeri) VPS, root veya sudo
- Alan adı **rebiovil.com** DNS yönetim paneli erişimi
- Supabase projesi + Gemini / OpenWeather anahtarları

## 1. DNS

Kayıt defterinde (Cloudflare, Natro, vb.):

| Tip | Ad | Değer |
|-----|-----|--------|
| A | `@` | Sunucu IPv4 |
| A | `www` | Aynı IPv4 |

TTL kaydedikten sonra yayılım birkaç dakika–saat sürebilir.

## 2. Sunucuda Docker

```bash
sudo apt update && sudo apt install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update && sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
```

## 3. Projeyi sunucuya alın

```bash
sudo mkdir -p /opt/rebi && sudo chown $USER:$USER /opt/rebi
cd /opt/rebi
git clone <repo-url> .
# veya rsync/scp ile mevcut projeyi kopyalayın
```

## 4. Ortam dosyaları

```bash
cp deploy/env.docker.example .env
# .env düzenleyin: VITE_* (Supabase public + VITE_API_URL=https://rebiovil.com/api)

cp deploy/.env.api.example deploy/.env.api
# deploy/.env.api düzenleyin: SUPABASE_SERVICE_KEY, GEMINI_API_KEY, CORS_ORIGINS, ...
```

**Önemli:** `VITE_API_URL` mutlaka **`https://rebiovil.com/api`** olmalı (sonunda `/api` yoksa yollar yanlış birleşir).

## 5. İlk açılış (sadece HTTP, port 80)

```bash
docker compose up -d --build
```

Tarayıcıdan `http://SUNUCU_IP` veya DNS yayıldıysa `http://rebiovil.com` deneyin.

## 6. HTTPS (Let’s Encrypt)

### 6a. Sertifika (certbot, nginx geçici kapalı)

```bash
sudo apt install -y certbot
sudo docker compose -f /opt/rebi/docker-compose.yml down
sudo certbot certonly --standalone -d rebiovil.com -d www.rebiovil.com
```

### 6b. nginx’e TLS ekleyin (iki seçenek)

**Kolay yol:** Repoda `deploy/nginx/prod.https.conf` ve `docker-compose.https.yml` hazır. Sertifikayı aldıktan sonra:

```bash
cd /opt/rebi
docker compose -f docker-compose.yml -f docker-compose.https.yml up -d --build
```

veya tek komut: `sudo LETSENCRYPT_EMAIL=siz@ornek.com bash deploy/enable-https.sh` (önce HTTP ile bir kez `docker compose up` yapılmış olmalı).

**Manuel yol:** `prod.conf` yerine aynı içeriği kullanın veya `deploy/nginx/prod.https.conf` dosyasına bakın; `docker-compose.https.yml` içindeki `volumes` ve `ports` ayarlarını referans alın.

Eski tek dosya yöntemi özeti — `prod.conf` içine 443 bloğu ekleyip `docker-compose.yml` içinde:

```yaml
    volumes:
      - /etc/letsencrypt:/etc/letsencrypt:ro
    ports:
      - "80:80"
      - "443:443"
```

Sonra:

```bash
cd /opt/rebi && docker compose up -d --build
```

Otomatik yenileme:

```bash
echo "0 3 * * * certbot renew --quiet && docker compose -f /opt/rebi/docker-compose.yml restart web" | sudo crontab -
```

(renew yönteminize göre `webroot` veya `reload nginx` ile uyumlayın.)

## 7. Supabase Auth

Supabase Dashboard → **Authentication → URL configuration**:

- **Site URL:** `https://rebiovil.com`
- **Redirect URLs:** `https://rebiovil.com/**`, `https://www.rebiovil.com/**`

## 8. Güvenlik kontrol listesi

- [ ] `SUPABASE_JWT_SECRET` üretimde tanımlı; `API_JWT_BYPASS_USER_IDS` boş
- [ ] `API_DEMO_USER_IDS` boş (veya sadece iç test)
- [ ] `deploy/.env.api` ve kök `.env` repoda yok
- [ ] Güvenlik duvarı: sadece 22 (SSH), 80, 443

## 9. Sorun giderme

- **Beyaz sayfa / 404:** React Router için nginx `try_files ... /index.html` gerekli (projede var).
- **API 502:** `docker compose logs api` — ortam değişkenleri veya healthcheck süresi.
- **CORS:** Aynı origin `/api` kullandığınızda tarayıcı CORS tetiklemez; API’yi ayrı subdomain’e alırsanız `CORS_ORIGINS` ve backend `main.py` listesini güncelleyin.

Genel dağıtım notları: [DEPLOY.md](./DEPLOY.md)
