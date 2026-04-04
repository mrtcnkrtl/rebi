# rebiovil.com — sıfırdan yayın (hiç bilmeyenler için)

Bu sayfa tek başına yeterli olacak şekilde yazıldı. **Ben (yapay zekâ asistanı) senin sunucu veya domain hesabına giriş yapamam**; güvenlik gereği şifre ve anahtarları senin girmen gerekir. Aşağıdaki adımları **yukarıdan aşağıya**, numaraları takip ederek yaparsan site yayına alınır.

**Hostinger kullanıyorsan:** Önce **[REBIOVIL-HOSTINGER.md](./REBIOVIL-HOSTINGER.md)** — VPS mi hosting mi, hPanel’de firewall ve DNS nerede, SSH nasıl; sonra bu sayfada 4. adımdan devam et.

---

## 0) Kısa sözlük

| Terim | Ne |
|--------|-----|
| **VPS** | İnternette sürekli açık duran küçük bir bilgisayar (sunucu). Site burada çalışır. |
| **DNS** | Alan adını (`rebiovil.com`) bu sunucunun adresine (IP) bağlayan kayıtlar. |
| **SSH** | Bilgisayarından sunucuya güvenli komut satırı bağlantısı. |
| **.env** | Şifre ve anahtarların yazıldığı gizli metin dosyası (Git’e eklenmez). |

---

## 1) Bir sunucu kirala (VPS)

1. **Hostinger:** [REBIOVIL-HOSTINGER.md](./REBIOVIL-HOSTINGER.md) — **VPS** planı ve **Ubuntu 22.04/24.04** şablonu şart; paylaşımlı “web hosting” bu proje için uygun değil.
2. **Başka sağlayıcı:** **Hetzner**, **DigitalOcean**, **Vultr**, **Linode** vb. — yine **Ubuntu 22.04 veya 24.04**, 1 CPU / 1–2 GB RAM genelde yeterli.
3. Sunucu oluşunca panelde **IPv4 adresini** not et (ör. `123.45.67.89`).
4. **root şifresi** veya SSH bilgilerini güvenli yere yaz; Hostinger’da hPanel → VPS → Overview üzerinden de yönetilir.

---

## 2) Alan adını sunucuya bağla (DNS)

Alan adını nereden aldıysan (**Hostinger** hPanel → Domains → DNS; Natro, GoDaddy, Cloudflare, vb.) **DNS / DNS Zone** bölümüne gir.

Şu iki kaydı ekle (örnekler; arayüz isimleri biraz değişebilir):

| Tür | Ad / Host | Değer / Hedef |
|-----|-----------|----------------|
| **A** | `@` veya boş veya `rebiovil.com` | Sunucunun IPv4’sü |
| **A** | `www` | Aynı IPv4 |

Kaydet. **5 dakika–birkaç saat** içinde dünya genelinde güncellenir.

---

## 3) Mac’ten sunucuya bağlan (SSH)

**Hostinger:** İstersen hPanel → VPS → **Browser terminal** ile tarayıcıdan da bağlanırsın; komutlar aynı.

Mac’te **Terminal** uygulamasını aç.

```bash
ssh root@SUNUCU_IP_YAZ
```

İlk seferde “yes” de. Şifre sorarsa paneldeki root şifresini yapıştır (yazarken ekranda görünmez; normal).

Bağlandıysan komut satırı prompt’u değişir; artık komutlar **sunucuda** çalışır.

---

## 4) Docker’ı kur ve klasör hazırla (otomatik script)

Sunucuda, repodaki script’i kullanmak için önce kodu sunucuya alman gerekir. **İki yol:**

### Yol A — GitHub’da repo varsa (tercih)

Sunucuda:

```bash
sudo mkdir -p /opt/rebi && sudo chown "$USER:$USER" /opt/rebi
cd /opt/rebi
git clone https://github.com/KULLANICI/rebi.git .
```

(`KULLANICI/rebi` kısmını kendi repo adresinle değiştir.)

Sonra:

```bash
sudo bash deploy/bootstrap-server.sh
```

(Bu script Docker’ı kurar, `/opt/rebi` izinlerini düzenler.)

### Yol B — Repo yoksa, zip ile

1. Kendi bilgisayarında projeyi zip’le, **scp** veya hosting panelinin dosya yüklemesi ile `/opt/rebi` içine at.
2. Sunucuda `/opt/rebi` içine geçip `sudo bash deploy/bootstrap-server.sh` çalıştır.

---

## 5) Gizli ayar dosyalarını doldur

Sunucuda `/opt/rebi` içindesin.

```bash
cd /opt/rebi
cp deploy/env.docker.example .env
nano .env
```

`nano` içinde:

- `VITE_SUPABASE_URL` → Supabase panelindeki proje URL’si  
- `VITE_SUPABASE_ANON_KEY` → Supabase **anon public** anahtarı  
- `VITE_API_URL` → **`https://rebiovil.com/api`** (bu tam metin kalsın)

Kaydet: `Ctrl+O`, Enter, çık: `Ctrl+X`.

```bash
cp deploy/.env.api.example deploy/.env.api
nano deploy/.env.api
```

Burada:

- `SUPABASE_URL` — aynı proje URL’si  
- `SUPABASE_SERVICE_KEY` — Supabase **service_role** (asla tarayıcıya koyma, sadece burada)  
- İstersen `GEMINI_API_KEY`, `OPENWEATHER_API_KEY`  
- `CORS_ORIGINS` satırında `https://rebiovil.com` ve `https://www.rebiovil.com` kalsın

Yine kaydet ve çık.

---

## 6) Siteyi ilk kez ayağa kaldır (HTTP)

```bash
cd /opt/rebi
docker compose up -d --build
```

Birkaç dakika sürebilir. Sonra tarayıcıdan:

- `http://SUNUCU_IP` veya  
- DNS yayıldıysa `http://rebiovil.com`  

açmayı dene.

---

## 7) HTTPS (kilit simgesi) — Let’s Encrypt

1. DNS’nin gerçekten bu sunucuyu gösterdiğinden emin ol (`rebiovil.com` açılıyor olmalı).
2. **Geçerli bir e-posta** hazırla (Let’s Encrypt uyarıları için).

Sunucuda:

```bash
cd /opt/rebi
export LETSENCRYPT_EMAIL=senin@emailin.com
sudo -E bash deploy/enable-https.sh
```

Script web konteynerini kısa süre durdurur, sertifikayı alır, sonra HTTPS ile yeniden başlatır.

Sonrasında site: **https://rebiovil.com**

Otomatik yenileme için script’in çıktısındaki **crontab** satırını root olarak ekleyebilirsin (`sudo crontab -e`).

---

## 8) Supabase giriş (Google vb.) ayarı

Supabase Dashboard → **Authentication → URL configuration**:

- **Site URL:** `https://rebiovil.com`  
- **Redirect URLs:**  
  `https://rebiovil.com/**`  
  `https://www.rebiovil.com/**`

Kaydet.

---

## 9) Takıldığında

| Sorun | Ne yap |
|--------|--------|
| `ssh` bağlanmıyor | Güvenlik duvarında **22** portu açık mı, IP doğru mu? |
| Site açılmıyor | `docker compose ps`, `docker compose logs web`, `docker compose logs api` |
| API hata veriyor | `deploy/.env.api` içindeki anahtarlar ve `CORS_ORIGINS` |
| HTTPS hata | DNS henüz yayılmamış olabilir; bir süre bekle, `enable-https.sh` tekrar |

Daha teknik özet: [REBIOVIL-YAYIN.md](./REBIOVIL-YAYIN.md)

---

## Özet: Senin yapman gereken tek şeyler

1. VPS + DNS kayıtları  
2. SSH ile bağlanıp bu dokümandaki komutları **sırayla** yapıştırmak  
3. `.env` ve `deploy/.env.api` içine **kendi** Supabase / API anahtarlarını yazmak  
4. Supabase panelinde Site URL / Redirect URL güncellemek  

Kod, Docker ve nginx tarafı repoda hazır; ben bunları senin için burada topladım ve script’leri ekledim.
