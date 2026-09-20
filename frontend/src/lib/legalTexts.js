/** KVKK aydınlatma ve açık rıza gövdeleri. Dil: tr | en */

export const LEGAL_UPDATED = "20.09.2026";

const TR_KVKK = [
  {
    title: "1. Veri sorumlusu",
    body: "Bu aydınlatma metni, 6698 sayılı Kişisel Verilerin Korunması Kanunu (“KVKK”) kapsamında Rebi cilt bakımı platformunun (“Rebi”) kullanıcılarına yöneliktir. Veri sorumlusu, Rebi’yi işleten A3 Biyoteknoloji’dir. Başvurularınızı uygulama içi Profil ekranı ve hesap e-postanız üzerinden iletebilirsiniz.",
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
    body: "Rutin ve sohbet için yapay zekâ işlemesi A3 Biyoteknoloji tarafından, Google Gemini AI altyapısı kullanılarak gerçekleştirilir. Barındırma ve veritabanı için veriler Supabase’e aktarılabilir. Konum izni verirseniz kesin koordinatlar Open-Meteo’ya (yedek olarak OpenWeather’a) iletilir. Fotoğraf izni verirseniz görüntüler private Supabase Storage alanında saklanır. Zorunlu hallerde yetkili kamu kurumlarına aktarım yapılabilir; yurt dışı aktarımlarda KVKK usulleri uygulanır.",
  },
  {
    title: "5. Saklama süresi",
    body: "Aktif profil ve rutin hesabınız açık olduğu sürece saklanır. Giriş sunumu IP hash’i 180 gün, günlük mikro olaylar 400 gün; günlük check-in ile kullanılmayan geçmiş rutin/değerlendirme kayıtları en fazla 730 gün tutulur. Cilt fotoğrafları siz silene veya hesabınızı kapatana kadar saklanır. Hesabı sildiğinizde profil, rutin, check-in, rıza kaydı ve fotoğraflar kaldırılır; kanunen zorunlu kayıtlar ilgili süre boyunca ayrıca tutulabilir.",
  },
  {
    title: "6. Haklarınız (KVKK m.11)",
    body: "Verilerinizin işlenip işlenmediğini öğrenme, bilgi talep etme, amaca uygunluğu öğrenme, yurt içinde/dışında aktarılan üçüncü kişileri bilme, düzeltilmesini isteme, silinmesini/yok edilmesini isteme, itiraz ve zararın giderilmesini talep etme haklarınız vardır. Başvurularınız makul sürede yanıtlanır.",
  },
  {
    title: "7. Çerez ve yerel depolama",
    body: "Oturum, dil, rutin takibi ve bu metinlere verdiğiniz onay tarayıcınızda (ör. localStorage) tutulabilir. Zorunlu olanlar hizmetin çalışması içindir.",
  },
];

const EN_KVKK = [
  {
    title: "1. Data controller",
    body: "This notice is provided under Türkiye’s Personal Data Protection Law No. 6698 (KVKK) for the Rebi skincare platform. The controller is A3 Biyoteknoloji, which operates Rebi. You can reach us via the in-app Profile screen and your account email.",
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
    body: "AI processing for routines and chat is performed by A3 Biyoteknoloji using Google Gemini AI infrastructure. Data may also be shared with Supabase for hosting and database services. If location permission is granted, precise coordinates are sent to Open-Meteo (or OpenWeather as fallback). If photo permission is granted, images are stored in private Supabase Storage. Transfers abroad follow applicable KVKK procedures.",
  },
  {
    title: "5. Retention",
    body: "Active profiles and routines are kept while the account remains open. Intro IP hashes are retained for 180 days, daily events for 400 days, and check-ins plus unused historical routines/assessments for up to 730 days. Skin photos remain until you delete them or close the account. Account deletion removes profile, routines, check-ins, consent evidence and photos; legally required records may be retained for the applicable period.",
  },
  {
    title: "6. Your rights (KVKK art. 11)",
    body: "You may learn whether your data is processed, request information, learn the purpose, know third-party recipients, request correction, erasure/destruction, object, and claim damages. We respond within a reasonable time.",
  },
  {
    title: "7. Cookies and local storage",
    body: "Session, language, routine tracking and this consent may be stored in your browser (e.g. localStorage). Strictly necessary items are required for the service to work.",
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

export function legalSections(kind, lang) {
  const en = String(lang || "").toLowerCase().startsWith("en");
  if (kind === "riza") return en ? EN_RIZA : TR_RIZA;
  return en ? EN_KVKK : TR_KVKK;
}
