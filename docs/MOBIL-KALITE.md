# Performans ve erişilebilirlik (Faz G2, G3)

Burada **ne ölçüldü, ne düzeltildi, neyin telefonda ölçülmesi gerekiyor** yazar. Geliştirme makinesinde emülatör açılmadığı için
cihaz üstü profil çıkarılamadı; aşağıdaki iyileştirmeler kod incelemesi ve testlerle yapıldı. Cihazdaki ölçümler
[`MOBIL-CIHAZ-TESTI.md`](MOBIL-CIHAZ-TESTI.md) §7'dedir.

## G2 — Performans

### Soğuk açılış

| Bulgu | Karar |
| --- | --- |
| Oturum açıkken uygulama doğrudan Bugün'e açılır (açılış animasyonu yalnızca oturum yokken: ~2,4 sn, dokununca ya da "hareketi azalt"ta 0,7 sn) | Değişmedi |
| Açılış hazırlığı (yerel depo, Supabase oturumu, tarih biçimleri, çeviriler) sıralı; tarih biçimi kurulumu ~12 ms, çeviri dosyaları yalnızca TR/EN'in dosyaları | Paralelleştirme kazancı tek hane ms; ölçüm olmadan karmaşıklık eklenmedi |
| **Bugün planı konum aramasını bekliyordu.** Cihazda son konum yoksa GPS 8 sn'ye kadar sürebilir, plan isteği de o kadar gecikirdi | **Düzeltildi:** konum en çok 2,5 sn beklenir (`locationWaitBudget`), sonra plan konumsuz (profil şehri) istenir; konum bulununca sonraki tazelemede kullanılır. Test: `performance_test.dart` |
| Kullanılmayan dil dosyaları pakette (ar, az, de, es, fr, it, pt: ~350 KB) | Dokunulmadı: paketin %1'inden azı; dil seçimi bunlara bağlı olabilir |

### Kaydırma akıcılığı

- Üst çubuk ve alt gezinti çubuğu `BackdropFilter` (σ=24 bulanıklık) ile sarılıydı. İkisinin de arkasında içerik yoktur
  (`Scaffold` gövdeyi çubukların arasına yerleştirir), yani bulanıklık **hiçbir görüntü farkı yaratmıyor ama her karede ek bir
  katman çiziyordu**. Kaldırıldı; görüntü aynıdır. Test (`performance_test.dart`): kod tabanında `BackdropFilter`, `ShaderMask`,
  `ImageFiltered`, `ColorFiltered` kalmadığını denetler.
- Uzun listeler tembel (`ListView.builder/separated`); gradyan, bulanıklık, `saveLayer` üreten ağır katmanlar yok.
- Gerçek akıcılık ölçüsü (janky kare yüzdesi) yalnızca cihazda alınır: `MOBIL-CIHAZ-TESTI.md` 7.3.

### Paket boyutu

- Android AAB: **59,8 MB, 3 ABI** (arm64, armeabi-v7a, x86_64; `MOBIL-YAYIN.md` §1). Play cihaza özel parça verir, indirilen boyut çok daha küçüktür.
- Mobile CI artık her koşuda AAB boyutunu iş özetine yazar (`Paket boyutu` adımı): zamanla büyüyüp büyümediği görülsün.
- Yazı tipleri 1,3 MB (Inter + Fraunces değişken, çalışma anında indirme yok).

### Yavaş ağ

Zaten testle korunur (`api_timeout_test.dart`, `performance_test.dart`, `event_outbox_test.dart`):

| Durum | Davranış |
| --- | --- |
| Okuma / kayıt isteği yanıt vermezse | 20 sn sonra bırakılır; ekran dönüp durmaz (yapay zekâ uçları 120 sn) |
| Bugün zaten açıkken tazeleme takılırsa | Eldeki plan ekranda kalır, hata ekranı çıkmaz |
| İlk açılışta ağ hiç yoksa | Yükleme biter, "alınamadı" + **Tekrar dene** |
| Kayıt (su, rutin…) ağsızken | Cihazdaki kuyruğa yazılır, ekranda "bekliyor", bağlantı gelince gönderilir |
| Sohbet gönderimi başarısız | Hata kartı + **Tekrar dene**; hata sohbet geçmişine yazılmaz |

## G3 — Erişilebilirlik

Kural seti (Flutter'ın kendi erişilebilirlik denetimleri) **52 senaryoda** çalışır (`test/accessibility_test.dart`; Bugün sabah / öğleden sonra / akşam saatinde + alt sayfalar,
Rutin, Sohbet 4 durum, Geçmiş, Ben, Hatırlatıcılar, Rafım, Temalar, Check-in, Abonelik, Analiz, Giriş, Açılış, KVKK; açık ve koyu):

- dokunma hedefi **≥ 48 dp (Android), ≥ 44 dp (iOS)**,
- dokunulabilir her öğenin **ekran okuyucu etiketi** var,
- metin kontrastı **≥ AA (4,5:1; büyük metinde 3:1)**.

Bu geçişte düzeltilenler (örnekler): hatırlatıcı anahtarlarına etiket; kategori renkli metinler (su mavisi, bal sarısı) koyulaştırılarak okunur kontrasta
getirildi (`Tw.readable`); gri-400 metinler gri-500; hap görünümlü çipler ve bağlantılar görsel olarak aynı kalıp dokunma alanı 48 dp'ye çıkarıldı;
hafta şeridi yeniden kuruldu; parola göster/gizle düğmesine etiket (`mobileAuth.showPassword/hidePassword`); sohbet kullanıcı balonu etiketsiz düğüm
üretmiyor. Geniş ekranda (tablet) sohbetin rutin kenar tutamacı bilgi çiplerinin üstüne biniyordu; çiplerin altına alındı.

`text_scale_test` (%150 / %200 yazı, 320×568) ve `screens_test` taşma kontrolünü yapar.

**Otomatik testin göremediği (cihazda):** TalkBack / VoiceOver'ın okuma sırası ve anlaşılırlığı, gerçek parmakla hedef isabeti,
sistem yazı boyutunun gerçek etkisi → `MOBIL-CIHAZ-TESTI.md` §6.

Kurallar ve yeni ekran yazarken izlenecek yol: [`MOBIL-TASARIM-DILI.md`](MOBIL-TASARIM-DILI.md) "Erişilebilirlik kuralları".
