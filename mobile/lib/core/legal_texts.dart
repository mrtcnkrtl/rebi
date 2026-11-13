/// KVKK aydınlatma ve açık rıza gövdeleri. Dil: tr | en
/// Kaynak: `frontend/src/lib/legalTexts.js` — metin değişirse ikisini birlikte güncelleyin;
/// `test/legal_texts_sync_test.dart` farkı yakalar.
library;

const legalUpdated = '04.11.2026';

class LegalSection {
  const LegalSection(this.title, this.body);

  final String title;
  final String body;
}

const _trKvkk = [
  LegalSection(
    '1. Veri sorumlusu',
    'Bu aydınlatma metni, 6698 sayılı Kişisel Verilerin Korunması Kanunu (“KVKK”) kapsamında Rebi cilt bakımı platformunun (“Rebi”) kullanıcılarına yöneliktir. Veri sorumlusu, Rebi’yi işleten A3 Biyoteknoloji’dir. Başvurularınızı uygulama içi Profil ekranı ve hesap e-postanız üzerinden iletebilirsiniz.',
  ),
  LegalSection(
    '2. İşlenen kişisel veriler',
    'Hesap: ad-soyad, e-posta, şifre (hash). Profil ve rutin: yaş, cinsiyet, cilt tipi, şikâyet, şiddet, yaşam tarzı (uyku, stres, su, sigara, alkol), makyaj alışkanlığı, hamilelik/döngü bilgisi, aktif madde deneyimi ve tolerans. İsteğe bağlı cilt fotoğrafları. Konum (hava/UV için enlem-boylam). Sohbet mesajları, check-in kayıtları, rutin ve analiz çıktıları. Teknik: oturum, dil tercihi, cihaz/ tarayıcı kayıtları.',
  ),
  LegalSection(
    '3. İşleme amaçları ve hukuki sebepler',
    'Hesap açmak, kimlik doğrulamak ve sözleşmeyi ifa etmek (KVKK m.5/2-c). Kişiselleştirilmiş rutin, check-in ve sohbet sunmak. Güvenlik, kötüye kullanımın önlenmesi ve yasal yükümlülükler (m.5/2-ç, f). İyileştirme ve hata ayıklama. Cilt görüntüsü, sağlık belirtisi, hamilelik gibi özel nitelikli veriler ancak açık rızanızla işlenir (KVKK m.6).',
  ),
  LegalSection(
    '4. Aktarım',
    'Rutin ve sohbet için yapay zekâ işlemesi A3 Biyoteknoloji tarafından, Google Gemini AI altyapısı kullanılarak gerçekleştirilir. Barındırma ve veritabanı için veriler Supabase’e aktarılabilir. Konum izni verirseniz kesin koordinatlar Open-Meteo’ya (yedek olarak OpenWeather’a) iletilir. Fotoğraf izni verirseniz görüntüler private Supabase Storage alanında saklanır. Zorunlu hallerde yetkili kamu kurumlarına aktarım yapılabilir; yurt dışı aktarımlarda KVKK usulleri uygulanır.',
  ),
  LegalSection(
    '5. Üçüncü taraf yapay zekâ hizmeti (Google Gemini)',
    'Rutin oluşturma, check-in yorumu, rutin çevirisi ve sohbet yanıtları için aşağıdaki veriler, uygulama içinde ayrıca izin vermenizden sonra Google LLC’nin Gemini API hizmetine şifreli bağlantıyla gönderilir: ad, yaş ve cinsiyet; cilt tipi, şikâyet ve analiz cevapları; hamilelik/döngü, sigara, alkol, uyku, stres ve su tüketimi gibi sağlık ve yaşam tarzı bilgileri; günlük check-in kayıtları ve rutindeki ürünler; sohbet mesajları; konum izni verdiyseniz bölgenizin hava ve UV bilgisi. Cilt fotoğrafları, e-posta adresi ve şifre Gemini’ye gönderilmez. Veriler yalnızca size yanıt üretmek amacıyla kullanılır; Google, ücretli Gemini API koşulları gereği bu verileri kendi modellerini eğitmek için kullanmaz ve veri işleme şartları kapsamında en az bu metinde açıklanan düzeyde koruma sağlar. Bu izni uygulamada Hesap > Gizlilik izinleri bölümünden istediğiniz zaman geri alabilirsiniz; bu durumda yapay zekâ özellikleri çalışmaz, diğer özellikler kullanılmaya devam edilebilir.',
  ),
  LegalSection(
    '6. Saklama süresi',
    'Aktif profil ve rutin hesabınız açık olduğu sürece saklanır. Giriş sunumu IP hash’i 180 gün, günlük mikro olaylar 400 gün; günlük check-in ile kullanılmayan geçmiş rutin/değerlendirme kayıtları en fazla 730 gün tutulur. Cilt fotoğrafları siz silene veya hesabınızı kapatana kadar saklanır. Hesabı sildiğinizde profil, rutin, check-in, rıza kaydı ve fotoğraflar kaldırılır; kanunen zorunlu kayıtlar ilgili süre boyunca ayrıca tutulabilir.',
  ),
  LegalSection(
    '7. Haklarınız (KVKK m.11)',
    'Verilerinizin işlenip işlenmediğini öğrenme, bilgi talep etme, amaca uygunluğu öğrenme, yurt içinde/dışında aktarılan üçüncü kişileri bilme, düzeltilmesini isteme, silinmesini/yok edilmesini isteme, itiraz ve zararın giderilmesini talep etme haklarınız vardır. Başvurularınız makul sürede yanıtlanır.',
  ),
  LegalSection(
    '8. Çerez ve yerel depolama',
    'Oturum, dil, rutin takibi ve bu metinlere verdiğiniz onay tarayıcınızda (ör. localStorage) tutulabilir. Zorunlu olanlar hizmetin çalışması içindir.',
  ),
];

const _enKvkk = [
  LegalSection(
    '1. Data controller',
    'This notice is provided under Türkiye’s Personal Data Protection Law No. 6698 (KVKK) for the Rebi skincare platform. The controller is A3 Biyoteknoloji, which operates Rebi. You can reach us via the in-app Profile screen and your account email.',
  ),
  LegalSection(
    '2. Data we process',
    'Account: name, email, password (hashed). Profile and routine: age, gender, skin type, concerns, severity, lifestyle (sleep, stress, water, smoking, alcohol), makeup habits, pregnancy/cycle information, active-ingredient experience and tolerance. Optional skin photos. Location (lat/lon for weather/UV). Chat messages, check-ins, routine and analysis outputs. Technical: session, language, device/browser logs.',
  ),
  LegalSection(
    '3. Purposes and legal bases',
    'Creating an account, authentication and performing the service (KVKK art. 5/2-c). Personalized routines, check-in and chat. Security, abuse prevention and legal duties (art. 5/2-ç, f). Product improvement. Skin images, health-related symptoms and pregnancy data are special-category data and are processed only with your explicit consent (KVKK art. 6).',
  ),
  LegalSection(
    '4. Recipients',
    'AI processing for routines and chat is performed by A3 Biyoteknoloji using Google Gemini AI infrastructure. Data may also be shared with Supabase for hosting and database services. If location permission is granted, precise coordinates are sent to Open-Meteo (or OpenWeather as fallback). If photo permission is granted, images are stored in private Supabase Storage. Transfers abroad follow applicable KVKK procedures.',
  ),
  LegalSection(
    '5. Third-party AI service (Google Gemini)',
    'For routine creation, check-in insights, routine translation and chat replies, the following data is sent over an encrypted connection to Google LLC’s Gemini API, only after you give separate permission in the app: name, age and gender; skin type, concerns and analysis answers; health and lifestyle information such as pregnancy/cycle, smoking, alcohol, sleep, stress and water intake; daily check-ins and the products in your routine; chat messages; and, if you granted location permission, weather and UV information for your area. Skin photos, email address and password are never sent to Gemini. The data is used only to generate responses for you; under the paid Gemini API terms Google does not use it to train its models, and under its data processing terms provides protection at least equal to that described in this notice. You can withdraw this permission at any time in Account > Privacy permissions in the app; AI features will then stop working while other features remain available.',
  ),
  LegalSection(
    '6. Retention',
    'Active profiles and routines are kept while the account remains open. Intro IP hashes are retained for 180 days, daily events for 400 days, and check-ins plus unused historical routines/assessments for up to 730 days. Skin photos remain until you delete them or close the account. Account deletion removes profile, routines, check-ins, consent evidence and photos; legally required records may be retained for the applicable period.',
  ),
  LegalSection(
    '7. Your rights (KVKK art. 11)',
    'You may learn whether your data is processed, request information, learn the purpose, know third-party recipients, request correction, erasure/destruction, object, and claim damages. We respond within a reasonable time.',
  ),
  LegalSection(
    '8. Cookies and local storage',
    'Session, language, routine tracking and this consent may be stored in your browser (e.g. localStorage). Strictly necessary items are required for the service to work.',
  ),
];

const _trRiza = [
  LegalSection(
    '1. Konu',
    '6698 sayılı KVKK’nın 6. maddesi uyarınca, özel nitelikli kişisel verilerimin (cilt görüntüsü; cilt tipi ve şikâyetler; hamilelik/döngü; yaşam tarzı ve aktif madde toleransı gibi sağlıkla ilgili bilgiler) A3 Biyoteknoloji tarafından Rebi platformu kapsamında işlenmesine açık rıza veriyorum.',
  ),
  LegalSection(
    '2. Amaç',
    'Cilt ve sağlık verilerimin A3 Biyoteknoloji tarafından işlenmesine ve rutin/sohbet hizmeti için Google Gemini AI altyapısının kullanılmasına açık rıza veriyorum. Bu, hizmetin sunulması için gereklidir. Rebi bir yapay zekâ asistanıdır; öneriler hata payı içerir ve tıbbi teşhis veya tedavi yerine geçmez. Kesin konumun hava servisine aktarılması ve cilt fotoğrafının private alanda saklanması ayrı ve isteğe bağlı izinlerdir.',
  ),
  LegalSection(
    '3. Aktarım',
    'Yukarıdaki amaçlarla sınırlı olmak üzere verilerimin A3 Biyoteknoloji tarafından işlenmesine ve barındırma, veritabanı ile yapay zekâ altyapı sağlayıcılarına aktarılmasına rıza gösteriyorum.',
  ),
  LegalSection(
    '4. Gönüllülük ve geri alma',
    'Rıza vermek zorunda değilim; vermezsem hesap açılamaz veya cilt analizi/fotoğraf özellikleri kullanılamaz. Rızamı dilediğim zaman Profil üzerinden hesabımı silerek veya veri sorumlusuyla iletişime geçerek geri alabilirim. Geri alma, geri alma anına kadar yapılan işlemi hukuka aykırı kılmaz.',
  ),
];

const _enRiza = [
  LegalSection(
    '1. Subject',
    'Under KVKK article 6, I give explicit consent to A3 Biyoteknoloji processing my special-category data on the Rebi platform (skin photos; skin type and concerns; pregnancy/cycle; lifestyle and active-ingredient tolerance and similar health-related information).',
  ),
  LegalSection(
    '2. Purpose',
    'I give explicit consent to A3 Biyoteknoloji processing my skin and health data and using Google Gemini AI infrastructure for routine and chat services. This is required to provide the service. Rebi is an AI assistant; its suggestions have a margin of error and are not medical diagnosis or treatment. Sharing precise location with a weather provider and storing skin photos privately are separate optional permissions.',
  ),
  LegalSection(
    '3. Sharing',
    'I consent to processing by A3 Biyoteknoloji and to transfers to hosting, database and AI infrastructure providers, limited to the purposes above.',
  ),
  LegalSection(
    '4. Voluntary and withdrawal',
    'I do not have to consent; without it I cannot open an account or use skin analysis/photo features. I may withdraw anytime by deleting my account in Profile or contacting the controller. Withdrawal does not make prior processing unlawful.',
  ),
];

const _trPre = [
  LegalSection(
    '1. Satıcı ve hizmet',
    'Rebi Plus, Rebi’yi işleten A3 Biyoteknoloji’nin sunduğu dijital aboneliktir. Kapsam: sınırsız sohbet, premium temalar ve Plus hesabına bağlı özellikler. Satıcıyla iletişim uygulama içi Profil ekranı ve hesap e-postası üzerinden kurulur.',
  ),
  LegalSection(
    '2. Bedel ve süre',
    'Fiyat, para birimi, vergi ve yenileme dönemi ödeme sayfasında, tahsilattan önce gösterilir. Bu form tutarı sabitlemez. Ödeme sayfası, aşağıdaki onaylar kayda geçmeden açılmaz.',
  ),
  LegalSection(
    '3. İfa',
    'Hizmet elektronik ortamda sunulur ve ödemenin onayından sonra hesaba tanımlanır.',
  ),
  LegalSection(
    '4. Cayma',
    'Tüketici, mesafeli dijital hizmetlerde mevzuattaki süre içinde cayma hakkını kullanabilir. Hizmetin derhal başlamasını ayrıca ister ve ifa başlarsa cayma hakkı ilgili istisna kapsamında sınırlanabilir.',
  ),
  LegalSection(
    '5. Başvuru',
    'Şikâyet ve talepler Profil üzerinden veya hesap e-postasıyla iletilir. Uyuşmazlıklarda tüketici hakem heyetleri ve tüketici mahkemeleri yetkilidir.',
  ),
];

const _enPre = [
  LegalSection(
    '1. Seller and service',
    'Rebi Plus is a digital subscription from A3 Biyoteknoloji, which operates Rebi. It covers unlimited chat, premium themes and features tied to a Plus account. Contact is through the in-app Profile screen and the account email.',
  ),
  LegalSection(
    '2. Price and term',
    'Price, currency, tax and renewal period are shown on the payment page before any charge. This form does not fix the amount. The payment page does not open until the approvals below are recorded.',
  ),
  LegalSection(
    '3. Performance',
    'The service is provided electronically and is applied to the account after payment is confirmed.',
  ),
  LegalSection(
    '4. Withdrawal',
    'A consumer may withdraw from a distance contract for a digital service within the statutory period. If you separately ask the service to start immediately and performance begins, withdrawal may be limited under the applicable exception.',
  ),
  LegalSection(
    '5. Complaints',
    'Requests go through Profile or the account email. Consumer arbitration committees and consumer courts have jurisdiction over disputes.',
  ),
];

const _trDistance = [
  LegalSection(
    '1. Taraflar',
    'Alıcı, Rebi hesabının sahibidir. Satıcı, Rebi’yi işleten A3 Biyoteknoloji’dir. İletişim: uygulama içi Profil ve hesap e-postası.',
  ),
  LegalSection(
    '2. Konu',
    'Konu, Rebi Plus dijital aboneliğinin satışı ve elektronik ortamda ifasıdır. Özellikler ön bilgilendirme formunda sayılır.',
  ),
  LegalSection(
    '3. Bedel',
    'Bedel, ödeme sayfasında tahsilattan önce açıklanan tutardır. Onaylar kayda geçmeden o sayfa açılmaz.',
  ),
  LegalSection(
    '4. Derhal başlama',
    'Alıcı, bu sözleşmeyi ön bilgilendirmeden ayrı onaylar ve dijital hizmetin ödeme onayından hemen sonra başlamasını talep eder. İfa başladığında cayma hakkı mevzuattaki istisnayla sınırlanabilir; aksi halde yasal cayma süresi geçerlidir.',
  ),
  LegalSection(
    '5. Kayıt',
    'Onay, ödeme sayfasına geçmeden önce satıcının kaydına yazılır. Hesap silindiğinde bu kayıt, diğer kişisel verilerle birlikte silinir.',
  ),
];

const _enDistance = [
  LegalSection(
    '1. Parties',
    'The buyer is the holder of the Rebi account. The seller is A3 Biyoteknoloji, which operates Rebi. Contact is the in-app Profile screen and the account email.',
  ),
  LegalSection(
    '2. Subject',
    'The subject is the sale and electronic performance of the Rebi Plus digital subscription. Features are listed in the pre-contract information form.',
  ),
  LegalSection(
    '3. Price',
    'The price is the amount shown on the payment page before the charge. That page does not open until the approvals are recorded.',
  ),
  LegalSection(
    '4. Immediate start',
    'The buyer accepts this contract separately from the pre-contract information and asks the digital service to start as soon as payment is confirmed. Once performance begins, withdrawal may be limited by the statutory exception; otherwise the statutory withdrawal period applies.',
  ),
  LegalSection(
    '5. Record',
    'The approval is written to the seller’s record before the payment page opens. When the account is deleted, this record is deleted with the other personal data.',
  ),
];

List<LegalSection> legalSections(String kind, String lang) {
  final en = lang.toLowerCase().startsWith('en');
  if (kind == 'riza') return en ? _enRiza : _trRiza;
  if (kind == 'onbilgi') return en ? _enPre : _trPre;
  if (kind == 'mesafeli') return en ? _enDistance : _trDistance;
  return en ? _enKvkk : _trKvkk;
}
