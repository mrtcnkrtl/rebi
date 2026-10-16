# Rebi Mobil — Tasarım Dili: "klinik sıcaklık"

Uygulamanın tamamı tek bir dildedir: **krem kâğıt zemin, orman yeşili mürekkep, Fraunces başlık, Inter gövde, çizgi ikonlar**.
Karşılama/giriş ekranlarında ortaya çıkan bu dil artık giriş sonrası ekranların da temelidir. Amaç: bir klinik
kadar güvenilir, bir bakım markası kadar sıcak; süs yok, tek odak var.

## İlkeler

1. **Az öğe, tek odak.** Her ekranda "şimdi şunu yap" diyen tek bir şey; gerisi ikinci planda.
2. **Tipografi taşır, süs taşımaz.** Başlık Fraunces, gövde Inter. Parıltı, cam hap, neon gradyan, glow, desen, emoji yok.
3. **Renk anlam taşır.** Zemin ve mürekkep nötrdür; renk yalnızca kategori ve durum bildirir ve hep soluk tonlardadır.
4. **Sakin hareket.** Halka dolumu, tik, hafif dokunsal geri bildirim. Kutlama bağırmaz.
5. **Her durum tasarlanır:** boş, yükleniyor (iskelet), hata, çevrimdışı, koyu mod, %200 yazı.

## Palet

Tek kaynak `lib/ui/tw.dart` (`Tw` alıcıları) ve `lib/ui/brand/palette.dart` (`Brand`). `Tw` adları webden gelen Tailwind
adlarıdır ve korunur; **değerleri bu paletten gelir**. Açık/koyu çiftleri ve kontrast ölçütü `test/dark_mode_test.dart`
ile denetlenir (metin/zemin ≥ 4.5:1, düğmede beyaz yazı ≥ 4.5:1).

| Rol | Açık | Koyu | Kod |
|-----|------|------|-----|
| Zemin (kâğıt) | `#F7F3EC` | `#071A18` | `Tw.background`, `Brand.paper` |
| Kart yüzeyi | `#FFFFFF` | `#0F2A27` | `Tw.surface`, `Brand.surface` |
| Yükseltilmiş yüzey (sayfa, menü) | `#FFFFFF` | `#163632` | `Tw.surfaceRaised` |
| Mürekkep (ana metin) | `#0B3D38` | `#EAF3EF` | `Tw.gray900`, `Brand.ink` |
| İkincil metin | `#566F68` | `#91ABA4` | `Tw.gray500` |
| İnce çizgi | `#EAE5DA` | `#183832` | `Tw.gray100` |
| Dolgu (çip, alan) | `#F4F0E7` | `#12302C` | `Tw.gray50` |

**Kategori renkleri** (ailelerin 50–950 tonları `Tw`'de; ana tonlar iki modda aynıdır):

| Aile | Anlam | Tailwind adları |
|------|-------|-----------------|
| Orman | marka, birincil eylem | `teal*` |
| Su | su içme, nem, hava | `blue*`, `sky*`, `cyan*` |
| Pudra | makyaj | `pink*`, `rose*` |
| Adaçayı | beslenme, başarı | `emerald*`, `green*` |
| Bal | güneş, uyarı | `amber*`, `yellow*` |
| Kil | dikkat | `orange*` |
| Lavanta | uyku, sakinlik | `indigo*`, `violet*`, `purple*`, `fuchsia*` |
| Tuğla | hata, risk | `red*` |

Ham renk (`Color(0xFF…)`) yazma; `Tw`/`Brand` kullan. Ham Tailwind neon tonları testle yasaktır (`test/design_system_test.dart`).

## Tipografi

- **Başlık:** `heading(size)` → Fraunces 500, mürekkep rengi. Sayfa başlığı 28–30, kart/sayfa başlığı 24–26, küçük başlık 20.
  Yalnızca kısa, insani başlıklar için; sayı ve etiket için kullanılmaz.
- **Gövde:** `tx(size, w:, c:)` → Inter. 14 gövde, 12–13 ikincil, 11 etiket. Büyük harfli etiketler 11 punto, `ls: 1.2`.
- Rakamlar tablo gibi hizalanacaksa `FontFeature.tabularFigures()`.

## Bileşenler

| Bileşen | Dosya | Not |
|---------|-------|-----|
| Kart | `RCard` | yüzey, 1 px sıcak kenarlık, çok hafif orman tonlu gölge (koyuda gölge yok), köşe 20 |
| Ana düğme | `PrimaryButton` | tam yuvarlak uç, gölgesiz, 52 yükseklik, rengi `theme.primary` |
| İkincil düğme | `SecondaryButton` | çerçeveli, yüzey dolgulu, tam yuvarlak |
| Seçim çipi | `ChoiceChipBox` | 1.5 px çerçeve, seçiliyken orman çerçeve + tint dolgu |
| Alt sayfa | `AppSheet` | tutamaç + Fraunces başlık + kapat + kaydırılabilir gövde |
| Giriş alanı | `inputDecoration` | 1.5 px çerçeve, odakta orman |
| Karşılama düğmesi | `BrandButton` | yalnızca açılış/giriş ekranlarında |
| İkonlar | `LucideIcons` + `ui/brand/glyphs.dart` | emoji yok; backend emojileri `glyphForEmoji` ile ikona çevrilir |
| Kabuk | `AppShell` | krem kâğıt + temanın hafif yıkaması **kabukta** çizilir (sayfalar zemini boyamaz), 5 sekmeli alt çubuk |

Sayfa zemini kabuktandır: `ThemedBackground` zemin boyamaz. Sayfada zemini yeniden boyamak, geri çubuğuyla sayfa arasında dikiş bırakır.

## Bugün ekranı

Tek odak "şimdi ne yapmalıyım": yukarıdan aşağı **başlık + hava hapı → kahraman rutin kartı → gün akışı → havaya göre üç karar →
gün içi kayıtlar → "Daha fazlası"**; altta sabit "Yaptım / Ürün bitti" çubuğu. Kurallar:

- Kahraman kart tek bir rutin bloğunu gösterir; tamamlanınca adımlar sakin bir özetin arkasına çekilir (istenirse açılır, "yeniden aç" ile geri alınır).
- Gün akışı şeridi bir **zaman çizelgesidir**: çubuk = pencere (yapıldıysa dolu), nokta = su, dikey çizgi = şimdi. Renkler kategori renkleridir; altında renk açıklaması durur.
- "Havaya göre" kartı her satırda **karar + tek cümle gerekçe** verir; metinler yapılandırılmış veriden uygulama dilinde kurulur (`mobileToday.decisions.*`).
- Su geniş, makyaj ve beslenme yan yana; 340 px altında ya da yazı %125 üstünde alt alta dizilir (taşma testle korunur).
- Aynı iş iki yerde tekrar etmez (rutin hatırlatıcısı "şimdi" listesinde yok; güneş kremi kaydı yalnız "havaya göre" kartında).
- Yeni durumlar galeriye eklenir: `bugun-tamam`, `bugun-hata`, `bugun-yukleniyor`, `bugun-bos`.

## Vurgu rengi (tema)

Uygulamanın dili tektir; kullanıcı yalnızca **vurgu rengini** seçer (düğme, seçim, vurgu): ücretsiz **Orman · Adaçayı · Pudra · Lavanta**,
Plus için **Gün Batımı · Derin Su · Gece**. Desen, emoji ve şekil farkı yoktur (web'deki kedi/ayıcık temaları kaldırıldı;
kayıtlı kimlik artık yoksa `Orman`a dönülür). Düğme dolgusu `theme.primary` (üstüne beyaz yazı, AA), metin/ikon olarak
kullanılacak vurgu `theme.fg` (koyu modda okunacak kadar açılır).

## Görsel doğrulama

```bash
cd mobile
REBI_SCREENSHOTS=1 flutter test test/visual_gallery_test.dart
```

`build/screenshots/` altına gerçek yazı tipleriyle (Inter, Fraunces, Lucide) ana ekranların ve Bugün alt sayfalarının açık/koyu
PNG'lerini yazar (veri API sözleşmesindeki gerçek örnekten gelir). Bilerek piksel karşılaştırması yapmaz: yazı tipi işleme işletim
sistemleri arasında piksel piksel aynı olmadığı için CI'da kararsız olurdu. Taşma ve yerleşim hataları `screens_test` ve
`text_scale_test` (%150/%200 yazı, 320×568) ile yakalanır. Yeni ekranı galeriye `screens` listesine bir satır ekleyerek koy.

## Kurallar (testle korunur)

- Arayüz kodunda emoji yok (`design_system_test`): `glyphs.dart` ikonlarını kullan.
- Ham Tailwind neon rengi yok.
- Her temanın düğme rengi üstünde beyaz yazı ≥ 4.5:1.
- Metin/zemin çiftleri iki modda ≥ 4.5:1 (`dark_mode_test`).
