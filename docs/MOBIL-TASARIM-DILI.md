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

Marka ilk izlenimi tek bir hikâyedir: **derin orman yeşili sahne** (açılış, karşılama, giriş, Bugün) ve gerektiğinde altına
yükselen **krem "kâğıt" panel** (giriş, kayıt, Bugün kartları). Açılış ve karşılama aynı yeşille başlar; iki temada da aynıdır
(koyu temada yalnızca paneller koyulaşır).

- **Açılış + karşılama tek sekanstır (`LandingScreen`).** Ayrı bir açılış rotası yoktur: uygulama oturumsuz açılınca
  (`buildRouter(splash: true)` → `landingIntroPending`) ilk karşılama kendi içinde ~3 sn'lik bir sekans oynatır; sonraki
  ziyaretler (ör. girişten geri dönüş) oynatmaz. **İlk kare yerel açılış ekranıyla birebir örtüşür:** düz orman yeşili zemin ve
  ekranın tam ortasında 104 dp marka karosu (`BrandMark.launchSize`; Android 12+ `splash_logo.xml`, Android 12 öncesi
  `launch_logo.png`, iOS `LaunchImage`; `test/launch_experience_test.dart` konumu ve boyutu korur). Sonra "Rebi" harf harf
  belirir, ince çizgi çekilir, geniş aralıklı slogan gelir; ardından **karo ve yazı sol üstteki yerine süzülür** (yazı 54→27
  puntoya iner, slogan solar), sahne ve içerik onun ardından kurulur. Marka bu katmanda kalır (üst çubuktaki marka gizli), bu
  yüzden yerleşmede kayma yoktur. Ekrana dokunmak sekansı atlatır; "animasyonları azalt" açıkken hiç oynamaz.
- **Karşılama içeriği.** Tek odak, **sıfır etiket**: tam ekran derin orman yeşili, arkasında tek bir yumuşak ışık havuzu; ortada
  tek kahraman görsel (`HeroArt`: podyum üstünde ürünler), altında ortalı iki satırlık Fraunces başlık, iki satırlık açıklama,
  krem tek ana düğme ("Rutini oluştur"), tek satır sessiz ikincil eylem (Giriş yap | Rebi ile konuş) ve en dipte silik yasal
  metin. Kaydırmalı sahne, yüzen kart/etiket, ilerleme göstergesi, yaprak gölgesi yoktur (testle korunur: `PageView` yok).
- **Günün ışığı (`HeroLight`).** Gökyüzü diski yerel saate göre değişir: 05–17 gündüz (şeftali güneş, turkuaz ışık), 17–21 akşam
  (alçak, sıcak güneş), 21–05 gece (hilal ay, birkaç yıldız, soğuk mavi ışık). Uygulamanın "sabah ve akşam rutini" fikrini
  yazısız anlatır; her kullanıcı kendi saatini görür.
- **Cila.** Kubbe ve ürün gövdelerinden birkaç saniyede bir geçen yumuşak ışık bandı (13 sn döngü); diskin halesi; çok yavaş
  nefes alma (güneş diski salınır, zeytin dalı sallanır). Başlık belirirken Fraunces'in eksenleri oturur (ağırlık 320→500,
  yumuşaklık 0→40). Ana düğmede belirdikten kısa süre sonra bir kez turkuaz ışık bandı geçer (`ShimmerOnce`); basınca çabuk
  küçülür, bırakınca yay gibi hafifçe aşıp oturur ve hafif darbe titreşimi verir. Sürekli çizilen sahne kendi katmanındadır.
- **Kayda geçiş.** Karşılamadan çıkarken yalnızca içerik yukarı süzülüp solar, zemin yerinde kalır (sayfa düzeyinde solma yok:
  arkada kâğıt rengi parlamaz); kayıt sayfasının krem paneli aynı zeminin üstüne yükselir. Geri dönüşte tersi olur.

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

Tek odak "şimdi ne yapmalıyım": yukarıdan aşağı **üst sahne (selamlama + hava hapı) → kahraman rutin kartı → gün akışı → havaya
göre üç karar → gün içi kayıtlar → "Daha fazlası"**; altta yüzen "Yaptım / Ürün bitti" dock'u. Kurallar:

- **Üst sahne (`TodayHeader`)** giriş ve karşılamayla aynı dildir: seçili temanın **derin tonunda** (`RebiTheme.deep`/`stage`; Orman'da
  marka yeşili, koyu modda biraz koyulaşır; üstünde krem yazı ≥ 4,5:1, testle korunur), tam genişlikte ve durum çubuğunun altına
  uzanır, alt köşeleri yuvarlaktır. İçinde: küçük harfli tarih, krem Fraunces selamlama (saate göre), krem hesap düğmesi, hava
  özeti (krem çerçeveli hap) ve çok silik sabit "R" imzası. İlk kart (`StageOverlap`) sahnenin alt kenarına **40 dp biner**; içerik
  sırayla süzülerek belirir. Sahne ekrandayken durum çubuğu simgeleri açık, kaydırılıp çıkınca sayfanın stiline döner
  (`AnnotatedRegion`). Bu yüzden kabuk Bugün ve Rutin kökünde üst güvenli alanı uygulamaz; sahnesiz durumlar (yükleniyor,
  tam plan) güvenli alanı kendileri uygular.
- **Alt dock (`TodayActionBar`)** tam genişlikte bant değil, kenarlardan boşluklu yuvarlak yüzeydir; altındaki gezinme çubuğuyla
  iki bant yığını oluşturmaz.
- **Rutinsiz karşılama (`TodayEmptyStart`, ilk giriş):** aynı sahne (selamlama = `dashboard.noAnalyzeTitle`) ve sahneye binen
  "İlk adım" kartı: küçük etiket, Fraunces başlık, kısa açıklama, kendini çizen üç adımlık yol (nasıl çalışır), tek ana düğme
  (Analiz Başlat) ve ikincil sohbet eylemi. Bugün ve Rutin sekmesinde aynıdır.

- Kahraman kart tek bir rutin bloğunu gösterir; tamamlanınca adımlar sakin bir özetin arkasına çekilir (istenirse açılır, "yeniden aç" ile geri alınır).
- Gün akışı şeridi bir **zaman çizelgesidir**: çubuk = pencere (yapıldıysa dolu), nokta = su, dikey çizgi = şimdi. Renkler kategori renkleridir; altında renk açıklaması durur.
- "Havaya göre" kartı her satırda **karar + tek cümle gerekçe** verir; metinler yapılandırılmış veriden uygulama dilinde kurulur (`mobileToday.decisions.*`).
- Su geniş, makyaj ve beslenme yan yana; 340 px altında ya da yazı %125 üstünde alt alta dizilir (taşma testle korunur).
- Aynı iş iki yerde tekrar etmez (rutin hatırlatıcısı "şimdi" listesinde yok; güneş kremi kaydı yalnız "havaya göre" kartında).
- Yeni durumlar galeriye eklenir: `bugun-tamam`, `bugun-hata`, `bugun-yukleniyor`, `bugun-bos`.

- **Hava paneli (sahnenin kahramanı).** "Hava durumuna göre" uygulamanın vaadidir; bu yüzden sahnede selamlamanın altında büyük bir
  panel durur (krem çerçeveli, `_WeatherPanel`): sol blokta büyük Fraunces derece ve simge, sağda **UV** ve **nem** değerleri, sözlü
  seviyeleri (UV: düşük / orta / yüksek / çok yüksek; nem: kuru / dengeli / nemli) ve beş parçalı küçük gösterge (UV ≥ 6'da bal tonu).
  Hava gerçek bir kaynaktan değilse köşede "tahmini" yazar. 330 dp panel genişliğinin altında ya da %125 üstü yazıda alt alta dizilir;
  satırlar sığmazsa küçülür (taşma yok). Ekran okuyucu için tek cümlelik özet (`weatherPill`) etikettir.
- **Rutin adımları zaman çizelgesidir** (Rutin sekmesiyle aynı dil): işaret dairesi + bir sonraki adıma inen ince çizgi; yapılan adım
  **soluklaşır, üstü çizilmez**. Biten ürünün adımı da aynı çizgide, bal tonlu.
- **Hava kararları tonlu panellerdir**: güneş kremi bal, nem su, dudak balsamı pudra (gerekmeyen karar nötr), her biri simge diskli;
  gerekçe ve "yeniledim" düğmesi panelin içinde.
- **Gün akışı**: "Şimdi" bölümü bekleyen yoksa sakin bir onay satırıdır, sıradaki hatırlatmalar simge diskli satırlardır.
- **"Daha fazlası" iki sütunlu karolardır** (check-in, rafım, hızlı fotoğraf, yeni analiz, haftanın tamamı, geçmiş): tonlu yüzey,
  simge diski, başlık ve alt metin; altı satırlık uzun liste kalktı.

## Sohbet ("Rebi ile konuş")

Sohbet "yazı kutusu" değil, **Rebi ile konuşma**dır. Karşılamadan açılan oturumsuz sayfa (`/rebi`) ve oturumlu sekme
(`/dashboard/chat`) aynı ekrandır; dil de aynıdır: **tema derin tonunda üst sahne + krem zemin**.

- **Üst sahne (`ChatStage`).** Tam genişlikte, krem yazılı. Soldan sağa: geri düğmesi (yalnız oturumsuzken; karşılamaya döner),
  Rebi imzası (marka karosu + Fraunces "Rebi"; **yanıt hazırlanırken karonun çevresinde iki halka sırayla yayılır**), kota hapı
  ve "Temizle" (yalnız konuşma varken). Kabuğun ayrı logo/menü çubuğu yoktur (çift başlık olmasın); kabuk `/rebi`'de çubuk
  çizmez, `/dashboard/chat`'te üst güvenli alanı sayfaya bırakır.
- **Boşken büyük sahne:** altında Fraunces karşılama sorusu (`chat.emptyTitle`) ve oturumluysa "Rebi bugünü biliyor" çipleri
  (krem çerçeveli, kaydırılır, dokununca Bugün). **İlk mesajla sahne ince çubuğa katlanır** (soru ve çipler kalkar), temizleyince
  yeniden açılır. Sığmayan durumlarda (yükseklik < 700 dp, yazı > %130, klavye açık) sahne ince kalır; soru klavye yokken
  kaydırılabilir gövdenin başında görünür (taşma testle korunur).
- **Öneriler** etiketsizdir (başlık yok), sırayla süzülerek belirir; altında tek satırlık dürüstlük notu. Konuşma sürerken
  giriş alanının üstünde yatay çip şeridi olarak kalır (yazarken ve beklerken gizli).
- **Mesajlar:** kullanıcı balonu vurgu rengiyle dolu, Rebi balonu yüzey rengi, ince çerçeve ve çok hafif gölgeli; **ekran açıkken
  eklenen mesajlar süzülerek gelir** (eskiler kaydırılınca yeniden oynamaz). Yanıt düz metin olarak okunaklı çizilir (maddeler
  asılı girinti, ":" ile biten satır alt başlık). Hata **sohbetin içine yazılmaz**: sakin bir kart ve "Tekrar dene". Hak
  dolunca sohbetin altında bilgi kartı çıkar, giriş alanı kilitlenir. Rutin adımından "Rebi'ye sor" sohbeti hazır soruyla açar.
- **Yazı alanı** yüzen yuvarlak bir dock'tur (alan + gönder düğmesi tek yüzeyde; gönder düğmesi yazı varken yaylı büyür).
  Klavye açılınca kota notu ve yapay zekâ beyanı gizlenir (pencere metrikleri dinlenir; `MediaQuery` gövdede klavyeyi vermez).

## Rutin sekmesi

Rutin, ilk görülen şeydir: uyarılar ve notlar rutinin önüne değil içine/arkasına konur. Yukarıdan aşağı:

- **Üst sahne (`RoutineStage`)** Bugün sahnesiyle aynı dildir (temanın derin tonu, krem Fraunces başlık, silik "R"): küçük harfli tarih,
  "Senin Rutinin, {ad}", cilt profili çipleri (cilt tipi · şiddet · yaş grubu), **haftanın gün şeridi** (krem; seçili gün dolu, bugün noktalı)
  ve seçili günün başlığı ("Çar · Bugün"). İlk kart sahneye 36 dp biner. Güvenli alanı sahne uygular (kabuk Rutin kökünde uygulamaz).
- **Sabah ve akşam kartları (`RoutineBlockCard`)**: tonlu başlık bandı (sabah bal + güneş, akşam lavanta + ay; renk anlam taşır),
  Fraunces başlık ve adım sayısı; altında **zaman çizelgesi gibi numaralı adımlar** (dolu numara düğümü, bir sonraki adıma inen ince çizgi,
  son adımda çizgi yok). "Neden bu ürün?" ayrıntısı soluk bir kutuda açılır; "Rebi'ye sor" orada. Yaşam notları numarasız, simgeyle.
- **Sabah kullanım uyarısı sabah kartının içinde** durur (ilgili yerde, ayrı sarı kutu olarak değil); sabah adımı olmayan günde kendi kartı olur.
- **Günlük yaşam dengesi** (risk düzeyi pilli) rutinden **sonra** gelir; sert sol şerit yerine tonlu simge diski.
- Kabul edilmemiş plan (analiz sonrası): **"rutini kabul et" kartı ilk karttır**, sahneye biner.
- Sonrası eskisi gibi sakin: seyrek adımlar, check-in, hava tek satır, katlanır bölümler (etken listesi, nasıl seçersin, yaşam/beslenme),
  su/uyku notları, ilerleme fotoğrafı, "Yeni analiz"; kalıcı yapay zekâ beyanı sayfanın **sonunda**.
- Testler: `routine_screen_test` ("üst sahne", "sabah uyarısı sabah bloğunun içinde", kabul kartı sırası), `accessibility_test`, `text_scale_test`.

## Analiz sihirbazı ("Seni tanıyalım")

Eski sihirbaz dört uzun sayfaydı (60'a yakın soru, renkli kartlar, 10–11 punto metin, 10 kaydırıcılı stres testi, 14 kartlı
ürün listesi). Yenisi **tek soru tek ekran**dır: yorulmayan, ne sorulduğu ve neden sorulduğu belli, her adımda tek karar.

- **Karşılama** (`AnalyzeScreen` ilk sayfa) girişle aynı sahnedir: derin orman yeşili üst sahne, Fraunces "Seni tanıyalım.",
  altında krem panelde üç sakin cümle (≈3 dk, her soru tek ekran, cevaplar yalnız rutin için) ve "Başlayalım".
- **Akış tam ekrandır**: alt sekme çubuğu ve geri çubuğu yoktur (kabuk `focusFlow`; `/dashboard/analyze?photo=1` hızlı yükleme eskisi gibi
  kabuklu kalır). Üstte geri, bölüm adı, kapat; altında **beş bölüm çizgisi** (Sen · Cildin · Günlük hayatın · Ürünlerin · Son adım).
  Android geri tuşu soru soru geri gider; karşılamada çıkış. Kapat, ilk sorudan sonra "cevapların kaydedilmez" diye sorar.
- **Soru ekranı**: küçük bölüm etiketi (gerekirse), Fraunces 30 soru, tek cümle açıklama, altında büyük seçenekler (≥64 dp satır,
  yuvarlak seçim işareti; çoklu seçimde kare onay). Tek seçimli sorular dokununca **0,28 sn sonra** ilerler; çoklu/bileşik
  sorular ve alt sorusu olanlar (sigara, alkol, makyaj) "Devam et" bekler. **Ekran okuyucu açıkken kendiliğinden ilerleme kapalıdır.**
  Alt çubukta tek ana düğme; gerektiğinde sessiz ikinci eylem (stres testini geç).
- **Sorular koşulludur**: cinsiyet kadın değilse hormonal durum yok; düzenli/düzensiz döngüde adet tarihi; birden çok sorun
  seçildiyse "Hangisinden başlayalım?" (öncelikli sorun = backend `concern`); genel bakımda bölge, işaret ve şiddet anketi yok;
  şiddet anketi **yalnız öncelikli sorun için** (backend yalnız onun skorunu kullanıyordu); stres testi isteğe bağlıdır (10 soru
  ayrı ekranlar; atlanırsa varsayılan cevaplar, eski sihirbazla aynı `stress_score`).
- **Seçenek dili**: cilt tipinde doku küçük resmi, sorunlarda çizgi ikon diski; su/uyku büyük Fraunces sayı + kaydırıcı + eksi/artı;
  ürün tepkileri tek yüzeyli liste (satırda durum hapı, dokununca alt sayfada 4 seçenek; dokunulmayan "Sorunsuz" kalır, **ciddi tepki
  rutine hiç yazılmaz**). Renk yalnız kategori/durum anlamı taşır (su mavisi, uyku lavantası, tepki sarı/tuğla).
- **Özet** ("Hazırız, {ad}."): yaş, cilt tipi, odak, şiddet, fotoğraf satırları ve isteğe bağlı **konum** satırı (hava/UV için);
  tek ana düğme "Rutinimi oluştur". Hata özette kalır ve tekrar denenir.
- **Backend gövdesi değişmedi** (web `Analyze.jsx` ile aynı alan kümesi; `AnalyzeForm.toBody`). Sihirbaz görünümünden bağımsız
  cevap modeli `analyze_form.dart`, yapı taşları `analyze_flow.dart`, sayfalar `analyze_pages.dart`, yönlendirme `analyze_screen.dart`.
- **Yaşa ve cinsiyete göre sorular** (kurallar `AnalyzeForm`'da, test: `analyze_flow_test` "yaş ve cinsiyete göre sorular"):
  yaş 13–100 dışı kabul edilmez (sunucu da bu aralığa kırpar; nedeni alanın altında yazar); **18 yaş altına sigara ve alkol sorulmaz**
  (gövdede sıfır gider, sonradan düzeltilen yaşta eski cevap gitmez); hormonal durumda **hamilelik 55 yaşına kadar, menopoz 40'tan
  sonra** sunulur; **erkeğe makyaj sorulmaz** (gövdede 0), yerine **tıraş** sorusu gelir (sıklık + tıraştan sonra cildin durumu).
  Kadın ve "diğer" için makyaj sorusu aynen sürer. Tıraş cevabı yalnız erkek gövdesinde `shaving_frequency` / `shaving_after`
  olarak gider (web gövdesinde yok; kadın/diğer gövdesi web ile aynı kalır). Sunucu bunları kaydeder (`lifestyle_data`), sohbet bağlamına verir ve
  **tıraş sonrası tahriş / batık tüy** bildiren erkeğe rutinde tek bir *Yaşam* notu ekler (`flow_engine.build_shaving_routine_items`:
  tıraş tekniği, tıraş sonrası bariyer bakımı, o gece o bölgeye güçlü aktif sürmeme, geçmezse dermatolog). Bakım satırı eklemez ve
  etken-madde kurallarına dokunmaz; "rahat" diyen ya da tıraş olmayan için not yoktur (`backend/tests/test_shaving_rule.py`).
- **Kaldırılan sorular**: beslenme (4), ne kadar süredir, tetikleyiciler, geçmiş tedaviler ve beklentiler. Bunlar web'de de
  toplanıyor ama **backend'e hiç gönderilmiyordu** (gövdede alanı yok); cevabı hiçbir yere gitmeyen soru sormak hem dürüst değil hem
  yorucuydu. Metinleri `analyzeWizard.json`'da duruyor; backend bu alanları kabul ettiğinde geri eklemek bir sayfa ekleyip
  `AnalyzeForm`'a alan koymaktan ibarettir.
- Testler: `test/analyze_flow_test.dart` (cevap modeli, dallar, geri/kapat, ekran okuyucu, konum/hata, **en uzun yolun** 4 boyut ×
  açık/koyu taşma denetimi), `screens_test` (uçtan uca gövde), `accessibility_test` ("Analiz · …" 12 senaryo, açık + koyu).

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

