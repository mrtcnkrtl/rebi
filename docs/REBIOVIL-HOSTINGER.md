# rebiovil.com — Hostinger üzerinden yayın

Bu rehber, siteyi **Hostinger VPS** üzerinde Docker ile çalıştırmak içindir. Genel adımların tamamı **[REBIOVIL-SIFIRDAN.md](./REBIOVIL-SIFIRDAN.md)** ile aynı; burada sadece Hostinger paneli ve sık karışan noktalar anlatılıyor.

---

## Önemli: Hangi ürün?

| Ürün | Bu proje ile uyum |
|------|-------------------|
| **Hostinger VPS** (Ubuntu) | Uygun. Aşağıdaki adımlar buna göre. |
| **Web hosting / WordPress / Website Builder** | **Uygun değil.** Docker ve kendi nginx/API kurulumu yok; `rebi` uygulaması VPS ister. |

Yani Hostinger’de **VPS** satın almış olmalısın; sadece “hosting” paketi yeterli değil.

---

## 1) VPS siparişi

1. [hostinger.com](https://www.hostinger.com) → giriş → **VPS** bölümünden plan seç.
2. İşletim sistemi şablonu olarak **Ubuntu 22.04** veya **Ubuntu 24.04** seç (Docker rehberi buna göre yazıldı).
3. Kurulum bitince **hPanel** → **VPS** → sunucunun **Overview** sayfasına gir.
4. **IPv4 adresini** not al (DNS ve SSH için lazım).

Şifre / root erişimi: Overview’da **SSH** bilgileri ve gerekirse **root şifresi** sıfırlama seçenekleri bulunur. Resmi yardım: [VPS’e SSH ile bağlanma](https://support.hostinger.com/en/articles/5723772-how-to-connect-to-your-vps-via-ssh).

---

## 2) Güvenlik duvarı (80, 443, 22)

Hostinger tarafında paket filtresi varsa site dışarıdan açılmaz. hPanel’de VPS’ini seç:

1. Solda **Security** → **Firewall** (veya benzeri “Firewall” menüsü).
2. Kural ekle: **Accept**, **TCP**, port **22** (SSH), kaynak **Anywhere**.
3. Aynı şekilde port **80** (HTTP) ve **443** (HTTPS) için **Accept** kuralları ekle.
4. Firewall’u **aktif** et; değişikliklerin uygulanması birkaç dakika sürebilir.

Resmi özet: [Managed VPS Firewall](https://support.hostinger.com/en/articles/8172641-how-to-use-a-managed-vps-firewall-at-hostinger).

---

## 3) Alan adını VPS IP’sine bağla (DNS)

**Alan adı Hostinger’de kayıtlıysa**

- hPanel → **Domains** → ilgili alan adı → **DNS / DNS Zone Editor** (veya “DNS kayıtları”) bölümüne gir.
- Şu kayıtları ekle veya güncelle:

| Tür | Ad / Name | Hedef / Target / Points to |
|-----|-----------|----------------------------|
| **A** | `@` (veya boş, kök domain) | VPS IPv4 |
| **A** | `www` | Aynı IPv4 |

Eski **A** kayıtları başka bir IP’ye gidiyorsa, rebiovil için doğru IP’yi yaz veya çakışan kaydı kaldır.

**Alan adı başka firmadaysa**

- O firmadaki DNS panelinde yine **A** (`@` ve `www` → VPS IP) kullan; mantık aynı.

Yayılım genelde dakikalar–24 saat arası değişir.

---

## 4) Sunucuya bağlanma (SSH)

İki yol:

1. **Tarayıcı terminali (kolay başlangıç):** hPanel → VPS → **Overview** → sağ üstte **Browser terminal** → tıkla; komutları doğrudan orada yapıştırabilirsin.
2. **Kendi bilgisayarından:** Overview’daki SSH komutunu kopyala veya Mac **Terminal**’de:

```bash
ssh root@VPS_IP_ADRESIN
```

Şifre ekranda görünmez; yapıştırıp Enter’a bas. Sorun olursa: Overview’da şifre **Change** / **Reset SSH** seçeneklerine bak.

---

## 5) Projeyi kurma (Hostinger VPS = normal Ubuntu)

Bundan sonrası Hostinger’a özel değil; standart Ubuntu + Docker:

1. Repoyu sunucuya al (`git clone` veya zip).
2. `sudo bash deploy/bootstrap-server.sh` ile Docker kurulumu.
3. `.env` ve `deploy/.env.api` dosyalarını doldur.
4. `docker compose up -d --build`
5. DNS yayıldıktan sonra HTTPS: `export LETSENCRYPT_EMAIL=...` ve `sudo -E bash deploy/enable-https.sh`

Tüm komutlar ve açıklamalar: **[REBIOVIL-SIFIRDAN.md](./REBIOVIL-SIFIRDAN.md)** (4. adımdan itibaren).

Teknik nginx/compose özeti: **[REBIOVIL-YAYIN.md](./REBIOVIL-YAYIN.md)**.

---

## 6) Sık sorunlar (Hostinger)

| Durum | Ne kontrol et |
|--------|----------------|
| Site / API dışarıdan açılmıyor | hPanel **Firewall**’da 80 ve 443 **Accept** mi? VPS “Running” mi? |
| SSH girilmiyor | Port **22** firewall’da açık mı? IP ve root şifresi doğru mu? |
| Sertifika (HTTPS) hata veriyor | `rebiovil.com` gerçekten bu VPS IP’sine **A** ile gidiyor mu? (yayılmayı bekle) |
| “Hosting” panelinde dosya yükledim | Docker burada çalışmaz; işlem **VPS SSH** üzerinden yapılmalı. |

---

## Özet

- Hostinger’de **VPS + Ubuntu** kullan.
- **Firewall**’da **22, 80, 443** aç.
- **DNS**’te `@` ve `www` **A** kayıtlarını VPS IP’sine ver.
- **SSH** (Browser terminal veya `ssh root@...`) ile [REBIOVIL-SIFIRDAN.md](./REBIOVIL-SIFIRDAN.md) adımlarını uygula.
