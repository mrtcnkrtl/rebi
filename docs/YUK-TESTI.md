# Yük testi

Amaç: gerçek kullanıcı gelmeden önce API'nin (ve altındaki Supabase, Redis, Gemini hattının) yük altında nasıl
davrandığını ölçmek. Araç `backend/loadtest.py` (api imajının içinde hazır gelir, ek kurulum gerekmez).

## Başlamadan önce

- **Düşük trafikli bir saat seç.** Test gerçek sunucuya karşı çalışır ve veritabanına (sentetik kullanıcılar adına) yazar.
- **Sentetik kullanıcılar kendini belli eder.** E-postaları `loadtest+...@loadtest.invalid` (hiçbir zaman gerçek bir
  alan adına çözülmez) ve hesaplarında `loadtest=true` işareti vardır. `cleanup` yalnızca bu üç koşulu birden
  taşıyanları siler; gerçek bir kullanıcıya dokunamaz. Silinen kullanıcının bütün verisi (olaylar, sohbet, rutin) cascade ile gider.
- **Yapay zekâ varsayılan olarak kapalıdır.** Sohbet mesajı göndermek için `--chat-messages N --allow-ai-cost`
  gerekir ve tahmini maliyet (mesaj başı ~0,002 USD) başlamadan yazılır. 200 mesaj ≈ 0,40 USD.
- Komutlar VPS'te, proje klasöründe (`/opt/rebi`) çalışır. Gerekli ortam değişkenleri (`SUPABASE_URL`,
  `SUPABASE_SERVICE_KEY`, `SUPABASE_JWT_SECRET`) api konteynerinde zaten vardır.

## 1) Sentetik kullanıcıları oluştur

```bash
docker compose exec api python loadtest.py provision --count 50 --out /tmp/tokens.json
```

Her kullanıcı Supabase'de oluşturulur, token'ı yerelde imzalanır (Supabase Auth'un giriş hız sınırına takılmaz) ve
rıza kaydı API üzerinden yazılır. Token dosyası hassastır (izinleri 0600); iş bitince silin.

## 2) Yapay zekâsız yük (uygulama açılışı, su kaydı, plan, geçmiş)

Küçükten büyüğe: önce ısınma, sonra artan eşzamanlılık.

```bash
docker compose exec api python loadtest.py run --tokens /tmp/tokens.json --users 10 --duration 60
```

```bash
docker compose exec api python loadtest.py run --tokens /tmp/tokens.json --users 50 --duration 120 --report /tmp/rapor.json
```

## 3) Sohbet (yapay zekâ maliyeti var)

```bash
docker compose exec api python loadtest.py run --tokens /tmp/tokens.json --users 10 --duration 90 --chat-messages 200 --allow-ai-cost
```

## Sonucu okumak

Çıktı uç başına istek sayısı ile p50/p95/p99/maks gecikmeyi (ms), 5xx ve 429 sayısını verir. Varsayılan eşikler
(`--p95-ms 500`, `--chat-p95-ms 8000`, `--health-ms 500`, `--max-error-rate 0.01`); biri aşılırsa `SONUÇ: KALDI` yazar ve
çıkış kodu 1 olur.

| Bulgu | Anlamı | Ne yapılır |
|---|---|---|
| `/health p95` yüksek | Olay döngüsü yük altında yanıtsız kaldı | `docker compose logs api` ve `docker stats`; thread/DB beklemesi aranır |
| 5xx oranı > %1 | Sunucu hatası | `docker compose logs api \| grep ERROR` |
| 429 oranı > %1 | Hız sınırı meşru yükü reddediyor | `RATE_LIMIT_IP_MULTIPLIER` / `AI_USER_LIMIT_PER_MINUTE` gözden geçirilir |
| Yalnızca `chat` p95 yüksek | Gemini ya da bilgi tabanı gecikmesi | `docker compose logs api \| grep gemini_usage` (ms alanı) |
| `ingest` 503 | Veritabanı yazımı başarısız (mobil kuyrukta tutar) | Supabase Reports > Database |

Yük sürerken ayrı bir terminalde izleyin:

```bash
docker stats --no-stream
```

```bash
docker compose logs --since 5m api | grep -E "gemini_usage|weather_call|ERROR"
```

Ayrıca Supabase Dashboard > Reports'ta bağlantı sayısı ve CPU'ya bakın.

## Sonuç ne kadar gerçek kullanıcıya denk gelir?

Kaba bir hesap (varsayımlar: kullanıcı başına günde ~20 işlem, günün %15'i tepe saatte): 5.000 kayıtlı kullanıcı tepe saatte
saniyede ~8 istek üretir. 50 sanal kullanıcı (işlemler arası ~0,6 sn bekleme) bunun yaklaşık 10 katı yük bindirir. 50 sanal
kullanıcıyla eşikler tutuyorsa, 5.000 kullanıcı için güvenli bir pay vardır. Bu bir tahmindir; gerçek davranış kullanım
alışkanlıklarına bağlıdır.

## Temizlik

```bash
docker compose exec api python loadtest.py cleanup
```

Önce yalnızca listeler. Listeyi kontrol edip silmek için:

```bash
docker compose exec api python loadtest.py cleanup --yes
```

```bash
docker compose exec api rm -f /tmp/tokens.json
```
