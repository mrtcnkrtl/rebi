# Rebi Mobil — Yol Haritası (2026-10-15)

Bu belge, müşterinin son mesajını karşılamak ve uygulamayı hem **çok iyi görünen** hem de
**canlı backend'de sorunsuz çalışan** bir ürüne çevirmek için ortak planımızdır.
Aşağıdaki "Bugünkü durum" bölümü varsayım değil, 2026-10-15'te koda bakılarak çıkarıldı.

Çalışma kuralları değişmiyor: web (`frontend/`) olduğu gibi kalır, işler `flutter-mobile`
dalında yapılır, backend değişiklikleri web'i bozmayacak şekilde geriye dönük uyumlu olur.

---

## 1. "Bitti" neye denir?

Müşteriye gösterdiğimizde şunların hepsi doğru olmalı:

1. Giriş yapınca ilk ekranda **bugünün rutini** var; rutin yapılınca **"Yaptım"**, altta sabit **"Ürün bitti"** düğmesi çalışıyor.
2. Gün içinde **su, makyaj (yaptıysa akşam temizlendi mi, nasıl), beslenme (abur cubur)** tek dokunuşla kaydediliyor.
3. **Havaya göre** güneş kremi, nemlendirici, balsam kararı ekranda ve gerekçesiyle görünüyor.
4. Bunların **saat aralıklı hatırlatıcıları** telefonda gerçekten, doğru saatte çalıyor ve bildirimden işlem yapılabiliyor.
5. **Web'deki sohbet botu** mobilde aynı hesapla, bugünün bağlamını bilerek çalışıyor.
6. Her ekran **tek bir tasarım dilinde**; "web'den taşınmış" ya da "yapay zekâ işi" görünmüyor.
7. Hepsi **canlı sunucuya karşı, gerçek telefonda** denenmiş.

---

## 2. Bugünkü durum (denetim)

Sağlık: `flutter analyze` temiz, **553 test geçiyor**, CI yeşil. Yani kod tabanı sağlam; eksik olan
şey "özellik yazmak"tan çok **cila, birlik ve canlıya çıkış**.

### 2.1 Müşterinin 5 isteği — kodda ne var?

| # | İstek | Durum | Kanıt / boşluk |
|---|-------|-------|----------------|
| 1 | Webdeki chatbot mobilde | **Var** | `ChatScreen`, web ile aynı uçlar (`/chat_general`, `/chat/history`, `/chat_usage`); bugünün bağlamı + öneri çipleri (Faz 4). Boşluk: cihazda hiç denenmedi; eski tasarım dilinde; rutin adımından sohbete kısayol yok. |
| 2a | Girişte günün rutini | **Var** | Açılış rotası `/dashboard` = Bugün; `RoutineChecklistCard` adım adım. Boşluk: ekran uzun ve kalabalık (kartlar + altta 4 ince düğme); "tek odak" yok. |
| 2b | "Yaptım" | **Var** | Alt sabit çubuk (`TodayActionBar`) + adım işaretleri. Boşluk: görsel olarak sıradan; tamamlanma anı sönük. |
| 2c | "Ürün bitti" (altta) | **Kısmen** | Düğme var, biten ürün `product_finished` olayı olarak yazılıyor. **Sonrası yok:** rutinde "bitti" görünmüyor, yeniden alma/raf yok, hatırlatma yok. Düğme şu an yalnız kayıt tutuyor. |
| 3a | Su | **Var** | Halka + 250/500 ml + ayrıntı sayfası. Boşluk: hedef sabit 2000 ml (kişiye/havaya göre değil). |
| 3b | Makyaj → akşam temizlendi mi, nasıl | **Var** | Evet/hayır → temizleme yöntemi sayfası. Boşluk: yalnız tasarım cilası. |
| 3c | Beslenme (abur cubur vb.) | **Var** | Evet/hayır + seçenek sayfası. Boşluk: tasarım cilası. |
| 4 | Havaya göre güneş kremi / nemlendirici / balsam | **Kısmen** | Backend kural motoru güçlü (UV, nem, sıcaklık dalları; soğuk/kuru havada dudak balsamı). Boşluklar: UV yalnız **günün en yüksek değeri**, saatlik eğri yok → SPF yenileme penceresi gerçek UV'ye bağlı değil; hava önbelleği vardı ama **servis çökünce varsayılan değeri (20°C/UV 3) 3 saat "canlı hava" diye sunuyordu** (Faz A'da düzeltildi); kart mavi gradyan + emoji; "bugünün kararı" tek bakışta okunmuyor. "Balsam"ı **dudak balsamı** diye yorumladık (müşteriden teyit lazım). |
| 5 | Saat aralıklı hatırlatıcılar | **Kısmen** | Ayar ekranı (uyanma/uyku, su aralığı, kategori aç/kapa), yerel bildirim, bildirimde eylem düğmeleri var. Boşluklar: **sunucu push cron'u dağıtımda tanımlı değil** (yalnız `MOBIL-API.md`'de örnek); Firebase dosyaları yok; pencereler uyanma/uyku saatinden türetiliyor, tek tek düzenlenemiyor; bildirim düğmeleri ve arka plan davranışı **cihazda doğrulanmadı**. |

### 2.2 Müşteri maddelerinin dışında çıkan bulgular

**Tasarım — iki ayrı dil var.**
- Karşılama/giriş/splash "klinik sıcaklık" dilinde (krem + orman yeşili, Fraunces + Inter): **8 dosya** `Brand` kullanıyor.
- İçerideki her şey (Bugün, Rutin, Geçmiş, Ben, Sohbet, Check-in, Analiz…) web'den gelen `Tw` paletinde: **40 dosya**. Mavi→turkuaz gradyan kartlar, ~20 yerde emoji, Bugün'ün altında üst üste 4 ince düğme.
- **9 tema** (kedi, ayıcık, gün batımı, okyanus, noir…) klinik dille çelişiyor; açılış ekranının ilk denemesi "hiç profesyonel durmuyor, yapay zekâ işi" diye reddedilmişti.
- Sonuç: kullanıcı girişten sonra uygulamanın "değiştiğini" hissediyor.

**Backend — kod hazır ama canlıda değil.**
- `flutter-mobile`, `main`'in **23 commit** önünde. Faz 1–4'ün backend değişiklikleri (12 dosya: `today_plan.py`, `main.py`, `chat_context.py`, yeni testler, **1 yeni migration**: `20261013120000_reminder_settings.sql`) canlıda yok.
- Dağıtım otomatik: `main`'e push → backend testleri → VPS'te `docker compose up --build`. **Migration otomatik uygulanmıyor** (elle Supabase'e çalıştırılmalı).
- Hava önbelleği kusurluydu: servis çökünce varsayılan değer 3 saat önbellekte kalıp `weather_source: "live"` etiketiyle sunuluyordu; `location` olayı önbelleği hiç kullanmıyor, başarısız çekimde `daily_events`'e sahte hava yazıyordu. *(Düzeltildi.)*
- Push cron'u (`POST /push/dispatch`) hiçbir yerde tanımlı değildi. *(Repoda `push-cron` servisi olarak eklendi.)*
- Hesap silme, henüz oluşmamış bir tabloda 502 ile duruyordu (migration'dan önce yayına çıkılırsa herkesin hesap silmesi bozulurdu). *(Düzeltildi.)*

**Doğrulama.**
- Gerçek cihaz testi **hiç yapılmadı** (emülatör bu makinede açılmıyor).
- Görsel regresyon güvencesi yok: ekran görüntüleri geçici testlerle alınıp atılıyor.
- `mobile_locales` yalnız TR/EN; diğer dillerdeki davranış doğrulanmadı (müşteri TR, düşük öncelik).

---

## 3. Tasarım yönü (kod yazmadan önce onaylanacak)

Kural: **önce tasarımı düşün, sonra uygula.** Faz B'nin ilk adımı Bugün ekranının görsel
taslağı; onay çıkmadan ekran kodu yazılmaz.

**İlkeler**
- Tek odak: her ekranda tek bir "şimdi şunu yap" şeyi, gerisi ikinci planda.
- Az öğe, güçlü tipografi: başlıklar Fraunces (kısa, insani), gövde Inter; süs, parıltı, cam hap, gradyan yok.
- Zemin krem, mürekkep orman yeşili; kategori renkleri **soluk ve tek ailede** (su = su yeşili-mavi, makyaj = pudra, beslenme = adaçayı, güneş = bal/amber).
- Emoji yerine kodla çizilmiş / Lucide ikonlar.
- Hareket sakin ve anlamlı: halka dolumu, tik çizimi, hafif haptic. Kutlama bağırmaz.
- Boş, yükleniyor, hata, çevrimdışı durumları da tasarlanır (şu an çoğu varsayılan).

**Bugün ekranı — yeni yerleşim (yukarıdan aşağı)**

```
┌──────────────────────────────────┐
│ Günaydın, Ayşe              ( A )│  Fraunces; tarih altında
│ Perşembe 15 Ekim · 18° · UV 6 · %40│  tek satır hava şeridi
│                                  │
│ ┌──────────────────────────────┐ │
│ │ ŞİMDİ · Sabah rutini    2/5 ◔│ │  KAHRAMAN KART
│ │ 1 ✓ Temizleyici              │ │  adımlar sıralı, ürün adı +
│ │ 2 ✓ Serum                    │ │  bir satır "nasıl"
│ │ 3 ○ Nemlendirici             │ │
│ │ 4 ○ SPF 50                   │ │
│ └──────────────────────────────┘ │
│                                  │
│ Gün akışı  ──●────────────────── │  uyanma→uyku şeridi; hatırlatıcı
│ 07:30  su  SPF   su  akşam  23:00│  aralıkları + "şimdi" işareti
│                                  │
│ BUGÜN HAVAYA GÖRE                │  3 satır, her biri tek cümle gerekçe
│ ☀  SPF 50 · 14:00'te yenile      │
│ ◌  Hafif jel nemlendirici        │
│ ◠  Dudak balsamı                 │
│                                  │
│ GÜN İÇİ                          │  2×2 ızgara, dokununca alt sayfa
│ [Su 750/2000] [Makyaj]           │
│ [Beslenme]   [SPF tazele]        │
│                                  │
│ Daha fazlası ›  (Check-in, analiz, geçmiş)  tek liste, 4 düğme değil
├──────────────────────────────────┤
│ [ Sabah rutinini yaptım ] [Ürün bitti] │  sabit alt çubuk
└──────────────────────────────────┘
```

Müşterinin "saat aralıkları" isteğinin görsel karşılığı **gün akışı şeridi**: hatırlatıcılar
sadece bildirim olarak değil, ekranda da bir zaman çizgisi olarak görünür.

---

## 4. Fazlar

Her faz sonunda `flutter analyze` + `flutter test` yeşil, CI yeşil, `docs/` ve README güncel.
Kim sütunu: **Ben** = Claude, **Sen** = hesap/cihaz/karar gerektirenler, **Müşteri** = teyit.

### Faz A — Zemin: backend'i canlıya güvenle taşı  *(boyut: orta)*

Amaç: "sorunsuz backend" şartı. Bunu başa koyuyoruz çünkü sonraki her faz canlı sunucuya karşı doğrulanacak.

| # | İş | Kim |
|---|----|-----|
| A1 | Uyumluluk denetimi: eski web ↔ yeni backend (`test_web_compat.py`, web'in gerçek istek biçimleriyle) ve mobilin zayıf ağda davranışı (20 sn zaman aşımı, yapay zekâ uçları 120 sn). | Ben — **yapıldı** |
| A2 | Eksik tablo durumunda zarif düşüş: ayar okuma varsayılana düşer; **hesap silme** tablo yoksa durmaz (yalnızca tablo-yok hatasında; diğer hatalar yine durdurur). | Ben — **yapıldı** |
| A3 | **Hava önbelleğini sağlamlaştır**: TTL tabanlı (30 dk), başarısız çekim 2 dk saklanır ve asla veri sayılmaz; plan canlı → bugünkü kayıt → profil → varsayılan sırasına düşer; `location` olayı önbellekten beslenir. | Ben — **yapıldı** |
| A4 | **Push zamanlayıcısı**: compose'ta `push-cron` servisi (5 dk, elle crontab yok). Ek olarak iki güvenilirlik açığı kapandı: defter hatası artık "zaten gönderilmiş" sayılmıyor; FCM geçici hatasında rezerv geri alınıp pencere bitmeden yeniden deneniyor. | Ben — **yapıldı**; Sen: `PUSH_DISPATCH_SECRET` (+ Firebase gelince `FCM_SERVICE_ACCOUNT_JSON`) |
| A5 | Gözlemlenebilirlik: `/health` içinde `push_dispatch` (son tur özeti), tur başına günlük özeti, kullanıcı sınırı uyarısı. | Ben — **yapıldı** |
| A6 | **Sözleşme testi**: `contract/*.json` backend'in gerçek yanıtlarından üretilir; backend yanıtın şekli bozulursa, mobil de ayrıştırılan değerler kayarsa kırılır (iki yönde mutasyonla kanıtlandı). Mobil yerel hatırlatıcı pencereleri sunucununkiyle karşılaştırılır. | Ben — **yapıldı** |
| A6b | **Canlı duman testi** `scripts/smoke_mobile_api.py` (okuma + yetki + isteğe bağlı yazma), yerel sunucuya karşı testlidir. | Ben — **yapıldı**; Sen: bir TEST hesabıyla canlıda çalıştır |
| A7 | `flutter-mobile` → `main` PR'ı, CI yeşil, birleştir, dağıtımı izle, duman testi. Ayrıntı: `docs/MOBIL-CANLIYA-ALMA.md`. Canlı `/health` `db_schema: ok` gösteriyor: yeni migration açılışta kendiliğinden uygulanır. | Sen (birleştirme onayı), Ben (PR, kontrol listesi) |

**Kabul:** canlı API'ye karşı `/me/snapshot`, `/today/plan`, `/me/reminder-settings`, olay yazma, sohbet uçları gerçek bir hesapla çalışıyor; web bozulmamış.

### Faz B — Tasarım sistemi birliği  *(boyut: büyük)*

| # | İş | Kim |
|---|----|-----|
| B1 | **Bugün ekranının görsel taslağı** (açık + koyu) → onay kapısı. Kod yok. | Ben, Sen onaylar |
| B2 | Tasarım belgesi (1 sayfa): palet, tipografi ölçeği, boşluk, köşe, gölge, ikon, hareket, kategori renkleri. | Ben |
| B3 | Token katmanı: `Brand` uygulamanın tek kaynağı olur; `Tw` kullanımı kademeli köprülenir (40 dosya, ekran ekran). | Ben |
| B4 | Ortak bileşenler: kart, düğme (ana/ikincil/metin), hap/çip, alt sayfa, ilerleme halkası, boş durum, iskelet, toast. | Ben |
| B5 | **Tema kararı** (bkz. §6-1): 9 tema → klinik paletle uyumlu vurgu seçenekleri. | Sen karar verir |
| B6 | Emoji → çizili/Lucide ikon (~20 yer). | Ben |
| B7 | Kabuk: 5 sekmeli alt gezinme ve üst çubuk yeni dilde. | Ben |
| B8 | **Kalıcı görsel test altyapısı**: gerçek yazı tipleriyle (Inter, Fraunces, Lucide) ekran görüntüsü testi; açık/koyu × %100/%150/%200 yazı. Geçici betik yerine repoda. | Ben |

**Kabul:** onaylı taslak + bileşen kitaplığı + görsel test altyapısı hazır; hiçbir ekranda yeni ve eski dil yan yana değil (geçiş sırasında bile ekran ekran tamamlanır).

### Faz C — Bugün ekranı baştan  *(boyut: büyük)*

| # | İş | Kim |
|---|----|-----|
| C1 | Yeni yerleşim (§3): selamlama + hava şeridi, kahraman rutin kartı, gün akışı şeridi, havaya göre 3 karar, 2×2 gün içi ızgara, "Daha fazlası" listesi. | Ben |
| C2 | Kahraman kart: adım işareti, tik animasyonu, blok tamamlanınca sakin bitiş durumu, sabah/akşam geçişi. | Ben |
| C3 | **Gün akışı şeridi**: uyanma→uyku, hatırlatıcı pencereleri, "şimdi" işareti, yapılanlar dolu. | Ben |
| C4 | **Havaya göre kararlar**: backend'e saatlik UV'den `uv_peak_window` (en yüksek UV aralığı) ve `weather_decisions` özeti; SPF yenileme penceresi buna bağlanır; "neden" tek cümle. Hava yoksa "tahmini" etiketi dürüstçe. | Ben (backend + mobil) |
| C5 | Gün içi kartlar ve alt sayfalar yeni dilde: su (şişe/bardak boyutu seçimi), makyaj (temizleme yöntemleri), beslenme (seçenekler). Su hedefini isteğe bağlı kişiselleştirme (ayarlardan). | Ben |
| C6 | Sabit alt çubuk: "Yaptım" + "Ürün bitti" yeni stil, tamamlanınca durum değişimi. | Ben |
| C7 | Boş / yükleniyor / hata / çevrimdışı / demo oturumu durumları. | Ben |

**Kabul:** müşterinin 2. ve 3. maddeleri tek ekranda, kaydırmadan "şimdi ne yapmalıyım" okunuyor; küçük telefonda (320×568) ve %200 yazıda taşma yok.

### Faz D — "Ürün bitti" gerçek bir akışa dönüşsün  *(boyut: orta)*

Bugün düğme sadece günlük olay yazıyor. Önerim "Rafım" mantığı:

| # | İş | Kim |
|---|----|-----|
| D1 | Backend: `product_restocked` olay tipi; `products_out` (biten ve yeniden alınmamış) türetimi `/today/plan` yanıtında; geriye dönük uyumlu. | Ben |
| D2 | Mobil: "Ürün bitti" sayfası yeniden; rutin adımında "bitti" etiketi (adım soluk, atlanabilir); **Rafım** listesi (Ben sekmesinde) + "Aldım" ile geri açma. | Ben |
| D3 | İsteğe bağlı tek hatırlatma: N gün sonra "hâlâ almadın mı?". | Ben |
| D4 | Sohbete kısayol: "Bu ürünün yerine ne kullanabilirim?" (bugünün bağlamıyla). | Ben |

**Müşteriye soru:** biten ürün için sadece takip mi, yoksa satın alma yönlendirmesi de mi isteniyor? (Öneri: v1'de takip + hatırlatma; satın alma bağlantısı yok.)

**Kabul:** ürünü "bitti" işaretleyince rutinde görünüyor, yeniden alınınca eski haline dönüyor, web/backend verisi tutarlı.

### Faz E — Hatırlatıcılar: güvenilir ve kontrol kullanıcıda  *(boyut: orta-büyük)*

| # | İş | Kim |
|---|----|-----|
| E1 | Ayar ekranı: kategori başına **başlangıç–bitiş saati** doğrudan düzenlenir, "sessiz saatler"; uyanma/uyku varsayılanları korunur. Backend `reminder_settings` bunu taşır (geriye dönük uyumlu). | Ben |
| E2 | Yerel bildirim güvenilirliği: Android 13+ izin akışı, tam zamanlı alarm, yeniden başlatma sonrası yeniden kurma, üretici pil kısıtı rehberi; iOS 64 bildirim sınırı için "en yakın pencereler" yöneticisi. | Ben |
| E3 | **Akıllı susma**: hedef tamamlandı / yapıldı ise o günün kalan hatırlatıcıları iptal (plan ile senkron). | Ben |
| E4 | Push: Firebase dosyaları geldiğinde `FIREBASE_ENABLED=true`; yerel + push **çift bildirimi** önleme kuralı. | Ben, Sen (dosyalar) |
| E5 | Bildirim eylemleri (Yaptım, +250 ml, Hayır) için cihaz test senaryosu; arka plan izolatı. | Ben (senaryo), Sen (telefonda dene) |
| E6 | Saat dilimi / yaz saati / yolculukta gün sınırı davranışı testleri. | Ben |

**Kabul:** 24 saatlik gerçek telefon denemesinde bildirimler doğru saat aralığında geliyor, yapılan iş için tekrar gelmiyor, bildirimden işlem uygulamaya yansıyor.

### Faz F — Sohbet ve kalan ekranlar yeni dilde  *(boyut: büyük)*

| # | İş | Kim |
|---|----|-----|
| F1 | **Sohbet**: yeni görünüm, "bugün" bağlam şeridi, öneri çipleri, kota/hata/çevrimdışı durumları, rutin adımından "bunu sor" derin bağlantısı. | Ben |
| F2 | Rutin (haftalık plan), Geçmiş, Ben, Check-in, Analiz, Hatırlatıcılar, Profil, Abonelik, Temalar yeni dilde. | Ben |
| F3 | Geçmiş: trend grafikleri yeni stil, su/makyaj/beslenme için haftalık özet. | Ben |
| F4 | İlk açılış: bildirim ve konum izinleri sırası, ilk gün Bugün durumu (boş veri ile de güzel). | Ben |

**Kabul:** uygulamanın hiçbir ekranında `Tw` mavi gradyan/eski kart kalmadı; tüm ekranlar açık/koyu ve küçük telefonda görsel testten geçiyor.

### Faz G — Cihaz doğrulama, kalite, yayın  *(boyut: orta, çoğu seni gerektirir)*

| # | İş | Kim |
|---|----|-----|
| G1 | **Gerçek cihaz testi** (USB'li Android; mümkünse bir iPhone): `docs/MOBIL-YAYIN.md` kontrol listesi + Faz E senaryosu. Bulunan hatalar bu fazda kapanır. | Sen (telefon), Ben (düzeltme) |
| G2 | Performans: soğuk açılış, kaydırma akıcılığı, APK/AAB boyutu, ağ yavaşken davranış. | Ben |
| G3 | Erişilebilirlik: TalkBack/VoiceOver etiketleri, kontrast, %200 yazı, dokunma hedefleri ≥ 48 dp. | Ben |
| G4 | Mağaza varlıkları: ekran görüntüleri (yeni tasarımdan), metinler, gizlilik tabloları (taslaklar hazır). | Ben (taslak), Sen (hesaplar) |
| G5 | **Müşteri kabul demosu**: §1'deki 7 maddeyi senaryo senaryo gösteren akış + kısa not. | Ben |

---

## 5. Sıra ve bağımlılıklar

```
A (zemin) ─┬─> B (tasarım sistemi) ──> C (Bugün) ──> D (Ürün bitti)
           │                                   └──> E (hatırlatıcılar) ──┐
           └─ (paralel, Sen: Firebase, hesaplar, VPS cron)               ├─> F (kalan ekranlar) ─> G (cihaz + yayın)
```

- **A önce**: sonraki her şey canlı sunucuya karşı doğrulanacak; ayrıca kısa ve riski düşük.
- **B1 (taslak) A ile paralel** başlayabilir; kod beklemez, yalnız senin onayını bekler.
- **C, B'ye bağlı**: yeni bileşenler olmadan Bugün'ü yeniden çizmek ikinci bir geçiş borcu doğurur.
- **D ve E, C'den sonra** (Bugün'ün yeni yerleşimine oturur); kendi aralarında bağımsız.
- **G'nin cihaz kısmı** hiçbir faza bağlı değil — **telefonun elinde olduğu an** kısmen başlayabilir; ne kadar erken denersek F'ye kadar o kadar az sürpriz çıkar. Önerim: A bittiğinde mevcut sürümü bir kez telefonda dene (bugünkü halini), kıyas noktası olsun.

---

## 6. Senden karar / teyit gereken noktalar (önerimle)

1. **Temalar**: 9 temayı (kedi, ayıcık, gün batımı, okyanus, noir…) ne yapalım?
   *Öneri:* klinik paletle uyumlu 4–5 **vurgu rengi** bırak; kedi/ayıcık gibi çocuksu olanları kaldır. Müşteri tema özelliğini özellikle istemediyse bu en temiz yol.
2. **"Balsam"** = dudak balsamı mı? *Öneri:* şu an öyle; müşteriye tek cümleyle teyit ettir (vücut balmı / temizleme balmı da olabilir).
3. **"Ürün bitti" sonrası**: yalnız takip mi, satın alma yönlendirmesi de mi? *Öneri:* v1'de "Rafım" + yeniden alma hatırlatması.
4. **Su hedefi** sabit 2000 ml; kişiselleştirilsin mi? *Öneri:* ayarlardan elle değiştirme; kilo/hava otomasyonu yok.
5. **Sıra**: A → B1 paralel → B → C → D/E → F → G. *Öneri:* böyle.

## 7. Senden beklenenler (kod dışı)

- Supabase'e `20261013120000_reminder_settings.sql` uygulaması ve `flutter-mobile` → `main` birleşme onayı (Faz A7).
- VPS'te push cron satırını ekleme (Faz A4) — betik/komutu ben hazırlarım.
- Firebase proje dosyaları (`google-services.json`, `GoogleService-Info.plist`) + servis hesabı (push için).
- **USB'li bir Android telefon** (mümkünse iPhone da) — gerçek cihaz testi.
- Android yükleme anahtarı, Apple/Play hesapları, gizlilik/destek/veri-silme URL'leri, inceleme demo hesabı (yayın için; `docs/MOBIL-YAYIN.md`).

## 8. Riskler

| Risk | Etki | Önlem |
|------|------|-------|
| Backend birleşmesi canlıyı bozar | Web de etkilenir | A1/A2 uyumluluk + zarif düşüş, testler CI'da, migration önce, birleşmeden sonra dağıtım izlenir |
| Tasarım "yine yapay zekâ işi" görünür | Kullanıcı reddeder | B1 onay kapısı: kod yazmadan önce taslak; ekran ekran gösterim |
| İki dil bir süre yan yana | Tutarsız his | Geçişi ekran bazında tamamla; B4 bileşenleri hazır olmadan ekrana dokunma |
| Bildirimler üreticiye göre güvenilmez (Xiaomi/Huawei pil kısıtı) | Müşterinin en önemli isteği zayıflar | E2 rehber + push yedek; G1'de en az iki marka dene |
| Cihaz testi gecikir | Hatalar son anda çıkar | A sonrası erken "kıyas" denemesi |
| Hava servisi yavaş/kapalı | Bugün ekranı boş kalır | A3 önbellek + varsayılan değer + "tahmini" etiketi |

## 9. Müşteri kabul senaryosu (G5'te kullanılacak)

1. Uygulamayı aç → bugünün sabah rutini kahraman kartta; adımları işaretle → **"Sabah rutinini yaptım"**.
2. Gün akışı şeridinde su ve güneş kremi aralıklarını göster; bildirim gelir, bildirimden **+250 ml** yaz.
3. "Makyaj yaptım" de → akşam bildirimi → **nasıl temizlendi** seç.
4. "Abur cubur yedim" → seçenekten işaretle.
5. Havaya göre kartta **SPF / nemlendirici / balsam** kararını ve gerekçesini göster; hava değişince karar değişsin.
6. Alt çubuktan **"Ürün bitti"** → ürünü seç → rutinde "bitti", Rafım'da görünür → "Aldım" ile geri dön.
7. Sohbet → "bugün cildim nasıl olmalı?" → bugünün bağlamıyla yanıt; web'deki aynı hesap geçmişi.
8. Karanlık mod, büyük yazı, uçak modu (kayıt sıraya girer, bağlanınca gider).
