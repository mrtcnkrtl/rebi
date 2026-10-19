# Müşteri kabul demosu (Faz G5)

Müşterinin 13 Ekim mesajındaki beş istek ve `MOBIL-YOL-HARITASI.md` §1'deki yedi "bitti" ölçütü, **gerçek telefonda, canlı
sunucuya karşı, tek akışta** gösterilir. Süre: ~15 dakika. Demodan önce [`MOBIL-CIHAZ-TESTI.md`](MOBIL-CIHAZ-TESTI.md) en az
bir kez geçilmiş olmalı: demoda ilk kez karşılaşılan bir hata en pahalı hatadır.

## Hazırlık (demodan bir gün önce)

| Ne | Neden |
| --- | --- |
| **Demo hesabı** (müşterinin hesabı değil): e-posta onaylı, rıza adımları tamam, **bir rutini olan** hesap | Boş hesapta Bugün ve Geçmiş ekranı boş durumda kalır |
| Hesabı **3–4 gün önceden** kullan: her gün su yaz, check-in yap, bir gün makyaj + temizleme, bir gün abur cubur | Geçmiş grafikleri ve haftalık özet dolu görünür. Veriyi uydurma: gerçekten kullanarak biriktir |
| Telefon: konum izni **ver**, bildirim izni **ver**, pil tasarrufunu Rebi için kapat (`MOBIL-BILDIRIM-TEST.md` §3) | Havaya göre karar ve bildirimler gösterilebilsin |
| Bir ürünü **önceden** "Ürün bitti" yap (3 gün önce) | "Yenisini aldın mı?" hatırlatmasını bekletmeden anlatabilmek için; Rafım dolu görünür |
| Hatırlatıcılar → bir kategorinin saat aralığını demo saatinin **5 dk sonrasına** ayarla | Bildirim demo sırasında gerçekten gelsin |
| Wi‑Fi açık, ekran parlaklığı yüksek, bildirimleri açık tut (Rahatsız Etme kapalı) | |
| Aynı hesapla web'i bir sekmede aç (rutin ve sohbet geçmişi aynı görünsün) | Madde 7'de kullanılır |

## Akış

| # | Müşterinin istediği | Ne yapılır / gösterilir | Beklenen |
| --- | --- | --- | --- |
| 1 | Giriş ekranında günün rutini; "yaptım" ve "ürün bitti" | Uygulamayı aç. Kahraman rutin kartını göster; adımları işaretle; **"Sabah rutinini yaptım"**'a bas. Alt çubuktaki sabit **"Ürün bitti"**'yi göster | Adımlar üstü çizilir, halka dolar, düğme değişir |
| 2 | Gün içi su takibi | Gün akışı şeridinde su aralıklarını göster; **+250 ml** yaz; "Diğer…" ile farklı miktar; yanlışı geri al | Su ilerlemesi anında güncellenir |
| 2b | Hatırlatıcı bildirimi (madde 5) | Bildirim gelince (ayarladığın dakikada) **bildirimden +250 ml** | Uygulamayı açınca su artmış. Bildirimin bildirim çubuğunda nasıl göründüğünü göster |
| 3 | Makyaj: yaptı mı, akşam temizlendi mi, nasıl | **"Makyaj yaptım"** → akşam **"Temizledim"** → yöntem seçimi (yağ bazlı + jel vb.) | "Makyajlı gün", sonra "Temizlendi · yöntem" görünür |
| 4 | Beslenme (abur cubur vb.) | **"Abur cubur yedim"** → seçenekten işaretle | Kaydedilir, Geçmiş'e yansır |
| 5 | Havaya göre güneş kremi / nemlendirici / balsam | Havaya göre kartı aç; **kararı ve gerekçesini** oku (SPF kaç, neden; nem; dudak balsamı) | Gerekçe cümlesi var, hava canlı. "Hava değişince karar değişir" kuralını **anlat** (UV, nem, sıcaklık eşikleri); canlıda hava anlık değişmediği için göstermeye çalışma, **sahte hava verisi gösterme** |
| 6 | Ürün bitti → raf | **"Ürün bitti"** → rutindeki ürünü seç → rutinde **"Bitti"** → **Rafım**'a git → **"Aldım"** ile geri dön. Önceden bitirdiğin ürünün **"Yenisini aldın mı?"** hatırlatmasını göster | Rutin ve raf tutarlı |
| 7 | Web'deki sohbet botu | **Rebi** sekmesi: üstteki bugünün çipleri (UV, rutin, su) → "Bugün cildim nasıl olmalı?" Web'de aynı hesabın sohbet geçmişini göster | Yanıt bugünün bağlamını kullanır; yapay zekâ / "tıbbi tanı değildir" uyarısı görünür |
| 8 | Kalite | **Karanlık mod**'a geç, tüm sekmeleri gez; **yazı boyutunu büyüt**; **uçak modu**: su ekle → "bekliyor" → bağlantıyı aç → gider | Hiçbir şey kırılmaz, kayıt kaybolmaz |
| 9 | Hatırlatıcıların kontrolü kullanıcıda | Ben → Hatırlatıcılar: kendi saat aralığı, **sessiz saatler**, bildirim testi | Ayarlar kaydedilir, "gelmiyorsa" kartı çözüm gösterir |
| 10 | Geçmiş | Geçmiş sekmesi: su, uyku, stres, rutin grafikleri; haftalık özet | Hazırlıkta biriken veriyle dolu |

## Bilinen sınırlar (müşteriye açıkça söylenir)

Demoda sürpriz çıkmasın diye bu liste **önce** söylenir:

- **Sunucudan push** (uygulama kapalıyken sunucunun göndermesi) Firebase dosyaları eklenene kadar **kapalı**; hatırlatıcılar
  **telefonda planlanır** (yerel bildirim). Telefon yeniden başlayınca yeniden kurulacak şekilde yazıldı (cihazda doğrulanacak, `MOBIL-BILDIRIM-TEST.md` 1.6); üreticiye göre bazı Android telefonlarda pil
  ayarı gerekir (uygulama içinde "Bildirimler gelmiyor mu?" kartı yönlendirir). Firebase açılınca sunucu gönderir, yerel
  bildirimler otomatik susar (çift bildirim olmaz).
- **iPhone**: kod ve CI derlemesi hazır; **gerçek iPhone'da test edilmedi** (Mac gerekir).
- **Rebi Plus** bu sürümde satılmıyor (mağaza kuralları uygulama içi satın alma ister; v1.1). Ücretsiz günlük sohbet hakkı geçerli.
- **"Balsam" = dudak balsamı** olarak anlaşıldı; başka bir ürünse müşteriden teyit gerekir.
- Su hedefi varsayılan 2000 ml'dir; kullanıcı Hatırlatıcılar'dan 1500–3000 ml arasında seçer. **Kilo / aktiviteye göre hesaplanmaz**, tıbbi hedef değildir.
- Gösterilen UV **günün en yüksek değeridir**; güneş kremi yenileme penceresi saatlik UV verisinden çıkar. Hava tahmini dış sağlayıcıdan gelir.
- Yapay zekâ tıbbi tanı koymaz; ekranda uyarı vardır.

## Müşteriye kısa not (gönderilecek metin)

> Merhaba,
>
> İstediğiniz mobil uygulama hazır; telefonda birlikte gezelim.
>
> **Hazır olanlar:** Açılışta günün rutini ve "Yaptım" / "Ürün bitti" düğmeleri; su, makyaj (ve nasıl temizlendiği), beslenme
> takibi; havaya göre güneş kremi, nemlendirici ve dudak balsamı kararı (nedeniyle birlikte); her biri için **kendi saat
> aralığınızı** seçebildiğiniz hatırlatıcılar ve bildirimden tek dokunuşla işlem; web'deki sohbet botu aynı hesapla, bugünün
> bilgisini bilerek. Ürün bitince "Rafım"da görünüyor, birkaç gün sonra "yenisini aldın mı?" diye soruyor.
>
> **Henüz olmayanlar:** uygulama kapalıyken sunucudan bildirim (Firebase kurulumu bekliyor; şimdilik bildirimler telefonda
> planlanıyor), iPhone testi (Mac gerekiyor) ve ücretli abonelik (mağaza kuralları nedeniyle sonraki sürüm).
>
> İki soru: "balsam" derken dudak balsamını mı kastettiniz? Mağaza sayfası için destek e-postası ve gizlilik politikası
> adresini paylaşır mısınız?

## Demo sonrası

Müşteriden gelen her istek / hata için: ne istendi, hangi ekranda, ekran görüntüsü. Demo sırasında çıkan hatalar
`MOBIL-CIHAZ-TESTI.md` sonuç tablosuna aynı biçimde yazılır.
