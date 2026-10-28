# Bildirim cihaz testi (Faz E)

Bu kontrol listesi **gerçek telefonda** yapılır; emülatör pil tasarrufunu, üretici kısıtlarını ve iOS bildirim davranışını
göstermez. Otomatik testler mantığı kanıtlar (`mobile/test/notification_reliability_test.dart`, `reminder_schedule_test.dart`,
`silence_budget_test.dart`, `backend/tests/test_reminder_windows.py`); aşağıdakiler yalnızca cihazda görülebilen şeylerdir.

Hazırlık: TEST hesabıyla giriş yap, **Ben → Hatırlatıcılar**'dan bildirimleri aç, izin ver. Not al: telefon modeli, Android/iOS sürümü,
uygulama sürümü, bildirimlerin yerelden mi sunucudan mı geldiği (Hatırlatıcılar ekranındaki kartta "bu telefonda planlanır" / "sunucudan gönderilir").

## 1. Temel (her telefonda)

| # | Adım | Beklenen |
|---|------|----------|
| 1.1 | Hatırlatıcılar → **Test bildirimi gönder** → uygulamayı tamamen kapat (son uygulamalardan kaydır) → 1 dk bekle | Bildirim gelir. Gelmezse Bölüm 3. |
| 1.2 | Bildirime dokun | Uygulama Bugün ekranında açılır |
| 1.3 | Sabah rutini penceresini 5 dk sonrasına ayarla (kategori satırına dokun → başlangıç), kaydet, uygulamayı kapat | Bildirim ayarlanan dakikada (± birkaç dk) gelir |
| 1.4 | Aynı rutini uygulamada "tamam" işaretle, sonra pencereyi bir 5 dk daha ileri ayarla | Tamamlanan rutin için bildirim **gelmez** |
| 1.5 | Sessiz saati şu andan 10 dk'lık bir aralığa kur; o aralığa denk gelen bir hatırlatıcı olsun | Aralıkta bildirim gelmez; tek seferlik ise aralık bitince gelir |
| 1.6 | Telefonu yeniden başlat, uygulamayı **açma**, bir sonraki hatırlatıcıyı bekle | Bildirim yine gelir (yeniden başlatma sonrası kurma) |

## 2. Bildirim düğmeleri (uygulama kapalıyken ve açıkken)

| # | Adım | Beklenen |
|---|------|----------|
| 2.1 | Su bildirimi gelince **+250 ml** düğmesine bas (uygulama kapalı) | Bildirim kapanır; uygulamayı açınca Bugün'de su 250 ml artmış |
| 2.2 | Su hedefine 250 ml kalana kadar uygulamada su ekle, sonra bildirimden **+250 ml** | Aynı günün **kalan su bildirimleri gelmez** (yarınkiler gelir) |
| 2.3 | Uygulama açıkken bildirimden **Yaptım** (sabah/akşam rutini) | Bugün ekranı hemen güncellenir, o günün aynı bildirimi tekrar gelmez |
| 2.4 | Uçak modunda düğmeye bas, sonra bağlantıyı aç | Kayıt cihazda bekler, bağlantıyla gönderilir (Bugün'de "bekliyor" → kaybolur) |
| 2.5 | Makyaj sorusuna bildirimden **Evet** (uygulama kapalı) | Yerel modda temizleme bildirimi uygulama açılana kadar **kurulmaz** (bilinen sınır); uygulamayı açınca kurulur |

## 3. Bildirim gelmiyorsa (Android)

Üreticiye göre ayar yeri değişir; genel yol: **Ayarlar → Uygulamalar → Rebi → Pil → "Kısıtlama yok" / "Optimize etme"**.

- Xiaomi/MIUI: Güvenlik → Uygulamalar → Rebi → *Otomatik başlat* aç, Pil tasarrufu → *Kısıtlama yok*.
- Huawei/EMUI: Pil → Uygulama başlatma → Rebi → *Elle yönet* (üçü de açık).
- Samsung: Pil → Arka plan kullanım sınırları → Rebi'yi *Hiç uyumayan uygulamalar*a ekle.
- Oppo/Realme/Vivo: Pil → Rebi → *Arka planda çalışmaya izin ver*.

Düzelttikten sonra 1.1'i tekrarla ve **hangi ayarın işe yaradığını** not et (rehber metnine eklenecek).

## 4. Saat dilimi ve yolculuk

| # | Adım | Beklenen |
|---|------|----------|
| 4.1 | Telefonun saat dilimini elle değiştir (ör. +03 → +01), uygulamayı aç | Plan yeniden okunur; bildirimler yeni yerel saatte kurulur (Bugün'deki saatler yeni dilime göre) |
| 4.2 | Sunucu push'u açıksa: saat dilimini değiştirip uygulamayı aç | `/devices/register` yeni `utc_offset_minutes` ile çağrılır (sunucu günlüğü / `device_tokens` tablosu) |
| 4.3 | Gece yarısını geçerken (23:55 → 00:05) uygulamayı arka planda tut, sabah aç | Bugün ekranı yeni günün planıdır, dünün hatırlatıcıları yoktur |

## 5. Sunucu push'u (yalnızca Firebase + `PUSH_DISPATCH_SECRET` kurulduktan sonra)

| # | Adım | Beklenen |
|---|------|----------|
| 5.1 | `GET /health` → `push_dispatch.at` son 5–10 dk içinde | Dağıtıcı çalışıyor |
| 5.2 | Uygulamayı aç; Hatırlatıcılar kartı | "Hatırlatmalar sunucudan gönderilir" ve **Bildirimler gelmiyor mu?** kartı görünmez |
| 5.3 | Bir hatırlatıcı penceresini bekle | **Tek** bildirim gelir (çift yok) |
| 5.4 | `push-cron` servisini durdur, 25 dk bekle, uygulamayı kapatıp aç | Kart "bu telefonda planlanır"a döner ve hatırlatmalar yerelden kurulur |
| 5.5 | `push-cron`'u başlat, uygulamayı tekrar öne getir | Yerel bildirimler silinir, push'a dönülür |
| 5.6 | Android: su penceresinde uygulamayı kapat, sunucu bildirimi gelince **+250 ml** | Bildirimde düğmeler var (yalnızca-veri mesajı, `rebiPushBackground`); uygulamayı açınca Bugün'de su 250 ml artmış |
| 5.7 | Android: aynı bildirimi uygulama **açıkken** bekle | Bildirim yine düğmeleriyle görünür (`onMessage`); **Yaptım** Bugün ekranını hemen günceller |
| 5.8 | iOS: sunucu bildirimini aşağı çek / uzun bas → **+250 ml** | Uygulama açılır, Bugün'de su 250 ml artmış (`AppDelegate` → `takePendingPushActions`) |
| 5.9 | iOS: düğmeye basıp uygulama açılmadan oturumu kapat, başka hesapla gir | Kayıt yeni hesaba **yazılmaz** (bildirimin `user_id`'si eşleşmez) |
| 5.10 | `device_tokens` tablosunda cihaz satırı | `actions_supported = true` |

## Sonuç tablosu

| Telefon / sürüm | 1.1 | 1.3 | 1.6 | 2.1 | 2.2 | 4.1 | Not |
|-----------------|-----|-----|-----|-----|-----|-----|-----|
| | | | | | | | |

Başarısız her satır için: adım numarası, ne beklendi, ne oldu, (varsa) ekran görüntüsü. Düzeltmeler Faz G1'de kapanır.
