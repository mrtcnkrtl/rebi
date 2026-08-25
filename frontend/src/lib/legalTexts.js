/** KVKK aydınlatma ve açık rıza gövdeleri. Dil: tr | en */

export const LEGAL_UPDATED = "25.08.2026";

const TR_KVKK = [
  {
    title: "1. Veri sorumlusu",
    body: "Bu aydınlatma metni, 6698 sayılı Kişisel Verilerin Korunması Kanunu (“KVKK”) kapsamında Rebi cilt bakımı platformunun (“Rebi”) kullanıcılarına yöneliktir. Veri sorumlusu, Rebi’yi işleten gerçek veya tüzel kişidir. Başvurularınızı uygulama içi Profil ekranı ve hesap e-postanız üzerinden iletebilirsiniz.",
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
    body: "Veriler, hizmeti sunmak için barındırma ve veritabanı sağlayıcılarına (ör. bulut altyapısı / Supabase), sohbet ve analiz için yapay zekâ işlemcilerine ve zorunlu hallerde yetkili kamu kurumlarına aktarılabilir. Yurt dışı aktarım varsa KVKK’daki usuller uygulanır.",
  },
  {
    title: "5. Saklama süresi",
    body: "Hesabınız aktifken işleme amacı sürdüğü müddetçe saklanır. Hesabı sildiğinizde profil, rutin, check-in ve fotoğraflar silinir veya anonimleştirilir; yasal saklama zorunluluğu olan kayıtlar ilgili süre kadar tutulabilir.",
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
    body: "This notice is provided under Türkiye’s Personal Data Protection Law No. 6698 (KVKK) for the Rebi skincare platform. The controller is the person or entity operating Rebi. You can reach us via the in-app Profile screen and your account email.",
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
    body: "Data may be shared with hosting/database providers (e.g. cloud / Supabase), AI processors used for chat and analysis, and competent authorities where required. Any transfer abroad follows KVKK procedures.",
  },
  {
    title: "5. Retention",
    body: "Kept while your account is active and the purpose continues. Deleting your account removes or anonymizes profile, routines, check-ins and photos; records we must keep by law may be retained for the required period.",
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
    body: "6698 sayılı KVKK’nın 6. maddesi uyarınca, özel nitelikli kişisel verilerimin (cilt görüntüsü; cilt tipi ve şikâyetler; hamilelik/döngü; yaşam tarzı ve aktif madde toleransı gibi sağlıkla ilgili bilgiler) Rebi tarafından işlenmesine açık rıza veriyorum.",
  },
  {
    title: "2. Amaç",
    body: "Bu rıza; hesabımın oluşturulması, kişiselleştirilmiş bakım rutini, günlük check-in, sohbet yanıtları, isteğe bağlı fotoğraf karşılaştırması ve hava/UV notları için gereklidir. Rebi tıbbi teşhis veya tedavi sunmaz.",
  },
  {
    title: "3. Aktarım",
    body: "Yukarıdaki amaçlarla sınırlı olmak üzere verilerimin barındırma, veritabanı ve yapay zekâ hizmet sağlayıcılarına aktarılmasına rıza gösteriyorum.",
  },
  {
    title: "4. Gönüllülük ve geri alma",
    body: "Rıza vermek zorunda değilim; vermezsem hesap açılamaz veya cilt analizi/fotoğraf özellikleri kullanılamaz. Rızamı dilediğim zaman Profil üzerinden hesabımı silerek veya veri sorumlusuyla iletişime geçerek geri alabilirim. Geri alma, geri alma anına kadar yapılan işlemi hukuka aykırı kılmaz.",
  },
];

const EN_RIZA = [
  {
    title: "1. Subject",
    body: "Under KVKK article 6, I give explicit consent to Rebi processing my special-category data (skin photos; skin type and concerns; pregnancy/cycle; lifestyle and active-ingredient tolerance and similar health-related information).",
  },
  {
    title: "2. Purpose",
    body: "This consent is needed to create my account, build a personalized routine, run check-in, answer chat, optionally compare photos, and add weather/UV notes. Rebi does not provide medical diagnosis or treatment.",
  },
  {
    title: "3. Sharing",
    body: "I consent to transfers to hosting, database and AI providers, limited to the purposes above.",
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
