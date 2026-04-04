import { useState, useEffect } from "react";
import { useNavigate } from "react-router-dom";
import { useAuth } from "../context/AuthContext";
import {
  getRoutineSnapshot,
  isRoutineTrackingAccepted,
  saveRoutineSnapshot,
} from "../lib/routineTracking";
import { useTheme } from "../context/ThemeContext";
import { StructuredRoutineBadges } from "../lib/structuredRoutineBadges";
import { formatApiErrorDetail, isNetworkError } from "../lib/apiErrors";
import { apiAuthHeaders } from "../lib/apiAuth";
import { DEMO_USER_ID } from "../lib/demoUser";
import {
  Moon, SmilePlus, Frown, Droplets, AlertCircle,
  CheckCircle2, Send, Loader2, ArrowRight, Sparkles,
} from "lucide-react";

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

export default function CheckIn() {
  const { user } = useAuth();
  const { theme } = useTheme();
  const navigate = useNavigate();

  useEffect(() => {
    const id = user?.id;
    if (!id) return;
    if (isRoutineTrackingAccepted(id)) return;
    navigate("/dashboard", { replace: true, state: { flashNeedAccept: true } });
  }, [user?.id, navigate]);

  const [sleepHours, setSleepHours] = useState(7);
  const [stressToday, setStressToday] = useState(3);
  const [skinFeeling, setSkinFeeling] = useState("");
  const [appliedRoutine, setAppliedRoutine] = useState(true);
  const [notes, setNotes] = useState("");
  const [loading, setLoading] = useState(false);
  const [result, setResult] = useState(null);
  const [alreadyCheckedIn, setAlreadyCheckedIn] = useState(false);
  const [statusLoading, setStatusLoading] = useState(true);
  const [submitError, setSubmitError] = useState("");

  const canSubmit = skinFeeling && !loading && !alreadyCheckedIn;

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
      const res = await fetch(`${API}/daily_checkin`, {
        method: "POST",
        headers: { "Content-Type": "application/json", ...auth },
        body: JSON.stringify({
          user_id: user?.id || DEMO_USER_ID,
          sleep_hours: sleepHours,
          stress_today: stressToday,
          skin_feeling: skinFeeling,
          applied_routine: appliedRoutine,
          notes: notes || null,
        }),
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
      <div className={`min-h-screen ${theme.bg} pb-24`}>
        <div className="max-w-lg mx-auto px-4 py-8">
          <div className="text-center mb-6">
            <div className="w-16 h-16 rounded-2xl flex items-center justify-center mx-auto mb-4 shadow-lg"
              style={{ background: `linear-gradient(135deg, ${theme.accent}, ${theme.primary})` }}>
              <Sparkles className="w-8 h-8 text-white" />
            </div>
            <h1 className="text-xl font-bold text-gray-900">Bugünün Raporu</h1>
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
            Dashboard'a Git <ArrowRight className="w-4 h-4" />
          </button>
        </div>
      </div>
    );
  }

  if (statusLoading) {
    return (
      <div className={`min-h-screen ${theme.bg} flex items-center justify-center pb-24`}>
        <Loader2 className="w-8 h-8 animate-spin text-gray-400" />
      </div>
    );
  }

  if (alreadyCheckedIn && !result) {
    return (
      <div className={`min-h-screen ${theme.bg} pb-24`}>
        <div className="max-w-lg mx-auto px-4 py-8 text-center">
          <CheckCircle2 className="w-14 h-14 mx-auto mb-4 text-teal-500" />
          <h1 className="text-xl font-bold text-gray-900">Bugün check-in yaptın</h1>
          <p className="text-sm text-gray-500 mt-2">Her gün tek kayıt tutulur. Yarın tekrar gelebilirsin.</p>
          <button
            type="button"
            onClick={() => navigate("/dashboard")}
            className="mt-6 w-full py-3 rounded-xl text-white font-semibold"
            style={{ backgroundColor: theme.primary }}
          >
            Dashboard&apos;a dön
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className={`min-h-screen ${theme.bg} pb-24`}>
      <div className="max-w-lg mx-auto px-4 py-8">
        {/* Header */}
        <div className="text-center mb-8">
          <h1 className="text-xl font-bold text-gray-900">Günlük Check-in</h1>
          <p className="text-sm text-gray-500 mt-1">Bugün nasıl hissediyorsun?</p>
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
            <><Send className="w-5 h-5" /> Check-in Gönder</>
          )}
        </button>
      </div>
    </div>
  );
}
