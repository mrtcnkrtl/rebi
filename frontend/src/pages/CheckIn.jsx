import { useState, useEffect } from "react";
import { useNavigate } from "react-router-dom";
import { useAuth } from "../context/AuthContext";
import {
  getRoutineSnapshot,
  isRoutineTrackingAccepted,
  saveRoutineSnapshot,
} from "../lib/routineTracking";
import { recordCheckInSuccess } from "../lib/checkinStats";
import { useTheme } from "../context/ThemeContext";
import { StructuredRoutineBadges } from "../lib/structuredRoutineBadges";
import { formatApiErrorDetail, isNetworkError } from "../lib/apiErrors";
import { apiAuthHeaders } from "../lib/apiAuth";
import { DEMO_USER_ID } from "../lib/demoUser";
import {
  Moon, SmilePlus, Droplets, AlertCircle,
  CheckCircle2, Send, Loader2, ArrowRight, Sparkles,
  Palette, FlaskConical, Hand, Sun, Wind, Flower2,
} from "lucide-react";
import { supabase } from "../lib/supabase";
import ThemePatternOverlay from "../components/ThemePatternOverlay";
import { useTranslation } from "react-i18next";

const API = import.meta.env.VITE_API_URL || "http://localhost:8000";

const SKIN_FEELINGS = [
  { id: "iyi", label: "İyi", icon: "😊", desc: "Normal hissediyorum" },
  { id: "kuru", label: "Kuru", icon: "🏜️", desc: "Sıkışma, gerginlik" },
  { id: "yagli", label: "Yağlı", icon: "💧", desc: "Parlaklık, yağlanma" },
  { id: "kirik", label: "Hassas", icon: "🩹", desc: "Kızarıklık, soyulma" },
  { id: "irritasyon", label: "İrritasyon", icon: "🔥", desc: "Yanma, batma" },
];

const STRESS_LEVELS = [
  { value: 1, label: "Çok düşük", emoji: "😌" },
  { value: 2, label: "Düşük", emoji: "🙂" },
  { value: 3, label: "Orta", emoji: "😐" },
  { value: 4, label: "Yüksek", emoji: "😣" },
  { value: 5, label: "Çok yüksek", emoji: "😰" },
];

/** Evet / Hayır / Atla — check-in ek soruları */
function ExtraTristate({ title, description, value, onChange }) {
  return (
    <div className="card mb-3">
      <h3 className="text-sm font-bold text-gray-800 mb-1">{title}</h3>
      {description ? (
        <p className="text-[11px] text-gray-500 mb-2 leading-relaxed">{description}</p>
      ) : null}
      <div className="grid grid-cols-3 gap-2">
        <button
          type="button"
          onClick={() => onChange(true)}
          className={`py-2 rounded-xl text-xs font-medium border-2 ${
            value === true ? "border-teal-500 bg-teal-50" : "border-gray-200"
          }`}
        >
          Evet
        </button>
        <button
          type="button"
          onClick={() => onChange(false)}
          className={`py-2 rounded-xl text-xs font-medium border-2 ${
            value === false ? "border-teal-500 bg-teal-50" : "border-gray-200"
          }`}
        >
          Hayır
        </button>
        <button
          type="button"
          onClick={() => onChange(null)}
          className="py-2 rounded-xl text-xs font-medium border-2 border-gray-200 text-gray-600"
        >
          Atla
        </button>
      </div>
    </div>
  );
}

const CONCERN_EXTRA_INITIAL = {
  picked_skin_today: null,
  high_glycemic_intake_today: null,
  heavy_dairy_today: null,
  long_sun_exposure_today: null,
  spf_applied_today: null,
  very_dry_environment_today: null,
  long_hot_shower_today: null,
  fragrance_new_product_today: null,
  tried_new_active_today: null,
};

const TRISTATE_PAYLOAD_KEYS = Object.keys(CONCERN_EXTRA_INITIAL);

/** Check-in su: Türkiye’de sık kullanılan “1 bardak ≈ 250 ml” (2 L ≈ 8 bardak). */
const ML_PER_GLASS = 250;

function parseWaterMlInput(raw) {
  const s = String(raw ?? "").trim().replace(",", ".");
  if (s === "") return null;
  const n = Number(s);
  if (!Number.isFinite(n) || n < 0) return null;
  return Math.min(8000, Math.round(n));
}

function formatGlassesLabel(ml) {
  if (ml <= 0) return "0 bardak";
  const glasses = ml / ML_PER_GLASS;
  const rounded =
    Math.abs(glasses - Math.round(glasses)) < 0.05
      ? Math.round(glasses)
      : Math.round(glasses * 10) / 10;
  return `yaklaşık ${rounded} bardak`;
}

function WaterMlCheckInCard({ value, onChange, theme }) {
  const parsed = parseWaterMlInput(value);
  const bumpMl = (delta) => {
    const base = parsed ?? 0;
    const next = Math.max(0, Math.min(8000, base + delta));
    onChange(String(next));
  };

  return (
    <div className="card mb-4">
      <div className="flex items-center gap-2 mb-2">
        <Droplets className="w-5 h-5 text-sky-500" />
        <h3 className="text-sm font-bold text-gray-800">Bugün içtiğin su (ml)</h3>
      </div>
      <p className="text-[11px] text-gray-500 mb-2 leading-relaxed">
        Miktarı <strong className="text-gray-700">mililitre (ml)</strong> olarak yaz. Hesaplama:{" "}
        <strong className="text-gray-700">1 bardak = {ML_PER_GLASS} ml</strong> (standart su bardağı).
        Boş bırakırsan uygulama içi su takibi veya analizdeki günlük hedefin kullanılır.
      </p>
      <div className="flex gap-2 items-stretch">
        <div className="relative flex-1 min-w-0">
          <input
            id="checkin-water-ml"
            type="number"
            inputMode="numeric"
            min={0}
            max={8000}
            step={50}
            placeholder={`Örn. ${ML_PER_GLASS * 8} (8 bardak)`}
            value={value}
            onChange={(e) => onChange(e.target.value)}
            className="w-full pl-4 pr-12 py-2.5 rounded-xl border border-gray-200 text-sm font-medium text-gray-900"
            aria-describedby="checkin-water-ml-hint"
          />
          <span className="pointer-events-none absolute right-3 top-1/2 -translate-y-1/2 text-xs font-semibold text-gray-400">
            ml
          </span>
        </div>
      </div>
      <p id="checkin-water-ml-hint" className="text-[10px] text-gray-400 mt-1.5">
        Gönderirken değer tam sayı ml olarak kaydedilir (en fazla 8000 ml).
      </p>
      {parsed != null && parsed > 0 && (
        <p className="text-xs font-semibold text-sky-800 mt-2 py-2 px-3 rounded-xl bg-sky-50 border border-sky-100">
          <span className="tabular-nums">{parsed.toLocaleString("tr-TR")}</span> ml → {formatGlassesLabel(parsed)}
        </p>
      )}
      <div className="flex flex-wrap gap-2 mt-3">
        <button
          type="button"
          onClick={() => bumpMl(-ML_PER_GLASS)}
          className="px-3 py-1.5 rounded-lg text-[11px] font-medium border border-gray-200 bg-white text-gray-700 hover:bg-gray-50"
        >
          −1 bardak (−{ML_PER_GLASS} ml)
        </button>
        <button
          type="button"
          onClick={() => bumpMl(ML_PER_GLASS)}
          className="px-3 py-1.5 rounded-lg text-[11px] font-medium border text-white shadow-sm"
          style={{ backgroundColor: theme?.primary || "#0ea5e9", borderColor: theme?.primary || "#0ea5e9" }}
        >
          +1 bardak (+{ML_PER_GLASS} ml)
        </button>
        <button
          type="button"
          onClick={() => bumpMl(125)}
          className="px-3 py-1.5 rounded-lg text-[11px] font-medium border border-gray-200 bg-white text-gray-700 hover:bg-gray-50"
        >
          +½ bardak (+125 ml)
        </button>
      </div>
    </div>
  );
}

export default function CheckIn() {
  const { user } = useAuth();
  const { theme } = useTheme();
  const navigate = useNavigate();
  const { t } = useTranslation();

  useEffect(() => {
    const id = user?.id;
    if (!id) return;
    if (isRoutineTrackingAccepted(id)) return;
    navigate("/dashboard", { replace: true, state: { flashNeedAccept: true } });
  }, [user?.id, navigate]);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      if (!user?.id || !supabase) {
        setCtxLoading(false);
        return;
      }
      try {
        const { data: row } = await supabase
          .from("assessments")
          .select("concern, lifestyle_data")
          .eq("user_id", user.id)
          .order("created_at", { ascending: false })
          .limit(1)
          .maybeSingle();
        if (cancelled) return;
        const life = row?.lifestyle_data || {};
        setAssessmentCtx({
          concern: row?.concern || "acne",
          water_intake: Number(life.water_intake ?? 2),
          makeup_frequency: Number(life.makeup_frequency ?? 0),
        });
      } catch {
        if (!cancelled) {
          setAssessmentCtx({ concern: "acne", water_intake: 2, makeup_frequency: 0 });
        }
      } finally {
        if (!cancelled) setCtxLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [user?.id]);

  const [sleepHours, setSleepHours] = useState(7);
  const [stressToday, setStressToday] = useState(3);
  const [skinFeeling, setSkinFeeling] = useState("");
  const [appliedRoutine, setAppliedRoutine] = useState(true);
  const [notes, setNotes] = useState("");
  /** Son assessment bağlamı: hangi ek soruları göstereceğiz */
  const [ctxLoading, setCtxLoading] = useState(true);
  const [assessmentCtx, setAssessmentCtx] = useState({
    concern: "acne",
    water_intake: 2,
    makeup_frequency: 0,
  });
  const [waterMlToday, setWaterMlToday] = useState("");
  const [makeupUsedToday, setMakeupUsedToday] = useState(null);
  const [makeupRemovalToday, setMakeupRemovalToday] = useState("cleanser");
  const [concernExtra, setConcernExtra] = useState(() => ({ ...CONCERN_EXTRA_INITIAL }));
  const [loading, setLoading] = useState(false);
  const [result, setResult] = useState(null);
  const [alreadyCheckedIn, setAlreadyCheckedIn] = useState(false);
  const [statusLoading, setStatusLoading] = useState(true);
  const [submitError, setSubmitError] = useState("");

  const canSubmit = skinFeeling && !loading && !alreadyCheckedIn && !ctxLoading;

  const concernDrivenExtras = ["acne", "dryness", "pigmentation", "sensitivity", "aging"];
  const showWaterExtra =
    concernDrivenExtras.includes(assessmentCtx.concern) || assessmentCtx.water_intake < 2;
  const showMakeupExtra =
    assessmentCtx.makeup_frequency >= 3 ||
    ["acne", "pigmentation", "sensitivity", "aging"].includes(assessmentCtx.concern);
  const showConcernIntro = concernDrivenExtras.includes(assessmentCtx.concern);

  const setExtraField = (key, val) => {
    setConcernExtra((p) => ({ ...p, [key]: val }));
  };

  const MAKEUP_REMOVAL_OPTS = [
    { id: "cleanser", label: "Temizleyici" },
    { id: "double", label: "Çift aşama" },
    { id: "water", label: "Sadece su" },
    { id: "none", label: "Temizlemedim" },
  ];

  useEffect(() => {
    const id = user?.id;
    if (!id) {
      setStatusLoading(false);
      return;
    }
    let cancelled = false;
    (async () => {
      try {
        const auth = await apiAuthHeaders();
        const res = await fetch(`${API}/daily_checkin/status?user_id=${encodeURIComponent(id)}`, {
          headers: { ...auth },
        });
        const data = await res.json().catch(() => ({}));
        if (!res.ok) {
          if (!cancelled) setSubmitError(formatApiErrorDetail(data));
          return;
        }
        if (!cancelled && data.already_checked_in) setAlreadyCheckedIn(true);
      } catch (e) {
        console.error("Check-in status:", e);
        if (!cancelled && isNetworkError(e)) {
          setSubmitError("Bağlantı kurulamadı. İnternetini ve API adresini kontrol et; backend çalışıyor mu?");
        }
      } finally {
        if (!cancelled) setStatusLoading(false);
      }
    })();
    return () => { cancelled = true; };
  }, [user?.id]);

  const handleSubmit = async () => {
    if (!canSubmit) return;
    setLoading(true);
    setSubmitError("");
    try {
      const auth = await apiAuthHeaders();
      const payload = {
        user_id: user?.id || DEMO_USER_ID,
        sleep_hours: sleepHours,
        stress_today: stressToday,
        skin_feeling: skinFeeling,
        applied_routine: appliedRoutine,
        notes: notes || null,
      };
      const wParsed = parseWaterMlInput(waterMlToday);
      if (wParsed != null && wParsed > 0) {
        payload.water_ml_today = wParsed;
      }
      if (makeupUsedToday === true || makeupUsedToday === false) {
        payload.makeup_used_today = makeupUsedToday;
        if (makeupUsedToday === true) {
          payload.makeup_removal_today = makeupRemovalToday;
        }
      }
      for (const k of TRISTATE_PAYLOAD_KEYS) {
        const v = concernExtra[k];
        if (v === true || v === false) payload[k] = v;
      }

      const res = await fetch(`${API}/daily_checkin`, {
        method: "POST",
        headers: { "Content-Type": "application/json", ...auth },
        body: JSON.stringify(payload),
      });
      const data = await res.json().catch(() => ({}));
      if (res.status === 409) {
        setSubmitError(typeof data.detail === "string" ? data.detail : "Bugün için check-in zaten yapıldı.");
        setAlreadyCheckedIn(true);
        return;
      }
      if (!res.ok) {
        setSubmitError(formatApiErrorDetail(data) + (res.status ? ` (${res.status})` : ""));
        return;
      }
      recordCheckInSuccess(user?.id, { appliedRoutine });
      setResult(data);
    } catch (err) {
      console.error("Check-in error:", err);
      setSubmitError(
        isNetworkError(err)
          ? "Bağlantı kurulamadı. İnternetini ve API adresini kontrol et; backend çalışıyor mu?"
          : (err?.message || "Beklenmeyen bir hata oluştu.")
      );
    } finally {
      setLoading(false);
    }
  };

  if (result) {
    return (
      <div className={`min-h-screen ${theme.bg} pb-24 relative`}>
        <ThemePatternOverlay pattern={theme.pattern} />
        <div className="max-w-lg mx-auto px-4 py-8 relative z-[1]">
          <div className="text-center mb-6">
            <div className="w-16 h-16 rounded-2xl flex items-center justify-center mx-auto mb-4 shadow-lg"
              style={{ background: `linear-gradient(135deg, ${theme.accent}, ${theme.primary})` }}>
              <Sparkles className="w-8 h-8 text-white" />
            </div>
            <h1 className="text-xl font-bold text-gray-900">{t("checkin.todayReport")}</h1>
            <p className="text-sm text-gray-500 mt-1">
              Risk: <span className="font-semibold" style={{ color: theme.primary }}>{result.risk_level}</span>
              {result.adaptation_type === "major" && " — Büyük değişiklikler yapıldı"}
            </p>
          </div>

          {/* AI Note */}
          {result.ai_note && (
            <div className="card mb-5 border-l-4" style={{ borderLeftColor: theme.primary }}>
              <div className="flex items-start gap-3">
                <Sparkles className="w-5 h-5 shrink-0 mt-0.5" style={{ color: theme.primary }} />
                <p className="text-sm text-gray-700 leading-relaxed">{result.ai_note}</p>
              </div>
            </div>
          )}

          {/* Changes */}
          {result.changes && result.changes.length > 0 && (
            <div className="mb-5">
              <h3 className="text-sm font-bold text-gray-700 mb-2 flex items-center gap-2">
                <AlertCircle className="w-4 h-4 text-amber-500" /> Değişiklikler
              </h3>
              <div className="space-y-2">
                {result.changes.map((c, i) => (
                  <div key={i} className="card !p-3 bg-amber-50/50 border-amber-100">
                    <p className="text-sm font-medium text-gray-800">{c.item}</p>
                    <p className="text-xs text-gray-500 mt-0.5">
                      {c.old} → <span className="font-semibold" style={{ color: theme.primary }}>{c.new}</span>
                    </p>
                    <p className="text-xs text-gray-400 mt-0.5">{c.reason}</p>
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* Today's Routine Summary */}
          {result.today_routine && result.today_routine.length > 0 && (
            <div className="mb-5">
              <h3 className="text-sm font-bold text-gray-700 mb-2">Bugünün Rutini</h3>
              <div className="space-y-1.5">
                {result.today_routine.slice(0, 10).map((item, i) => (
                  <div key={i} className="card !p-3 flex items-start gap-2.5">
                    <span className="text-sm shrink-0">{item.icon || "•"}</span>
                    <div className="min-w-0">
                      <p className="text-xs font-semibold text-gray-800">{item.action}</p>
                      <StructuredRoutineBadges item={item} />
                      <p className="text-[11px] text-gray-500 mt-0.5 line-clamp-2">{item.detail}</p>
                    </div>
                    <span className="text-[9px] px-1.5 py-0.5 rounded-full shrink-0 mt-0.5"
                      style={{ backgroundColor: theme.primaryLight, color: theme.primaryDark }}>
                      {item.time}
                    </span>
                  </div>
                ))}
              </div>
            </div>
          )}

          <button
            onClick={() => {
              const id = user?.id;
              if (id && isRoutineTrackingAccepted(id) && result.today_routine?.length) {
                const prev = getRoutineSnapshot(id) || {};
                saveRoutineSnapshot(id, {
                  ...prev,
                  routine: result.today_routine,
                  checkinResult: result,
                });
              }
              navigate("/dashboard", {
                state: {
                  routine: result.today_routine,
                  checkinResult: result,
                },
              });
            }}
            className="w-full py-3 rounded-xl text-white font-semibold flex items-center justify-center gap-2"
            style={{ backgroundColor: theme.primary }}
          >
            {t("checkin.backToDashboard")} <ArrowRight className="w-4 h-4" />
          </button>
        </div>
      </div>
    );
  }

  if (statusLoading) {
    return (
      <div className={`min-h-screen ${theme.bg} flex items-center justify-center pb-24 relative`}>
        <ThemePatternOverlay pattern={theme.pattern} />
        <Loader2 className="w-8 h-8 animate-spin text-gray-400 relative z-[1]" />
      </div>
    );
  }

  if (alreadyCheckedIn && !result) {
    return (
      <div className={`min-h-screen ${theme.bg} pb-24 relative`}>
        <ThemePatternOverlay pattern={theme.pattern} />
        <div className="max-w-lg mx-auto px-4 py-8 text-center relative z-[1]">
          <CheckCircle2 className="w-14 h-14 mx-auto mb-4 text-teal-500" />
          <h1 className="text-xl font-bold text-gray-900">{t("checkin.alreadyTitle")}</h1>
          <p className="text-sm text-gray-500 mt-2">{t("checkin.alreadyDesc")}</p>
          <button
            type="button"
            onClick={() => navigate("/dashboard")}
            className="mt-6 w-full py-3 rounded-xl text-white font-semibold"
            style={{ backgroundColor: theme.primary }}
          >
            {t("checkin.backToDashboard")}
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className={`min-h-screen ${theme.bg} pb-24 relative`}>
      <ThemePatternOverlay pattern={theme.pattern} />
      <div className="max-w-lg mx-auto px-4 py-8 relative z-[1]">
        {/* Header */}
        <div className="text-center mb-8">
          <h1 className="text-xl font-bold text-gray-900">{t("checkin.title")}</h1>
          <p className="text-sm text-gray-500 mt-1">{t("checkin.subtitle")}</p>
          <p className="text-[11px] text-gray-400 mt-2 max-w-sm mx-auto leading-relaxed">
            Uyku ve stres cevapların, geçmiş check-in kayıtlarınla kısa süreli harmanlanarak risk özetine girer.
          </p>
        </div>

        {submitError && (
          <div className="mb-4 p-3 rounded-xl bg-amber-50 border border-amber-200 text-sm text-amber-900">
            {submitError}
          </div>
        )}

        {/* Q1: Sleep */}
        <div className="card mb-4">
          <div className="flex items-center gap-2 mb-3">
            <Moon className="w-5 h-5 text-indigo-500" />
            <h3 className="text-sm font-bold text-gray-800">Dün gece kaç saat uyudun?</h3>
          </div>
          <div className="flex items-center gap-4">
            <input
              type="range"
              min={3}
              max={12}
              step={0.5}
              value={sleepHours}
              onChange={(e) => setSleepHours(parseFloat(e.target.value))}
              className="flex-1 accent-indigo-500"
            />
            <span className="text-lg font-bold text-indigo-600 w-12 text-center">{sleepHours}s</span>
          </div>
          <div className="flex justify-between text-[10px] text-gray-400 mt-1 px-1">
            <span>3s</span><span>7.5s</span><span>12s</span>
          </div>
        </div>

        {/* Q2: Stress */}
        <div className="card mb-4">
          <div className="flex items-center gap-2 mb-3">
            <SmilePlus className="w-5 h-5 text-purple-500" />
            <h3 className="text-sm font-bold text-gray-800">Bugün stres seviyeni nasıl tanımlarsın?</h3>
          </div>
          <div className="grid grid-cols-5 gap-2">
            {STRESS_LEVELS.map((s) => (
              <button
                key={s.value}
                onClick={() => setStressToday(s.value)}
                className={`rounded-xl py-2 text-center transition-all ${
                  stressToday === s.value
                    ? "ring-2 shadow-md scale-105"
                    : "bg-gray-50 hover:bg-gray-100"
                }`}
                style={stressToday === s.value ? {
                  ringColor: theme.primary,
                  backgroundColor: theme.primaryLight,
                  borderColor: theme.primary,
                } : {}}
              >
                <span className="text-xl">{s.emoji}</span>
                <p className="text-[9px] text-gray-500 mt-0.5">{s.label}</p>
              </button>
            ))}
          </div>
        </div>

        {/* Q3: Skin Feeling */}
        <div className="card mb-4">
          <div className="flex items-center gap-2 mb-3">
            <Droplets className="w-5 h-5" style={{ color: theme.primary }} />
            <h3 className="text-sm font-bold text-gray-800">Cildin bugün nasıl hissediyor?</h3>
          </div>
          <div className="space-y-2">
            {SKIN_FEELINGS.map((f) => (
              <button
                key={f.id}
                onClick={() => setSkinFeeling(f.id)}
                className={`w-full text-left px-4 py-3 rounded-xl flex items-center gap-3 transition-all ${
                  skinFeeling === f.id
                    ? "ring-2 shadow-md"
                    : "bg-gray-50 hover:bg-gray-100"
                }`}
                style={skinFeeling === f.id ? {
                  ringColor: theme.primary,
                  backgroundColor: theme.primaryLight,
                } : {}}
              >
                <span className="text-xl">{f.icon}</span>
                <div>
                  <p className="text-sm font-medium text-gray-800">{f.label}</p>
                  <p className="text-[11px] text-gray-500">{f.desc}</p>
                </div>
                {skinFeeling === f.id && (
                  <CheckCircle2 className="w-5 h-5 ml-auto shrink-0" style={{ color: theme.primary }} />
                )}
              </button>
            ))}
          </div>
        </div>

        {/* Q4: Applied Routine */}
        <div className="card mb-4">
          <div className="flex items-center gap-2 mb-3">
            <CheckCircle2 className="w-5 h-5 text-green-500" />
            <h3 className="text-sm font-bold text-gray-800">Dünkü rutini uyguladın mı?</h3>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <button
              onClick={() => setAppliedRoutine(true)}
              className={`py-3 rounded-xl text-center font-medium transition-all ${
                appliedRoutine
                  ? "ring-2 shadow-md text-white"
                  : "bg-gray-50 text-gray-600 hover:bg-gray-100"
              }`}
              style={appliedRoutine ? { backgroundColor: theme.primary, ringColor: theme.primary } : {}}
            >
              Evet
            </button>
            <button
              onClick={() => setAppliedRoutine(false)}
              className={`py-3 rounded-xl text-center font-medium transition-all ${
                !appliedRoutine
                  ? "ring-2 shadow-md text-white"
                  : "bg-gray-50 text-gray-600 hover:bg-gray-100"
              }`}
              style={!appliedRoutine ? { backgroundColor: "#ef4444", ringColor: "#ef4444" } : {}}
            >
              Hayır
            </button>
          </div>
        </div>

        {showConcernIntro && (
          <div className="card mb-4 bg-slate-50/90 border-slate-100">
            <p className="text-[11px] text-slate-600 leading-relaxed">
              <span className="font-semibold text-slate-800">Endişene özel:</span> Aşağıdaki ek sorular
              analizindeki ana soruna göre seçilir. Cevap vermezsen atla; geçmiş check-in örüntüleri bazen
              risk özetine yansır. Uyku ve stres üstte, geçmiş kayıtlarla harmanlanır.
            </p>
          </div>
        )}

        {/* Koşullu: su (endişe / düşük profil suyu) */}
        {showWaterExtra && (
          <WaterMlCheckInCard
            value={waterMlToday}
            onChange={setWaterMlToday}
            theme={theme}
          />
        )}

        {/* Koşullu: makyaj (sık makyaj profili) */}
        {showMakeupExtra && (
          <div className="card mb-4">
            <div className="flex items-center gap-2 mb-2">
              <Palette className="w-5 h-5 text-rose-500" />
              <h3 className="text-sm font-bold text-gray-800">Bugün makyaj</h3>
            </div>
            <p className="text-[11px] text-gray-500 mb-2 leading-relaxed">
              İstersen atla; seçmezsen risk hesabında yalnızca profil makyaj sıklığın kullanılır.
            </p>
            <div className="grid grid-cols-3 gap-2 mb-3">
              <button
                type="button"
                onClick={() => setMakeupUsedToday(true)}
                className={`py-2 rounded-xl text-xs font-medium border-2 ${
                  makeupUsedToday === true ? "border-teal-500 bg-teal-50" : "border-gray-200"
                }`}
              >
                Evet
              </button>
              <button
                type="button"
                onClick={() => setMakeupUsedToday(false)}
                className={`py-2 rounded-xl text-xs font-medium border-2 ${
                  makeupUsedToday === false ? "border-teal-500 bg-teal-50" : "border-gray-200"
                }`}
              >
                Hayır
              </button>
              <button
                type="button"
                onClick={() => {
                  setMakeupUsedToday(null);
                  setMakeupRemovalToday("cleanser");
                }}
                className="py-2 rounded-xl text-xs font-medium border-2 border-gray-200 text-gray-600"
              >
                Atla
              </button>
            </div>
            {makeupUsedToday === true && (
              <div className="space-y-1">
                <p className="text-[11px] font-medium text-gray-700">Nasıl temizledin?</p>
                <div className="flex flex-wrap gap-1.5">
                  {MAKEUP_REMOVAL_OPTS.map((o) => (
                    <button
                      key={o.id}
                      type="button"
                      onClick={() => setMakeupRemovalToday(o.id)}
                      className={`px-2.5 py-1 rounded-lg text-[10px] font-medium border-2 ${
                        makeupRemovalToday === o.id
                          ? "border-teal-500 bg-teal-50"
                          : "border-gray-200 text-gray-600"
                      }`}
                    >
                      {o.label}
                    </button>
                  ))}
                </div>
              </div>
            )}
          </div>
        )}

        {assessmentCtx.concern === "acne" && (
          <div className="mb-4">
            <p className="text-xs font-bold text-gray-800 mb-2 flex items-center gap-2">
              <Hand className="w-4 h-4 text-rose-500" />
              Akneye özel
            </p>
            <ExtraTristate
              title="Ciltte sivilce/komedon kurcaladın mı?"
              description="Mekanik irritasyon bariyeri zayıflatır; risk özetine yansır."
              value={concernExtra.picked_skin_today}
              onChange={(v) => setExtraField("picked_skin_today", v)}
            />
            <ExtraTristate
              title="Bugün belirgin şeker / hızlı yükselen kan şekerine yol açan öğün?"
              description="Beyaz un, tatlı, şekerli içecek gibi."
              value={concernExtra.high_glycemic_intake_today}
              onChange={(v) => setExtraField("high_glycemic_intake_today", v)}
            />
            <ExtraTristate
              title="Belirgin süt ürünü (süt, yoğurt, peynir bol) tükettin mi?"
              description="Bazı akne eğilimlerinde tetikleyici olabilir."
              value={concernExtra.heavy_dairy_today}
              onChange={(v) => setExtraField("heavy_dairy_today", v)}
            />
          </div>
        )}

        {(assessmentCtx.concern === "aging" || assessmentCtx.concern === "pigmentation") && (
          <div className="mb-4">
            <p className="text-xs font-bold text-gray-800 mb-2 flex items-center gap-2">
              <Sun className="w-4 h-4 text-amber-500" />
              {assessmentCtx.concern === "aging" ? "Yaşlanma endişesine özel" : "Lekelenmeye özel"}
            </p>
            <ExtraTristate
              title="Uzun süre doğrudan güneş altında kaldın mı?"
              description="30 dk+ açık güneş veya yoğun UV günü."
              value={concernExtra.long_sun_exposure_today}
              onChange={(v) => setExtraField("long_sun_exposure_today", v)}
            />
            <ExtraTristate
              title="Yüz için güneş koruyucu uyguladın mı?"
              description="Rutindeki SPF adımını tamamladıysan Evet."
              value={concernExtra.spf_applied_today}
              onChange={(v) => setExtraField("spf_applied_today", v)}
            />
          </div>
        )}

        {assessmentCtx.concern === "dryness" && (
          <div className="mb-4">
            <p className="text-xs font-bold text-gray-800 mb-2 flex items-center gap-2">
              <Wind className="w-4 h-4 text-sky-500" />
              Kuruluğa özel
            </p>
            <ExtraTristate
              title="Ev/iş ortamı çok kuru muydu? (ısıtma, klima, rüzgâr)"
              value={concernExtra.very_dry_environment_today}
              onChange={(v) => setExtraField("very_dry_environment_today", v)}
            />
            <ExtraTristate
              title="Uzun veya çok sıcak duş aldın mı?"
              description="Bariyer kuruluğunu artırabilir."
              value={concernExtra.long_hot_shower_today}
              onChange={(v) => setExtraField("long_hot_shower_today", v)}
            />
          </div>
        )}

        {assessmentCtx.concern === "sensitivity" && (
          <div className="mb-4">
            <p className="text-xs font-bold text-gray-800 mb-2 flex items-center gap-2">
              <Flower2 className="w-4 h-4 text-violet-500" />
              Hassasiyete özel
            </p>
            <ExtraTristate
              title="Yeni parfüm veya yoğun kokulu ürün kullandın mı?"
              value={concernExtra.fragrance_new_product_today}
              onChange={(v) => setExtraField("fragrance_new_product_today", v)}
            />
            <ExtraTristate
              title="Uzun veya çok sıcak duş aldın mı?"
              value={concernExtra.long_hot_shower_today}
              onChange={(v) => setExtraField("long_hot_shower_today", v)}
            />
            <div className="flex items-center gap-2 mb-1 mt-1">
              <FlaskConical className="w-4 h-4 text-violet-500" />
              <span className="text-[11px] font-semibold text-gray-700">Aktif madde</span>
            </div>
            <ExtraTristate
              title="Yeni güçlü madde veya peeling denedin mi?"
              description="Örn. retinol, AHA/BHA, yüksek konsantrasyon serum."
              value={concernExtra.tried_new_active_today}
              onChange={(v) => setExtraField("tried_new_active_today", v)}
            />
          </div>
        )}

        {/* Q5: Notes (optional) */}
        <div className="card mb-6">
          <h3 className="text-sm font-bold text-gray-800 mb-2">Eklemek istediğin bir şey var mı? <span className="text-gray-400 font-normal">(opsiyonel)</span></h3>
          <textarea
            value={notes}
            onChange={(e) => setNotes(e.target.value)}
            placeholder="Dün yeni bir madde denedim, güneşte kaldım..."
            className="w-full px-4 py-3 rounded-xl border border-gray-200 text-sm resize-none focus:ring-2 focus:outline-none"
            style={{ focusRingColor: theme.primary }}
            rows={2}
          />
        </div>

        {/* Submit */}
        <button
          onClick={handleSubmit}
          disabled={!canSubmit}
          className={`w-full py-4 rounded-xl text-white font-semibold flex items-center justify-center gap-2 transition-all ${
            canSubmit ? "shadow-lg hover:shadow-xl" : "opacity-50 cursor-not-allowed"
          }`}
          style={{ backgroundColor: canSubmit ? theme.primary : "#9ca3af" }}
        >
          {loading ? (
            <><Loader2 className="w-5 h-5 animate-spin" /> Analiz ediliyor...</>
          ) : (
            <><Send className="w-5 h-5" /> {t("checkin.submit")}</>
          )}
        </button>
      </div>
    </div>
  );
}
