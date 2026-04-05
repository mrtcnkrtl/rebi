import { useState, useRef, useMemo, useEffect } from "react";
import { useNavigate } from "react-router-dom";
import { useAuth } from "../context/AuthContext";
import { API_URL, supabase } from "../lib/supabase";
import { apiAuthHeaders } from "../lib/apiAuth";
import { DEMO_USER_ID } from "../lib/demoUser";
import { hasCompletedOnboarding } from "../lib/routineTracking";
import { formatApiErrorDetail, isNetworkError } from "../lib/apiErrors";
import LoadingScreen from "../components/LoadingScreen";
import SkinTypeVisual from "../components/SkinTypeVisual";
import SeverityTest from "../components/SeverityTest";
import WebcamCapture from "../components/WebcamCapture";
import {
  MapPin, ArrowRight, ArrowLeft, Camera, ImagePlus, Monitor,
  Droplets, Moon, Cigarette, Wine, AlertCircle, CheckCircle,
  User, Sparkles, Heart, Send, Bot, Loader2,
  UtensilsCrossed, Palette, AlertTriangle,
} from "lucide-react";

/* ═══════════ SABİT VERİLER ═══════════ */
const genders = [
  { id: "female", label: "Kadın" },
  { id: "male", label: "Erkek" },
  { id: "other", label: "Diğer" },
];
const concernOptions = [
  { id: "acne", label: "Sivilce / Akne", icon: "🔴" },
  { id: "aging", label: "Kırışıklık / Yaşlanma", icon: "✨" },
  { id: "dryness", label: "Kuruluk", icon: "🏜️" },
  { id: "pigmentation", label: "Lekelenme", icon: "🎯" },
  { id: "sensitivity", label: "Hassasiyet / Kızarıklık", icon: "🌸" },
];
const zoneOptions = [
  { id: "forehead", label: "Alın" }, { id: "nose", label: "Burun" },
  { id: "cheeks", label: "Yanaklar" }, { id: "chin", label: "Çene" },
  { id: "undereye", label: "Göz altı" }, { id: "lips", label: "Dudak çevresi" },
  { id: "temples", label: "Şakak" },
];
/** Step 3 kullanım soruları – yapılandırılmış seçenekler */
const durationOpts = [
  { id: "1-3", label: "1–3 ay" },
  { id: "3-6", label: "3–6 ay" },
  { id: "6-12", label: "6–12 ay" },
  { id: "1y+", label: "1 yıldan fazla" },
];
const triggerOpts = [
  { id: "stress", label: "Stres" },
  { id: "period", label: "Adet dönemi" },
  { id: "sun", label: "Güneş" },
  { id: "food", label: "Yediklerim" },
  { id: "season", label: "Mevsim" },
  { id: "cold", label: "Soğuk" },
  { id: "heat", label: "Sıcak" },
  { id: "other", label: "Diğer" },
];
const pastTreatmentOpts = [
  { id: "none", label: "Hiçbir şey denemedim" },
  { id: "cleanser", label: "Temizleyici" },
  { id: "moisturizer", label: "Nemlendirici" },
  { id: "rx", label: "Reçeteli krem/ilaç" },
  { id: "derm", label: "Dermatolog" },
  { id: "otc", label: "Eczane (reçetesiz) kullanımı" },
];
/** Retinol, asit, güçlü C vb. — rutin sıklığı ve alıştırma için */
const activesExperienceOpts = [
  { id: "none", label: "Hiç / çok nadiren" },
  { id: "occasional", label: "Ara sıra denedim" },
  { id: "regular", label: "Düzenli kullanıyorum" },
];
/** Güçlü aktif aileleri — önceki kullanım + cilt tepkisi (API actives_tolerance) */
const strongActiveFamilies = [
  { id: "retinol", label: "Retinol / retinal" },
  { id: "bha", label: "Salisilik asit (BHA)" },
  { id: "aha", label: "AHA (glikolik, laktik asit)" },
  { id: "benzoyl", label: "Benzoil peroksit" },
  { id: "azelaic", label: "Azelaik asit" },
  { id: "vitamin_c", label: "C vitamini (askorbik) serum" },
  { id: "bakuchiol", label: "Bakuchiol" },
  { id: "pigment", label: "Arbutin / traneksamik asit" },
  { id: "niacinamide", label: "Niasinamid" },
];
const toleranceLevels = [
  { id: "never", label: "Hiç kullanmadım" },
  { id: "good", label: "Kullandım, sorunsuz" },
  { id: "mild", label: "Hafif kuruluk / hafif tepki" },
  { id: "bad", label: "Ciddi tepki — rutine ekleme" },
];
const expectationOpts = [
  { id: "acne_less", label: "Sivilcelerin azalması" },
  { id: "spots_less", label: "Lekelerin solması" },
  { id: "clean_skin", label: "Daha temiz / sade cilt" },
  { id: "hydration", label: "Daha iyi nem" },
  { id: "aging_slow", label: "Yaşlanma belirtilerinin yavaşlaması" },
  { id: "comfort", label: "Daha az hassasiyet / rahatlık" },
];
/** PSS-10: Algılanan Stres Ölçeği (10 madde). 4, 5, 7, 8. maddeler ters puanlanır. Toplam 0–40. */
const pss10Questions = [
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
];
const smokingAmountOpts = [
  { id: 0, label: "İçmiyorum" }, { id: 1, label: "Bıraktım" },
  { id: 5, label: "1-10/gün" }, { id: 15, label: "10-20/gün" }, { id: 25, label: "20+/gün" },
];
const smokingYearsOpts = [
  { id: 0, label: "Yeni/bıraktım" }, { id: 2, label: "1-3 yıl" },
  { id: 5, label: "3-5 yıl" }, { id: 10, label: "5-10 yıl" }, { id: 20, label: "10+ yıl" },
];
const alcoholFreqOpts = [
  { id: 0, label: "İçmiyorum" }, { id: 1, label: "Ayda 1-2" },
  { id: 3, label: "Haftada 1-2" }, { id: 5, label: "Haftada 3-5" }, { id: 7, label: "Her gün" },
];
const alcoholAmtOpts = [
  { id: 1, label: "1 kadeh" }, { id: 2, label: "2-3 kadeh" },
  { id: 4, label: "4-5 kadeh" }, { id: 6, label: "6+ kadeh" },
];
const nutritionOpts = [
  { id: "fastfood", label: "Fast food / işlenmiş gıda", opts: [
    { id: 0, label: "Hiç/nadir" }, { id: 1, label: "Haftada 1-2" }, { id: 3, label: "Haftada 3+" }, { id: 5, label: "Her gün" },
  ]},
  { id: "sugar", label: "Şekerli gıda / tatlı", opts: [
    { id: 0, label: "Hiç/nadir" }, { id: 1, label: "Haftada 1-2" }, { id: 3, label: "Haftada 3+" }, { id: 5, label: "Her gün" },
  ]},
  { id: "dairy", label: "Süt ürünleri", opts: [
    { id: 0, label: "Hiç" }, { id: 1, label: "Haftada 1-2" }, { id: 3, label: "Her gün" },
  ]},
  { id: "veggies", label: "Sebze & meyve", opts: [
    { id: 0, label: "Nadir" }, { id: 1, label: "Haftada 1-2" }, { id: 3, label: "Her gün az" }, { id: 5, label: "Her gün bol" },
  ]},
];
const makeupOpts = {
  frequency: [
    { id: 0, label: "Kullanmıyorum" }, { id: 1, label: "Özel günlerde" },
    { id: 3, label: "Haftada birkaç" }, { id: 5, label: "Her gün" },
  ],
  removal: [
    { id: "none", label: "Temizlemiyorum" }, { id: "water", label: "Su ile" },
    { id: "cleanser", label: "Temizleyici ile" }, { id: "double", label: "Çift aşamalı" },
  ],
};

function calcCyclePhase(lastPeriodDate, cycleLength) {
  if (!lastPeriodDate) return "unknown";
  const diff = Math.floor((new Date() - new Date(lastPeriodDate)) / 86400000);
  const day = ((diff % cycleLength) + cycleLength) % cycleLength;
  if (day <= 5) return "menstrual";
  if (day <= 13) return "follicular";
  if (day <= 15) return "ovulation";
  return "luteal";
}

/* ═══════════ CHIP SELECT COMPONENT ═══════════ */
function ChipSelect({ options, value, onChange, cols = 2 }) {
  return (
    <div className={`grid gap-1 grid-cols-${cols}`}>
      {options.map((o) => (
        <button key={o.id} onClick={() => onChange(o.id)}
          className={`text-[10px] py-1.5 px-1.5 rounded-lg border-2 transition-all leading-tight ${
            value === o.id ? "border-teal-500 bg-teal-50 text-teal-800 font-medium" : "border-gray-200 text-gray-500"
          }`}>{o.label}</button>
      ))}
    </div>
  );
}

/* ═══════════ MAIN COMPONENT ═══════════ */
export default function Analyze() {
  const { user } = useAuth();
  const navigate = useNavigate();
  const cameraUserRef = useRef(null);
  const cameraEnvRef = useRef(null);
  const galleryRef = useRef(null);
  const previewUrlRef = useRef(null);

  const [step, setStep] = useState(1);
  const [loading, setLoading] = useState(false);
  const [submitError, setSubmitError] = useState("");
  /** İlk analizden sonra varsayılan: kısa ekran; kullanıcı isterse tam sihirbazı açar. */
  const [forceFullWizard, setForceFullWizard] = useState(false);

  useEffect(() => {
    setSubmitError("");
  }, [step]);

  // Step 1
  const [name, setName] = useState(user?.user_metadata?.full_name || "");
  const [age, setAge] = useState("");
  const [gender, setGender] = useState("");
  const [lat, setLat] = useState(null);
  const [lon, setLon] = useState(null);
  const [locationSet, setLocationSet] = useState(false);
  const [locationLoading, setLocationLoading] = useState(false);
  const [locationError, setLocationError] = useState("");
  const [hormonalStatus, setHormonalStatus] = useState("");
  const [lastPeriodDate, setLastPeriodDate] = useState("");
  const [cycleLength, setCycleLength] = useState(28);

  // Step 2
  const [skinType, setSkinType] = useState("");
  const [concerns, setConcerns] = useState([]);
  /** Her sorun için etkilenen bölgeler: { [concernId]: [zoneId, ...] } */
  const [concernZones, setConcernZones] = useState({});
  const [waterIntake, setWaterIntake] = useState(2);
  const [sleepHours, setSleepHours] = useState(7);
  const [pssAnswers, setPssAnswers] = useState(Array(10).fill(0));
  const [smokingPerDay, setSmokingPerDay] = useState(0);
  const [smokingYears, setSmokingYears] = useState(0);
  const [alcoholFreq, setAlcoholFreq] = useState(0);
  const [alcoholAmt, setAlcoholAmt] = useState(1);
  const [nutrition, setNutrition] = useState({ fastfood: 0, sugar: 0, dairy: 0, veggies: 3 });
  const [makeupFreq, setMakeupFreq] = useState(0);
  const [makeupRemoval, setMakeupRemoval] = useState("cleanser");

  // Step 3 - Kullanım soruları (tek tek: şiddet → tetikleyici → tedavi → beklenti)
  const [step3Section, setStep3Section] = useState(0);
  const [severityScoresByConcern, setSeverityScoresByConcern] = useState({});
  const [duration, setDuration] = useState("");
  const [triggers, setTriggers] = useState([]);
  const [pastTreatments, setPastTreatments] = useState([]);
  const [expectations, setExpectations] = useState([]);
  const [activesExperience, setActivesExperience] = useState("occasional");

  // Step 4 - Foto + rutin oluştur (Rebi bu sayfada yok; rutin sonrası başka yerde kullanılabilir)
  const [photoFile, setPhotoFile] = useState(null);
  const [photoPreview, setPhotoPreview] = useState(null);
  const [showRoutineModal, setShowRoutineModal] = useState(false);
  const [showSkipPhotoModal, setShowSkipPhotoModal] = useState(false);
  const [showWebcam, setShowWebcam] = useState(false);
  /** Fotoğrafsız rutin için kullanıcı bir kez onayladı (aynı oturumda tekrar sorma). */
  const allowRoutineWithoutPhotoRef = useRef(false);
  /** Her güçlü aktif ailesi: never | good | mild | bad */
  const [activesTolerance, setActivesTolerance] = useState(() =>
    Object.fromEntries(strongActiveFamilies.map((f) => [f.id, "good"]))
  );

  const isFemale = gender === "female";
  // PSS-10: maddeler 4,5,7,8 (0-based: 3,4,6,7) ters puanlanır. Toplam 0–40.
const stressScore = pssAnswers.reduce((acc, v, i) => {
  if ([3, 4, 6, 7].includes(i)) return acc + (4 - v);
  return acc + v;
}, 0);
  const packYears = ((smokingPerDay / 20) * smokingYears).toFixed(1);

  const cyclePhase = useMemo(() => {
    if (!isFemale) return "";
    if (hormonalStatus === "pregnant") return "";
    if (hormonalStatus === "menopause") return "menopause";
    if ((hormonalStatus === "regular" || hormonalStatus === "irregular") && lastPeriodDate)
      return calcCyclePhase(lastPeriodDate, cycleLength);
    return "";
  }, [isFemale, hormonalStatus, lastPeriodDate, cycleLength]);

  const zones = [...new Set(Object.values(concernZones).flat())];
  const primaryConcern = concerns[0] || "acne";
  const toggleArr = (a, s, v) => s(a.includes(v) ? a.filter((x) => x !== v) : [...a, v]);
  const setFamilyTolerance = (familyId, level) => {
    setActivesTolerance((prev) => ({ ...prev, [familyId]: level }));
  };
  const toggleConcernZone = (concernId, zoneId) => {
    setConcernZones((prev) => {
      const list = prev[concernId] || [];
      const next = list.includes(zoneId) ? list.filter((z) => z !== zoneId) : [...list, zoneId];
      const out = { ...prev };
      if (next.length) out[concernId] = next;
      else delete out[concernId];
      return out;
    });
  };
  const setNut = (key, val) => setNutrition((p) => ({ ...p, [key]: val }));

  const getLocation = () => {
    setLocationLoading(true); setLocationError("");
    navigator.geolocation?.getCurrentPosition(
      (p) => { setLat(p.coords.latitude); setLon(p.coords.longitude); setLocationSet(true); setLocationLoading(false); },
      () => { setLocationError("Konum alınamadı."); setLocationLoading(false); },
      { enableHighAccuracy: true, timeout: 10000 }
    );
  };

  /* ─── Foto: galeri / mobil kamera / webcam ─── */
  const applyPhotoFile = (file) => {
    if (!file) return;
    allowRoutineWithoutPhotoRef.current = false;
    if (previewUrlRef.current?.startsWith("blob:")) URL.revokeObjectURL(previewUrlRef.current);
    setPhotoFile(file);
    const url = URL.createObjectURL(file);
    previewUrlRef.current = url;
    setPhotoPreview(url);
  };

  const clearPhoto = () => {
    allowRoutineWithoutPhotoRef.current = false;
    if (previewUrlRef.current?.startsWith("blob:")) URL.revokeObjectURL(previewUrlRef.current);
    previewUrlRef.current = null;
    setPhotoFile(null);
    setPhotoPreview(null);
  };

  const handlePhotoChange = (e) => {
    const file = e.target.files?.[0];
    if (file) applyPhotoFile(file);
    e.target.value = "";
  };

  const triggerHiddenInput = (ref) => {
    const el = ref.current;
    if (el) el.click();
  };

  const handleSubmit = async () => {
    setSubmitError("");
    setLoading(true);
    try {
      let photoUrl = null;
      if (photoFile && supabase) {
        const ext = photoFile.name.split(".").pop();
        const path = `${user?.id || DEMO_USER_ID}/${Date.now()}.${ext}`;
        const { error } = await supabase.storage.from("skin-photos").upload(path, photoFile);
        if (error) {
          setSubmitError(
            "Fotoğraf şu an sunucuya yüklenemedi; rutin yine de oluşturulacak. Süreç takibi için sonra tekrar yükleyebilirsin."
          );
        } else {
          photoUrl = supabase.storage.from("skin-photos").getPublicUrl(path)?.data?.publicUrl;
        }
      } else if (photoFile && !supabase) {
        setSubmitError(
          "Depolama (Supabase) kapalı; fotoğraf sunucuya gidemiyor. Rutin oluşturuluyor; ileride fotoğraf için ayarları kontrol et."
        );
      }
      const body = {
        user_id: user?.id || DEMO_USER_ID, full_name: name, age: parseInt(age), gender,
        concern: primaryConcern, skin_type: skinType || "normal",
        severity_score: severityScoresByConcern[primaryConcern] != null ? Math.round(severityScoresByConcern[primaryConcern]) : 5,
        water_intake: waterIntake, sleep_hours: sleepHours, stress_score: Math.round((stressScore * 16) / 40),
        smoking: smokingPerDay > 0, smoking_per_day: smokingPerDay, smoking_years: smokingYears,
        alcohol: alcoholFreq > 0, alcohol_frequency: alcoholFreq, alcohol_amount: alcoholAmt,
        location_lat: lat, location_lon: lon, photo_url: photoUrl,
        is_pregnant: hormonalStatus === "pregnant", cycle_phase: cyclePhase, acne_zones: zones,
        actives_experience: activesExperience,
        actives_tolerance: activesTolerance,
        makeup_frequency: makeupFreq,
        makeup_removal: makeupRemoval,
      };
      const auth = await apiAuthHeaders();
      const response = await fetch(`${API_URL}/generate_routine`, {
        method: "POST",
        headers: { "Content-Type": "application/json", ...auth },
        body: JSON.stringify(body),
      });
      const data = await response.json().catch(() => ({}));
      if (!response.ok) {
        const msg = formatApiErrorDetail(data);
        setSubmitError(msg + (response.status ? ` (${response.status})` : ""));
        return;
      }
      navigate("/dashboard", {
        state: {
          routine: data.routine,
          weather: data.weather,
          insights: data.holistic_insights,
          assessmentId: data.assessment_id,
          photoUrl: photoUrl || photoPreview || null,
          routineWithoutPhoto: !photoUrl && !photoPreview,
          userName: name,
          concern: primaryConcern,
          flowDebug: data.flow_debug,
          safetyAbsoluteRules: data.safety_absolute_rules,
          ruleEnforcementReport: data.rule_enforcement_report,
          aiPolishNote: data.ai_polish_note || null,
        },
      });
    } catch (err) {
      console.error(err);
      if (isNetworkError(err)) {
        setSubmitError(
          "Sunucuya bağlanılamadı. API adresini (VITE_API_URL) ve internet bağlantını kontrol et; geliştirme ortamında backend’in çalıştığından emin ol."
        );
      } else {
        setSubmitError(err?.message || "Beklenmeyen bir hata oluştu.");
      }
    } finally {
      setLoading(false);
    }
  };

  if (loading) return <LoadingScreen />;

  const uid = user?.id || DEMO_USER_ID;
  const showCompactHub =
    !forceFullWizard && hasCompletedOnboarding(uid);

  if (showCompactHub) {
    return (
      <div className="min-h-screen bg-gradient-to-b from-teal-50/50 to-white pb-24">
        <div className="max-w-lg mx-auto px-4 py-10">
          <div className="card space-y-4 !p-6 text-center border-teal-100">
            <div className="w-16 h-16 rounded-2xl bg-gradient-to-br from-teal-400 to-teal-600 flex items-center justify-center mx-auto shadow-lg">
              <Sparkles className="w-8 h-8 text-white" />
            </div>
            <h1 className="text-xl font-bold text-gray-900">Rutinin hazır</h1>
            <p className="text-sm text-gray-600 leading-relaxed">
              İlk analizini tamamladın; uzun formu her gün tekrarlamana gerek yok. Panele dön veya
              cildinde büyük bir değişiklik olduysa yeni analiz başlat.
            </p>
            <div className="flex flex-col gap-2 pt-2">
              <button
                type="button"
                onClick={() => navigate("/dashboard")}
                className="btn-primary w-full justify-center"
              >
                Panele dön <ArrowRight className="w-5 h-5" />
              </button>
              <button
                type="button"
                onClick={() => {
                  setForceFullWizard(true);
                  setStep(1);
                }}
                className="btn-secondary w-full justify-center text-sm"
              >
                Yeni analiz başlat (tam form)
              </button>
            </div>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-gradient-to-b from-teal-50/50 to-white">
      <div className="max-w-lg mx-auto px-4 py-8">
        {/* Progress */}
        <div className="flex items-center gap-2 mb-6">
          {[1, 2, 3, 4].map((s) => (
            <div key={s} className="flex-1"><div className={`h-1.5 rounded-full transition-all ${s < step ? "bg-teal-500" : s === step ? "bg-gradient-to-r from-teal-400 to-teal-600" : "bg-gray-200"}`} /></div>
          ))}
          <span className="text-xs text-gray-400 ml-1">{step}/4</span>
        </div>

        {submitError && (
          <div className="mb-5 flex items-start gap-3 rounded-2xl border border-red-200 bg-red-50/90 px-4 py-3 text-sm text-red-900">
            <AlertCircle className="w-5 h-5 shrink-0 text-red-600 mt-0.5" />
            <div className="min-w-0 flex-1">
              <p className="font-semibold text-red-950">Rutin oluşturulamadı</p>
              <p className="mt-1 text-red-900/95 leading-relaxed">{submitError}</p>
            </div>
            <button
              type="button"
              onClick={() => setSubmitError("")}
              className="shrink-0 text-xs font-semibold text-red-700 underline-offset-2 hover:underline"
            >
              Kapat
            </button>
          </div>
        )}

        {/* ═══ STEP 1: Temel ═══ */}
        {step === 1 && (
          <div className="space-y-5 animate-in fade-in">
            <div><h2 className="text-2xl font-bold text-gray-900 mb-1">Seni Tanıyalım</h2><p className="text-gray-500 text-sm">Temel bilgilerin.</p></div>
            <div className="card space-y-4">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">Adın</label>
                <div className="relative"><User className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400" />
                  <input type="text" value={name} onChange={(e) => setName(e.target.value)} className="input-field !pl-10" placeholder="Adın" /></div>
              </div>
              <div className="grid grid-cols-2 gap-3">
                <div><label className="block text-sm font-medium text-gray-700 mb-1">Yaş</label>
                  <input type="number" value={age} onChange={(e) => setAge(e.target.value)} className="input-field" placeholder="25" min="10" max="120" /></div>
                <div><label className="block text-sm font-medium text-gray-700 mb-1">Cinsiyet</label>
                  <div className="flex gap-1.5">
                    {genders.map((g) => (<button key={g.id} onClick={() => { setGender(g.id); if (g.id !== "female") setHormonalStatus(""); }}
                      className={`flex-1 py-2.5 rounded-xl text-xs font-medium border-2 transition-all ${gender === g.id ? "border-teal-500 bg-teal-50 text-teal-700" : "border-gray-200 text-gray-500"}`}>{g.label}</button>))}
                  </div></div>
              </div>
              <div>{locationSet ? (<div className="flex items-center gap-2 p-2.5 bg-teal-50 rounded-xl text-teal-700 text-xs"><CheckCircle className="w-4 h-4" /> Konum alındı</div>
              ) : (<button onClick={getLocation} disabled={locationLoading} className="btn-secondary w-full text-sm">{locationLoading ? <Loader2 className="w-4 h-4 animate-spin" /> : <><MapPin className="w-4 h-4" />Konum</>}</button>)}
                {locationError && <p className="text-red-500 text-xs mt-1">{locationError}</p>}</div>
            </div>
            {isFemale && (
              <div className="card space-y-3 border-pink-100 bg-pink-50/20">
                <div className="flex items-center gap-2"><Heart className="w-4 h-4 text-pink-600" /><span className="font-semibold text-gray-900 text-sm">Hormonal Durum</span></div>
                <div className="grid grid-cols-2 gap-1.5">
                  {[{ id: "regular", label: "Düzenli döngü" }, { id: "irregular", label: "Düzensiz" }, { id: "pregnant", label: "Hamileyim" }, { id: "menopause", label: "Menopoz" }].map((o) => (
                    <button key={o.id} onClick={() => setHormonalStatus(o.id)} className={`text-xs py-2 px-2 rounded-xl border-2 transition-all ${hormonalStatus === o.id ? "border-pink-400 bg-pink-50 text-pink-800 font-medium" : "border-gray-200 text-gray-500"}`}>{o.label}</button>))}
                </div>
                {(hormonalStatus === "regular" || hormonalStatus === "irregular") && (
                  <div className="space-y-2">
                    <input type="date" value={lastPeriodDate} onChange={(e) => setLastPeriodDate(e.target.value)} max={new Date().toISOString().split("T")[0]} className="input-field text-sm" />
                    {hormonalStatus === "regular" && (<div className="flex items-center gap-2">
                      <input type="range" min="21" max="35" value={cycleLength} onChange={(e) => setCycleLength(parseInt(e.target.value))} className="flex-1 accent-pink-500 h-1.5" />
                      <span className="text-xs font-medium text-pink-700 w-10">{cycleLength}g</span></div>)}
                  </div>)}
              </div>)}
            <button
              onClick={() => setStep(2)}
              disabled={
                !name || !age || !gender
                || (isFemale && (hormonalStatus === "regular" || hormonalStatus === "irregular") && !lastPeriodDate)
              }
              className="btn-primary w-full"
            >
              Devam Et <ArrowRight className="w-5 h-5" />
            </button>
            {isFemale && (hormonalStatus === "regular" || hormonalStatus === "irregular") && !lastPeriodDate && (
              <p className="text-center text-xs text-amber-700 mt-2">Son adet tarihini seçerek devam edebilirsin.</p>
            )}
          </div>
        )}

        {/* ═══ STEP 2: Cilt + Yaşam Tarzı (detaylı) ═══ */}
        {step === 2 && (
          <div className="space-y-5 animate-in fade-in">
            <div><h2 className="text-2xl font-bold text-gray-900 mb-1">Cildin & Yaşam Tarzın</h2><p className="text-gray-500 text-sm">Detaylı bilgiler topla, sonra Rebi AI değerlendirme yapacak.</p></div>

            {/* Cilt Tipi */}
            <div className="card space-y-3">
              <label className="block text-sm font-medium text-gray-700">Cilt Tipin</label>
              <SkinTypeVisual value={skinType} onChange={setSkinType} />
            </div>

            {/* Sorunlar + her biri için etkilenen bölgeler */}
            <div className="card space-y-3">
              <label className="block text-sm font-medium text-gray-700">Sorunların (çoklu seç)</label>
              <div className="grid grid-cols-1 gap-1.5">
                {concernOptions.map((c) => (
                  <div key={c.id} className="space-y-2">
                    <button
                      onClick={() => toggleArr(concerns, setConcerns, c.id)}
                      className={`w-full flex items-center gap-2.5 px-3 py-2.5 rounded-xl border-2 text-left text-sm transition-all ${concerns.includes(c.id) ? "border-teal-500 bg-teal-50 text-teal-800 font-medium" : "border-gray-200 text-gray-600"}`}
                    >
                      <span className="text-lg">{c.icon}</span><span>{c.label}</span>
                      {concerns.includes(c.id) && <CheckCircle className="w-4 h-4 ml-auto text-teal-500" />}
                    </button>
                    {concerns.includes(c.id) && (
                      <div className="pl-2 space-y-1.5">
                        <p className="text-[10px] text-gray-500">{c.label} için etkilenen bölgeler</p>
                        <div className="flex flex-wrap gap-1.5">
                          {zoneOptions.map((z) => (
                            <button
                              key={z.id}
                              onClick={() => toggleConcernZone(c.id, z.id)}
                              className={`px-3 py-1.5 rounded-full text-xs font-medium border-2 transition-all ${(concernZones[c.id] || []).includes(z.id) ? "border-teal-500 bg-teal-50 text-teal-700" : "border-gray-200 text-gray-500"}`}
                            >
                              {z.label}
                            </button>
                          ))}
                        </div>
                      </div>
                    )}
                  </div>
                ))}
              </div>
            </div>

            {/* Su & Uyku */}
            <div className="card space-y-3">
              <div className="flex gap-4">
                <div className="flex-1">
                  <label className="text-xs font-medium text-gray-600 flex items-center gap-1"><Droplets className="w-3 h-3 text-blue-500" />Su: {waterIntake}L</label>
                  <input type="range" min="0.5" max="4" step="0.5" value={waterIntake} onChange={(e) => setWaterIntake(parseFloat(e.target.value))} className="w-full accent-blue-500 h-1.5" />
                </div>
                <div className="flex-1">
                  <label className="text-xs font-medium text-gray-600 flex items-center gap-1"><Moon className="w-3 h-3 text-indigo-500" />Uyku: {sleepHours}s</label>
                  <input type="range" min="3" max="12" step="0.5" value={sleepHours} onChange={(e) => setSleepHours(parseFloat(e.target.value))} className="w-full accent-indigo-500 h-1.5" />
                </div>
              </div>
            </div>

            {/* PSS-10 Stres Testi */}
            <div className="card space-y-4 border-purple-100 bg-purple-50/20">
              <div className="flex items-center gap-2">
                <div className="w-7 h-7 bg-purple-100 rounded-lg flex items-center justify-center"><span className="text-sm">🧠</span></div>
                <div><h3 className="font-bold text-gray-900 text-xs">PSS-10 Stres Testi</h3><p className="text-[10px] text-gray-500">Stres tüm cilt sorunlarını etkiler.</p></div>
              </div>
              {pss10Questions.map((q, i) => (
                <div key={i} className="space-y-1.5">
                  <p className="text-xs text-gray-700">{q}</p>
                  <input type="range" min="0" max="4" value={pssAnswers[i]}
                    onChange={(e) => { const a = [...pssAnswers]; a[i] = parseInt(e.target.value); setPssAnswers(a); }}
                    className="w-full accent-purple-500 h-1.5" />
                  <div className="flex justify-between text-[9px] text-gray-400"><span>Hiçbir zaman</span><span>Çok sık</span></div>
                </div>))}
            </div>

            {/* Sigara */}
            <div className="card space-y-3 border-amber-100 bg-amber-50/10">
              <div className="flex items-center gap-2"><Cigarette className="w-4 h-4 text-amber-700" /><span className="font-bold text-gray-900 text-xs">Sigara</span></div>
              <ChipSelect options={smokingAmountOpts} value={smokingPerDay} onChange={setSmokingPerDay} cols={3} />
              {smokingPerDay > 0 && (
                <div className="space-y-2">
                  <p className="text-[10px] text-gray-500">Kaç yıldır?</p>
                  <ChipSelect options={smokingYearsOpts} value={smokingYears} onChange={setSmokingYears} cols={3} />
                  {smokingYears > 0 && <p className="text-[10px] text-red-600 font-medium">Paket-yıl: {packYears}</p>}
                </div>)}
            </div>

            {/* Alkol */}
            <div className="card space-y-3 border-purple-100 bg-purple-50/10">
              <div className="flex items-center gap-2"><Wine className="w-4 h-4 text-purple-700" /><span className="font-bold text-gray-900 text-xs">Alkol</span></div>
              <ChipSelect options={alcoholFreqOpts} value={alcoholFreq} onChange={setAlcoholFreq} cols={3} />
              {alcoholFreq > 0 && (
                <div className="space-y-2">
                  <p className="text-[10px] text-gray-500">Bir seansta ne kadar?</p>
                  <ChipSelect options={alcoholAmtOpts} value={alcoholAmt} onChange={setAlcoholAmt} cols={2} />
                  <p className="text-[10px] text-purple-600">Haftalık: ~{alcoholFreq * alcoholAmt} kadeh</p>
                </div>)}
            </div>

            {/* Beslenme */}
            <div className="card space-y-3 border-green-100 bg-green-50/10">
              <div className="flex items-center gap-2"><UtensilsCrossed className="w-4 h-4 text-green-700" /><span className="font-bold text-gray-900 text-xs">Beslenme</span></div>
              {nutritionOpts.map((n) => (
                <div key={n.id} className="space-y-1">
                  <p className="text-[10px] text-gray-600 font-medium">{n.label}</p>
                  <ChipSelect options={n.opts} value={nutrition[n.id]} onChange={(v) => setNut(n.id, v)} cols={n.opts.length} />
                </div>))}
            </div>

            {/* Makyaj */}
            <div className="card space-y-3 border-pink-100 bg-pink-50/10">
              <div className="flex items-center gap-2"><Palette className="w-4 h-4 text-pink-700" /><span className="font-bold text-gray-900 text-xs">Makyaj</span></div>
              <div className="space-y-1">
                <p className="text-[10px] text-gray-600 font-medium">Ne sıklıkla makyaj yapıyorsun?</p>
                <ChipSelect options={makeupOpts.frequency} value={makeupFreq} onChange={setMakeupFreq} cols={2} />
              </div>
              {makeupFreq > 0 && (
                <div className="space-y-1">
                  <p className="text-[10px] text-gray-600 font-medium">Makyaj temizleme yöntemin?</p>
                  <ChipSelect options={makeupOpts.removal} value={makeupRemoval} onChange={setMakeupRemoval} cols={2} />
                </div>)}
            </div>

            <div className="flex gap-3">
              <button onClick={() => setStep(1)} className="btn-secondary flex-1"><ArrowLeft className="w-5 h-5" />Geri</button>
              <button onClick={() => { setStep3Section(0); setStep(3); }} disabled={!skinType || concerns.length === 0} className="btn-primary flex-1">Devam Et <ArrowRight className="w-5 h-5" /></button>
            </div>
          </div>
        )}

        {/* ═══ STEP 3: Kullanım soruları (yapılandırılmış, Rebi’ye geçmeden önce) ═══ */}
        {step === 3 && (
          <div className="space-y-5 animate-in fade-in">
            {step3Section === 0 && (
              <>
                <div>
                  <h2 className="text-2xl font-bold text-gray-900 mb-1">Aktif içerikli ürünler</h2>
                  <p className="text-gray-500 text-sm">Retinol, AHA/BHA, yüksek % C vitamini gibi ürünleri ne sıklıkla kullandın? Genel deneyim burada; her madde için önceki kullanım ve cilt tepkisini rutin oluşturmadan önceki ekranda tek tek işaretleyeceksin.</p>
                </div>
                <div className="card space-y-3">
                  <label className="block text-sm font-medium text-gray-700">Deneyimin</label>
                  <ChipSelect options={activesExperienceOpts} value={activesExperience} onChange={setActivesExperience} cols={1} />
                </div>
                <div className="flex gap-3">
                  <button type="button" onClick={() => setStep(2)} className="btn-secondary flex-1"><ArrowLeft className="w-5 h-5" />Geri</button>
                  <button type="button" onClick={() => setStep3Section(1)} className="btn-primary flex-1">Devam <ArrowRight className="w-5 h-5" /></button>
                </div>
              </>
            )}
            {step3Section === 1 && (
              <>
                <div><h2 className="text-2xl font-bold text-gray-900 mb-1">Soruna özel şiddet</h2><p className="text-gray-500 text-sm">Her sorun için soruları cevapla.</p></div>
                {concerns.map((concernId) => (
              <SeverityTest
                key={concernId}
                concern={concernId}
                onScoreChange={(score) => setSeverityScoresByConcern((prev) => ({ ...prev, [concernId]: score }))}
              />
            ))}

            <div className="card space-y-2">
              <label className="block text-sm font-medium text-gray-700">Ne kadar süredir?</label>
              <div className="flex flex-wrap gap-1.5">
                {durationOpts.map((o) => (
                  <button key={o.id} onClick={() => setDuration(o.id)} className={`px-3 py-2 rounded-xl text-xs font-medium border-2 transition-all ${duration === o.id ? "border-teal-500 bg-teal-50 text-teal-700" : "border-gray-200 text-gray-500"}`}>{o.label}</button>
                ))}
              </div>
            </div>
            <div className="flex gap-3">
              <button type="button" onClick={() => setStep3Section(0)} className="btn-secondary flex-1"><ArrowLeft className="w-5 h-5" />Geri</button>
              <button type="button" onClick={() => setStep3Section(2)} className="btn-primary flex-1">Devam <ArrowRight className="w-5 h-5" /></button>
            </div>
              </>
            )}
            {step3Section === 2 && (
              <>
                <div><h2 className="text-2xl font-bold text-gray-900 mb-1">Tetikleyiciler</h2><p className="text-gray-500 text-sm">Sorunların ne zaman artıyor? (çoklu seç)</p></div>
                <div className="card space-y-2">
                  <div className="flex flex-wrap gap-1.5">
                    {triggerOpts.map((o) => (
                      <button key={o.id} onClick={() => toggleArr(triggers, setTriggers, o.id)} className={`px-3 py-2 rounded-xl text-xs font-medium border-2 transition-all ${triggers.includes(o.id) ? "border-teal-500 bg-teal-50 text-teal-700" : "border-gray-200 text-gray-500"}`}>{o.label}</button>
                    ))}
                  </div>
                </div>
                <div className="flex gap-3">
                  <button type="button" onClick={() => setStep3Section(1)} className="btn-secondary flex-1"><ArrowLeft className="w-5 h-5" />Geri</button>
                  <button type="button" onClick={() => setStep3Section(3)} className="btn-primary flex-1">Devam <ArrowRight className="w-5 h-5" /></button>
                </div>
              </>
            )}
            {step3Section === 3 && (
              <>
                <div><h2 className="text-2xl font-bold text-gray-900 mb-1">Geçmiş tedaviler</h2><p className="text-gray-500 text-sm">Daha önce ne denedin? (çoklu seç)</p></div>
                <div className="card space-y-2">
                  <div className="flex flex-wrap gap-1.5">
                    {pastTreatmentOpts.map((o) => (
                      <button key={o.id} onClick={() => toggleArr(pastTreatments, setPastTreatments, o.id)} className={`px-3 py-2 rounded-xl text-xs font-medium border-2 transition-all ${pastTreatments.includes(o.id) ? "border-teal-500 bg-teal-50 text-teal-700" : "border-gray-200 text-gray-500"}`}>{o.label}</button>
                    ))}
                  </div>
                </div>
                <div className="flex gap-3">
                  <button type="button" onClick={() => setStep3Section(2)} className="btn-secondary flex-1"><ArrowLeft className="w-5 h-5" />Geri</button>
                  <button type="button" onClick={() => setStep3Section(4)} className="btn-primary flex-1">Devam <ArrowRight className="w-5 h-5" /></button>
                </div>
              </>
            )}
            {step3Section === 4 && (
              <>
                <div><h2 className="text-2xl font-bold text-gray-900 mb-1">Beklentilerin</h2><p className="text-gray-500 text-sm">Ne istiyorsun? (çoklu seç)</p></div>
                <div className="card space-y-2">
                  <div className="flex flex-wrap gap-1.5">
                    {expectationOpts.map((o) => (
                      <button key={o.id} onClick={() => toggleArr(expectations, setExpectations, o.id)} className={`px-3 py-2 rounded-xl text-xs font-medium border-2 transition-all ${expectations.includes(o.id) ? "border-teal-500 bg-teal-50 text-teal-700" : "border-gray-200 text-gray-500"}`}>{o.label}</button>
                    ))}
                  </div>
                </div>
                <div className="flex gap-3">
                  <button type="button" onClick={() => setStep3Section(3)} className="btn-secondary flex-1"><ArrowLeft className="w-5 h-5" />Geri</button>
                  <button type="button" onClick={() => setStep(4)} className="btn-primary flex-1">Devam Et <ArrowRight className="w-5 h-5" /></button>
                </div>
              </>
            )}
          </div>
        )}

        {/* ═══ STEP 4: Fotoğraf + Rutin oluştur (Rebi en sonda, rutin sonrası) ═══ */}
        {step === 4 && (
          <div className="space-y-5 animate-in fade-in">
            <div>
              <h2 className="text-2xl font-bold text-gray-900 mb-1">Son Adım</h2>
              <p className="text-gray-500 text-sm">
                İstersen hemen rutin oluşturabilirsin. <span className="font-medium text-gray-700">Süreç takibi</span> (ilerleyişi karşılaştırmak)
                için net bir yüz fotoğrafı <span className="font-medium text-gray-700">çok önerilir</span> — galeri, kamera veya web kamerası.
              </p>
            </div>
            <div className="card border-sky-100 bg-sky-50/90 text-[11px] text-sky-950 leading-relaxed space-y-2">
              <p className="font-semibold text-sky-950">Fotoğraf telefonda klasöre kaydolur mu?</p>
              <p className="text-sky-900/95">
                Hayır. Rebi tarayıcı/PWA üzerinden çalıştığında seçtiğin fotoğraf genelde{" "}
                <strong>uygulamanın bağlı olduğu güvenli bulut depoya</strong> (ör. Supabase Storage) yüklenir;
                telefonda otomatik bir &quot;Rebi&quot; klasörü oluşmaz. İndirmediğin sürece galerinde ekstra kopya da oluşmayabilir.
              </p>
            </div>
            <div className="card space-y-3">
              {photoPreview ? (
                <div className="space-y-3">
                  <img src={photoPreview} alt="" className="w-full h-64 object-cover rounded-2xl" />
                  <button type="button" onClick={clearPhoto} className="btn-secondary w-full text-sm">
                    Değiştir
                  </button>
                </div>
              ) : (
                <>
                  <p className="text-[11px] text-amber-900/95 bg-amber-50 border border-amber-100 rounded-xl px-3 py-2 leading-relaxed">
                    <span className="font-semibold">Öneri:</span> Süreç takibini kolaylaştırmak için net bir yüz fotoğrafı ekle. Mobil: Kamera ön/arka veya Galeri; masaüstü: Web kamerası veya dosya.
                  </p>
                  <p className="text-[11px] text-gray-500 leading-relaxed">
                    <span className="font-medium text-gray-700">Mod seç:</span> Telefonda ön/arka kamera; bilgisayarda galeri/dosya veya canlı webcam.
                  </p>
                  <div className="grid grid-cols-2 sm:grid-cols-4 gap-2">
                    <button
                      type="button"
                      onClick={() => triggerHiddenInput(galleryRef)}
                      className="flex flex-col items-center gap-2 p-3 border-2 border-gray-200 rounded-2xl hover:border-teal-200 transition-colors"
                    >
                      <ImagePlus className="w-6 h-6 text-gray-500" />
                      <span className="text-[10px] font-medium text-gray-600 text-center leading-tight">Galeri / dosya</span>
                    </button>
                    <button
                      type="button"
                      onClick={() => triggerHiddenInput(cameraUserRef)}
                      className="flex flex-col items-center gap-2 p-3 border-2 border-teal-200 rounded-2xl bg-teal-50/50"
                    >
                      <Camera className="w-6 h-6 text-teal-600" />
                      <span className="text-[10px] font-medium text-teal-800 text-center leading-tight">Kamera ön</span>
                    </button>
                    <button
                      type="button"
                      onClick={() => triggerHiddenInput(cameraEnvRef)}
                      className="flex flex-col items-center gap-2 p-3 border-2 border-teal-100 rounded-2xl bg-teal-50/30"
                    >
                      <Camera className="w-6 h-6 text-teal-500" />
                      <span className="text-[10px] font-medium text-teal-800 text-center leading-tight">Kamera arka</span>
                    </button>
                    <button
                      type="button"
                      onClick={() => setShowWebcam(true)}
                      className="flex flex-col items-center gap-2 p-3 border-2 border-indigo-200 rounded-2xl bg-indigo-50/50"
                    >
                      <Monitor className="w-6 h-6 text-indigo-600" />
                      <span className="text-[10px] font-medium text-indigo-800 text-center leading-tight">Web kamerası</span>
                    </button>
                  </div>
                </>
              )}
              <input
                ref={cameraUserRef}
                type="file"
                accept="image/*"
                capture="user"
                onChange={handlePhotoChange}
                className="hidden"
              />
              <input
                ref={cameraEnvRef}
                type="file"
                accept="image/*"
                capture="environment"
                onChange={handlePhotoChange}
                className="hidden"
              />
              <input ref={galleryRef} type="file" accept="image/*" onChange={handlePhotoChange} className="hidden" />
            </div>
            <div className="card bg-teal-50/50 border-teal-100 space-y-2">
              <h3 className="font-bold text-teal-800 text-xs flex items-center gap-1"><Sparkles className="w-3 h-3" />Özet</h3>
              <div className="grid grid-cols-3 gap-1.5 text-[11px]">
                <div className="bg-white rounded-lg p-2"><span className="text-gray-400 block">Yaş</span><span className="font-medium">{age}</span></div>
                <div className="bg-white rounded-lg p-2"><span className="text-gray-400 block">Cilt</span><span className="font-medium">{skinType}</span></div>
                <div className="bg-white rounded-lg p-2"><span className="text-gray-400 block">Şiddet</span><span className="font-medium">{severityScoresByConcern[primaryConcern] != null ? Math.round(severityScoresByConcern[primaryConcern]) : "?"}/10</span></div>
                <div className="bg-white rounded-lg p-2 col-span-3"><span className="text-gray-400 block">Sorunlar</span><span className="font-medium">{concerns.map((c) => concernOptions.find((o) => o.id === c)?.label).join(", ")}</span></div>
              </div>
            </div>
            <div className="flex gap-3">
              <button type="button" onClick={() => setStep(3)} className="btn-secondary flex-1"><ArrowLeft className="w-5 h-5" />Geri</button>
              <button
                type="button"
                onClick={() => {
                  setSubmitError("");
                  setShowRoutineModal(true);
                }}
                className="btn-primary flex-1"
              >
                <Sparkles className="w-5 h-5" />Optimal Rutini Oluştur
              </button>
            </div>
            {!photoFile && (
              <p className="text-center text-[11px] text-gray-500">
                Fotoğraf eklemeden de devam edebilirsin; son adımda süreç takibi için kısa bir uyarı gösterilir.
              </p>
            )}
          </div>
        )}

        {showRoutineModal && (
          <div
            className="fixed inset-0 z-[100] flex items-end sm:items-center justify-center p-3 sm:p-4 bg-black/55"
            role="dialog"
            aria-modal="true"
            aria-labelledby="routine-modal-title"
            onClick={() => setShowRoutineModal(false)}
          >
            <div
              className="bg-white rounded-2xl shadow-xl max-w-lg w-full max-h-[90vh] overflow-y-auto p-4 sm:p-5 space-y-4 border border-gray-100"
              onClick={(e) => e.stopPropagation()}
            >
              <div className="flex items-start gap-3">
                <div className="w-10 h-10 rounded-xl bg-amber-100 flex items-center justify-center shrink-0">
                  <AlertTriangle className="w-5 h-5 text-amber-600" />
                </div>
                <div>
                  <h3 id="routine-modal-title" className="font-bold text-gray-900 text-lg leading-tight">
                    Rutin öncesi bilgilendirme
                  </h3>
                  <p className="text-xs text-gray-600 mt-1.5 leading-relaxed">
                    Rebi etken madde ve konsantrasyonla yönlendirir; tıbbi teşhis veya reçete yerine geçmez. Şüphe, hamilelik/emzirme veya ilaç kullanımında mutlaka sağlık uzmanına danış.
                  </p>
                </div>
              </div>
              {!photoFile && (
                <div className="rounded-xl border border-amber-200 bg-amber-50/90 p-3 text-[11px] text-amber-950 leading-relaxed">
                  <p className="font-semibold text-amber-950 mb-1">Fotoğraf eklemedin</p>
                  <p>
                    Rutin yine oluşturulur; ilerleyişi fotoğrafla kıyaslamak zorlaşır. İstersen geri dönüp kamera veya galeriden ekleyebilirsin.
                    Yüklenen fotoğraflar güvenli bulutta saklanır, telefonda ayrı bir Rebi klasörü oluşmaz.
                  </p>
                </div>
              )}
              <div className="rounded-xl bg-teal-50/80 border border-teal-100 p-3 space-y-2 text-xs text-gray-700 leading-relaxed">
                <p className="font-semibold text-teal-900">Ürün ve formül gerçeği</p>
                <ul className="list-disc list-inside space-y-1.5 text-gray-600">
                  <li>Bir satırda birden fazla madde yazıyorsa hepsi tek şişede olmak zorunda değil; ayrı serum + nemlendirici gibi ürünlerle aynı sırayı kurabilirsin.</li>
                  <li>Etiketteki % değeri birebir olmayabilir; yakın ve daha düşük konsantrasyonla başlamak çoğu zaman uygundur.</li>
                </ul>
              </div>
              <div className="space-y-3">
                <div>
                  <p className="text-sm font-semibold text-gray-900">Daha önce kullandın mı, cildin ne yaptı?</p>
                  <p className="text-[11px] text-gray-500 leading-relaxed mt-1">
                    <strong>Ciddi tepki</strong> seçtiğin maddeler rutine hiç yazılmaz. <strong>Hiç kullanmadım</strong> → düşük sıklıkla alıştırma. <strong>Hafif tepki</strong> → daha seyrek kullanım notu. Sorunsuz → normal öneri (genel deneyimine göre).
                  </p>
                </div>
                <div className="space-y-3 max-h-[42vh] overflow-y-auto pr-1">
                  {strongActiveFamilies.map((fam) => (
                    <div key={fam.id} className="rounded-xl border border-gray-200 p-2.5 bg-gray-50/50">
                      <p className="text-xs font-medium text-gray-800 mb-1.5">{fam.label}</p>
                      <div className="flex flex-wrap gap-1">
                        {toleranceLevels.map((lv) => (
                          <button
                            key={lv.id}
                            type="button"
                            onClick={() => setFamilyTolerance(fam.id, lv.id)}
                            className={`px-2 py-1 rounded-lg text-[10px] font-medium border-2 transition-all ${
                              activesTolerance[fam.id] === lv.id
                                ? "border-teal-500 bg-teal-50 text-teal-900"
                                : "border-gray-200 text-gray-600 bg-white"
                            }`}
                          >
                            {lv.label}
                          </button>
                        ))}
                      </div>
                    </div>
                  ))}
                </div>
              </div>
              <div className="flex flex-col-reverse sm:flex-row gap-2 pt-1">
                <button
                  type="button"
                  className="btn-secondary flex-1"
                  onClick={() => setShowRoutineModal(false)}
                >
                  Geri
                </button>
                <button
                  type="button"
                  className="btn-primary flex-1"
                  onClick={() => {
                    if (!photoFile && !allowRoutineWithoutPhotoRef.current) {
                      setShowSkipPhotoModal(true);
                      return;
                    }
                    setShowRoutineModal(false);
                    handleSubmit();
                  }}
                >
                  Anladım, rutini oluştur
                </button>
              </div>
            </div>
          </div>
        )}

        {showSkipPhotoModal && (
          <div
            className="fixed inset-0 z-[110] flex items-center justify-center p-4 bg-black/60"
            role="dialog"
            aria-modal="true"
            aria-labelledby="skip-photo-title"
            onClick={() => setShowSkipPhotoModal(false)}
          >
            <div
              className="bg-white rounded-2xl shadow-xl max-w-md w-full p-5 space-y-4 border border-amber-100"
              onClick={(e) => e.stopPropagation()}
            >
              <div className="flex items-start gap-3">
                <div className="w-10 h-10 rounded-xl bg-amber-100 flex items-center justify-center shrink-0">
                  <AlertTriangle className="w-5 h-5 text-amber-700" />
                </div>
                <div>
                  <h3 id="skip-photo-title" className="font-bold text-gray-900 text-base leading-tight">
                    Süreç takibi için fotoğraf önerilir
                  </h3>
                  <p className="text-xs text-gray-600 mt-2 leading-relaxed">
                    Fotoğrafsız devam edebilirsin; rutin üretilir. İlerleyişi zaman içinde karşılaştırmak için yüz fotoğrafı faydalıdır.
                  </p>
                  <p className="text-xs text-gray-600 mt-2 leading-relaxed">
                    Yüklediğin görüntü <strong>uygulamanın sunucu tarafındaki güvenli depoda</strong> tutulur.
                    Bu bir web uygulaması olduğu için fotoğraf genelde <strong>telefonda ayrı bir Rebi klasörüne kaydedilmez</strong>
                    (galerinde yalnızca çektiğin/ seçtiğin kopya kalabilir).
                  </p>
                </div>
              </div>
              <div className="flex flex-col-reverse sm:flex-row gap-2 pt-1">
                <button
                  type="button"
                  className="btn-secondary flex-1"
                  onClick={() => {
                    setShowSkipPhotoModal(false);
                  }}
                >
                  Fotoğraf ekleyeyim
                </button>
                <button
                  type="button"
                  className="btn-primary flex-1"
                  onClick={() => {
                    allowRoutineWithoutPhotoRef.current = true;
                    setShowSkipPhotoModal(false);
                    setShowRoutineModal(false);
                    handleSubmit();
                  }}
                >
                  Yine de rutini oluştur
                </button>
              </div>
            </div>
          </div>
        )}

        <WebcamCapture
          open={showWebcam}
          onClose={() => setShowWebcam(false)}
          onPhoto={applyPhotoFile}
        />
      </div>
    </div>
  );
}
