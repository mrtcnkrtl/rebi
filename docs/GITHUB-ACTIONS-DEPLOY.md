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
| `VPS_SSH_KEY` | Private key’in **base64 tek satırı** (aşağıdaki komutla üret) |

**Private key’i asla commit etme, ekran görüntüsünde paylaşma.**

Secret adları **tam olarak** tablodaki gibi olmalı (`VPS_SSH_KEY` vb.).

### `VPS_SSH_KEY` — base64 (zorunlu)

Çok satırlı PEM’i doğrudan secret’a yapıştırmak Actions’ta dosyayı bozar (`libcrypto` / `no key found`). Mac’te:

```bash
base64 -i ~/.ssh/gha_deploy | tr -d '\n' | pbcopy
```

(`-i` macOS’ta dosyadan okur; `base64 < dosya` da olur.) Anahtar dosyan `rebi_deploy` ise yolu ona çevir. **Tek satır** panoya gelir → GitHub’da `VPS_SSH_KEY` → **Update** → yapıştır; başına/sonuna boşluk veya tırnak ekleme.

**Alternatif:** Secret’a doğrudan private key’in tamamını yapıştırabilirsin (ilk satır `-----BEGIN … PRIVATE KEY-----` olmalı). Workflow bunu da kabul eder.

### `Incorrect padding` (Actions log)

Genelde base64 **kesik** veya sonundaki `=` karakterleri eksik. Çözüm: secret’ı silip yeniden oluştur (`base64 -i … | tr -d '\n' | pbcopy`), tek seferde yapıştır; ya da ham PEM’i çok satırlı yapıştır.

### Hata özeti

- **`Incorrect padding`:** Base64 bozuk/kısa; secret’ı yeniden kopyala veya **ham PEM** yapıştır (yukarıda).
- **`error in libcrypto`:** Bozuk PEM; **base64** veya tam PEM kullan.
- **`ssh: no key found`:** Public key yapıştırma veya yanlış secret.

PEM RSA anahtarı yoksa:

```bash
ssh-keygen -t rsa -b 4096 -m PEM -f ~/.ssh/gha_deploy -N "" -C "gha"
```

`.pub` satırını sunucuda `authorized_keys` sonuna ekle; sonra yukarıdaki `base64` komutunu `gha_deploy` için çalıştır.

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

## 7) “exit code 1” / kırmızı iş

1. **Actions** → başarısız koşuya tıkla → **SSH — pull + docker compose** adımını aç → logda **en alttaki kırmızı / hata satırlarını** oku.
2. **Zaman aşımı** (`timeout`, `i/o timeout`): VPS’te ilk build uzun sürer; workflow’da `command_timeout: 45m` kullanılıyor, yine yetmezse süreyi artır.
3. **`docker: command not found`:** Sunucuda Docker kurulu mu? `ssh` ile bağlanıp `docker compose version` dene.
4. **`fatal: not a git repository`** veya **`cd: /opt/rebi`:** Klasör ve `git clone` kurulumu eksik.
5. **Disk dolu** (`no space`): VPS disk temizliği veya `docker system prune` (dikkatli kullan).

Workflow dosyası güncellenince `git push` ile repoya gönder; bir sonraki deploy yeni ayarlarla çalışır.
