# Gerçek cihaz testi (Faz G1)

Otomatik testler (830+ test) mantığı, yerleşimi ve erişilebilirlik kurallarını kanıtlar; **telefonda ancak şunlar görülür:**
gerçek yazı tipi işleme, parmakla kaydırma akıcılığı, pil tasarrufu / üretici kısıtları, bildirimin gerçekten gelmesi,
R8 küçültmesinden sonra davranış, gerçek ağ. Bu belge tek oturumda (~1,5 saat) hepsini yapmak için hazırlanmış kontrol
listesidir. Bildirim ayrıntıları [`MOBIL-BILDIRIM-TEST.md`](MOBIL-BILDIRIM-TEST.md)'dedir; burada yalnızca özet satırı var.

## Hazırlık

| Ne | Nasıl |
| --- | --- |
| Android telefon (Android 8+; mümkünse 13+) | Ayarlar → Telefon hakkında → "Derleme numarası"na 7 kez dokun → Geliştirici seçenekleri → **USB hata ayıklama** aç; kabloyla bağla, "bu bilgisayara güven" de |
| iPhone (isteğe bağlı) | **Mac + Xcode gerekir**; Mac yoksa iOS testi TestFlight'a kadar bekler (`MOBIL-YAYIN.md` §4). CI iOS derlemesini zaten doğruluyor |
| **TEST hesabı** | Müşteri hesabı değil; e-postası onaylı, rıza adımları tamamlanmış, bir rutini olan hesap. `env/dev.json` canlı Supabase'e bağlıdır: yazdığın her şey gerçek veritabanına gider |
| Bilgisayar | `mobile/env/dev.json` dolu olmalı (`env/example.json`'dan kopyalanır); Flutter 3.47, `adb` |

Telefonu bağla, görünüp görünmediğine bak:

```bash
cd mobile
flutter devices
```

**Release** olarak kur (debug değil: R8 küçültmesi, bildirim simgesi ve gerçek hız ancak release'te görülür):

```bash
flutter run --release --dart-define-from-file=env/dev.json -d <cihaz-kimliği>
```

Ya da APK üretip kur (bilgisayar bağlı kalmasın istiyorsan):

```bash
flutter build apk --release --dart-define-from-file=env/dev.json
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

Not: bu kurulum debug anahtarıyla imzalıdır, yalnızca test içindir; mağaza paketi `tool/build_release.sh android` ile üretilir.

Her satırı **GEÇTİ / KALDI / —** ile işaretle. KALDI olanlar için: adım numarası, ne beklendi, ne oldu, ekran görüntüsü.

## 1. Kurulum ve giriş

| # | Adım | Beklenen |
| --- | --- | --- |
| 1.1 | Uygulamayı aç (oturum yok) | Koyu yeşil açılış animasyonu (~2,4 sn, dokununca geçilir), ardından karşılama. İlk karede **beyaz parlama yok** |
| 1.2 | Giriş yap (e-posta + parola); parola alanındaki göz düğmesiyle göster/gizle | Girilir; Bugün ekranı açılır |
| 1.3 | Çıkış yap, tekrar giriş yap; uygulamayı tamamen kapatıp aç | Oturum açık kalır, doğrudan Bugün açılır (açılış animasyonu yok) |
| 1.4 | Yeni hesap kaydı (isteğe bağlı, ayrı bir e-postayla) | Kayıt, e-posta onayı, KVKK + açık rıza + yapay zekâ onayı adımları sorunsuz |
| 1.5 | Ben → Hesap ve gizlilik → "Hesabı kalıcı olarak sil" (**yalnızca 1.4'te açtığın deneme hesabında**) | Onay istenir; silinince girişe döner |

## 2. Bugün (müşteri maddeleri 1–5)

| # | Adım | Beklenen |
| --- | --- | --- |
| 2.1 | Bugün'de kahraman rutin kartı: adımları işaretle, **"Sabah rutinini yaptım"** | Adımlar üstü çizilir, ilerleme halkası dolar; düğme tamamlanınca değişir |
| 2.2 | "+250 ml" ve su sayfasından farklı miktar yaz; yanlış girileni geri al | Su ilerlemesi güncellenir; geri alma çalışır |
| 2.3 | "Makyaj yaptım" → akşam "nasıl temizlendi" | Seçenekler görünür; seçim kaydedilir |
| 2.4 | "Abur cubur yedim" seçeneklerinden birini işaretle | Kaydedilir, geçmişe yansır |
| 2.5 | Havaya göre kart: SPF / nemlendirici / dudak balsamı kararı ve gerekçesi | Gerekçe cümlesi var; konum izni verildiyse hava gerçek (UV, sıcaklık) |
| 2.6 | Konum önerisi kartı çıkarsa "Konumu aç" → sistem izni → ver | Hava canlı olur; izni reddedersen uygulama bozulmaz, şehir bilgisine döner |
| 2.7 | Gün akışı şeridi: su aralıkları ve güneş kremi pencereleri | Şimdiki saate göre doğru pencere vurgulu |

## 3. Ürün bitti ve Rafım (madde 6)

| # | Adım | Beklenen |
| --- | --- | --- |
| 3.1 | Alt çubuk "Ürün bitti" → rutindeki bir ürünü seç | Rutinde "Bitti" etiketi; Rafım'da görünür |
| 3.2 | Rutin dışı bir ürün ekle ("Gece kremi" gibi) | Rafım'da listelenir, "rutinine sayılmaz" notu |
| 3.3 | "Aldım" → ürün geri döner | Bitti etiketi kalkar |
| 3.4 | Bir ürünü bittiye aldıktan 3 gün sonra (akşamın erken saati) | "Yenisini aldın mı?" hatırlatması ürünün adıyla gelir; her gün tekrarlamaz |

## 4. Bildirimler (özet; ayrıntı: `MOBIL-BILDIRIM-TEST.md`)

| # | Adım | Beklenen |
| --- | --- | --- |
| 4.1 | Ben → Hatırlatıcılar → izin ver → **Test bildirimi gönder**, uygulamayı kapat | Bildirim gelir, dokununca Bugün açılır |
| 4.2 | Bir kategorinin saat aralığını 5 dk sonrasına ayarla | Ayarlanan dakikada gelir |
| 4.3 | Sessiz saat kur | Aralıkta bildirim gelmez |
| 4.4 | Bildirimden **+250 ml** (uygulama kapalı) | Uygulamayı açınca su artmış |
| 4.5 | Telefonu yeniden başlat | Bildirimler yine gelir |
| 4.6 | Gelmezse: üreticiye göre pil ayarı (`MOBIL-BILDIRIM-TEST.md` §3) | İşe yarayan ayarı not et |

## 5. Sohbet, Geçmiş, Ben

| # | Adım | Beklenen |
| --- | --- | --- |
| 5.1 | Rebi sekmesi: üstteki "bugünü biliyor" çipleri (UV, rutin, su) | Bugünün gerçek verisi; çipe dokununca Bugün açılır |
| 5.2 | "Bugün cildim nasıl olmalı?" sor | Yanıt bugünün bağlamını kullanır; yapay zekâ uyarısı görünür |
| 5.3 | Uçak modunda soru sor | Hata kartı ("bağlantı yok"), mesaj sohbete yazılmaz; bağlantı gelince **Tekrar dene** çalışır |
| 5.4 | Sohbet hakkını bitir (ücretsiz kota) | Limit kartı; Plus satın alma düğmesi **yok** (v1'de satılmıyor), yazma alanı kilitli |
| 5.5 | Aynı hesapla web'e gir | Sohbet geçmişi ve rutin aynı |
| 5.6 | Geçmiş: su, uyku, stres, rutin grafikleri; haftalık özet | Birkaç gün veri varsa dolu; yoksa boş durum metni |
| 5.7 | Ben: profil düzenle, görünüm (tema), dil (TR/EN) | Kaydedilir, dil anında değişir |

## 6. Çevrimdışı, karanlık mod, erişilebilirlik

| # | Adım | Beklenen |
| --- | --- | --- |
| 6.1 | Uçak modu: su ekle, rutin işaretle → bağlantıyı aç | Kayıtlar "bekliyor" gösterir, bağlantıyla gider; hiçbiri kaybolmaz |
| 6.2 | Karanlık mod (Ayarlar → Ekran) aç; tüm sekmeleri gez | Okunmayan metin, kaybolan kenarlık yok |
| 6.3 | Ayarlar → Ekran → **Yazı boyutu en büyük** (≈%200), Bugün/Rutin/Sohbet/Ben'i gez | Metin kesilmez, düğmeler erişilebilir kalır |
| 6.4 | **TalkBack** aç (Ayarlar → Erişilebilirlik): Bugün'de sağa kaydırarak gez | Her düğme anlamlı okunur ("Sabah rutinini yaptım", "Ürün bitti", sekme adları); adı olmayan "düğme" duymazsın |
| 6.5 | TalkBack ile bir rutin adımını işaretle ve su ekle | Çift dokunuşla çalışır, durum ("işaretli") okunur |
| 6.6 | Yazı tipi: Türkçe karakterler (ğ ı İ ş ç ö ü) başlık ve gövdede doğru | Eksik harf / kare yok |

## 7. Performans gözlemi (isteğe bağlı ama istenir)

Bunlar **ölçü**: sayıyı sonuç tablosuna yaz. Eşikler başlangıç önerisidir; telefon sınıfına göre sen ayarla.

| # | Ölçü | Nasıl | Öneri eşiği |
| --- | --- | --- | --- |
| 7.1 | Soğuk açılış (oturum açıkken) | Uygulamayı son uygulamalardan kapat; `adb shell am start -W -n com.rebiovil.rebi/.MainActivity` → `TotalTime` | < 2000 ms |
| 7.2 | Bugün'ün dolması | Açılıştan "Sabah rutini" kartı görünene kadar (kronometre) | Veri ağdan gelir; < 3 sn (iyi ağ) |
| 7.3 | Kaydırma | Bugün ve Rutin'i hızlı kaydır; takılma, yırtılma var mı | Gözle: takılma yok. Sayı için: `adb shell dumpsys gfxinfo com.rebiovil.rebi reset`, kaydır, `adb shell dumpsys gfxinfo com.rebiovil.rebi` → "Janky frames" < %5 |
| 7.4 | Yavaş ağ | Zayıf çekimde (bodrum / asansör) ya da hotspot'u 2G'ye düşürerek Bugün'ü aç | Eldeki plan ekranda kalır; ilk açılışta en geç 20 sn sonra "alınamadı" ve **Tekrar dene**, sonsuz dönme yok |
| 7.5 | GPS soğuk | Konum izni açık, telefonu yeni başlat, hemen uygulamayı aç | Bugün en geç ~3 sn sonra konumsuz planla açılır (konum sonra gelir) |
| 7.6 | Paket boyutu | Mobile CI özetinde "Android paketi (AAB)" satırı | Bilgi amaçlı; Play'in gösterdiği indirme boyutu daha küçüktür |

Takılma görürsen: `flutter run --profile` ile aç, DevTools → Performance'ta hangi ekranda olduğunu yakala ve bildir.

## Sonuç

| Telefon / Android | 1 | 2 | 3 | 4 | 5 | 6 | 7 (açılış ms / janky %) | Not |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| | | | | | | | | |

Bulunan hatalar bu fazda (G1) kapatılır; sonuçları (özellikle KALDI satırlarını) bana ilet.
