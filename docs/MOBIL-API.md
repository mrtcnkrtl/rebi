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

### `GET /today/plan?user_id=...&lat=&lon=`

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
  "weather": { "uv_index": 7, "humidity": 42, "temperature": 24 },
  "weather_source": "live",
  "environment_advice": [
    { "time": "Sabah", "category": "Koruma", "icon": "☀️", "action": "SPF 50 (…)", "detail": "…", "priority": 1 }
  ],
  "reminders": [
    {
      "id": "water_intake",
      "title": "Su içme zamanı",
      "body": "Günlük hedef 2000 ml. İçtikçe kaydet.",
      "start": "09:00",
      "end": "21:00",
      "every_minutes": 120,
      "log_event": "water_intake",
      "category": "water_intake",
      "actions": [
        { "id": "ml_250", "label": "1 bardak (250 ml)", "log_event": "water_intake", "payload": { "ml": 250 } },
        { "id": "ml_500", "label": "2 bardak (500 ml)", "log_event": "water_intake", "payload": { "ml": 500 } }
      ],
      "open_path": "/dashboard"
    }
  ],
  "progress": { "water_ml_total": 750, "makeup": { "logged": true, "used": true, "removed": false } },
  "checkin_done": false
}
```

Hatırlatıcı saatleri **yerel duvar saatidir**. Sunucu planı üretir; cihaz bu pencereleri
kendi saat diliminde yerel bildirim olarak kurabilir veya sunucudan push bekleyebilir
(aşağıya bakın). `every_minutes` doluysa hatırlatıcı pencere boyunca o aralıkla tekrarlar.
`log_event` alanı, kullanıcı hatırlatıcıya yanıt verdiğinde gönderilecek olay tipidir.

Yapılan iş listeden otomatik düşer: su hedefi dolunca su hatırlatıcısı, rutin blok
işaretlenince rutin hatırlatıcısı gelmez.

### Hatırlatıcı kimlikleri

| id | pencere | koşul |
| --- | --- | --- |
| `routine_morning` | 07:30–09:30 | sabah rutini işaretlenmemişse |
| `makeup_log` | 10:00–11:00 | bugün makyaj kaydı yoksa |
| `water_intake` | 09:00–21:00, 120 dk | toplam < 2000 ml |
| `spf_refresh` | 11:00–16:00, 120 dk | UV ≥ 5 ve günde 2'den az tazeleme |
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
| `water_intake` | `{ "ml": 250 }` | gün toplamına eklenir |
| `nutrition` | `{ "junk_food": true }` | alanlar gün içinde birleştirilir |
| `makeup` | `{ "used": true }` / `{ "removed": true, "method": "double" }` | `method`: `double`, `cleanser`, `water`, `wipe`, `none` |
| `product_finished` | `{ "product": "SPF 50", "step_order": 40 }` | "ürün bitti" butonu; günde en fazla 20 kayıt |
| `routine_completed_block` | `{ "morning": true }` / `{ "evening": true }` | "yaptım" butonu |
| `routine_step` | `{ "done": true, "step_order": 20 }` | adım adım işaretleme |
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

- `POST /chat_general` — `{ user_id, message, history }`. Yanıt: `reply`, kota alanları
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
  "push_enabled": true,
  "actions_supported": true
}
```

`actions_supported`: uygulama bildirim butonlarını (aşağıya bakın) işleyebiliyorsa
`true` gönderin. Android'de bu durumda sunucu **yalnızca veri taşıyan** mesaj gönderir
ve bildirimi butonlarıyla birlikte uygulama kendisi kurar. Varsayılan `false`'tur;
eski sürümler sistemin gösterdiği düz bildirimi almaya devam eder.

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

Cron örneği (10 dakikada bir):

```bash
*/10 * * * * curl -fsS -X POST \
  -H "X-Push-Dispatch-Token: $PUSH_DISPATCH_SECRET" \
  https://rebiovil.com/api/push/dispatch >/dev/null
```

Her hatırlatıcı gün içinde bir kez gider (`push_sends` defteri). Geçersiz hâle gelen
cihaz anahtarları (FCM 403/404) otomatik silinir.

Bildirim verisi (`data`, tüm değerler metin):

| alan | örnek | not |
| --- | --- | --- |
| `reminder_id` | `water_intake` | hatırlatıcı kimliği |
| `log_event` | `water_intake` | ilgili olay tipi |
| `log_date` | `2026-10-28` | kullanıcının **yerel** günü |
| `slot` | `13:00` | pencere içindeki gönderim saati |
| `open_path` | `/dashboard` | dokununca açılacak ekran (web yolu) |
| `actions` | `[{"id":"ml_250","label":"1 bardak (250 ml)"}]` | JSON metni; buton yoksa `[]` |
| `title`, `body` | | yalnızca Android `actions_supported` cihazlarda |

iOS mesajında `aps.category` = `reminder_id` olarak gelir.

### Bildirimden günlük veri toplama

Kullanıcı uygulamayı açmadan bildirimin üzerindeki butonla cevap verir; cevap günlük
kayda (`daily_events`) yazılır ve hatırlatıcı planı buna göre güncellenir (ör. su hedefi
dolunca su hatırlatıcısı susar, makyaj temizlendiyse temizlik hatırlatıcısı düşer).

**1. Kategorileri kaydet.** iOS butonları ancak bildirim gelmeden önce kaydedilmiş
kategoriden çizer. Açılışta `GET /push/actions` çağırın ve her kategoriyi
`UNNotificationCategory` olarak kaydedin (kimlik doğrulaması gerekmez):

```json
{
  "categories": [
    { "id": "water_intake", "open_path": "/dashboard",
      "actions": [ { "id": "ml_250", "label": "1 bardak (250 ml)" }, { "id": "ml_500", "label": "2 bardak (500 ml)" } ] },
    { "id": "makeup_removal", "open_path": "/dashboard",
      "actions": [ { "id": "double", "label": "Çift temizlik" }, { "id": "cleanser", "label": "Temizleyici" }, { "id": "wipe", "label": "Mendil" } ] }
  ]
}
```

Android'de `onMessageReceived` içinde `data.actions` listesinden `NotificationCompat`
butonları kurulur. Butonlar arka planda çalışmalı (uygulamayı öne getirmeden).

**2. Cevabı gönder.**

```
POST /push/respond
Authorization: Bearer <supabase_access_token>
{
  "user_id": "…",
  "reminder_id": "water_intake",
  "action_id": "ml_250",
  "log_date": "2026-10-28",
  "slot": "13:00"
}
```

`log_date` ve `slot` bildirim verisinden aynen geri gönderilir. Hangi olayın hangi yükle
yazılacağına sunucu karar verir; uygulama yük göndermez. Aynı bildirime (aynı
`reminder_id` + `log_date` + `slot`) ikinci dokunuş sayılmaz, bu yüzden çevrimdışı
kuyruğun tekrar denemesi güvenlidir. Kendi kimliğinizi kullanmak isterseniz
`client_event_id` gönderebilirsiniz.

Yanıt:

```json
{ "ok": true, "log_date": "2026-10-28", "log_event": "water_intake",
  "aggregated": { "water_ml_total": 750, "…": "…" } }
```

| kod | anlamı |
| --- | --- |
| 422 | bu hatırlatıcıda böyle bir buton yok veya `slot` biçimi `SS:DD` değil |
| 403 | `user_id` anahtarla uyuşmuyor |

Butonlar:

| reminder_id | butonlar (`action_id` → yazılan kayıt) |
| --- | --- |
| `routine_morning` | `done` → sabah rutini yapıldı |
| `routine_evening` | `done` → akşam rutini yapıldı |
| `makeup_log` | `yes` / `no` → makyaj yapıldı / yapılmadı |
| `water_intake` | `ml_250` / `ml_500` → su eklendi |
| `spf_refresh` | `done` → güneş kremi tazelendi |
| `nutrition_log` | `junk` / `clean` → abur cubur yedi / yemedi |
| `makeup_removal` | `double` / `cleanser` / `wipe` → temizleme yöntemi |
| `lip_balm`, `daily_checkin` | buton yok; dokununca `open_path` açılır |

**Yerel bildirimler.** Sunucuda FCM kapalıysa (`push_configured: false`) uygulama
`GET /today/plan` yanıtındaki `reminders` ile yerel bildirim kurar; her hatırlatıcıda
`category`, `actions` ve `open_path` aynı biçimde gelir. Cevap yine `POST /push/respond`
ile gönderilir (`slot` = bildirimin kurulduğu saat). Cevap deftere de yazıldığı için
sunucu aynı pencereye ayrıca push göndermez.

**Arka planda oturum.** Buton arka planda çalıştığında erişim anahtarının süresi dolmuş
olabilir; isteği göndermeden önce Supabase SDK'sıyla oturumu tazeleyin. İstek
başarısız olursa cevabı kuyruğa alıp uygulama açıldığında tekrar gönderin.

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
