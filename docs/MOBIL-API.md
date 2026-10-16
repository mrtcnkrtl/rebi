# Rebi mobil API sözleşmesi

Mobil uygulamanın ihtiyaç duyduğu uçlar, veri şekilleri ve akışlar.
Temel adres: `https://rebiovil.com/api`

## Kimlik doğrulama

Supabase oturumundan alınan erişim anahtarı her istekte gönderilir:

```
Authorization: Bearer <supabase_access_token>
```

`user_id` alanı anahtarın `sub` değeriyle aynı olmalıdır; farklıysa sunucu 403 döner.
Anahtar yoksa 401 döner. Supabase girişi, storage ve veritabanı erişimi mobilde
hâlihazırda kullanılan Supabase SDK'sı ile aynı projeye bağlanır.

## Açılış akışı

1. `GET /me/snapshot` — profil, yürürlükteki rutin, bugünün ilerlemesi, rıza durumu,
   sohbet imleci ve Plus durumu tek çağrıda gelir.
2. `consent.legal_accepted` veya `consent.ai_processing_allowed` `false` ise kullanıcıyı
   onay ekranına al ve `POST /legal-consent/accept` çağır. **Bu kayıt olmadan tüm yapay
   zekâ uçları 403 döner.**
3. `GET /today/plan` — gün içi ekran: rutin, havaya göre ürün önerileri ve hatırlatıcılar.
4. `POST /devices/register` — bildirim izni verildiyse cihazı kaydet.

## Ana ekran

### `GET /today/plan?user_id=...&lat=&lon=&utc_offset_minutes=`

`lat`/`lon` verilirse canlı hava durumu kullanılır ve **konum izni** gerekir
(`consent.location_processing_allowed`). Verilmezse sırayla bugün kaydedilmiş hava
olayı, profildeki son bilinen koordinat (konum izni varsa) ve varsayılan değerler
denenir; hangisinin kullanıldığı `weather_source` alanındadır
(`live` | `tracking` | `profile` | `default`).

Varsayılan değerlerde UV 3 kabul edilir ve güneş kremi tazeleme hatırlatıcısı
oluşmaz. Hava durumuna bağlı hatırlatıcıların çalışması için uygulama ya `lat`/`lon`
göndermeli ya da gün içinde bir `location` olayı kaydetmelidir.

```json
{
  "user_id": "…",
  "log_date": "2026-10-04",
  "has_routine": true,
  "routine": [{ "time": "Sabah", "action": "Jel temizleyici", "detail": "…", "step_order": 10 }],
  "weather": {
    "uv_index": 7, "humidity": 42, "temperature": 24,
    "uv_window": { "start": "11:00", "end": "16:00", "peak": "13:00", "max": 7 }, "uv_now": 4
  },
  "weather_source": "live",
  "environment_advice": [
    { "time": "Sabah", "category": "Koruma", "icon": "☀️", "action": "SPF 50 (…)", "detail": "…", "priority": 1 }
  ],
  "weather_decisions": {
    "spf": { "spf": "50", "level": "high", "uv": 7, "refresh": true, "refresh_every_minutes": 120,
             "window": { "start": "11:00", "end": "16:00", "peak": "13:00" } },
    "moisture": { "kind": "boost", "humidity": 38, "temperature": 18, "night_mask": false },
    "lip_balm": { "needed": false, "reason": null }
  },
  "reminder_settings": { "wake_time": "07:30", "sleep_time": "23:00", "water_every_minutes": 120, "water_target_ml": 2000, "enabled": { "water": true } },
  "reminders": [
    {
      "id": "water_intake",
      "title": "Su içme zamanı",
      "body": "Günlük hedef 2000 ml. İçtikçe kaydet.",
      "start": "09:00",
      "end": "21:00",
      "every_minutes": 120,
      "log_event": "water_intake"
    }
  ],
  "progress": {
    "water_ml_total": 750,
    "routine_steps": { "morning": [10, 20], "evening": [] },
    "makeup": { "logged": true, "used": true, "removed": false, "removal_method": null }
  },
  "checkin_done": false
}
```

**Hava ve kararlar.** `weather.uv_window` (saatlik UV biliniyorsa) UV'nin eşiğe (5) ulaştığı, en yüksek saati içeren
kesintisiz aralıktır (konumun yerel duvar saati); `uv_now` o saatteki UV'dir. Alanlar yoksa kaynak saatlik veri vermemiştir.
`weather_decisions` bugünün üç kararını **yapılandırılmış** verir (metin yok; istemci cümleleri kendi dilinde kurar):

| karar | alanlar |
| --- | --- |
| `spf` | `spf` (`30`, `30+`, `50`, `50+`), `level` (`low`, `moderate`, `high`, `extreme`), `uv`, `refresh` (UV ≥ 5), `refresh_every_minutes`, `window` (UV aralığı ya da null) |
| `moisture` | `kind` (`intense`, `barrier`, `boost`, `light`, `light_hot`, `standard`), `humidity`, `temperature`, `night_mask` |
| `lip_balm` | `needed`, `reason` (`cold`, `dry`, `both` ya da null) |

Nemlendirici türü öncelik sırasıyla seçilir: nem < %25 → `intense`; sıcaklık < 5 → `barrier`; nem < %40 → `boost`;
nem > %75 → `light`; sıcaklık > 35 → `light_hot`; aksi `standard`. Eski sunucu bu alanı göndermez; istemci o zaman
`environment_advice` listesini gösterir.

`utc_offset_minutes` (−840…840) verilirse "bugün" kullanıcının yerel günüdür; verilmezse sunucu günü
kullanılır. Mobil bunu her zaman göndermelidir: yoksa gece 00:00–03:00 (TR) arası bir önceki gün görünür.
Aynı parametre `/me/snapshot`, `/me/history`, `/daily_tracking/today` ve `/daily_checkin/status`
uçlarında, check-in isteğinde ise gövdede (`utc_offset_minutes`) vardır.

Hatırlatıcı saatleri **yerel duvar saatidir**. Sunucu planı üretir; cihaz bu pencereleri
kendi saat diliminde yerel bildirim olarak kurabilir veya sunucudan push bekleyebilir
(aşağıya bakın). `every_minutes` doluysa hatırlatıcı pencere boyunca o aralıkla tekrarlar.
`log_event` alanı, kullanıcı hatırlatıcıya yanıt verdiğinde gönderilecek olay tipidir.

Yapılan iş listeden otomatik düşer: su hedefi dolunca su hatırlatıcısı, rutin blok
işaretlenince rutin hatırlatıcısı gelmez.

### Hatırlatıcı ayarları

Pencereler kullanıcının gün düzenine göre kayar. Aşağıdaki saatler varsayılan düzenin (uyanma 07:30,
uyku 23:00) sonucudur.

- `GET /me/reminder-settings?user_id=…` — `{ "settings": {…}, "synced": true }`. Kayıt yoksa varsayılan döner.
- `PUT /me/reminder-settings` — `{ "user_id": "…", "wake_time": "06:30", "sleep_time": "22:30",
  "water_every_minutes": 90, "water_target_ml": 2500, "enabled": { "spf": false } }`; yalnızca gönderilen alanlar değişir
  (`enabled` içinde yalnızca gönderilen kategoriler). Yanıt güncel ayardır.

| alan | kural |
| --- | --- |
| `wake_time` | `SS:DD`, en erken 04:00 |
| `sleep_time` | `SS:DD`, en geç 23:59; uyanmadan en az 9 saat sonra |
| `water_every_minutes` | `60`, `90`, `120` ya da `180` |
| `water_target_ml` | günlük su hedefi: `1500`, `1750`, `2000` (varsayılan), `2250`, `2500` ya da `3000` |
| `enabled` | `routine`, `water`, `makeup`, `nutrition`, `spf`, `lip_balm`, `checkin` → `true`/`false` |

Geçersiz değer 422 döner ve hiçbir şey kaydedilmez. Kapatılan kategorinin hatırlatıcıları ne plana ne
push'a girer. Pencereler: sabah rutini uyanma + 0–2 sa; makyaj sorusu +2,5–3,5 sa; güneş kremi +3,5–8,5 sa;
dudak balsamı +4,5–5,5 sa; su +1,5 sa ile uykudan 2 sa önce arası; akşam rutini ve makyaj temizliği uykudan
2 sa önce–uyku; check-in uykudan 2 sa–30 dk önce; beslenme kaydı uykudan 3–2,5 sa önce.

### Hatırlatıcı kimlikleri

| id | pencere (varsayılan düzen) | koşul |
| --- | --- | --- |
| `routine_morning` | 07:30–09:30 | sabah rutini işaretlenmemişse |
| `makeup_log` | 10:00–11:00 | bugün makyaj kaydı yoksa |
| `water_intake` | 09:00–21:00, 120 dk | toplam < kullanıcının su hedefi (`water_target_ml`, varsayılan 2000 ml) |
| `spf_refresh` | 11:00–16:00, 120 dk (saatlik UV biliniyorsa `uv_window`; uyanma–uyku gününe kırpılır, 30 dk'dan kısaysa sabit pencere) | UV ≥ 5 ve günde 2'den az tazeleme |
| `lip_balm` | 12:00–13:00 | sıcaklık ≤ 10 °C veya nem < %35 |
| `nutrition_log` | 20:00–20:30 | beslenme kaydı yoksa |
| `makeup_removal` | 21:00–23:00 | makyaj yapıldı ve temizlenmedi |
| `routine_evening` | 21:00–23:00 | akşam rutini işaretlenmemişse |
| `daily_checkin` | 21:00–22:30 | bugün check-in yapılmadıysa |

### `GET /routine/active?user_id=...`

Yalnızca yürürlükteki rutini döndürür (`has_routine`, `routine`, `assessment_id`,
`created_at`). Rutin üretmez; üretim `POST /generate_routine` ile yapılır.

## Gün içi kayıt

### `POST /daily_tracking/ingest`

```json
{
  "user_id": "…",
  "type": "water_intake",
  "payload": { "ml": 250 },
  "timestamp": "2026-10-04T09:12:00+03:00",
  "source": "mobile",
  "client_event_id": "cihazda-uretilen-tekil-kimlik"
}
```

`client_event_id` göndermek **çevrimdışı kuyruk için şarttır**: aynı kimlikle gelen
ikinci istek veritabanına yazılmaz, böylece ağ tekrar denemesi su miktarını iki kez
saymaz. Yanıt, o güne ait güncel toplamı (`aggregated`) döndürür.

Olay tipleri ve yükleri:

| type | payload | not |
| --- | --- | --- |
| `water_intake` | `{ "ml": 250 }` | gün toplamına eklenir. Negatif değer (`-250`) yanlış girişi düzeltir; toplam 0'ın altına inmez, tek kayıt en çok ±5000 ml |
| `nutrition` | `{ "junk_food": true, "snacks": true, "sweets": false, "fried_food": false, "dairy": false, "balanced": false }` | alanlar gün içinde birleştirilir, her alan için son değer geçerlidir. `junk_food` bütün abur cubur seçeneklerinin özetidir |
| `makeup` | `{ "used": true }` / `{ "removed": true, "method": "double" }` | `method`: `double`, `cleanser`, `water`, `wipe`, `none` |
| `product_finished` | `{ "product": "SPF 50", "step_order": 40 }` | "ürün bitti" butonu; günde en fazla 20 kayıt |
| `routine_completed_block` | `{ "morning": true }` / `{ "evening": true }` | "yaptım" butonu. `false` bloğu yeniden açar (son olay geçerli) |
| `routine_step` | `{ "done": true, "block": "morning", "step_order": 20 }` | adım adım işaretleme; `block`: `morning` / `evening`. Aynı adım için son olay geçerlidir, `done: false` işareti kaldırır. `progress.routine_steps` işaretli adımları döndürür |
| `spf_refresh` | `{}` | güneş kremi tazelendi |
| `stress` / `sleep` | `{ "value": 3 }` / `{ "hours": 7 }` | |
| `location` | `{ "lat": 41.0, "lon": 29.0 }` | sunucu hava durumu anlık görüntüsü ekler; **konum izni yoksa 403** |
| `photo_meta` | serbest | fotoğraf üst verisi |
| `checkin_feedback` | serbest | |

Bir yöntemle (`method`) gelen makyaj kaydı, makyajın yapıldığı **ve** temizlendiği
anlamına gelir (`none` hariç).

### `GET /daily_tracking/today?user_id=...&log_date=`

O günün olayları ve toplamı.

### `POST /daily_checkin`

Akşam check-in'i; rutini risk skoruna göre uyarlar. Yapay zekâ izni gerekir.

## Kullanıcı verisi

- `GET /me/snapshot?user_id=...` — açılış paketi (yukarıda).
- `GET /me/profile?user_id=...` — profil.
- `PATCH /me/profile` — `{ "user_id": "…", "skin_type": "dry" }`; yalnızca gönderilen
  alanlar değişir. `skin_type`: `normal`, `dry`, `oily`, `combination`, `sensitive`.
  `age` 13–100 arasına sabitlenir.
- `GET /me/history?user_id=...&days=30` — en fazla 90 gün; her gün için takip özeti
  (`tracking`), o günün check-in'i (`checkin`) ve son değerlendirmeler.

## Sohbet

Sohbet geçmişi sunucuda tutulur; web ve mobil aynı konuşmayı görür.

- `POST /chat_general` — `{ user_id, message, history, utc_offset_minutes }`. `utc_offset_minutes` (−840…840) verilirse sohbet kullanıcının yerel gününün özetini (hava, su, makyaj ve temizleme yöntemi, beslenme, rutin) yanıt için kullanır; özet kısa tutulur, ürün adı içermez ve yalnızca soruyla ilgiliyse kullanılır. Yanıt: `reply`, kota alanları
  (`usage_kind`, `usage_remaining`, `usage_limit`, `chat_quota_exceeded`). Başarılı her
  tur sunucuda saklanır.
- `GET /chat/history?user_id=...&limit=50&after_seq=&surface=general` — eskiden yeniye
  mesajlar ve `cursor`. `after_seq` verilirse yalnızca o imleçten sonrakiler gelir;
  cihaz `cursor` değerini saklayıp her açılışta tüm geçmişi indirmemelidir.
- `DELETE /chat/history?user_id=...` — sohbeti her iki platformdan siler.
- `POST /chat/history/import` — `{ user_id, messages: [{ role, content }], surface }`.
  Sunucu öncesi dönemden kalan yerel geçmişi bir kez yukarı taşır; sunucuda kayıt
  varsa `skipped: true` döner ve kopya oluşmaz (en fazla 60 mesaj).
- `GET /chat_usage?user_id=...` — üst sayaç için kota özeti.

## Bildirimler

### Cihaz kaydı

```
POST /devices/register
{
  "user_id": "…",
  "token": "<fcm_token>",
  "platform": "android",
  "utc_offset_minutes": 180,
  "locale": "tr",
  "app_version": "1.0.0",
  "push_enabled": true
}
```

`utc_offset_minutes` zorunludur: hatırlatıcı saatleri yerel olduğu için sunucu cihazın
saat dilimini bilmek zorundadır. Uygulama her açılışta bu ucu çağırmalı (kayıt `token`
üzerinde upsert edilir ve `last_seen_at` güncellenir). Kullanıcı bildirimleri kapatırsa
`push_enabled: false` gönderin veya `DELETE /devices/register?user_id=…&token=…` çağırın.

Yanıttaki `push_configured`, sunucuda FCM yapılandırmasının açık olup olmadığını söyler;
`false` ise bildirimler istemci tarafı yerel bildirim olarak kurulmalıdır.

### Sunucudan gönderim

`POST /push/dispatch` zamanı gelen hatırlatıcıları kayıtlı cihazlara gönderir.
Bu uç kullanıcıya açık değildir; yalnızca sunucu cron'u içindir:

```
X-Push-Dispatch-Token: <PUSH_DISPATCH_SECRET>
```

Gerekli sunucu ortam değişkenleri:

- `FCM_SERVICE_ACCOUNT_JSON` — Firebase servis hesabı JSON'u (ya da dosya yolu)
- `FCM_PROJECT_ID` — isteğe bağlı; yoksa servis hesabındaki `project_id` kullanılır
- `PUSH_DISPATCH_SECRET` — dağıtım anahtarı; tanımlı değilse uç 503 döner

Zamanlayıcı repoda hazırdır: `docker-compose.yml` içindeki **`push-cron`** servisi (`backend/push_cron.py`)
her 5 dakikada bir (saat başlarına hizalı) bu ucu çağırır; sunucuda elle crontab gerekmez.
`deploy/.env.api` içine `PUSH_DISPATCH_SECRET` ve `FCM_SERVICE_ACCOUNT_JSON` yazıp
`docker compose up -d --build` yeterlidir. `PUSH_DISPATCH_SECRET` boşsa servis kapalı bekler ve tek satır bildirir.
Elle denemek için:

```bash
curl -fsS -X POST -H "X-Push-Dispatch-Token: $PUSH_DISPATCH_SECRET"   "https://rebiovil.com/api/push/dispatch?max_users=1000"
```

Yanıt: `users_considered`, `reminders_sent`, `notifications_sent`, `invalid_tokens_removed`,
`push_configured` ve **`deliveries_failed`** (FCM'e ulaşılamadığı için gitmeyen; gönderim rezervi geri alınır
ve pencere bitmeden sonraki turda yeniden denenir). Son turun özeti `GET /health` içinde
`push_dispatch` altında görünür (`at` zamanı bayatlarsa dağıtıcı çalışmıyordur).
`max_users` sınırına ulaşılırsa sunucu günlüğüne uyarı düşer.

Her hatırlatıcı gün içinde bir kez gider (`push_sends` defteri). Bildirim verisinde
`reminder_id`, `log_event` ve `log_date` taşınır; kullanıcı bildirime dokunduğunda
uygulama ilgili ekranı açıp `log_event` ile kayıt gönderebilir. Geçersiz hâle gelen
cihaz anahtarları (FCM 403/404) otomatik silinir.

## Rıza ve gizlilik

- `GET /legal-consent/status?user_id=...`
- `POST /legal-consent/accept` — `kvkk_accepted`, `explicit_consent_accepted`,
  `ai_processing_accepted` zorunlu; konum ve fotoğraf izinleri isteğe bağlıdır.
- `GET /privacy-preferences?user_id=...`, `POST /privacy-preferences`
- `POST /account/delete` — `confirm_text: "HESABIMI_SIL"`; hesap, uygulama verisi ve
  fotoğraflar kalıcı silinir.

Yapay zekâ izni olmadan sohbet, rutin üretimi ve check-in uçları 403 döner; konum izni
olmadan konumlu istekler, fotoğraf izni olmadan fotoğraf yükleme reddedilir.

## Hata kodları

| kod | anlamı |
| --- | --- |
| 401 | anahtar yok veya geçersiz |
| 403 | `user_id` anahtarla uyuşmuyor ya da gerekli rıza yok |
| 422 | gövde/parametre doğrulaması başarısız |
| 429 | hız sınırı; kısa süre sonra tekrar deneyin |
| 502 | veritabanı veya sağlayıcı geçici hatası |
| 503 | sunucu yapılandırması eksik (ör. push anahtarı yok) |

## Şema dosyası

Üretimde `/docs`, `/redoc` ve `/openapi.json` kapalıdır (uç listesini dışarıya
açmamak için). Şemayı üretmek gerektiğinde:

```bash
cd backend
API_DOCS_ENABLED=1 python -c "import json, main; print(json.dumps(main.app.openapi(), ensure_ascii=False))" > openapi.json
```

Geliştirme ortamında `API_DOCS_ENABLED=1` ile `/docs` arayüzü açılır.
