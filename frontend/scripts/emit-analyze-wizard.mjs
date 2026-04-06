/**
 * analyzeWizard.json üretimi (en + tr). Çalıştır: node scripts/emit-analyze-wizard.mjs
 */
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const locales = path.join(__dirname, "../src/locales");

const en = {
  errors: {
    pickPhotoFirst: "Choose or take a photo first.",
    storageNotConfigured: "Storage is not configured; photo cannot be uploaded.",
    uploadSuccess: "Photo uploaded to secure storage. You can see it under Profile → Skin photos.",
    uploadFailed: "Upload failed. Check your connection or storage permissions.",
    supabaseAnalyzeMissing: "Supabase is not configured; photo cannot be uploaded.",
    photoOnlyIntro1: "Without the full analysis form you can still save the image for progress tracking or an archive.",
    photoOnlyIntro2: "",
    locationFailed: "Could not get location.",
    photoUploadWarn:
      "Photo could not be uploaded right now; your routine will still be generated. You can upload later for progress tracking.",
    storageOffWarn:
      "Storage (Supabase) is off; the photo cannot reach the server. Routine is still generated; check settings for photos later.",
    networkError:
      "Could not reach the server. Check VITE_API_URL and your connection; in development ensure the backend is running.",
    unexpectedError: "Something went wrong.",
    sessionRequired: "Session required.",
  },
  photoOnly: {
    fullFormLink: "Full new analysis (long form)",
    savePhoto: "Save photo",
    goProfilePhotos: "Go to profile photos",
    change: "Change",
    cameraFront: "Front camera",
    cameraBack: "Back camera",
    webcam: "Webcam",
  },
  compactHub: {
    description:
      "You finished your first analysis; you do not need the long form every day. Use the shortcut below to add a skin photo, or open the full form if something big changed.",
    backToDashboard: "Back to dashboard",
  },
  step1: {
    title: "Let’s get to know you",
    subtitle: "Basics about you.",
    nameLabel: "Your name",
    namePlaceholder: "Your name",
    ageLabel: "Age",
    genderLabel: "Gender",
    hormonalTitle: "Hormonal status",
    hormonal_regular: "Regular cycle",
    hormonal_irregular: "Irregular",
    hormonal_pregnant: "Pregnant",
    hormonal_menopause: "Menopause",
    periodHint: "Pick your last period date to continue.",
  },
  step2: {
    title: "Your skin & lifestyle",
    subtitle: "Gather details; Rebi will evaluate next.",
    zonesHint: "Affected areas for {{concern}}",
    clarifyTitle: "Quick clarification",
    agingIntro:
      "If you chose wrinkles/aging, which lines show up most for you?",
    aging_frown: "Frown lines between brows / forehead",
    aging_crow: "Crow’s feet when smiling",
    aging_smile: "Smile lines (nose–mouth)",
    sensitivityIntro:
      "If you chose sensitivity/redness, this is about general redness and reactivity.",
    sensitivityNote:
      "If you mean post-acne red marks, the Acne option may fit better.",
    redness_diffuse: "General / diffuse redness",
    redness_acne_marks: "Redness after breakouts",
    cold_sensitive: "Worse in the cold",
    stings_products: "Stings when applying products",
    sensitivityFootnote:
      "These signs are not the same as skin type (oily/dry/combination/normal); normal skin can still react to cold.",
    pssTitle: "PSS-10 stress check",
    pssSubtitle: "Stress affects many skin concerns.",
    scaleNever: "Never",
    scaleOften: "Very often",
    smokingTitle: "Smoking",
    smokingYears: "For how many years?",
    packYears: "Pack-years: {{n}}",
    alcoholTitle: "Alcohol",
    alcoholSession: "How much per session?",
    alcoholWeekly: "Weekly: ~{{n}} drinks",
    nutritionTitle: "Nutrition",
    makeupTitle: "Makeup",
    makeupFreqQ: "How often do you wear makeup?",
    makeupRemovalQ: "How do you remove makeup?",
    waterLabel: "Water: {{n}} L",
    sleepLabel: "Sleep: {{n}} h",
  },
  step3: {
    activesTitle: "Active-ingredient products",
    activesSubtitle:
      "How often have you used retinol, AHA/BHA, high-% vitamin C, etc.? This is your overall experience; you will mark each ingredient and skin response before generating the routine.",
    experienceLabel: "Your experience",
    severityTitle: "Severity per concern",
    severitySubtitle: "Answer for each selected concern.",
    durationLabel: "How long has this been going on?",
    triggersTitle: "Triggers",
    triggersSubtitle: "When do issues flare? (multi-select)",
    pastTitle: "Past treatments",
    pastSubtitle: "What have you tried before? (multi-select)",
    expectationsTitle: "Your goals",
    expectationsSubtitle: "What do you want? (multi-select)",
  },
  step4: {
    finalLead:
      "You can generate your routine now. For {{tracking}} (comparing progress), a clear face photo is {{recommended}} — gallery, camera, or webcam.",
    final_tracking: "For progress tracking",
    final_recommended: "highly recommended",
    changePhoto: "Change",
    tipTitle: "Tip:",
    tipBody:
      "Add a clear face photo to make progress tracking easier. Mobile: front/back camera or gallery; desktop: webcam or file.",
    modeHint:
      "Choose a mode: front/back camera on phone; gallery/file or live webcam on desktop.",
    galleryFile: "Gallery / file",
    cameraFront: "Front camera",
    cameraRear: "Back camera",
    webcam: "Webcam",
    summaryTitle: "Summary",
    age: "Age",
    skin: "Skin",
    severity: "Severity",
    concerns: "Concerns",
    createRoutineCta: "Build my optimal routine",
    noPhotoNote:
      "You can continue without a photo; you will see a short note about progress tracking at the end.",
  },
  modal: {
    routineBeforeTitle: "Before we generate your routine",
    routineBeforeBody:
      "Rebi guides with actives and concentrations; it is not a medical diagnosis or prescription. If unsure, pregnant/breastfeeding, or on medication, talk to a clinician.",
    noPhotoTitle: "No photo added",
    noPhotoBody:
      "Your routine can still be created; comparing progress with photos gets harder. You can go back and add from camera or gallery. Uploaded images are stored in secure cloud storage; this web app does not create a separate Rebi folder on your phone.",
    productTruthTitle: "Products and formulas",
    productTruth1:
      "If several actives appear on one line, they do not have to be in a single bottle; you can use separate serums and moisturizers in the same order.",
    productTruth2:
      "Label percentages may not match exactly; starting near or slightly below is often sensible.",
    toleranceExplTitle: "Prior use and skin response",
    toleranceExplBody:
      "Ingredients you mark as severe reaction are omitted from the routine. Never used → gentle ramp-up. Mild reaction → sparser use notes. No issues → standard suggestion based on your overall experience.",
    back: "Back",
    understandCreate: "Got it, create routine",
  },
  skipPhoto: {
    title: "A photo helps track progress",
    body1:
      "You can continue without one; the routine is still generated. Face photos help compare changes over time.",
    body2:
      "Your image is kept in the app’s secure server-side storage. As a web app, photos are usually not saved into a separate Rebi folder on your phone (your gallery copy may remain).",
    addPhoto: "I’ll add a photo",
    createAnyway: "Create routine anyway",
  },
  skinPicker: {
    oily: { label: "Oily", desc: "Shine in T-zone, larger pores" },
    dry: { label: "Dry", desc: "Tightness, flaking, matte look" },
    combination: { label: "Combination", desc: "Oily T-zone, dry or normal cheeks" },
    normal: { label: "Normal", desc: "Balanced moisture, even texture" },
    sensitive: { label: "Sensitive", desc: "Flushes easily, stinging, irritation" },
    guideOpen: "How do I know my skin type?",
    guideClose: "Close guide",
    guideTitle: "How to tell your skin type",
    morningTitle: "Morning check",
    morningDesc: "Before washing, look in the mirror:",
    tissueTitle: "Blotting test",
    tissueDesc: "Press clean tissue on your face and wait ~30 seconds:",
    morningSign: {
      oily: "Shiny all over, especially forehead and nose",
      dry: "Feels tight, slight flaking possible",
      combination: "Only nose/forehead shiny, cheeks matte or tight",
      normal: "Comfortable—not oily or dry",
      sensitive: "Flushes/warms easily; quicker reactions to products or temperature",
    },
    tissueSign: {
      oily: "Oil marks across the tissue",
      dry: "No oil on tissue",
      combination: "Oil mainly on nose/forehead area",
      normal: "Very light, even moisture marks",
      sensitive: "Redness/mark lasts longer after pressing; friction irritates easily",
    },
    tipLine: 'Tip: If unsure, choose "Normal". Rebi will refine needs from your other answers.',
  },
  gender: { female: "Female", male: "Male", other: "Other" },
  concern: {
    acne: "Acne / breakouts",
    aging: "Wrinkles / aging",
    dryness: "Dryness",
    pigmentation: "Pigmentation / spots",
    sensitivity: "Sensitivity / redness",
  },
  zone: {
    forehead: "Forehead",
    nose: "Nose",
    cheeks: "Cheeks",
    chin: "Chin",
    undereye: "Under eyes",
    lips: "Around lips",
    temples: "Temples",
  },
  duration: {
    "1-3": "1–3 months",
    "3-6": "3–6 months",
    "6-12": "6–12 months",
    "1y+": "More than a year",
  },
  trigger: {
    stress: "Stress",
    period: "Menstrual cycle",
    sun: "Sun",
    food: "Diet",
    season: "Season",
    cold: "Cold",
    heat: "Heat",
    other: "Other",
  },
  pastTreatment: {
    none: "Nothing yet",
    cleanser: "Cleanser",
    moisturizer: "Moisturizer",
    rx: "Prescription cream/medicine",
    derm: "Dermatologist",
    otc: "OTC pharmacy products",
  },
  activesExperience: {
    none: "Rarely / never",
    occasional: "Tried occasionally",
    regular: "Use regularly",
  },
  strongFamily: {
    retinol: "Retinol / retinal",
    bha: "Salicylic acid (BHA)",
    aha: "AHA (glycolic, lactic)",
    benzoyl: "Benzoyl peroxide",
    azelaic: "Azelaic acid",
    vitamin_c: "Vitamin C (ascorbic) serum",
    bakuchiol: "Bakuchiol",
    pigment: "Arbutin / tranexamic acid",
    niacinamide: "Niacinamide",
  },
  tolerance: {
    never: "Never used",
    good: "Used, no issues",
    mild: "Mild dryness / mild reaction",
    bad: "Severe reaction — do not add to routine",
  },
  expectation: {
    acne_less: "Fewer breakouts",
    spots_less: "Fading spots",
    clean_skin: "Clearer, calmer skin",
    hydration: "Better hydration",
    aging_slow: "Slower visible aging",
    comfort: "Less sensitivity / more comfort",
  },
  pss10: [
    "In the last month, how often have you been upset because of something that happened unexpectedly?",
    "In the last month, how often have you felt that you were unable to control the important things in your life?",
    "In the last month, how often have you felt nervous and stressed?",
    "In the last month, how often have you felt confident about your ability to handle personal problems?",
    "In the last month, how often have you felt that things were going your way?",
    "In the last month, how often have you found that you could not cope with all the things you had to do?",
    "In the last month, how often have you been able to control irritations in your life?",
    "In the last month, how often have you felt that you were on top of things?",
    "In the last month, how often have you been angered because of things outside your control?",
    "In the last month, how often have you felt difficulties were piling up so high you could not overcome them?",
  ],
  smokingAmount: {
    "0": "I don’t smoke",
    "1": "Quit",
    "5": "1–10/day",
    "15": "10–20/day",
    "25": "20+/day",
  },
  smokingYears: {
    "0": "New / quit",
    "2": "1–3 years",
    "5": "3–5 years",
    "10": "5–10 years",
    "20": "10+ years",
  },
  alcoholFreq: {
    "0": "I don’t drink",
    "1": "1–2/month",
    "3": "1–2/week",
    "5": "3–5/week",
    "7": "Daily",
  },
  alcoholAmt: {
    "1": "1 drink",
    "2": "2–3 drinks",
    "4": "4–5 drinks",
    "6": "6+ drinks",
  },
  nutrition: {
    fastfood: {
      label: "Fast food / ultra-processed",
      opts: { "0": "Rarely", "1": "1–2/week", "3": "3+/week", "5": "Daily" },
    },
    sugar: {
      label: "Sugary foods / desserts",
      opts: { "0": "Rarely", "1": "1–2/week", "3": "3+/week", "5": "Daily" },
    },
    dairy: {
      label: "Dairy",
      opts: { "0": "None", "1": "1–2/week", "3": "Daily" },
    },
    veggies: {
      label: "Vegetables & fruit",
      opts: { "0": "Rarely", "1": "1–2/week", "3": "Daily light", "5": "Daily plenty" },
    },
  },
  makeup: {
    frequency: {
      "0": "I don’t wear makeup",
      "1": "Special occasions",
      "3": "A few times a week",
      "5": "Daily",
    },
    removal: {
      none: "I don’t cleanse it off",
      water: "Water only",
      cleanser: "With cleanser",
      double: "Double cleanse",
    },
  },
};

const tr = {
  errors: {
    pickPhotoFirst: "Önce bir fotoğraf seç veya çek.",
    storageNotConfigured: "Depolama yapılandırılmamış; fotoğraf yüklenemiyor.",
    uploadSuccess:
      "Fotoğraf güvenli depoya yüklendi. Profil → Cilt fotoğrafları bölümünde görebilirsin.",
    uploadFailed: "Yükleme başarısız. Bağlantı veya depo izinlerini kontrol et.",
    supabaseAnalyzeMissing: "Supabase yapılandırılmamış; fotoğraf yüklenemiyor.",
    photoOnlyIntro1:
      "Tam analiz formuna girmeden sadece görüntüyü kaydedebilirsin. İlerleyişi kıyaslamak veya arşiv tutmak için kullan.",
    photoOnlyIntro2: "",
    locationFailed: "Konum alınamadı.",
    photoUploadWarn:
      "Fotoğraf şu an sunucuya yüklenemedi; rutin yine de oluşturulacak. Süreç takibi için sonra tekrar yükleyebilirsin.",
    storageOffWarn:
      "Depolama (Supabase) kapalı; fotoğraf sunucuya gidemiyor. Rutin oluşturuluyor; ileride fotoğraf için ayarları kontrol et.",
    networkError:
      "Sunucuya bağlanılamadı. API adresini (VITE_API_URL) ve internet bağlantını kontrol et; geliştirme ortamında backend’in çalıştığından emin ol.",
    unexpectedError: "Beklenmeyen bir hata oluştu.",
    sessionRequired: "Oturum gerekli.",
  },
  photoOnly: {
    fullFormLink: "Tam yeni analiz (uzun form)",
    savePhoto: "Fotoğrafı kaydet",
    goProfilePhotos: "Profildeki fotoğraflara git",
    change: "Değiştir",
    cameraFront: "Kamera ön",
    cameraBack: "Kamera arka",
    webcam: "Web kamerası",
  },
  compactHub: {
    description:
      "İlk analizini tamamladın; uzun formu her gün tekrarlamana gerek yok. Sadece cilt fotoğrafı eklemek için aşağıdaki kısayolu kullan; büyük bir değişiklikte tam formu aç.",
    backToDashboard: "Panele dön",
  },
  step1: {
    title: "Seni Tanıyalım",
    subtitle: "Temel bilgilerin.",
    nameLabel: "Adın",
    namePlaceholder: "Adın",
    ageLabel: "Yaş",
    genderLabel: "Cinsiyet",
    hormonalTitle: "Hormonal Durum",
    hormonal_regular: "Düzenli döngü",
    hormonal_irregular: "Düzensiz",
    hormonal_pregnant: "Hamileyim",
    hormonal_menopause: "Menopoz",
    periodHint: "Son adet tarihini seçerek devam edebilirsin.",
  },
  step2: {
    title: "Cildin & Yaşam Tarzın",
    subtitle: "Detaylı bilgiler topla, sonra Rebi AI değerlendirme yapacak.",
    zonesHint: "{{concern}} için etkilenen bölgeler",
    clarifyTitle: "Kısa netleştirme",
    agingIntro:
      "Kırışıklık/yaşlanma seçtiysen, aşağıdaki çizgilerden hangisi daha çok sende var?",
    aging_frown: "Kaş çatınca alın/iki kaş arası",
    aging_crow: "Gülünce göz kenarı (kaz ayağı)",
    aging_smile: "Gülme çizgileri (burun–ağız)",
    sensitivityIntro:
      "Hassasiyet / Kızarıklık seçtiysen: bu madde genel kızarıklık ve reaktivite içindir.",
    sensitivityNote:
      "Eğer “sivilce sonrası kırmızılık/iz” diyorsan, Akne seçimi daha doğru olabilir.",
    redness_diffuse: "Genel/difüz kızarıklık",
    redness_acne_marks: "Sivilce sonrası kırmızılık",
    cold_sensitive: "Soğukta hassaslaşıyor",
    stings_products: "Ürün sürünce batma/yanma",
    sensitivityFootnote:
      "Not: Bu işaretler cilt tipi (yağlı/kuru/karma/normal) ile aynı şey değil; bazen normal cilt olup soğukta hassaslaşmak mümkündür.",
    pssTitle: "PSS-10 Stres Testi",
    pssSubtitle: "Stres tüm cilt sorunlarını etkiler.",
    scaleNever: "Hiçbir zaman",
    scaleOften: "Çok sık",
    smokingTitle: "Sigara",
    smokingYears: "Kaç yıldır?",
    packYears: "Paket-yıl: {{n}}",
    alcoholTitle: "Alkol",
    alcoholSession: "Bir seansta ne kadar?",
    alcoholWeekly: "Haftalık: ~{{n}} kadeh",
    nutritionTitle: "Beslenme",
    makeupTitle: "Makyaj",
    makeupFreqQ: "Ne sıklıkla makyaj yapıyorsun?",
    makeupRemovalQ: "Makyaj temizleme yöntemin?",
    waterLabel: "Su: {{n}}L",
    sleepLabel: "Uyku: {{n}}s",
  },
  step3: {
    activesTitle: "Aktif içerikli ürünler",
    activesSubtitle:
      "Retinol, AHA/BHA, yüksek % C vitamini gibi ürünleri ne sıklıkla kullandın? Genel deneyim burada; her madde için önceki kullanım ve cilt tepkisini rutin oluşturmadan önceki ekranda tek tek işaretleyeceksin.",
    experienceLabel: "Deneyimin",
    severityTitle: "Soruna özel şiddet",
    severitySubtitle: "Her sorun için soruları cevapla.",
    durationLabel: "Ne kadar süredir?",
    triggersTitle: "Tetikleyiciler",
    triggersSubtitle: "Sorunların ne zaman artıyor? (çoklu seç)",
    pastTitle: "Geçmiş tedaviler",
    pastSubtitle: "Daha önce ne denedin? (çoklu seç)",
    expectationsTitle: "Beklentilerin",
    expectationsSubtitle: "Ne istiyorsun? (çoklu seç)",
  },
  step4: {
    finalLead:
      "İstersen hemen rutin oluşturabilirsin. {{tracking}} (ilerleyişi karşılaştırmak) için net bir yüz fotoğrafı {{recommended}} — galeri, kamera veya web kamerası.",
    final_tracking: "Süreç takibi",
    final_recommended: "çok önerilir",
    changePhoto: "Değiştir",
    tipTitle: "Öneri:",
    tipBody:
      "Süreç takibini kolaylaştırmak için net bir yüz fotoğrafı ekle. Mobil: Kamera ön/arka veya Galeri; masaüstü: Web kamerası veya dosya.",
    modeHint:
      "Mod seç: Telefonda ön/arka kamera; bilgisayarda galeri/dosya veya canlı webcam.",
    galleryFile: "Galeri / dosya",
    cameraFront: "Kamera ön",
    cameraRear: "Kamera arka",
    webcam: "Web kamerası",
    summaryTitle: "Özet",
    age: "Yaş",
    skin: "Cilt",
    severity: "Şiddet",
    concerns: "Sorunlar",
    createRoutineCta: "Optimal Rutini Oluştur",
    noPhotoNote:
      "Fotoğraf eklemeden de devam edebilirsin; son adımda süreç takibi için kısa bir uyarı gösterilir.",
  },
  modal: {
    routineBeforeTitle: "Rutin öncesi bilgilendirme",
    routineBeforeBody:
      "Rebi etken madde ve konsantrasyonla yönlendirir; tıbbi teşhis veya reçete yerine geçmez. Şüphe, hamilelik/emzirme veya ilaç kullanımında mutlaka sağlık uzmanına danış.",
    noPhotoTitle: "Fotoğraf eklemedin",
    noPhotoBody:
      "Rutin yine oluşturulur; ilerleyişi fotoğrafla kıyaslamak zorlaşır. İstersen geri dönüp kamera veya galeriden ekleyebilirsin. Yüklenen fotoğraflar güvenli bulutta saklanır, telefonda ayrı bir Rebi klasörü oluşmaz.",
    productTruthTitle: "Ürün ve formül gerçeği",
    productTruth1:
      "Bir satırda birden fazla madde yazıyorsa hepsi tek şişede olmak zorunda değil; ayrı serum + nemlendirici gibi ürünlerle aynı sırayı kurabilirsin.",
    productTruth2:
      "Etiketteki % değeri birebir olmayabilir; yakın ve daha düşük konsantrasyonla başlamak çoğu zaman uygundur.",
    toleranceExplTitle: "Daha önce kullandın mı, cildin ne yaptı?",
    toleranceExplBody:
      "Ciddi tepki seçtiğin maddeler rutine hiç yazılmaz. Hiç kullanmadım → düşük sıklıkla alıştırma. Hafif tepki → daha seyrek kullanım notu. Sorunsuz → normal öneri (genel deneyimine göre).",
    back: "Geri",
    understandCreate: "Anladım, rutini oluştur",
  },
  skipPhoto: {
    title: "Süreç takibi için fotoğraf önerilir",
    body1:
      "Fotoğrafsız devam edebilirsin; rutin üretilir. İlerleyişi zaman içinde karşılaştırmak için yüz fotoğrafı faydalıdır.",
    body2:
      "Yüklediğin görüntü uygulamanın sunucu tarafındaki güvenli depoda tutulur. Bu bir web uygulaması olduğu için fotoğraf genelde telefonda ayrı bir Rebi klasörüne kaydedilmez (galerinde yalnızca çektiğin/ seçtiğin kopya kalabilir).",
    addPhoto: "Fotoğraf ekleyeyim",
    createAnyway: "Yine de rutini oluştur",
  },
  skinPicker: {
    oily: { label: "Yağlı", desc: "T-bölgede parlaklık, geniş gözenekler" },
    dry: { label: "Kuru", desc: "Gerginlik, pul pul dökülme, mat görünüm" },
    combination: { label: "Karma", desc: "T-bölge yağlı, yanaklar kuru veya normal" },
    normal: { label: "Normal", desc: "Dengeli nem, düzgün doku, sorunsuz" },
    sensitive: { label: "Hassas", desc: "Kolay kızarır, batma hissi, tahriş" },
    guideOpen: "Cilt tipimi nasıl anlarım?",
    guideClose: "Kılavuzu kapat",
    guideTitle: "Cilt Tipini Nasıl Tespit Edersin?",
    morningTitle: "Sabah Testi",
    morningDesc: "Sabah uyandığında yüzünü yıkamadan aynaya bak:",
    tissueTitle: "Kağıt Mendil Testi",
    tissueDesc: "Temiz bir kağıt mendili yüzüne bastır ve 30 saniye bekle:",
    morningSign: {
      oily: "Yüzün her yerde parlıyor, özellikle alın ve burun",
      dry: "Gergin hissediyorsun, hafif pul pul olabilir",
      combination: "Sadece burun/alın parlıyor, yanaklar mat veya gergin",
      normal: "Rahat hissediyorsun, ne yağlı ne kuru",
      sensitive: "Kolay kızarır/ısınır; ürün sürünce veya sıcak-soğukta daha çabuk tepki verir",
    },
    tissueSign: {
      oily: "Mendil her yerde yağ izi bırakıyor",
      dry: "Mendilde hiç yağ yok",
      combination: "Sadece burun/alın bölgesinde yağ izi var",
      normal: "Çok hafif, eşit dağılmış nem izi",
      sensitive: "Bastırınca kızarıklık/iz daha uzun süre kalır; sık sürtünmede kolay tahriş olur",
    },
    tipLine:
      'İpucu: Emin olamıyorsan "Normal" seç. Rebi diğer verilerden cildinin ihtiyacını tespit edecek.',
  },
  gender: { female: "Kadın", male: "Erkek", other: "Diğer" },
  concern: {
    acne: "Sivilce / Akne",
    aging: "Kırışıklık / Yaşlanma",
    dryness: "Kuruluk",
    pigmentation: "Lekelenme",
    sensitivity: "Hassasiyet / Kızarıklık",
  },
  zone: {
    forehead: "Alın",
    nose: "Burun",
    cheeks: "Yanaklar",
    chin: "Çene",
    undereye: "Göz altı",
    lips: "Dudak çevresi",
    temples: "Şakak",
  },
  duration: {
    "1-3": "1–3 ay",
    "3-6": "3–6 ay",
    "6-12": "6–12 ay",
    "1y+": "1 yıldan fazla",
  },
  trigger: {
    stress: "Stres",
    period: "Adet dönemi",
    sun: "Güneş",
    food: "Yediklerim",
    season: "Mevsim",
    cold: "Soğuk",
    heat: "Sıcak",
    other: "Diğer",
  },
  pastTreatment: {
    none: "Hiçbir şey denemedim",
    cleanser: "Temizleyici",
    moisturizer: "Nemlendirici",
    rx: "Reçeteli krem/ilaç",
    derm: "Dermatolog",
    otc: "Eczane (reçetesiz) kullanımı",
  },
  activesExperience: {
    none: "Hiç / çok nadiren",
    occasional: "Ara sıra denedim",
    regular: "Düzenli kullanıyorum",
  },
  strongFamily: {
    retinol: "Retinol / retinal",
    bha: "Salisilik asit (BHA)",
    aha: "AHA (glikolik, laktik asit)",
    benzoyl: "Benzoil peroksit",
    azelaic: "Azelaik asit",
    vitamin_c: "C vitamini (askorbik) serum",
    bakuchiol: "Bakuchiol",
    pigment: "Arbutin / traneksamik asit",
    niacinamide: "Niasinamid",
  },
  tolerance: {
    never: "Hiç kullanmadım",
    good: "Kullandım, sorunsuz",
    mild: "Hafif kuruluk / hafif tepki",
    bad: "Ciddi tepki — rutine ekleme",
  },
  expectation: {
    acne_less: "Sivilcelerin azalması",
    spots_less: "Lekelerin solması",
    clean_skin: "Daha temiz / sade cilt",
    hydration: "Daha iyi nem",
    aging_slow: "Yaşlanma belirtilerinin yavaşlaması",
    comfort: "Daha az hassasiyet / rahatlık",
  },
  pss10: [
    "Son bir ayda, beklenmedik bir şey olduğunda ne sıklıkla üzüldünüz?",
    "Son bir ayda, hayatınızdaki önemli şeyleri kontrol edemediğinizi ne sıklıkla hissettiniz?",
    "Son bir ayda, ne sıklıkla gergin ve stresli hissettiniz?",
    "Son bir ayda, kişisel sorunlarınızla başa çıkabildiğinize ne sıklıkla güvendiniz?",
    "Son bir ayda, işlerin sizin istediğiniz gibi gittiğini ne sıklıkla hissettiniz?",
    "Son bir ayda, yapmanız gereken tüm işlerle başa çıkamadığınızı ne sıklıkla fark ettiniz?",
    "Son bir ayda, hayatınızdaki sinir bozucu şeyleri ne sıklıkla kontrol edebildiniz?",
    "Son bir ayda, işlerin üstesinden geldiğinizi ne sıklıkla hissettiniz?",
    "Son bir ayda, kontrolünüz dışındaki şeyler yüzünden ne sıklıkla kızdınız?",
    "Son bir ayda, zorlukların o kadar biriktiğini ne sıklıkla hissettiniz ki üstesinden gelemediniz?",
  ],
  smokingAmount: {
    "0": "İçmiyorum",
    "1": "Bıraktım",
    "5": "1-10/gün",
    "15": "10-20/gün",
    "25": "20+/gün",
  },
  smokingYears: {
    "0": "Yeni/bıraktım",
    "2": "1-3 yıl",
    "5": "3-5 yıl",
    "10": "5-10 yıl",
    "20": "10+ yıl",
  },
  alcoholFreq: {
    "0": "İçmiyorum",
    "1": "Ayda 1-2",
    "3": "Haftada 1-2",
    "5": "Haftada 3-5",
    "7": "Her gün",
  },
  alcoholAmt: {
    "1": "1 kadeh",
    "2": "2-3 kadeh",
    "4": "4-5 kadeh",
    "6": "6+ kadeh",
  },
  nutrition: {
    fastfood: {
      label: "Fast food / işlenmiş gıda",
      opts: { "0": "Hiç/nadir", "1": "Haftada 1-2", "3": "Haftada 3+", "5": "Her gün" },
    },
    sugar: {
      label: "Şekerli gıda / tatlı",
      opts: { "0": "Hiç/nadir", "1": "Haftada 1-2", "3": "Haftada 3+", "5": "Her gün" },
    },
    dairy: {
      label: "Süt ürünleri",
      opts: { "0": "Hiç", "1": "Haftada 1-2", "3": "Her gün" },
    },
    veggies: {
      label: "Sebze & meyve",
      opts: { "0": "Nadir", "1": "Haftada 1-2", "3": "Her gün az", "5": "Her gün bol" },
    },
  },
  makeup: {
    frequency: {
      "0": "Kullanmıyorum",
      "1": "Özel günlerde",
      "3": "Haftada birkaç",
      "5": "Her gün",
    },
    removal: {
      none: "Temizlemiyorum",
      water: "Su ile",
      cleanser: "Temizleyici ile",
      double: "Çift aşamalı",
    },
  },
};

function write(lang, obj) {
  const dir = path.join(locales, lang);
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(
    path.join(dir, "analyzeWizard.json"),
    JSON.stringify(obj, null, 2) + "\n",
    "utf8"
  );
}

write("en", en);
write("tr", tr);

const rest = ["es", "de", "it", "fr", "pt", "ar", "az"];
for (const lng of rest) {
  write(lng, en);
}

console.log("Wrote analyzeWizard.json for", ["en", "tr", ...rest].join(", "));
