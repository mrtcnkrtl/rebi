/** Yasal metin gövdeleri (KVKK, açık rıza, satış, çerez, gizlilik, koşullar, iade, künye). Dil: tr | en */
import { COMPANY, companyIdentity, companyRows } from "./company";

export const LEGAL_UPDATED = "15.11.2026";

const NAME = COMPANY.legalName;
const MAIL = COMPANY.email;
// KVKK ve açık rıza blokları düz metin kalır: mobil uygulama aynı metni taşır ve `mobile/test/web_sync_test.dart`
// bu dosyayı okuyarak karşılaştırır. Şirket adı ya da e-posta değişirse o bloklar ve `mobile/lib/core/legal_texts.dart`
// elle güncellenir.
const ID_TR = companyIdentity(false);
const ID_EN = companyIdentity(true);

const TR_KVKK = [
  {
    title: "1. Veri sorumlusu",
    body: "Bu aydınlatma metni, 6698 sayılı Kişisel Verilerin Korunması Kanunu (“KVKK”) kapsamında Rebi cilt bakımı platformunun (“Rebi”) kullanıcılarına yöneliktir. Veri sorumlusu, Rebi’yi işleten A3 Biyoteknoloji A.Ş.’dir; şirket künyesi rebiovil.com/sirket sayfasındadır. Başvurularınızı sosyal@rebiovil.com adresine hesap e-postanızdan ya da uygulama içi Profil ekranı üzerinden iletebilirsiniz.",
  },
  {
    title: "2. İşlenen kişisel veriler",
    body: "Hesap: ad-soyad, e-posta, şifre (hash). Profil ve rutin: yaş, cinsiyet, cilt tipi, şikâyet, şiddet, yaşam tarzı (uyku, stres, su, sigara, alkol), makyaj alışkanlığı, hamilelik/döngü bilgisi, aktif madde deneyimi ve tolerans. İsteğe bağlı cilt fotoğrafları. Konum (hava/UV için enlem-boylam). Sohbet mesajları, check-in kayıtları, rutin ve analiz çıktıları. Teknik: oturum, dil tercihi, cihaz/ tarayıcı kayıtları.",
  },
  {
    title: "3. İşleme amaçları ve hukuki sebepler",
    body: "Hesap açmak, kimlik doğrulamak ve sözleşmeyi ifa etmek (KVKK m.5/2-c). Kişiselleştirilmiş rutin, check-in ve sohbet sunmak. Güvenlik, kötüye kullanımın önlenmesi ve yasal yükümlülükler (m.5/2-ç, f). İyileştirme ve hata ayıklama. Cilt görüntüsü, sağlık belirtisi, hamilelik gibi özel nitelikli veriler ancak açık rızanızla işlenir (KVKK m.6).",
  },
  {
    title: "4. Aktarım",
    body: "Rutin ve sohbet için yapay zekâ işlemesi A3 Biyoteknoloji tarafından, Google Gemini AI altyapısı kullanılarak gerçekleştirilir. Barındırma ve veritabanı için veriler Supabase’e aktarılabilir. Konum izni verirseniz kesin koordinatlar Open-Meteo’ya (yedek olarak OpenWeather’a) iletilir. Fotoğraf izni verirseniz görüntüler private Supabase Storage alanında saklanır. Mobil uygulamada bildirim izni verirseniz cihazınızın bildirim anahtarı ve bildirim metni Google Firebase Cloud Messaging üzerinden iletilir. Zorunlu hallerde yetkili kamu kurumlarına aktarım yapılabilir; yurt dışı aktarımlarda KVKK usulleri uygulanır.",
  },
  {
    title: "5. Üçüncü taraf yapay zekâ hizmeti (Google Gemini)",
    body: "Rutin oluşturma, check-in yorumu, rutin çevirisi ve sohbet yanıtları için aşağıdaki veriler, uygulama içinde ayrıca izin vermenizden sonra Google LLC’nin Gemini API hizmetine şifreli bağlantıyla gönderilir: ad, yaş ve cinsiyet; cilt tipi, şikâyet ve analiz cevapları; hamilelik/döngü, sigara, alkol, uyku, stres ve su tüketimi gibi sağlık ve yaşam tarzı bilgileri; günlük check-in kayıtları ve rutindeki ürünler; sohbet mesajları; konum izni verdiyseniz bölgenizin hava ve UV bilgisi. Cilt fotoğrafları, e-posta adresi ve şifre Gemini’ye gönderilmez. Veriler yalnızca size yanıt üretmek amacıyla kullanılır; Google, ücretli Gemini API koşulları gereği bu verileri kendi modellerini eğitmek için kullanmaz ve veri işleme şartları kapsamında en az bu metinde açıklanan düzeyde koruma sağlar. Bu izni uygulamada Hesap > Gizlilik izinleri bölümünden istediğiniz zaman geri alabilirsiniz; bu durumda yapay zekâ özellikleri çalışmaz, diğer özellikler kullanılmaya devam edilebilir.",
  },
  {
    title: "6. Saklama süresi",
    body: "Aktif profil ve rutin hesabınız açık olduğu sürece saklanır. Giriş sunumu IP hash’i 180 gün, günlük mikro olaylar 400 gün; günlük check-in ile kullanılmayan geçmiş rutin/değerlendirme kayıtları en fazla 730 gün tutulur. Cilt fotoğrafları siz silene veya hesabınızı kapatana kadar saklanır. Hesabı sildiğinizde profil, rutin, check-in, rıza kaydı ve fotoğraflar kaldırılır; kanunen zorunlu kayıtlar ilgili süre boyunca ayrıca tutulabilir.",
  },
  {
    title: "7. Haklarınız (KVKK m.11)",
    body: "Verilerinizin işlenip işlenmediğini öğrenme, bilgi talep etme, amaca uygunluğu öğrenme, yurt içinde/dışında aktarılan üçüncü kişileri bilme, düzeltilmesini isteme, silinmesini/yok edilmesini isteme, itiraz ve zararın giderilmesini talep etme haklarınız vardır. Başvurularınız makul sürede yanıtlanır.",
  },
  {
    title: "8. Çerez ve yerel depolama",
    body: "Oturum, dil, rutin takibi ve bu metinlere verdiğiniz onay tarayıcınızda (ör. localStorage) tutulabilir. Zorunlu olanlar hizmetin çalışması içindir. Site analitik ya da reklam çerezi kullanmaz; ayrıntı Çerez Politikası’ndadır (rebiovil.com/cerez).",
  },
];

const EN_KVKK = [
  {
    title: "1. Data controller",
    body: "This notice is provided under Türkiye’s Personal Data Protection Law No. 6698 (KVKK) for the Rebi skincare platform. The controller is A3 Biyoteknoloji A.Ş., which operates Rebi; company details are at rebiovil.com/sirket. You can send requests to sosyal@rebiovil.com from your account email, or through the in-app Profile screen.",
  },
  {
    title: "2. Data we process",
    body: "Account: name, email, password (hashed). Profile and routine: age, gender, skin type, concerns, severity, lifestyle (sleep, stress, water, smoking, alcohol), makeup habits, pregnancy/cycle information, active-ingredient experience and tolerance. Optional skin photos. Location (lat/lon for weather/UV). Chat messages, check-ins, routine and analysis outputs. Technical: session, language, device/browser logs.",
  },
  {
    title: "3. Purposes and legal bases",
    body: "Creating an account, authentication and performing the service (KVKK art. 5/2-c). Personalized routines, check-in and chat. Security, abuse prevention and legal duties (art. 5/2-ç, f). Product improvement. Skin images, health-related symptoms and pregnancy data are special-category data and are processed only with your explicit consent (KVKK art. 6).",
  },
  {
    title: "4. Recipients",
    body: "AI processing for routines and chat is performed by A3 Biyoteknoloji using Google Gemini AI infrastructure. Data may also be shared with Supabase for hosting and database services. If location permission is granted, precise coordinates are sent to Open-Meteo (or OpenWeather as fallback). If photo permission is granted, images are stored in private Supabase Storage. If you allow notifications in the mobile app, your device’s notification token and the notification text are delivered through Google Firebase Cloud Messaging. Transfers abroad follow applicable KVKK procedures.",
  },
  {
    title: "5. Third-party AI service (Google Gemini)",
    body: "For routine creation, check-in insights, routine translation and chat replies, the following data is sent over an encrypted connection to Google LLC’s Gemini API, only after you give separate permission in the app: name, age and gender; skin type, concerns and analysis answers; health and lifestyle information such as pregnancy/cycle, smoking, alcohol, sleep, stress and water intake; daily check-ins and the products in your routine; chat messages; and, if you granted location permission, weather and UV information for your area. Skin photos, email address and password are never sent to Gemini. The data is used only to generate responses for you; under the paid Gemini API terms Google does not use it to train its models, and under its data processing terms provides protection at least equal to that described in this notice. You can withdraw this permission at any time in Account > Privacy permissions in the app; AI features will then stop working while other features remain available.",
  },
  {
    title: "6. Retention",
    body: "Active profiles and routines are kept while the account remains open. Intro IP hashes are retained for 180 days, daily events for 400 days, and check-ins plus unused historical routines/assessments for up to 730 days. Skin photos remain until you delete them or close the account. Account deletion removes profile, routines, check-ins, consent evidence and photos; legally required records may be retained for the applicable period.",
  },
  {
    title: "7. Your rights (KVKK art. 11)",
    body: "You may learn whether your data is processed, request information, learn the purpose, know third-party recipients, request correction, erasure/destruction, object, and claim damages. We respond within a reasonable time.",
  },
  {
    title: "8. Cookies and local storage",
    body: "Session, language, routine tracking and this consent may be stored in your browser (e.g. localStorage). Strictly necessary items are required for the service to work. The site uses no analytics or advertising cookies; see the Cookie Policy (rebiovil.com/cerez).",
  },
];

const TR_RIZA = [
  {
    title: "1. Konu",
    body: "6698 sayılı KVKK’nın 6. maddesi uyarınca, özel nitelikli kişisel verilerimin (cilt görüntüsü; cilt tipi ve şikâyetler; hamilelik/döngü; yaşam tarzı ve aktif madde toleransı gibi sağlıkla ilgili bilgiler) A3 Biyoteknoloji tarafından Rebi platformu kapsamında işlenmesine açık rıza veriyorum.",
  },
  {
    title: "2. Amaç",
    body: "Cilt ve sağlık verilerimin A3 Biyoteknoloji tarafından işlenmesine ve rutin/sohbet hizmeti için Google Gemini AI altyapısının kullanılmasına açık rıza veriyorum. Bu, hizmetin sunulması için gereklidir. Rebi bir yapay zekâ asistanıdır; öneriler hata payı içerir ve tıbbi teşhis veya tedavi yerine geçmez. Kesin konumun hava servisine aktarılması ve cilt fotoğrafının private alanda saklanması ayrı ve isteğe bağlı izinlerdir.",
  },
  {
    title: "3. Aktarım",
    body: "Yukarıdaki amaçlarla sınırlı olmak üzere verilerimin A3 Biyoteknoloji tarafından işlenmesine ve barındırma, veritabanı ile yapay zekâ altyapı sağlayıcılarına aktarılmasına rıza gösteriyorum.",
  },
  {
    title: "4. Gönüllülük ve geri alma",
    body: "Rıza vermek zorunda değilim; vermezsem hesap açılamaz veya cilt analizi/fotoğraf özellikleri kullanılamaz. Rızamı dilediğim zaman Profil üzerinden hesabımı silerek veya veri sorumlusuyla iletişime geçerek geri alabilirim. Geri alma, geri alma anına kadar yapılan işlemi hukuka aykırı kılmaz.",
  },
];

const EN_RIZA = [
  {
    title: "1. Subject",
    body: "Under KVKK article 6, I give explicit consent to A3 Biyoteknoloji processing my special-category data on the Rebi platform (skin photos; skin type and concerns; pregnancy/cycle; lifestyle and active-ingredient tolerance and similar health-related information).",
  },
  {
    title: "2. Purpose",
    body: "I give explicit consent to A3 Biyoteknoloji processing my skin and health data and using Google Gemini AI infrastructure for routine and chat services. This is required to provide the service. Rebi is an AI assistant; its suggestions have a margin of error and are not medical diagnosis or treatment. Sharing precise location with a weather provider and storing skin photos privately are separate optional permissions.",
  },
  {
    title: "3. Sharing",
    body: "I consent to processing by A3 Biyoteknoloji and to transfers to hosting, database and AI infrastructure providers, limited to the purposes above.",
  },
  {
    title: "4. Voluntary and withdrawal",
    body: "I do not have to consent; without it I cannot open an account or use skin analysis/photo features. I may withdraw anytime by deleting my account in Profile or contacting the controller. Withdrawal does not make prior processing unlawful.",
  },
];

const TR_PRE = [
  {
    title: "1. Satıcı ve hizmet",
    body: `Satıcı: ${ID_TR}. Rebi Plus, satıcının sunduğu dijital aboneliktir. Kapsam: sınırsız sohbet, premium temalar ve Plus hesabına bağlı özellikler. Satıcıyla iletişim ${MAIL} adresi, uygulama içi Profil ekranı ve hesap e-postası üzerinden kurulur.`,
  },
  {
    title: "2. Bedel ve süre",
    body: "Fiyat, para birimi, vergi ve yenileme dönemi ödeme sayfasında, tahsilattan önce gösterilir. Bu form tutarı sabitlemez. Ödeme sayfası, aşağıdaki onaylar kayda geçmeden açılmaz.",
  },
  {
    title: "3. İfa",
    body: "Hizmet elektronik ortamda sunulur ve ödemenin onayından sonra hesaba tanımlanır.",
  },
  {
    title: "4. Cayma",
    body: "Tüketici, mesafeli dijital hizmetlerde mevzuattaki süre içinde cayma hakkını kullanabilir. Hizmetin derhal başlamasını ayrıca ister ve ifa başlarsa cayma hakkı ilgili istisna kapsamında sınırlanabilir.",
  },
  {
    title: "5. Başvuru",
    body: `Şikâyet ve talepler ${MAIL} adresine, Profil üzerinden veya hesap e-postasıyla iletilir. Cayma ve geri ödeme adımları Cayma ve İade Politikası’ndadır (rebiovil.com/iade). Uyuşmazlıklarda tüketici hakem heyetleri ve tüketici mahkemeleri yetkilidir.`,
  },
];

const EN_PRE = [
  {
    title: "1. Seller and service",
    body: `Seller: ${ID_EN}. Rebi Plus is a digital subscription offered by the seller. It covers unlimited chat, premium themes and features tied to a Plus account. Contact is through ${MAIL}, the in-app Profile screen and the account email.`,
  },
  {
    title: "2. Price and term",
    body: "Price, currency, tax and renewal period are shown on the payment page before any charge. This form does not fix the amount. The payment page does not open until the approvals below are recorded.",
  },
  {
    title: "3. Performance",
    body: "The service is provided electronically and is applied to the account after payment is confirmed.",
  },
  {
    title: "4. Withdrawal",
    body: "A consumer may withdraw from a distance contract for a digital service within the statutory period. If you separately ask the service to start immediately and performance begins, withdrawal may be limited under the applicable exception.",
  },
  {
    title: "5. Complaints",
    body: `Requests go to ${MAIL}, through Profile or the account email. Withdrawal and refund steps are in the Withdrawal and Refund Policy (rebiovil.com/iade). Consumer arbitration committees and consumer courts have jurisdiction over disputes.`,
  },
];

const TR_DISTANCE = [
  {
    title: "1. Taraflar",
    body: `Alıcı, Rebi hesabının sahibidir. Satıcı, Rebi’yi işleten şirkettir: ${ID_TR}. İletişim: ${MAIL}, uygulama içi Profil ve hesap e-postası.`,
  },
  {
    title: "2. Konu",
    body: "Konu, Rebi Plus dijital aboneliğinin satışı ve elektronik ortamda ifasıdır. Özellikler ön bilgilendirme formunda sayılır.",
  },
  {
    title: "3. Bedel",
    body: "Bedel, ödeme sayfasında tahsilattan önce açıklanan tutardır. Onaylar kayda geçmeden o sayfa açılmaz.",
  },
  {
    title: "4. Derhal başlama",
    body: "Alıcı, bu sözleşmeyi ön bilgilendirmeden ayrı onaylar ve dijital hizmetin ödeme onayından hemen sonra başlamasını talep eder. İfa başladığında cayma hakkı mevzuattaki istisnayla sınırlanabilir; aksi halde yasal cayma süresi geçerlidir.",
  },
  {
    title: "5. Kayıt",
    body: "Onay, ödeme sayfasına geçmeden önce satıcının kaydına yazılır. Hesap silindiğinde bu kayıt, diğer kişisel verilerle birlikte silinir.",
  },
];

const EN_DISTANCE = [
  {
    title: "1. Parties",
    body: `The buyer is the holder of the Rebi account. The seller is the company that operates Rebi: ${ID_EN}. Contact: ${MAIL}, the in-app Profile screen and the account email.`,
  },
  {
    title: "2. Subject",
    body: "The subject is the sale and electronic performance of the Rebi Plus digital subscription. Features are listed in the pre-contract information form.",
  },
  {
    title: "3. Price",
    body: "The price is the amount shown on the payment page before the charge. That page does not open until the approvals are recorded.",
  },
  {
    title: "4. Immediate start",
    body: "The buyer accepts this contract separately from the pre-contract information and asks the digital service to start as soon as payment is confirmed. Once performance begins, withdrawal may be limited by the statutory exception; otherwise the statutory withdrawal period applies.",
  },
  {
    title: "5. Record",
    body: "The approval is written to the seller’s record before the payment page opens. When the account is deleted, this record is deleted with the other personal data.",
  },
];

const TR_COOKIE = [
  {
    title: "1. Kısaca",
    body: "rebiovil.com kendi adına çerez (cookie) yerleştirmez. Oturumunuzu ve tercihlerinizi tarayıcınızın yerel depolama alanında (localStorage ve sessionStorage) tutar. Sitede analitik, reklam ya da izleme amaçlı çerez ve üçüncü taraf betiği yoktur.",
  },
  {
    title: "2. Zorunlu kayıtlar",
    body: "Giriş yaptığınızda oturum anahtarınız (kimlik doğrulama), KVKK ve açık rıza onayınızın kaydı, yapay zekâ bilgilendirmesini gördüğünüz bilgisi ve bu sayfanın altındaki bildirimi kapattığınız bilgisi tarayıcınızda saklanır. Bunlar hizmetin çalışması ve yasal kayıt için gereklidir (KVKK m.5/2-c, ç, f); ayrıca onay istenmez.",
  },
  {
    title: "3. Tercih ve işlev kayıtları",
    body: "Seçtiğiniz dil ve tema, bu cihazdaki sohbet geçmişiniz ve günlük mesaj sayacınız, rutin takibiniz, adım seçimleriniz ve check-in özetiniz yalnızca sizin eyleminizle oluşur ve yalnızca sizin cihazınızda durur. Amaçları, sayfayı yeniden açtığınızda kaldığınız yerden devam etmenizdir.",
  },
  {
    title: "4. Üçüncü taraf siteleri",
    body: "“Google ile devam et” seçeneğini kullanırsanız Google’ın giriş sayfasına yönlendirilirsiniz; orada Google’ın kendi çerez politikası geçerlidir. App Store ve Google Play bağlantıları ilgili mağazanın sitesini açar ve o sitenin politikasına tabidir.",
  },
  {
    title: "5. Kayıtları silmek",
    body: "Çıkış yaptığınızda oturum anahtarı silinir. Tarayıcınızın ayarlarından bu siteye ait verileri dilediğiniz zaman temizleyebilirsiniz; bu durumda yeniden giriş yapmanız gerekir. Hesabınızı sildiğinizde bu cihazdaki sohbet ve onay kayıtları da temizlenir.",
  },
  {
    title: "6. Değişiklik",
    body: `İleride analitik ya da pazarlama amaçlı bir çerez eklenirse önce bu politika güncellenir ve çerez yerleştirilmeden önce açık onayınız istenir. Sorularınız için: ${MAIL}.`,
  },
];

const EN_COOKIE = [
  {
    title: "1. In short",
    body: "rebiovil.com does not set cookies of its own. It keeps your session and preferences in your browser’s local storage (localStorage and sessionStorage). The site has no analytics, advertising or tracking cookies and no third-party scripts.",
  },
  {
    title: "2. Strictly necessary records",
    body: "When you sign in, your session key (authentication), the record of your privacy notice and explicit consent approvals, the fact that you have seen the AI notice, and the fact that you closed the notice at the bottom of the page are stored in your browser. These are required for the service to work and for legal record keeping (KVKK art. 5/2-c, ç, f); no separate consent is requested.",
  },
  {
    title: "3. Preference and function records",
    body: "Your chosen language and theme, the chat history and daily message counter on this device, your routine tracking, step choices and check-in summary are created only by your own actions and stay only on your device. They let you continue where you left off.",
  },
  {
    title: "4. Third-party sites",
    body: "If you use “Continue with Google”, you are sent to Google’s sign-in page, where Google’s own cookie policy applies. The App Store and Google Play links open the store’s own site under that site’s policy.",
  },
  {
    title: "5. Deleting records",
    body: "Signing out removes the session key. You can clear this site’s data from your browser settings at any time; you will then need to sign in again. Deleting your account also clears the chat and consent records on this device.",
  },
  {
    title: "6. Changes",
    body: `If an analytics or marketing cookie is ever added, this policy will be updated first and your explicit consent will be requested before any such cookie is set. Questions: ${MAIL}.`,
  },
];

const TR_PRIVACY = [
  {
    title: "1. Kapsam",
    body: `Bu politika rebiovil.com sitesi ile Rebi iOS ve Android uygulamaları için geçerlidir. Hizmeti işleten ve veri sorumlusu olan şirket: ${ID_TR}. İşleme amaçları, hukuki sebepler ve haklarınız ayrıntılı olarak KVKK Aydınlatma Metni’nde (rebiovil.com/kvkk) yer alır; bu sayfa aynı bilgilerin sade özetidir.`,
  },
  {
    title: "2. Topladığımız veriler",
    body: "Hesap için ad-soyad, e-posta ve şifre (yalnız hash olarak). Rutin için yaş, cinsiyet, cilt tipi, şikâyet ve yaşam tarzı cevaplarınız. Yazdığınız sohbet mesajları ve günlük check-in kayıtları. İzin verirseniz konumunuz (hava ve UV için) ve cilt fotoğraflarınız. Güvenlik için oturum ve cihaz/tarayıcı kayıtları.",
  },
  {
    title: "3. Neden topluyoruz",
    body: "Hesabınızı açmak ve korumak, size özel dermokozmetik bakım rutini ve sohbet yanıtı üretmek, havaya göre öneri ve hatırlatıcı sunmak, kötüye kullanımı önlemek ve hizmeti iyileştirmek için. Bu amaçlar için gerekmeyen veri istenmez; konum ve fotoğraf isteğe bağlıdır ve izin vermeden de hizmeti kullanabilirsiniz.",
  },
  {
    title: "4. Yapmadıklarımız",
    body: "Verilerinizi satmayız ve reklam amacıyla üçüncü kişilerle paylaşmayız. Sitede reklam veya izleme amaçlı çerez ve betik kullanmayız. Sitede ödeme kartı bilgisi toplamaz ve saklamayız. Cilt fotoğraflarınızı, e-posta adresinizi ve şifrenizi yapay zekâ sağlayıcısına göndermeyiz.",
  },
  {
    title: "5. Hizmet sağlayıcılar",
    body: "Supabase: barındırma, veritabanı, kimlik doğrulama ve özel fotoğraf deposu. Google Gemini API: yalnızca uygulama içinde ayrıca izin verdiğinizde, rutin ve sohbet yanıtı üretmek için. Open-Meteo (yedek olarak OpenWeather): konum izni verdiğinizde hava ve UV bilgisi için. Google Firebase Cloud Messaging: mobil uygulamada bildirim izni verdiğinizde bildirim iletimi için. Google ile giriş: yalnızca bu seçeneği kullanırsanız. PubMed ve Europe PMC: bilimsel kaynak araması için sorunuzun konusuna ait arama terimleri, hesabınıza ait kimlik bilgisi eklenmeden gönderilebilir. Bu sağlayıcıların bir kısmı yurt dışındadır; aktarımlarda KVKK usulleri uygulanır.",
  },
  {
    title: "6. Saklama ve silme",
    body: `Verileriniz hesabınız açık olduğu sürece saklanır; süreler KVKK Aydınlatma Metni’nin 6. bölümündedir. Hesabınızı Profil ekranından kalıcı olarak silebilirsiniz; profil, rutin, check-in, rıza kaydı ve fotoğraflar kaldırılır. Uygulamaya erişemiyorsanız hesap e-postanızdan ${MAIL} adresine “Hesap silme talebi” konulu bir e-posta göndermeniz yeterlidir.`,
  },
  {
    title: "7. Güvenlik",
    body: "Site ve uygulama ile sunucu arasındaki tüm bağlantılar şifrelidir (HTTPS/TLS). Şifreniz düz metin olarak saklanmaz. Veritabanında her kullanıcı yalnızca kendi kayıtlarına erişebilir; cilt fotoğrafları herkese açık olmayan, erişim kontrollü bir alanda tutulur.",
  },
  {
    title: "8. Çocuklar",
    body: "Rebi 13 yaşından küçükler için tasarlanmamıştır. 18 yaşından küçükseniz hizmeti velinizin veya vasinizin onayıyla kullanabilirsiniz.",
  },
  {
    title: "9. İzinleriniz ve haklarınız",
    body: `Konum, fotoğraf ve yapay zekâ izinlerini Profil ekranındaki gizlilik izinlerinden dilediğiniz zaman değiştirebilirsiniz. KVKK’nın 11. maddesindeki haklarınızı (bilgi alma, düzeltme, silme, itiraz) kullanmak için ${MAIL} adresine yazabilirsiniz.`,
  },
  {
    title: "10. Değişiklikler",
    body: "Bu politika değiştiğinde sayfanın başındaki tarih güncellenir. Veri işleme amacını değiştiren bir güncellemede yeniden onayınız istenir.",
  },
];

const EN_PRIVACY = [
  {
    title: "1. Scope",
    body: `This policy applies to rebiovil.com and to the Rebi iOS and Android apps. The company that operates the service and acts as data controller: ${ID_EN}. Purposes, legal bases and your rights are set out in full in the Privacy Notice (rebiovil.com/kvkk); this page is a plain summary of the same information.`,
  },
  {
    title: "2. Data we collect",
    body: "For your account: name, email and password (stored only as a hash). For your routine: age, gender, skin type, concerns and lifestyle answers. The chat messages you write and your daily check-ins. If you allow it, your location (for weather and UV) and your skin photos. For security: session and device/browser logs.",
  },
  {
    title: "3. Why we collect it",
    body: "To open and protect your account, to produce a personal dermocosmetic care routine and chat replies, to offer weather-aware suggestions and reminders, to prevent abuse and to improve the service. We do not ask for data these purposes do not need; location and photos are optional and you can use the service without them.",
  },
  {
    title: "4. What we do not do",
    body: "We do not sell your data and do not share it with third parties for advertising. We do not use advertising or tracking cookies or scripts on the site. We do not collect or store payment card details on the site. We do not send your skin photos, email address or password to the AI provider.",
  },
  {
    title: "5. Service providers",
    body: "Supabase: hosting, database, authentication and private photo storage. Google Gemini API: only after you give separate permission in the app, to produce routine and chat replies. Open-Meteo (OpenWeather as fallback): weather and UV information when you grant location permission. Google Firebase Cloud Messaging: notification delivery when you allow notifications in the mobile app. Google sign-in: only if you choose that option. PubMed and Europe PMC: search terms on the topic of your question may be sent for literature search, with no account identity attached. Some of these providers are outside Türkiye; transfers follow KVKK procedures.",
  },
  {
    title: "6. Retention and deletion",
    body: `Your data is kept while your account is open; periods are listed in section 6 of the Privacy Notice. You can permanently delete your account from the Profile screen; profile, routines, check-ins, consent records and photos are removed. If you cannot access the app, an email titled “Account deletion request” from your account address to ${MAIL} is enough.`,
  },
  {
    title: "7. Security",
    body: "All connections between the site or app and the server are encrypted (HTTPS/TLS). Your password is never stored in plain text. In the database each user can reach only their own records; skin photos are kept in a non-public, access-controlled area.",
  },
  {
    title: "8. Children",
    body: "Rebi is not designed for children under 13. If you are under 18, you may use the service with the approval of your parent or guardian.",
  },
  {
    title: "9. Your permissions and rights",
    body: `You can change location, photo and AI permissions at any time under privacy permissions on the Profile screen. To use your rights under KVKK article 11 (information, correction, erasure, objection), write to ${MAIL}.`,
  },
  {
    title: "10. Changes",
    body: "When this policy changes, the date at the top of the page is updated. If an update changes the purpose of processing, your approval is requested again.",
  },
];

const TR_TERMS = [
  {
    title: "1. Taraflar ve kabul",
    body: `Bu koşullar, rebiovil.com sitesi ile Rebi mobil uygulamalarını (“Rebi”) işleten ${NAME} ile hizmeti kullanan kişi arasındadır. Hesap açarak ya da hizmeti kullanarak bu koşulları kabul etmiş olursunuz.`,
  },
  {
    title: "2. Hizmet",
    body: "Rebi; cilt tipinizi, şikâyetlerinizi, yaşam tarzınızı ve o günün havasını birlikte değerlendirerek dermokozmetik bakım rutini önerir, sorularınıza yapay zekâ destekli sohbetle yanıt verir ve günlük takibinizi tutar. Hizmet web sitesi ve mobil uygulamalar üzerinden, aynı hesapla sunulur.",
  },
  {
    title: "3. Tıbbi hizmet değildir",
    body: "Rebi bir yapay zekâ asistanıdır; öneriler hata payı içerir ve tıbbi teşhis veya tedavi yerine geçmez. Öneriler kozmetik bakım ve günlük düzen içindir. Ciddi, ani ya da süren cilt sorunlarında, hamilelikte ve ilaç kullanırken bir dermatoloğa ya da hekime danışın.",
  },
  {
    title: "4. Hesap",
    body: "Hesap açarken doğru bilgi vermeniz ve şifrenizi gizli tutmanız gerekir; hesabınızla yapılan işlemlerden siz sorumlusunuz. Rebi 13 yaşından küçükler için değildir; 18 yaşından küçükseniz hizmeti velinizin veya vasinizin onayıyla kullanabilirsiniz.",
  },
  {
    title: "5. Kabul edilebilir kullanım",
    body: "Hizmeti hukuka aykırı amaçla kullanmak, başkasına ait kişisel veriyi ya da fotoğrafı yüklemek, otomatik araçlarla toplu sorgu göndermek, sistemi zorlamak, güvenlik önlemlerini aşmaya çalışmak ve yazılımı tersine çözmek yasaktır. Bu kurallar ihlal edilirse hesap askıya alınabilir ya da kapatılabilir.",
  },
  {
    title: "6. Ücretsiz kullanım ve Rebi Plus",
    body: "Temel analiz ve rutin ücretsizdir; ücretsiz sohbette günlük mesaj sınırı vardır. Rebi Plus ücretli bir dijital aboneliktir. Fiyat, dönem ve vergiler ödeme adımından önce açıkça gösterilir; gösterilen tutar dışında bir ücret alınmaz. Satın alımlarda Ön Bilgilendirme Formu, Mesafeli Satış Sözleşmesi ve Cayma ve İade Politikası uygulanır.",
  },
  {
    title: "7. Öneriler hakkında",
    body: "Rutin önerileri marka değil madde odaklıdır. Öneriler bir sonuç garantisi vermez; cildin vereceği yanıt kişiden kişiye değişir. Bir üründe tahriş, yanma ya da alerji belirtisi görürseniz kullanmayı bırakın.",
  },
  {
    title: "8. Fikri mülkiyet",
    body: `Rebi adı, logosu, yazılımı, tasarımı ve içerikleri ${NAME}’ye aittir; yazılı izin olmadan kopyalanamaz ve ticari amaçla kullanılamaz. Sizin girdiğiniz bilgi ve fotoğraflar size aittir; yalnızca size hizmet sunmak için işlenir.`,
  },
  {
    title: "9. Sorumluluk",
    body: "Hizmetin kesintisiz ve hatasız çalışacağı garanti edilmez; bakım ve güncelleme için hizmet geçici olarak durdurulabilir. Tüketici mevzuatından doğan haklarınız saklıdır; bu koşullar o hakları sınırlamaz.",
  },
  {
    title: "10. Sona erme",
    body: "Hesabınızı Profil ekranından dilediğiniz zaman kalıcı olarak silebilirsiniz. Bu koşulların ağır ihlalinde hesap, bildirimle kapatılabilir.",
  },
  {
    title: "11. Değişiklik",
    body: "Koşullar güncellendiğinde sayfanın başındaki tarih değişir. Haklarınızı etkileyen değişiklikler yürürlüğe girmeden önce site ya da uygulama içinde duyurulur.",
  },
  {
    title: "12. Uygulanacak hukuk ve iletişim",
    body: `Bu koşullara Türkiye Cumhuriyeti hukuku uygulanır. Tüketici uyuşmazlıklarında tüketici hakem heyetleri ve tüketici mahkemeleri yetkilidir. İletişim: ${MAIL}.`,
  },
];

const EN_TERMS = [
  {
    title: "1. Parties and acceptance",
    body: `These terms are between ${NAME}, which operates rebiovil.com and the Rebi mobile apps (“Rebi”), and the person using the service. By creating an account or using the service you accept these terms.`,
  },
  {
    title: "2. The service",
    body: "Rebi looks at your skin type, concerns, lifestyle and the day’s weather together to suggest a dermocosmetic care routine, answers your questions through AI-assisted chat and keeps your daily tracking. The service is offered on the website and in the mobile apps with the same account.",
  },
  {
    title: "3. Not a medical service",
    body: "Rebi is an AI assistant; its suggestions have a margin of error and are not a medical diagnosis or treatment. Suggestions are for cosmetic care and daily habits. For serious, sudden or persistent skin problems, during pregnancy and while taking medication, consult a dermatologist or physician.",
  },
  {
    title: "4. Account",
    body: "You must give accurate information when creating an account and keep your password confidential; you are responsible for activity on your account. Rebi is not for children under 13; if you are under 18, you may use the service with the approval of your parent or guardian.",
  },
  {
    title: "5. Acceptable use",
    body: "You may not use the service for unlawful purposes, upload another person’s personal data or photo, send bulk queries with automated tools, overload the system, try to bypass security measures or reverse engineer the software. If these rules are broken, the account may be suspended or closed.",
  },
  {
    title: "6. Free use and Rebi Plus",
    body: "Core analysis and the routine are free; free chat has a daily message limit. Rebi Plus is a paid digital subscription. Price, term and taxes are shown clearly before the payment step; nothing is charged beyond the amount shown. Purchases are subject to the Pre-contract Information Form, the Distance Sales Contract and the Withdrawal and Refund Policy.",
  },
  {
    title: "7. About the suggestions",
    body: "Routine suggestions focus on ingredients, not brands. They do not guarantee a result; how skin responds differs from person to person. If a product causes irritation, burning or signs of allergy, stop using it.",
  },
  {
    title: "8. Intellectual property",
    body: `The Rebi name, logo, software, design and content belong to ${NAME}; they may not be copied or used commercially without written permission. The information and photos you enter belong to you and are processed only to provide the service to you.`,
  },
  {
    title: "9. Liability",
    body: "The service is not guaranteed to run without interruption or error; it may be paused temporarily for maintenance and updates. Your rights under consumer law are reserved; these terms do not limit them.",
  },
  {
    title: "10. Termination",
    body: "You can permanently delete your account from the Profile screen at any time. In case of a serious breach of these terms, the account may be closed with notice.",
  },
  {
    title: "11. Changes",
    body: "When the terms are updated, the date at the top of the page changes. Changes that affect your rights are announced on the site or in the app before they take effect.",
  },
  {
    title: "12. Governing law and contact",
    body: `These terms are governed by the laws of the Republic of Türkiye. Consumer arbitration committees and consumer courts have jurisdiction over consumer disputes. Contact: ${MAIL}.`,
  },
];

const TR_REFUND = [
  {
    title: "1. Kapsam",
    body: "Bu politika Rebi Plus dijital aboneliği için geçerlidir. Temel analiz ve rutin ücretsizdir; ücretsiz kullanımda ödeme alınmaz.",
  },
  {
    title: "2. 14 gün cayma hakkı",
    body: "Satın alma tarihinden itibaren 14 gün içinde, gerekçe göstermeden ve cezai şart ödemeden sözleşmeden cayabilirsiniz.",
  },
  {
    title: "3. Derhal başlayan hizmet",
    body: "Satın alırken Mesafeli Satış Sözleşmesi’nde hizmetin ödeme onayından hemen sonra başlamasını ayrıca talep edersiniz. İfa başladığında cayma hakkı, mevzuatta anında ifa edilen dijital hizmetler için öngörülen istisnayla sınırlanabilir; aksi halde 14 günlük süre geçerlidir.",
  },
  {
    title: "4. Nasıl başvurulur",
    body: `Hesabınıza kayıtlı e-posta adresinden ${MAIL} adresine “Cayma talebi” konulu bir e-posta gönderin; satın alma tarihini yazmanız yeterlidir. Talebinizin ulaştığı size e-postayla bildirilir.`,
  },
  {
    title: "5. Geri ödeme",
    body: "Cayma bildiriminiz ulaştıktan sonra en geç 14 gün içinde, ödediğiniz tutar ödemede kullandığınız araca, sizden masraf alınmadan iade edilir.",
  },
  {
    title: "6. Aboneliği sona erdirme",
    body: `Aboneliğinizi dilediğiniz zaman sona erdirme hakkınız vardır; talebinizi aynı adrese (${MAIL}) iletebilirsiniz.`,
  },
  {
    title: "7. Uyuşmazlık",
    body: "Talebiniz sonuçlanmazsa yerleşim yerinizdeki tüketici hakem heyetine ya da tüketici mahkemesine başvurabilirsiniz.",
  },
];

const EN_REFUND = [
  {
    title: "1. Scope",
    body: "This policy applies to the Rebi Plus digital subscription. Core analysis and the routine are free; no payment is taken for free use.",
  },
  {
    title: "2. 14-day right of withdrawal",
    body: "You may withdraw from the contract within 14 days of purchase, without giving a reason and without paying a penalty.",
  },
  {
    title: "3. Service that starts immediately",
    body: "At purchase, in the Distance Sales Contract, you separately ask the service to start as soon as payment is confirmed. Once performance begins, the right of withdrawal may be limited by the statutory exception for digital services performed instantly; otherwise the 14-day period applies.",
  },
  {
    title: "4. How to apply",
    body: `Send an email titled “Withdrawal request” from the address registered to your account to ${MAIL}; stating the purchase date is enough. You will be told by email that your request has arrived.`,
  },
  {
    title: "5. Refund",
    body: "Within 14 days at the latest after your withdrawal notice arrives, the amount you paid is returned to the payment method you used, at no cost to you.",
  },
  {
    title: "6. Ending the subscription",
    body: `You have the right to end your subscription at any time; send your request to the same address (${MAIL}).`,
  },
  {
    title: "7. Disputes",
    body: "If your request is not resolved, you may apply to the consumer arbitration committee or consumer court where you live.",
  },
];

/** Künye: her dolu alan bir bölüm olarak gösterilir. */
function companySections(en) {
  return companyRows(en).map(([title, body]) => ({ title, body }));
}

export function legalSections(kind, lang) {
  const en = String(lang || "").toLowerCase().startsWith("en");
  if (kind === "riza") return en ? EN_RIZA : TR_RIZA;
  if (kind === "onbilgi") return en ? EN_PRE : TR_PRE;
  if (kind === "mesafeli") return en ? EN_DISTANCE : TR_DISTANCE;
  if (kind === "cerez") return en ? EN_COOKIE : TR_COOKIE;
  if (kind === "gizlilik") return en ? EN_PRIVACY : TR_PRIVACY;
  if (kind === "kosullar") return en ? EN_TERMS : TR_TERMS;
  if (kind === "iade") return en ? EN_REFUND : TR_REFUND;
  if (kind === "sirket") return companySections(en);
  return en ? EN_KVKK : TR_KVKK;
}
