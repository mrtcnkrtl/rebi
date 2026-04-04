# GitHub Actions ile otomatik deploy (rebiovil VPS)

`main` dalına her **push** geldiğinde GitHub, VPS’e SSH ile bağlanır; `/opt/rebi` içinde kodu günceller ve Docker’ı yeniden derler. Manuel `ssh` + `git pull` gerekmez.

## 1) Sunucuda deploy SSH anahtarı

**Mac Terminal** (kendi bilgisayarında; anahtarları repoya koyma):

```bash
ssh-keygen -t ed25519 -f ~/.ssh/rebi_deploy -N "" -C "github-actions-rebiovil"
```

- **Public key** (`.pub`) → VPS’e eklenecek  
- **Private key** → sadece GitHub Secret olarak

Public içeriği göster:

```bash
cat ~/.ssh/rebi_deploy.pub
```

**VPS’e bağlan** (Browser terminal veya `ssh root@IP`), sonra:

```bash
mkdir -p ~/.ssh
chmod 700 ~/.ssh
nano ~/.ssh/authorized_keys
```

Dosyanın **son satırına** `rebi_deploy.pub` içindeki **tek satırlık** metni yapıştır. Kaydet, çık.

```bash
chmod 600 ~/.ssh/authorized_keys
```

İstersen bağlantı testi (Mac’te):

```bash
ssh -i ~/.ssh/rebi_deploy root@SUNUCU_IP "echo ok"
```

Şiforsuz `ok` yazmalı.

## 2) GitHub Secrets

Repo: **https://github.com/mrtcnkrtl/rebi** → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**

| Ad | Değer |
|----|--------|
| `VPS_HOST` | VPS IPv4 (ör. `76.13.14.133`) |
| `VPS_USER` | `root` (veya SSH kullanıcı adın) |
| `VPS_SSH_KEY` | **Private key** tam metni (`cat ~/.ssh/rebi_deploy` — `BEGIN` / `END` satırları dahil) |

**Private key’i asla commit etme, ekran görüntüsünde paylaşma.**

## 3) Workflow dosyası

Repoda: `.github/workflows/deploy-rebiovil.yml` (zaten ekli).

Push sonrası kontrol: GitHub → **Actions** sekmesi → **Deploy rebiovil** işinin yeşil olması.

## 4) Repo private ise

VPS’te `/opt/rebi` zaten `git clone` ile kurulduysa ve **HTTPS + public** ise ek iş yok.  
Repo **private** yapılırsa sunucuda `git pull` için [deploy key](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/managing-deploy-keys) veya token gerekir; ayrı kurulum.

## 5) Davranış

- `git reset --hard origin/main` kullanılır: sunucudaki **izlenen** dosyalarda yerel fark kalmasın diye.  
- **`.env`** ve **`deploy/.env.api`** `.gitignore`’da olduğu sürece silinmez / ezilmez.

## 6) Elle tetikleme

GitHub → **Actions** → **Deploy rebiovil** → **Run workflow**.
