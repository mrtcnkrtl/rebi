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

## Açılış ve karşılama

Marka ilk izlenimi tek bir hikâyedir: **derin orman yeşili sahne, altında krem "kâğıt" panel**. Açılış ve karşılama aynı
yeşille başlar; iki temada da aynıdır (koyu temada yalnızca panel koyulaşır).

- **Açılış (`SplashScreen`, ~2,4 sn).** İlk kare yerel açılış ekranıyla **birebir** örtüşür: düz orman yeşili zemin ve ekranın
  tam ortasında 104 dp marka karosu (`BrandMark.launchSize`). Android 12+ `drawable-v31/splash_logo.xml`, Android 12 öncesi
  `launch_logo.png`, iOS `LaunchImage` aynı karoyu gösterir (`test/launch_experience_test.dart` konumu ve boyutu korur).
  Sonra karo yukarı süzülür, "Rebi" harf harf belirir, ince bir çizgi çekilir, geniş aralıklı büyük harfli slogan gelir.
  Halka, ışıltı, cam gibi süs yoktur; tek hareket "marka kuruluyor"dur. Çıkış karşılamanın üstünde solarak olur.
- **Karşılama (`LandingScreen`).** Üstte orman sahnesi: marka karosu + "Rebi" ve dil seçici (krem), ortada üç çizim; sahnenin
  altında zemine sahne renginde (nane / pudra / kum) tek bir yumuşak ışık havuzu düşer. Çizimler her zaman bu koyu zemine
  göre çizilir; etiket kartları kremdir. Altta krem panel, hiyerarşi: **küçük etiket → Fraunces başlık → açıklama → üç ince
  ilerleme çizgisi → tek ana düğme → tek satır ikincil eylem (Giriş yap | Rebi ile konuş) → tek satır yasal metin.**
- Büyük harfli etiketler `brandCaps` ile yazılır (Türkçede i→İ; Arapçada büyük harf ve harf aralığı yoktur).
- Logoyu ya da karo boyutunu değiştirirseniz yerel açılış görselleri `test/brand_assets_test.dart` ile yeniden üretilir
  (`mobile/README.md` → "Uygulama kimliği ve yayın").

### Giriş ve kayıt (`AuthScreen`)

Karşılamanın devamıdır (aynı orman sahnesi + krem panel); düz krem sayfaya düşme kopukluğu yoktur.

- **Üst sahne** düz orman yeşilidir (gradyan yok): krem Fraunces başlık, sağ üstte çok silik (%7,5) dev "R" monogramı.
  Monogram sayfa açılırken kendini çizer, sonunda köşedeki parıltı belirir: tek ve sakin hareket. Giriş, parola sıfırlama
  ve yeni parola kiplerinde sahne ekran yüksekliğinin ~%40'ına uzar, başlık alta oturur; **kayıtta kompakt** kalır (form
  uzundur). Kip değişince yükseklik ve başlık yumuşakça değişir.
- **Krem panel** alttan yükselir, alanlar sırayla belirir. Alanlar küçük çizgi ikonlu (kişi, posta, kilit), 16 px köşeli,
  ince çerçevelidir; odakta çerçeve koyulaşır.
- **Alt şerit** (giriş ↔ kayıt bağlantısı + güven notu) kaydırma alanının dışında, ekranın dibinde sabittir; klavye açılınca
  yer açmak için gizlenir. Kısa formda boşluk panelin ortasında değil, form ile şerit arasında kalır.
- **Kayıt onayları sadeleştirildi:** iki zorunlu onay (KVKK, açık rıza) açıktadır; isteğe bağlı izinler (konum, fotoğraf)
  tek satıra **katlıdır**, varsayılan kapalı ve hiçbiri önceden işaretli değildir. Açık izin sayısı satırda (`1/2`) görünür.
  Zorunlu onaylar ile ilk iki `Checkbox` sırası testlerce korunur (`auth_flow_test`, `screens_test`).
- Sahne her iki temada orman yeşilidir (açık/koyu farkı yalnızca panelde); durum çubuğu simgeleri açıktır.

## Bugün ekranı

Tek odak "şimdi ne yapmalıyım": yukarıdan aşağı **başlık + hava hapı → kahraman rutin kartı → gün akışı → havaya göre üç karar →
gün içi kayıtlar → "Daha fazlası"**; altta sabit "Yaptım / Ürün bitti" çubuğu. Kurallar:

- Kahraman kart tek bir rutin bloğunu gösterir; tamamlanınca adımlar sakin bir özetin arkasına çekilir (istenirse açılır, "yeniden aç" ile geri alınır).
- Gün akışı şeridi bir **zaman çizelgesidir**: çubuk = pencere (yapıldıysa dolu), nokta = su, dikey çizgi = şimdi. Renkler kategori renkleridir; altında renk açıklaması durur.
- "Havaya göre" kartı her satırda **karar + tek cümle gerekçe** verir; metinler yapılandırılmış veriden uygulama dilinde kurulur (`mobileToday.decisions.*`).
- Su geniş, makyaj ve beslenme yan yana; 340 px altında ya da yazı %125 üstünde alt alta dizilir (taşma testle korunur).
- Aynı iş iki yerde tekrar etmez (rutin hatırlatıcısı "şimdi" listesinde yok; güneş kremi kaydı yalnız "havaya göre" kartında).
- Yeni durumlar galeriye eklenir: `bugun-tamam`, `bugun-hata`, `bugun-yukleniyor`, `bugun-bos`.

## Sohbet

Sohbet "yazı kutusu" değil, **Rebi ile konuşma**dır: üstte Fraunces "Rebi" imzası ve kota hapı; hemen altında **"Rebi bugünü biliyor" şeridi**
(hava, rutin, su, makyaj, biten ürün; yalnızca gerçek veri; dokununca Bugün). Kullanıcı balonu vurgu rengiyle dolu, Rebi balonu yüzey rengi ve ince
çerçeveli; yanıt düz metin olarak okunaklı çizilir (maddeler asılı girinti, ":" ile biten satır alt başlık). Hata **sohbetin içine yazılmaz**: sakin bir
kart ve "Tekrar dene" (çevrimdışı / sunucu / oturum / genel). Hak dolunca sohbetin altında bilgi kartı çıkar, giriş alanı kilitlenir. Rutin
adımından "Rebi'ye sor" sohbeti hazır soruyla açar.

## Rutin sekmesi

Tek sütun, sakin: önce güvenlik bilgisi (sabah kullanım uyarısı, günlük denge), sonra **gün seçici ve seçilen günün sabah/akşam blokları**; ayrıntı
("Neden bu ürün?") ve uzun rehberler katlanır. Hava tek satırdır; renkli gradyan kart yok. Aynı adım dili Bugün'deki kahraman kartla ortaktır.

## İlk açılış izinleri

Tek seferde tek öneri, değerini gösterdiği sırayla: **konum** (ekrandaki hava ve havaya göre kararlar gerçek olur) → **bildirim** (hatırlatmalar). İzin
penceresi hiçbir zaman uygulama açılırken değil, kullanıcı önerideki düğmeye dokununca açılır; "Şimdi değil" kalıcıdır.

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
- Ekranlarda ve bileşenlerde süs gradyanı yok (izinli: kabuğun temalı yıkaması, karşılama/yükleme zemini, marka çizimleri) ve koyu mor "cam"
  panel renkleri yok (`design_system_test`).
- Her temanın düğme rengi üstünde beyaz yazı ≥ 4.5:1.
- Metin/zemin çiftleri iki modda ≥ 4.5:1 (`dark_mode_test`).
- **Erişilebilirlik** (`accessibility_test`, Faz G3): 52 senaryo (tüm ana ekranlar + alt sayfalar, açık ve koyu) şu kurallardan geçer:
  dokunma hedefi ≥ 48 dp (Android) / 44 dp (iOS), dokunulabilir her öğenin ekran okuyucu etiketi, metin kontrastı ≥ AA.

## Erişilebilirlik kuralları (yeni ekran yazarken)

- **Dokunma alanı büyür, görsel büyümez.** Küçük bir hap / simge görünümü 32 dp kalabilir; etrafındaki `InkWell` / `ConstrainedBox(minHeight: 48)`
  48 dp olur (örnek: sohbet bilgi çipleri, `TextLink`, `ChoiceChipBox`). `VisualDensity.compact` ve `MaterialTapTargetSize.shrinkWrap`
  hedefi 48'in altına çeker; yalnızca içinde 48 dp'lik bir sarmalayıcı varsa kullan.
- **Metin rengi** bir kategori renginden (su mavisi, bal sarısı, pembe…) geliyorsa `Tw.readable(renk, bg: zemin)` ile geçir; renkli dolgunun
  üzerine beyaz yazı gelecekse dolguyu `Tw.fillWithWhiteText(renk)` ile geçir. `gray400` yalnızca süs / kenar için; **metin** en az `gray500`.
  Vurgu rengi metin olacaksa `theme.fg` (koyu modda açılır), `theme.primary` değil.
- **Etiket:** yalnızca simge olan düğmeye `tooltip` / `Semantics(label:)` ver (`Switch` için de: `Semantics(label: ..., child: Switch(...))`).
  Başlık + açıklama + kontrol tek satırsa `MergeSemantics` ile tek düğüm yap (örnek: onay kutusu satırı).
- Seçilebilir kullanıcı metni için `SelectableText` yerine `SelectionArea(child: Text(...))` (aynı seçim, etiketsiz fazladan düğüm üretmez).
- Yeni ekranı `test/accessibility_test.dart`'a bir senaryo olarak ekle; hata satırı elemanı, ölçüyü ve oranı söyler.

