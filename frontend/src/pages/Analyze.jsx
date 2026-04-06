import { useState, useRef, useMemo, useEffect } from "react";
import { useNavigate, useSearchParams, Link } from "react-router-dom";
import { useAuth } from "../context/AuthContext";
import { useTheme } from "../context/ThemeContext";
import { API_URL, supabase } from "../lib/supabase";
import ThemePatternOverlay from "../components/ThemePatternOverlay";
import { apiAuthHeaders } from "../lib/apiAuth";
import { DEMO_USER_ID } from "../lib/demoUser";
import { hasCompletedOnboarding } from "../lib/routineTracking";
import { formatApiErrorDetail, isNetworkError } from "../lib/apiErrors";
import { analyzeSkinPhotoQuality } from "../lib/imageQuality";
import { ingestDailyTrackingEvent } from "../lib/dailyTracking";
import LoadingScreen from "../components/LoadingScreen";
import SkinTypeVisual from "../components/SkinTypeVisual";
import SeverityTest from "../components/SeverityTest";
import WebcamCapture from "../components/WebcamCapture";
import { useTranslation } from "react-i18next";
import { interpolate } from "../lib/interpolate";
import { useAnalyzeWizardPack } from "../lib/localePacks";
import {
  MapPin, ArrowRight, ArrowLeft, Camera, ImagePlus, Monitor,
  Droplets, Moon, Cigarette, Wine, AlertCircle, CheckCircle,
  User, Sparkles, Heart, Send, Bot, Loader2,
  UtensilsCrossed, Palette, AlertTriangle,
} from "lucide-react";

const STRONG_ACTIVE_FAMILY_IDS = [
  "retinol",
  "bha",
  "aha",
  "benzoyl",
  "azelaic",
  "vitamin_c",
  "bakuchiol",
  "pigment",
  "niacinamide",
];

const CONCERN_DEFS = [
  { id: "acne", icon: "🔴" },
  { id: "aging", icon: "✨" },
  { id: "dryness", icon: "🏜️" },
  { id: "pigmentation", icon: "🎯" },
  { id: "sensitivity", icon: "🌸" },
];

function calcCyclePhase(lastPeriodDate, cycleLength) {
  if (!lastPeriodDate) return "unknown";
  const diff = Math.floor((new Date() - new Date(lastPeriodDate)) / 86400000);
  const day = ((diff % cycleLength) + cycleLength) % cycleLength;
  if (day <= 5) return "menstrual";
  if (day <= 13) return "follicular";
  if (day <= 15) return "ovulation";
  return "luteal";
}

/** Profilden veya rutin hazır ekranından: yalnızca depoya foto yükle (tam analiz zorunlu değil). */
function AnalyzePhotoOnly({ user, navigate }) {
  const { theme } = useTheme();
  const { t } = useTranslation();
  const pack = useAnalyzeWizardPack();
  const cameraUserRef = useRef(null);
  const cameraEnvRef = useRef(null);
  const galleryRef = useRef(null);
  const previewUrlRef = useRef(null);
  const [photoFile, setPhotoFile] = useState(null);
  const [photoPreview, setPhotoPreview] = useState(null);
  const [showWebcam, setShowWebcam] = useState(false);
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState({ type: "", text: "" });
  const [photoContext, setPhotoContext] = useState("unsure");
  const [photoQuality, setPhotoQuality] = useState(null);

  const applyPhotoFile = async (file) => {
    if (!file) return;
    if (previewUrlRef.current?.startsWith("blob:")) URL.revokeObjectURL(previewUrlRef.current);
    setPhotoFile(file);
    const url = URL.createObjectURL(file);
    previewUrlRef.current = url;
    setPhotoPreview(url);
    setPhotoQuality(null);
    setMsg({ type: "", text: "" });
    const q = await analyzeSkinPhotoQuality(file);
    setPhotoQuality(q);
  };

  const clearPhoto = () => {
    if (previewUrlRef.current?.startsWith("blob:")) URL.revokeObjectURL(previewUrlRef.current);
    previewUrlRef.current = null;
    setPhotoFile(null);
    setPhotoPreview(null);
    setPhotoQuality(null);
  };

  const handlePhotoChange = async (e) => {
    const file = e.target.files?.[0];
    if (file) await applyPhotoFile(file);
    e.target.value = "";
  };

  const triggerHiddenInput = (ref) => ref.current?.click();

  const uploadOnly = async () => {
    if (!photoFile) {
      setMsg({ type: "err", text: pack.errors.pickPhotoFirst });
      return;
    }
    if (!supabase) {
      setMsg({ type: "err", text: pack.errors.storageNotConfigured });
      return;
    }
    const uid = user?.id;
    if (!uid) {
      setMsg({ type: "err", text: pack.errors.sessionRequired });
      return;
    }
    setBusy(true);
    setMsg({ type: "", text: "" });
    try {
      const ext = (photoFile.name.split(".").pop() || "jpg").replace(/[^a-z0-9]/gi, "") || "jpg";
      const path = `${uid}/${Date.now()}.${ext}`;
      const { error } = await supabase.storage.from("skin-photos").upload(path, photoFile);
      if (error) throw error;
      await ingestDailyTrackingEvent(uid, "photo_meta", {
        context: photoContext,
        meanLuma: photoQuality?.meanLuma ?? null,
        variance: photoQuality?.variance ?? null,
        sharpnessApprox: photoQuality?.sharpnessApprox ?? null,
        flow: "photo_only",
      });
      setMsg({
        type: "ok",
        text: pack.errors.uploadSuccess,
      });
      clearPhoto();
    } catch (e) {
      setMsg({
        type: "err",
        text: e?.message || pack.errors.uploadFailed,
      });
    } finally {
      setBusy(false);
    }
  };

  if (!supabase) {
    return (
      <div className={`min-h-screen ${theme.bg} pb-24 relative flex items-center justify-center px-4`}>
        <ThemePatternOverlay pattern={theme.pattern} />
        <p className="relative z-[1] text-sm text-gray-600 text-center">
          {pack.errors.supabaseAnalyzeMissing}
        </p>
      </div>
    );
  }

  return (
    <div className={`min-h-screen ${theme.bg} pb-[calc(8rem+env(safe-area-inset-bottom))] relative`}>
      <ThemePatternOverlay pattern={theme.pattern} />
      <div className="relative z-[1] max-w-lg mx-auto px-4 py-8 space-y-4">
        <button
          type="button"
          onClick={() => navigate(-1)}
          className="text-xs font-medium text-gray-500 hover:text-gray-800 flex items-center gap-1"
        >
          <ArrowLeft className="w-4 h-4" /> {t("analyze.photoOnlyBack")}
        </button>
        <div className="text-center space-y-2">
          <div
            className="w-14 h-14 rounded-2xl flex items-center justify-center mx-auto shadow-lg text-white"
            style={{ background: `linear-gradient(135deg, ${theme.accent}, ${theme.primary})` }}
          >
            <Camera className="w-7 h-7" />
          </div>
          <h1 className="text-xl font-bold text-gray-900">{t("analyze.photoOnlyTitle")}</h1>
          <p className="text-sm text-gray-600 leading-relaxed">
            {pack.errors.photoOnlyIntro1}
            {pack.errors.photoOnlyIntro2 ? ` ${pack.errors.photoOnlyIntro2}` : ""}
          </p>
        </div>

        {msg.text && (
          <div
            className={`rounded-xl px-3 py-2 text-sm ${
              msg.type === "ok"
                ? "bg-emerald-50 text-emerald-900 border border-emerald-100"
                : "bg-red-50 text-red-800 border border-red-100"
            }`}
          >
            {msg.text}
          </div>
        )}

        <div className="card space-y-3">
          {photoPreview ? (
            <div className="space-y-3">
              <img src={photoPreview} alt="" className="w-full h-64 object-cover rounded-2xl" />
              <button type="button" onClick={clearPhoto} className="btn-secondary w-full text-sm">
                {pack.photoOnly.change}
              </button>
              <div className="space-y-2">
                <label className="text-xs font-semibold text-gray-700">{t("analyze.photoContextLabel")}</label>
                <select
                  value={photoContext}
                  onChange={(e) => setPhotoContext(e.target.value)}
                  className="w-full rounded-xl border border-gray-200 px-3 py-2 text-sm bg-white"
                >
                  <option value="first">{t("analyze.photoContextFirst")}</option>
                  <option value="same_light">{t("analyze.photoContextSame")}</option>
                  <option value="progress">{t("analyze.photoContextProgress")}</option>
                  <option value="unsure">{t("analyze.photoContextUnsure")}</option>
                </select>
                {photoQuality?.tooDark ? (
                  <p className="text-[11px] text-amber-900 bg-amber-50 border border-amber-100 rounded-lg px-2 py-1.5">
                    {t("analyze.photoTooDark")}
                  </p>
                ) : null}
                {photoQuality?.tooBlurry ? (
                  <p className="text-[11px] text-amber-900 bg-amber-50 border border-amber-100 rounded-lg px-2 py-1.5">
                    {t("analyze.photoTooBlurry")}
                  </p>
                ) : null}
                {photoQuality && !photoQuality.tooDark && !photoQuality.tooBlurry ? (
                  <p className="text-[11px] text-emerald-800 bg-emerald-50 border border-emerald-100 rounded-lg px-2 py-1.5">
                    {t("analyze.photoQualityOk")}
                  </p>
                ) : null}
              </div>
            </div>
          ) : (
            <div className="grid grid-cols-2 sm:grid-cols-4 gap-2">
              <button
                type="button"
                onClick={() => triggerHiddenInput(galleryRef)}
                className="flex flex-col items-center gap-2 p-3 border-2 border-gray-200 rounded-2xl hover:border-teal-200 transition-colors"
              >
                <ImagePlus className="w-6 h-6 text-gray-500" />
                <span className="text-[10px] font-medium text-gray-600 text-center leading-tight">
                  {pack.step4.galleryFile}
                </span>
              </button>
              <button
                type="button"
                onClick={() => triggerHiddenInput(cameraUserRef)}
                className="flex flex-col items-center gap-2 p-3 border-2 border-teal-200 rounded-2xl bg-teal-50/50"
              >
                <Camera className="w-6 h-6 text-teal-600" />
                <span className="text-[10px] font-medium text-teal-800 text-center leading-tight">
                  {pack.step4.cameraFront}
                </span>
              </button>
              <button
                type="button"
                onClick={() => triggerHiddenInput(cameraEnvRef)}
                className="flex flex-col items-center gap-2 p-3 border-2 border-teal-100 rounded-2xl bg-teal-50/30"
              >
                <Camera className="w-6 h-6 text-teal-500" />
                <span className="text-[10px] font-medium text-teal-800 text-center leading-tight">
                  {pack.step4.cameraRear}
                </span>
              </button>
              <button
                type="button"
                onClick={() => setShowWebcam(true)}
                className="flex flex-col items-center gap-2 p-3 border-2 border-indigo-200 rounded-2xl bg-indigo-50/50"
              >
                <Monitor className="w-6 h-6 text-indigo-600" />
                <span className="text-[10px] font-medium text-indigo-800 text-center leading-tight">
                  {pack.step4.webcam}
                </span>
              </button>
            </div>
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

        <button
          type="button"
          onClick={uploadOnly}
          disabled={busy || !photoFile}
          className="btn-primary w-full justify-center disabled:opacity-50"
          style={{ backgroundColor: theme.primary }}
        >
          {busy ? <Loader2 className="w-5 h-5 animate-spin" /> : pack.photoOnly.savePhoto}
        </button>

        <div className="flex flex-col gap-2 text-center text-sm">
          <Link to="/dashboard/profile" className="font-semibold" style={{ color: theme.primary }}>
            {pack.photoOnly.goProfilePhotos}
          </Link>
          <Link to="/dashboard/analyze" className="text-gray-500 hover:text-gray-700 text-xs">
            {pack.photoOnly.fullFormLink}
          </Link>
        </div>

        <WebcamCapture open={showWebcam} onClose={() => setShowWebcam(false)} onPhoto={applyPhotoFile} />
      </div>
    </div>
  );
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
  const [searchParams] = useSearchParams();
  const { theme } = useTheme();
  const { t } = useTranslation();
  const pack = useAnalyzeWizardPack();
  const photoOnlyMode = searchParams.get("photo") === "1";
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
  const [specialFlags, setSpecialFlags] = useState({
    // aging / lines
    frown_lines: false,
    smile_lines: false,
    eye_crows_feet: false,
    // sensitivity / redness nuances
    redness_diffuse: false,
    redness_acne_marks: false,
    cold_sensitive: false,
    stings_with_products: false,
  });

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
  const [photoContext, setPhotoContext] = useState("unsure");
  const [photoQuality, setPhotoQuality] = useState(null);
  const [showRoutineModal, setShowRoutineModal] = useState(false);
  const [showSkipPhotoModal, setShowSkipPhotoModal] = useState(false);
  const [showWebcam, setShowWebcam] = useState(false);
  /** Fotoğrafsız rutin için kullanıcı bir kez onayladı (aynı oturumda tekrar sorma). */
  const allowRoutineWithoutPhotoRef = useRef(false);
  /** Her güçlü aktif ailesi: never | good | mild | bad */
  const [activesTolerance, setActivesTolerance] = useState(() =>
    Object.fromEntries(STRONG_ACTIVE_FAMILY_IDS.map((id) => [id, "good"]))
  );

  const genders = useMemo(
    () => ["female", "male", "other"].map((id) => ({ id, label: pack.gender[id] || id })),
    [pack]
  );
  const concernOptions = useMemo(
    () => CONCERN_DEFS.map((c) => ({ ...c, label: pack.concern[c.id] || c.id })),
    [pack]
  );
  const zoneOptions = useMemo(
    () =>
      ["forehead", "nose", "cheeks", "chin", "undereye", "lips", "temples"].map((id) => ({
        id,
        label: pack.zone[id] || id,
      })),
    [pack]
  );
  const durationOpts = useMemo(
    () => ["1-3", "3-6", "6-12", "1y+"].map((id) => ({ id, label: pack.duration[id] || id })),
    [pack]
  );
  const triggerOpts = useMemo(
    () =>
      ["stress", "period", "sun", "food", "season", "cold", "heat", "other"].map((id) => ({
        id,
        label: pack.trigger[id] || id,
      })),
    [pack]
  );
  const pastTreatmentOpts = useMemo(
    () =>
      ["none", "cleanser", "moisturizer", "rx", "derm", "otc"].map((id) => ({
        id,
        label: pack.pastTreatment[id] || id,
      })),
    [pack]
  );
  const activesExperienceOpts = useMemo(
    () =>
      ["none", "occasional", "regular"].map((id) => ({
        id,
        label: pack.activesExperience[id] || id,
      })),
    [pack]
  );
  const strongActiveFamilies = useMemo(
    () =>
      STRONG_ACTIVE_FAMILY_IDS.map((id) => ({
        id,
        label: pack.strongFamily[id] || id,
      })),
    [pack]
  );
  const toleranceLevels = useMemo(
    () =>
      ["never", "good", "mild", "bad"].map((id) => ({
        id,
        label: pack.tolerance[id] || id,
      })),
    [pack]
  );
  const expectationOpts = useMemo(
    () =>
      ["acne_less", "spots_less", "clean_skin", "hydration", "aging_slow", "comfort"].map((id) => ({
        id,
        label: pack.expectation[id] || id,
      })),
    [pack]
  );
  const pss10Questions = useMemo(() => pack.pss10 || [], [pack]);
  const smokingAmountOpts = useMemo(
    () => [0, 1, 5, 15, 25].map((id) => ({ id, label: pack.smokingAmount[String(id)] || "" })),
    [pack]
  );
  const smokingYearsOpts = useMemo(
    () => [0, 2, 5, 10, 20].map((id) => ({ id, label: pack.smokingYears[String(id)] || "" })),
    [pack]
  );
  const alcoholFreqOpts = useMemo(
    () => [0, 1, 3, 5, 7].map((id) => ({ id, label: pack.alcoholFreq[String(id)] || "" })),
    [pack]
  );
  const alcoholAmtOpts = useMemo(
    () => [1, 2, 4, 6].map((id) => ({ id, label: pack.alcoholAmt[String(id)] || "" })),
    [pack]
  );
  const nutritionOpts = useMemo(
    () =>
      ["fastfood", "sugar", "dairy", "veggies"].map((key) => ({
        id: key,
        label: pack.nutrition[key]?.label || key,
        opts: Object.entries(pack.nutrition[key]?.opts || {}).map(([oid, label]) => ({
          id: Number(oid),
          label,
        })),
      })),
    [pack]
  );
  const makeupOpts = useMemo(
    () => ({
      frequency: [0, 1, 3, 5].map((id) => ({
        id,
        label: pack.makeup.frequency[String(id)] || "",
      })),
      removal: ["none", "water", "cleanser", "double"].map((id) => ({
        id,
        label: pack.makeup.removal[id] || id,
      })),
    }),
    [pack]
  );
  const hormonalOpts = useMemo(
    () =>
      ["regular", "irregular", "pregnant", "menopause"].map((id) => ({
        id,
        label: pack.step1[`hormonal_${id}`],
      })),
    [pack]
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
  const toggleFlag = (k) => setSpecialFlags((p) => ({ ...p, [k]: !p[k] }));
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
      () => {
        setLocationError(pack.errors.locationFailed);
        setLocationLoading(false);
      },
      { enableHighAccuracy: true, timeout: 10000 }
    );
  };

  /* ─── Foto: galeri / mobil kamera / webcam ─── */
  const applyPhotoFile = async (file) => {
    if (!file) return;
    allowRoutineWithoutPhotoRef.current = false;
    if (previewUrlRef.current?.startsWith("blob:")) URL.revokeObjectURL(previewUrlRef.current);
    setPhotoFile(file);
    const url = URL.createObjectURL(file);
    previewUrlRef.current = url;
    setPhotoPreview(url);
    setPhotoQuality(null);
    const q = await analyzeSkinPhotoQuality(file);
    setPhotoQuality(q);
  };

  const clearPhoto = () => {
    allowRoutineWithoutPhotoRef.current = false;
    if (previewUrlRef.current?.startsWith("blob:")) URL.revokeObjectURL(previewUrlRef.current);
    previewUrlRef.current = null;
    setPhotoFile(null);
    setPhotoPreview(null);
    setPhotoQuality(null);
  };

  const handlePhotoChange = async (e) => {
    const file = e.target.files?.[0];
    if (file) await applyPhotoFile(file);
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
          setSubmitError(pack.errors.photoUploadWarn);
        } else {
          photoUrl = supabase.storage.from("skin-photos").getPublicUrl(path)?.data?.publicUrl;
          if (photoUrl && user?.id) {
            ingestDailyTrackingEvent(user.id, "photo_meta", {
              context: photoContext,
              meanLuma: photoQuality?.meanLuma ?? null,
              variance: photoQuality?.variance ?? null,
              sharpnessApprox: photoQuality?.sharpnessApprox ?? null,
              flow: "analyze_full",
            }).catch(() => {});
          }
        }
      } else if (photoFile && !supabase) {
        setSubmitError(pack.errors.storageOffWarn);
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
        special_flags: Object.values(specialFlags).some(Boolean) ? specialFlags : null,
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
        setSubmitError(pack.errors.networkError);
      } else {
        setSubmitError(err?.message || pack.errors.unexpectedError);
      }
    } finally {
      setLoading(false);
    }
  };

  if (photoOnlyMode) {
    return <AnalyzePhotoOnly user={user} navigate={navigate} />;
  }

  if (loading) return <LoadingScreen />;

  const uid = user?.id || DEMO_USER_ID;
  const showCompactHub =
    !forceFullWizard && hasCompletedOnboarding(uid);

  if (showCompactHub) {
    return (
      <div className={`min-h-screen ${theme.bg} pb-[calc(8rem+env(safe-area-inset-bottom))] relative`}>
        <ThemePatternOverlay pattern={theme.pattern} />
        <div className="relative z-[1] max-w-lg mx-auto px-4 py-10">
          <div
            className="card space-y-4 !p-6 text-center border-opacity-80"
            style={{ borderColor: theme.primaryLight }}
          >
            <div
              className="w-16 h-16 rounded-2xl flex items-center justify-center mx-auto shadow-lg text-white"
              style={{ background: `linear-gradient(135deg, ${theme.accent}, ${theme.primary})` }}
            >
              <Sparkles className="w-8 h-8 text-white" />
            </div>
            <h1 className="text-xl font-bold text-gray-900">{t("analyze.routineReadyTitle")}</h1>
            <p className="text-sm text-gray-600 leading-relaxed">{pack.compactHub.description}</p>
            <div className="flex flex-col gap-2 pt-2">
              <button
                type="button"
                onClick={() => navigate("/dashboard")}
                className="btn-primary w-full justify-center"
                style={{ backgroundColor: theme.primary }}
              >
                {pack.compactHub.backToDashboard} <ArrowRight className="w-5 h-5" />
              </button>
              <Link
                to="/dashboard/analyze?photo=1"
                className="w-full py-3 rounded-xl text-sm font-semibold border-2 flex items-center justify-center gap-2"
                style={{ borderColor: theme.primaryLight, color: theme.primary }}
              >
                <Camera className="w-5 h-5" />
                {t("analyze.quickPhotoUpload")}
              </Link>
              <button
                type="button"
                onClick={() => {
                  setForceFullWizard(true);
                  setStep(1);
                }}
                className="btn-secondary w-full justify-center text-sm"
                style={{ borderColor: theme.primaryLight, color: theme.primary }}
              >
                {t("analyze.newAnalyzeFull")}
              </button>
            </div>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className={`min-h-screen ${theme.bg} pb-[calc(8rem+env(safe-area-inset-bottom))] relative`}>
      <ThemePatternOverlay pattern={theme.pattern} />
      <div className="relative z-[1] max-w-lg mx-auto px-4 py-8">
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
              <p className="font-semibold text-red-950">{t("analyze.generateFailedTitle")}</p>
              <p className="mt-1 text-red-900/95 leading-relaxed">{submitError}</p>
            </div>
            <button
              type="button"
              onClick={() => setSubmitError("")}
              className="shrink-0 text-xs font-semibold text-red-700 underline-offset-2 hover:underline"
            >
              {t("common.close")}
            </button>
          </div>
        )}

        {/* ═══ STEP 1: Temel ═══ */}
        {step === 1 && (
          <div className="space-y-5 animate-in fade-in">
            <div>
              <h2 className="text-2xl font-bold text-gray-900 mb-1">{pack.step1.title}</h2>
              <p className="text-gray-500 text-sm">{pack.step1.subtitle}</p>
            </div>
            <div className="card space-y-4">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">{pack.step1.nameLabel}</label>
                <div className="relative"><User className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400" />
                  <input type="text" value={name} onChange={(e) => setName(e.target.value)} className="input-field !pl-10" placeholder={pack.step1.namePlaceholder} /></div>
              </div>
              <div className="grid grid-cols-2 gap-3">
                <div><label className="block text-sm font-medium text-gray-700 mb-1">{pack.step1.ageLabel}</label>
                  <input type="number" value={age} onChange={(e) => setAge(e.target.value)} className="input-field" placeholder="25" min="10" max="120" /></div>
                <div><label className="block text-sm font-medium text-gray-700 mb-1">{pack.step1.genderLabel}</label>
                  <div className="flex gap-1.5">
                    {genders.map((g) => (<button key={g.id} onClick={() => { setGender(g.id); if (g.id !== "female") setHormonalStatus(""); }}
                      className={`flex-1 py-2.5 rounded-xl text-xs font-medium border-2 transition-all ${gender === g.id ? "border-teal-500 bg-teal-50 text-teal-700" : "border-gray-200 text-gray-500"}`}>{g.label}</button>))}
                  </div></div>
              </div>
              <div>{locationSet ? (<div className="flex items-center gap-2 p-2.5 bg-teal-50 rounded-xl text-teal-700 text-xs"><CheckCircle className="w-4 h-4" /> {t("analyze.locationSet")}</div>
              ) : (<button onClick={getLocation} disabled={locationLoading} className="btn-secondary w-full text-sm">{locationLoading ? <Loader2 className="w-4 h-4 animate-spin" /> : <><MapPin className="w-4 h-4" />{t("analyze.location")}</>}</button>)}
                {locationError && <p className="text-red-500 text-xs mt-1">{locationError}</p>}</div>
            </div>
            {isFemale && (
              <div className="card space-y-3 border-pink-100 bg-pink-50/20">
                <div className="flex items-center gap-2"><Heart className="w-4 h-4 text-pink-600" /><span className="font-semibold text-gray-900 text-sm">{pack.step1.hormonalTitle}</span></div>
                <div className="grid grid-cols-2 gap-1.5">
                  {hormonalOpts.map((o) => (
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
              {t("analyze.continue")} <ArrowRight className="w-5 h-5" />
            </button>
            {isFemale && (hormonalStatus === "regular" || hormonalStatus === "irregular") && !lastPeriodDate && (
              <p className="text-center text-xs text-amber-700 mt-2">{pack.step1.periodHint}</p>
            )}
          </div>
        )}

        {/* ═══ STEP 2: Cilt + Yaşam Tarzı (detaylı) ═══ */}
        {step === 2 && (
          <div className="space-y-5 animate-in fade-in">
            <div>
              <h2 className="text-2xl font-bold text-gray-900 mb-1">{pack.step2.title}</h2>
              <p className="text-gray-500 text-sm">{pack.step2.subtitle}</p>
            </div>

            {/* Cilt Tipi */}
            <div className="card space-y-3">
              <label className="block text-sm font-medium text-gray-700">{t("analyze.skinType")}</label>
              <SkinTypeVisual value={skinType} onChange={setSkinType} />
            </div>

            {/* Sorunlar + her biri için etkilenen bölgeler */}
            <div className="card space-y-3">
              <label className="block text-sm font-medium text-gray-700">{t("analyze.concerns")}</label>
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
                        <p className="text-[10px] text-gray-500">
                          {interpolate(pack.step2.zonesHint, { concern: c.label })}
                        </p>
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

            {/* Soruna göre netleştirici mini sorular (karışıklığı azaltır) */}
            {(concerns.includes("aging") || concerns.includes("sensitivity")) && (
              <div className="card space-y-3 border-slate-100 bg-slate-50/60">
                <p className="text-xs font-bold text-gray-800">{pack.step2.clarifyTitle}</p>
                {concerns.includes("aging") && (
                  <div className="space-y-2">
                    <p className="text-[11px] text-gray-600 leading-relaxed">{pack.step2.agingIntro}</p>
                    <div className="flex flex-wrap gap-2">
                      <button
                        type="button"
                        onClick={() => toggleFlag("frown_lines")}
                        className={`px-3 py-1.5 rounded-full text-xs font-medium border-2 ${
                          specialFlags.frown_lines ? "border-teal-500 bg-teal-50 text-teal-800" : "border-gray-200 text-gray-600"
                        }`}
                      >
                        {pack.step2.aging_frown}
                      </button>
                      <button
                        type="button"
                        onClick={() => toggleFlag("eye_crows_feet")}
                        className={`px-3 py-1.5 rounded-full text-xs font-medium border-2 ${
                          specialFlags.eye_crows_feet ? "border-teal-500 bg-teal-50 text-teal-800" : "border-gray-200 text-gray-600"
                        }`}
                      >
                        {pack.step2.aging_crow}
                      </button>
                      <button
                        type="button"
                        onClick={() => toggleFlag("smile_lines")}
                        className={`px-3 py-1.5 rounded-full text-xs font-medium border-2 ${
                          specialFlags.smile_lines ? "border-teal-500 bg-teal-50 text-teal-800" : "border-gray-200 text-gray-600"
                        }`}
                      >
                        {pack.step2.aging_smile}
                      </button>
                    </div>
                  </div>
                )}

                {concerns.includes("sensitivity") && (
                  <div className="space-y-2">
                    <p className="text-[11px] text-gray-600 leading-relaxed">
                      {pack.step2.sensitivityIntro}
                      <span className="text-gray-500"> {pack.step2.sensitivityNote}</span>
                    </p>
                    <div className="flex flex-wrap gap-2">
                      <button
                        type="button"
                        onClick={() => toggleFlag("redness_diffuse")}
                        className={`px-3 py-1.5 rounded-full text-xs font-medium border-2 ${
                          specialFlags.redness_diffuse ? "border-teal-500 bg-teal-50 text-teal-800" : "border-gray-200 text-gray-600"
                        }`}
                      >
                        {pack.step2.redness_diffuse}
                      </button>
                      <button
                        type="button"
                        onClick={() => toggleFlag("redness_acne_marks")}
                        className={`px-3 py-1.5 rounded-full text-xs font-medium border-2 ${
                          specialFlags.redness_acne_marks ? "border-teal-500 bg-teal-50 text-teal-800" : "border-gray-200 text-gray-600"
                        }`}
                      >
                        {pack.step2.redness_acne_marks}
                      </button>
                      <button
                        type="button"
                        onClick={() => toggleFlag("cold_sensitive")}
                        className={`px-3 py-1.5 rounded-full text-xs font-medium border-2 ${
                          specialFlags.cold_sensitive ? "border-teal-500 bg-teal-50 text-teal-800" : "border-gray-200 text-gray-600"
                        }`}
                      >
                        {pack.step2.cold_sensitive}
                      </button>
                      <button
                        type="button"
                        onClick={() => toggleFlag("stings_with_products")}
                        className={`px-3 py-1.5 rounded-full text-xs font-medium border-2 ${
                          specialFlags.stings_with_products ? "border-teal-500 bg-teal-50 text-teal-800" : "border-gray-200 text-gray-600"
                        }`}
                      >
                        {pack.step2.stings_products}
                      </button>
                    </div>
                    <p className="text-[10px] text-gray-500 leading-relaxed">{pack.step2.sensitivityFootnote}</p>
                  </div>
                )}
              </div>
            )}

            {/* Su & Uyku */}
            <div className="card space-y-3">
              <div className="flex gap-4">
                <div className="flex-1">
                  <label className="text-xs font-medium text-gray-600 flex items-center gap-1"><Droplets className="w-3 h-3 text-blue-500" />{interpolate(pack.step2.waterLabel, { n: waterIntake })}</label>
                  <input type="range" min="0.5" max="4" step="0.5" value={waterIntake} onChange={(e) => setWaterIntake(parseFloat(e.target.value))} className="w-full accent-blue-500 h-1.5" />
                </div>
                <div className="flex-1">
                  <label className="text-xs font-medium text-gray-600 flex items-center gap-1"><Moon className="w-3 h-3 text-indigo-500" />{interpolate(pack.step2.sleepLabel, { n: sleepHours })}</label>
                  <input type="range" min="3" max="12" step="0.5" value={sleepHours} onChange={(e) => setSleepHours(parseFloat(e.target.value))} className="w-full accent-indigo-500 h-1.5" />
                </div>
              </div>
            </div>

            {/* PSS-10 Stres Testi */}
            <div className="card space-y-4 border-purple-100 bg-purple-50/20">
              <div className="flex items-center gap-2">
                <div className="w-7 h-7 bg-purple-100 rounded-lg flex items-center justify-center"><span className="text-sm">🧠</span></div>
                <div><h3 className="font-bold text-gray-900 text-xs">{pack.step2.pssTitle}</h3><p className="text-[10px] text-gray-500">{pack.step2.pssSubtitle}</p></div>
              </div>
              {pss10Questions.map((q, i) => (
                <div key={i} className="space-y-1.5">
                  <p className="text-xs text-gray-700">{q}</p>
                  <input type="range" min="0" max="4" value={pssAnswers[i]}
                    onChange={(e) => { const a = [...pssAnswers]; a[i] = parseInt(e.target.value); setPssAnswers(a); }}
                    className="w-full accent-purple-500 h-1.5" />
                  <div className="flex justify-between text-[9px] text-gray-400"><span>{pack.step2.scaleNever}</span><span>{pack.step2.scaleOften}</span></div>
                </div>))}
            </div>

            {/* Sigara */}
            <div className="card space-y-3 border-amber-100 bg-amber-50/10">
              <div className="flex items-center gap-2"><Cigarette className="w-4 h-4 text-amber-700" /><span className="font-bold text-gray-900 text-xs">{pack.step2.smokingTitle}</span></div>
              <ChipSelect options={smokingAmountOpts} value={smokingPerDay} onChange={setSmokingPerDay} cols={3} />
              {smokingPerDay > 0 && (
                <div className="space-y-2">
                  <p className="text-[10px] text-gray-500">{pack.step2.smokingYears}</p>
                  <ChipSelect options={smokingYearsOpts} value={smokingYears} onChange={setSmokingYears} cols={3} />
                  {smokingYears > 0 && <p className="text-[10px] text-red-600 font-medium">{interpolate(pack.step2.packYears, { n: packYears })}</p>}
                </div>)}
            </div>

            {/* Alkol */}
            <div className="card space-y-3 border-purple-100 bg-purple-50/10">
              <div className="flex items-center gap-2"><Wine className="w-4 h-4 text-purple-700" /><span className="font-bold text-gray-900 text-xs">{pack.step2.alcoholTitle}</span></div>
              <ChipSelect options={alcoholFreqOpts} value={alcoholFreq} onChange={setAlcoholFreq} cols={3} />
              {alcoholFreq > 0 && (
                <div className="space-y-2">
                  <p className="text-[10px] text-gray-500">{pack.step2.alcoholSession}</p>
                  <ChipSelect options={alcoholAmtOpts} value={alcoholAmt} onChange={setAlcoholAmt} cols={2} />
                  <p className="text-[10px] text-purple-600">{interpolate(pack.step2.alcoholWeekly, { n: alcoholFreq * alcoholAmt })}</p>
                </div>)}
            </div>

            {/* Beslenme */}
            <div className="card space-y-3 border-green-100 bg-green-50/10">
              <div className="flex items-center gap-2"><UtensilsCrossed className="w-4 h-4 text-green-700" /><span className="font-bold text-gray-900 text-xs">{pack.step2.nutritionTitle}</span></div>
              {nutritionOpts.map((n) => (
                <div key={n.id} className="space-y-1">
                  <p className="text-[10px] text-gray-600 font-medium">{n.label}</p>
                  <ChipSelect options={n.opts} value={nutrition[n.id]} onChange={(v) => setNut(n.id, v)} cols={n.opts.length} />
                </div>))}
            </div>

            {/* Makyaj */}
            <div className="card space-y-3 border-pink-100 bg-pink-50/10">
              <div className="flex items-center gap-2"><Palette className="w-4 h-4 text-pink-700" /><span className="font-bold text-gray-900 text-xs">{pack.step2.makeupTitle}</span></div>
              <div className="space-y-1">
                <p className="text-[10px] text-gray-600 font-medium">{pack.step2.makeupFreqQ}</p>
                <ChipSelect options={makeupOpts.frequency} value={makeupFreq} onChange={setMakeupFreq} cols={2} />
              </div>
              {makeupFreq > 0 && (
                <div className="space-y-1">
                  <p className="text-[10px] text-gray-600 font-medium">{pack.step2.makeupRemovalQ}</p>
                  <ChipSelect options={makeupOpts.removal} value={makeupRemoval} onChange={setMakeupRemoval} cols={2} />
                </div>)}
            </div>

            <div className="flex gap-3">
              <button onClick={() => setStep(1)} className="btn-secondary flex-1"><ArrowLeft className="w-5 h-5" />{t("common.back")}</button>
              <button onClick={() => { setStep3Section(0); setStep(3); }} disabled={!skinType || concerns.length === 0} className="btn-primary flex-1">{t("common.continue")} <ArrowRight className="w-5 h-5" /></button>
            </div>
          </div>
        )}

        {/* ═══ STEP 3: Kullanım soruları (yapılandırılmış, Rebi’ye geçmeden önce) ═══ */}
        {step === 3 && (
          <div className="space-y-5 animate-in fade-in">
            {step3Section === 0 && (
              <>
                <div>
                  <h2 className="text-2xl font-bold text-gray-900 mb-1">{pack.step3.activesTitle}</h2>
                  <p className="text-gray-500 text-sm">{pack.step3.activesSubtitle}</p>
                </div>
                <div className="card space-y-3">
                  <label className="block text-sm font-medium text-gray-700">{pack.step3.experienceLabel}</label>
                  <ChipSelect options={activesExperienceOpts} value={activesExperience} onChange={setActivesExperience} cols={1} />
                </div>
                <div className="flex gap-3">
                  <button type="button" onClick={() => setStep(2)} className="btn-secondary flex-1"><ArrowLeft className="w-5 h-5" />{t("common.back")}</button>
                  <button type="button" onClick={() => setStep3Section(1)} className="btn-primary flex-1">{t("common.continue")} <ArrowRight className="w-5 h-5" /></button>
                </div>
              </>
            )}
            {step3Section === 1 && (
              <>
                <div><h2 className="text-2xl font-bold text-gray-900 mb-1">{pack.step3.severityTitle}</h2><p className="text-gray-500 text-sm">{pack.step3.severitySubtitle}</p></div>
                {concerns.map((concernId) => (
              <SeverityTest
                key={concernId}
                concern={concernId}
                onScoreChange={(score) => setSeverityScoresByConcern((prev) => ({ ...prev, [concernId]: score }))}
              />
            ))}

            <div className="card space-y-2">
              <label className="block text-sm font-medium text-gray-700">{pack.step3.durationLabel}</label>
              <div className="flex flex-wrap gap-1.5">
                {durationOpts.map((o) => (
                  <button key={o.id} onClick={() => setDuration(o.id)} className={`px-3 py-2 rounded-xl text-xs font-medium border-2 transition-all ${duration === o.id ? "border-teal-500 bg-teal-50 text-teal-700" : "border-gray-200 text-gray-500"}`}>{o.label}</button>
                ))}
              </div>
            </div>
            <div className="flex gap-3">
              <button type="button" onClick={() => setStep3Section(0)} className="btn-secondary flex-1"><ArrowLeft className="w-5 h-5" />{t("common.back")}</button>
              <button type="button" onClick={() => setStep3Section(2)} className="btn-primary flex-1">{t("common.continue")} <ArrowRight className="w-5 h-5" /></button>
            </div>
              </>
            )}
            {step3Section === 2 && (
              <>
                <div><h2 className="text-2xl font-bold text-gray-900 mb-1">{pack.step3.triggersTitle}</h2><p className="text-gray-500 text-sm">{pack.step3.triggersSubtitle}</p></div>
                <div className="card space-y-2">
                  <div className="flex flex-wrap gap-1.5">
                    {triggerOpts.map((o) => (
                      <button key={o.id} onClick={() => toggleArr(triggers, setTriggers, o.id)} className={`px-3 py-2 rounded-xl text-xs font-medium border-2 transition-all ${triggers.includes(o.id) ? "border-teal-500 bg-teal-50 text-teal-700" : "border-gray-200 text-gray-500"}`}>{o.label}</button>
                    ))}
                  </div>
                </div>
                <div className="flex gap-3">
                  <button type="button" onClick={() => setStep3Section(1)} className="btn-secondary flex-1"><ArrowLeft className="w-5 h-5" />{t("common.back")}</button>
                  <button type="button" onClick={() => setStep3Section(3)} className="btn-primary flex-1">{t("common.continue")} <ArrowRight className="w-5 h-5" /></button>
                </div>
              </>
            )}
            {step3Section === 3 && (
              <>
                <div><h2 className="text-2xl font-bold text-gray-900 mb-1">{pack.step3.pastTitle}</h2><p className="text-gray-500 text-sm">{pack.step3.pastSubtitle}</p></div>
                <div className="card space-y-2">
                  <div className="flex flex-wrap gap-1.5">
                    {pastTreatmentOpts.map((o) => (
                      <button key={o.id} onClick={() => toggleArr(pastTreatments, setPastTreatments, o.id)} className={`px-3 py-2 rounded-xl text-xs font-medium border-2 transition-all ${pastTreatments.includes(o.id) ? "border-teal-500 bg-teal-50 text-teal-700" : "border-gray-200 text-gray-500"}`}>{o.label}</button>
                    ))}
                  </div>
                </div>
                <div className="flex gap-3">
                  <button type="button" onClick={() => setStep3Section(2)} className="btn-secondary flex-1"><ArrowLeft className="w-5 h-5" />{t("common.back")}</button>
                  <button type="button" onClick={() => setStep3Section(4)} className="btn-primary flex-1">{t("common.continue")} <ArrowRight className="w-5 h-5" /></button>
                </div>
              </>
            )}
            {step3Section === 4 && (
              <>
                <div><h2 className="text-2xl font-bold text-gray-900 mb-1">{pack.step3.expectationsTitle}</h2><p className="text-gray-500 text-sm">{pack.step3.expectationsSubtitle}</p></div>
                <div className="card space-y-2">
                  <div className="flex flex-wrap gap-1.5">
                    {expectationOpts.map((o) => (
                      <button key={o.id} onClick={() => toggleArr(expectations, setExpectations, o.id)} className={`px-3 py-2 rounded-xl text-xs font-medium border-2 transition-all ${expectations.includes(o.id) ? "border-teal-500 bg-teal-50 text-teal-700" : "border-gray-200 text-gray-500"}`}>{o.label}</button>
                    ))}
                  </div>
                </div>
                <div className="flex gap-3">
                  <button type="button" onClick={() => setStep3Section(3)} className="btn-secondary flex-1"><ArrowLeft className="w-5 h-5" />{t("common.back")}</button>
                  <button type="button" onClick={() => setStep(4)} className="btn-primary flex-1">{t("analyze.continue")} <ArrowRight className="w-5 h-5" /></button>
                </div>
              </>
            )}
          </div>
        )}

        {/* ═══ STEP 4: Fotoğraf + Rutin oluştur (Rebi en sonda, rutin sonrası) ═══ */}
        {step === 4 && (
          <div className="space-y-5 animate-in fade-in">
            <div>
              <h2 className="text-2xl font-bold text-gray-900 mb-1">{t("analyze.finalStep")}</h2>
              <p className="text-gray-500 text-sm">
                {interpolate(pack.step4.finalLead, {
                  tracking: pack.step4.final_tracking,
                  recommended: pack.step4.final_recommended,
                })}
              </p>
            </div>
            <div className="card space-y-3">
              {photoPreview ? (
                <div className="space-y-3">
                  <img src={photoPreview} alt="" className="w-full h-64 object-cover rounded-2xl" />
                  <button type="button" onClick={clearPhoto} className="btn-secondary w-full text-sm">
                    {pack.step4.changePhoto}
                  </button>
                  <div className="space-y-2">
                    <label className="text-xs font-semibold text-gray-700">{t("analyze.photoContextLabel")}</label>
                    <select
                      value={photoContext}
                      onChange={(e) => setPhotoContext(e.target.value)}
                      className="w-full rounded-xl border border-gray-200 px-3 py-2 text-sm bg-white"
                    >
                      <option value="first">{t("analyze.photoContextFirst")}</option>
                      <option value="same_light">{t("analyze.photoContextSame")}</option>
                      <option value="progress">{t("analyze.photoContextProgress")}</option>
                      <option value="unsure">{t("analyze.photoContextUnsure")}</option>
                    </select>
                    {photoQuality?.tooDark ? (
                      <p className="text-[11px] text-amber-900 bg-amber-50 border border-amber-100 rounded-lg px-2 py-1.5">
                        {t("analyze.photoTooDark")}
                      </p>
                    ) : null}
                    {photoQuality?.tooBlurry ? (
                      <p className="text-[11px] text-amber-900 bg-amber-50 border border-amber-100 rounded-lg px-2 py-1.5">
                        {t("analyze.photoTooBlurry")}
                      </p>
                    ) : null}
                    {photoQuality && !photoQuality.tooDark && !photoQuality.tooBlurry ? (
                      <p className="text-[11px] text-emerald-800 bg-emerald-50 border border-emerald-100 rounded-lg px-2 py-1.5">
                        {t("analyze.photoQualityOk")}
                      </p>
                    ) : null}
                  </div>
                </div>
              ) : (
                <>
                  <p className="text-[11px] text-amber-900/95 bg-amber-50 border border-amber-100 rounded-xl px-3 py-2 leading-relaxed">
                    <span className="font-semibold">{pack.step4.tipTitle}</span> {pack.step4.tipBody}
                  </p>
                  <p className="text-[11px] text-gray-500 leading-relaxed">{pack.step4.modeHint}</p>
                  <div className="grid grid-cols-2 sm:grid-cols-4 gap-2">
                    <button
                      type="button"
                      onClick={() => triggerHiddenInput(galleryRef)}
                      className="flex flex-col items-center gap-2 p-3 border-2 border-gray-200 rounded-2xl hover:border-teal-200 transition-colors"
                    >
                      <ImagePlus className="w-6 h-6 text-gray-500" />
                      <span className="text-[10px] font-medium text-gray-600 text-center leading-tight">{pack.step4.galleryFile}</span>
                    </button>
                    <button
                      type="button"
                      onClick={() => triggerHiddenInput(cameraUserRef)}
                      className="flex flex-col items-center gap-2 p-3 border-2 border-teal-200 rounded-2xl bg-teal-50/50"
                    >
                      <Camera className="w-6 h-6 text-teal-600" />
                      <span className="text-[10px] font-medium text-teal-800 text-center leading-tight">{pack.step4.cameraFront}</span>
                    </button>
                    <button
                      type="button"
                      onClick={() => triggerHiddenInput(cameraEnvRef)}
                      className="flex flex-col items-center gap-2 p-3 border-2 border-teal-100 rounded-2xl bg-teal-50/30"
                    >
                      <Camera className="w-6 h-6 text-teal-500" />
                      <span className="text-[10px] font-medium text-teal-800 text-center leading-tight">{pack.step4.cameraRear}</span>
                    </button>
                    <button
                      type="button"
                      onClick={() => setShowWebcam(true)}
                      className="flex flex-col items-center gap-2 p-3 border-2 border-indigo-200 rounded-2xl bg-indigo-50/50"
                    >
                      <Monitor className="w-6 h-6 text-indigo-600" />
                      <span className="text-[10px] font-medium text-indigo-800 text-center leading-tight">{pack.step4.webcam}</span>
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
              <h3 className="font-bold text-teal-800 text-xs flex items-center gap-1"><Sparkles className="w-3 h-3" />{pack.step4.summaryTitle}</h3>
              <div className="grid grid-cols-3 gap-1.5 text-[11px]">
                <div className="bg-white rounded-lg p-2"><span className="text-gray-400 block">{pack.step4.age}</span><span className="font-medium">{age}</span></div>
                <div className="bg-white rounded-lg p-2"><span className="text-gray-400 block">{pack.step4.skin}</span><span className="font-medium">{skinType}</span></div>
                <div className="bg-white rounded-lg p-2"><span className="text-gray-400 block">{pack.step4.severity}</span><span className="font-medium">{severityScoresByConcern[primaryConcern] != null ? Math.round(severityScoresByConcern[primaryConcern]) : "?"}/10</span></div>
                <div className="bg-white rounded-lg p-2 col-span-3"><span className="text-gray-400 block">{pack.step4.concerns}</span><span className="font-medium">{concerns.map((c) => concernOptions.find((o) => o.id === c)?.label).join(", ")}</span></div>
              </div>
            </div>
            <div className="flex gap-3">
              <button type="button" onClick={() => setStep(3)} className="btn-secondary flex-1"><ArrowLeft className="w-5 h-5" />{t("common.back")}</button>
              <button
                type="button"
                onClick={() => {
                  setSubmitError("");
                  setShowRoutineModal(true);
                }}
                className="btn-primary flex-1"
              >
                <Sparkles className="w-5 h-5" />{pack.step4.createRoutineCta}
              </button>
            </div>
            {!photoFile && (
              <p className="text-center text-[11px] text-gray-500">
                {pack.step4.noPhotoNote}
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
                    {pack.modal.routineBeforeTitle}
                  </h3>
                  <p className="text-xs text-gray-600 mt-1.5 leading-relaxed">
                    {pack.modal.routineBeforeBody}
                  </p>
                </div>
              </div>
              {!photoFile && (
                <div className="rounded-xl border border-amber-200 bg-amber-50/90 p-3 text-[11px] text-amber-950 leading-relaxed">
                  <p className="font-semibold text-amber-950 mb-1">{pack.modal.noPhotoTitle}</p>
                  <p>{pack.modal.noPhotoBody}</p>
                </div>
              )}
              <div className="rounded-xl bg-teal-50/80 border border-teal-100 p-3 space-y-2 text-xs text-gray-700 leading-relaxed">
                <p className="font-semibold text-teal-900">{pack.modal.productTruthTitle}</p>
                <ul className="list-disc list-inside space-y-1.5 text-gray-600">
                  <li>{pack.modal.productTruth1}</li>
                  <li>{pack.modal.productTruth2}</li>
                </ul>
              </div>
              <div className="space-y-3">
                <div>
                  <p className="text-sm font-semibold text-gray-900">{pack.modal.toleranceExplTitle}</p>
                  <p className="text-[11px] text-gray-500 leading-relaxed mt-1">{pack.modal.toleranceExplBody}</p>
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
                  {pack.modal.back}
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
                  {pack.modal.understandCreate}
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
                    {pack.skipPhoto.title}
                  </h3>
                  <p className="text-xs text-gray-600 mt-2 leading-relaxed">
                    {pack.skipPhoto.body1}
                  </p>
                  <p className="text-xs text-gray-600 mt-2 leading-relaxed">
                    {pack.skipPhoto.body2}
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
                  {pack.skipPhoto.addPhoto}
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
                  {pack.skipPhoto.createAnyway}
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
