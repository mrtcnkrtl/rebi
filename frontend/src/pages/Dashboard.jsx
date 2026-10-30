import { useMemo, useState, useEffect } from "react";
import { useLocation, Link, useNavigate } from "react-router-dom";
import { useAuth } from "../context/AuthContext";
import { useTheme } from "../context/ThemeContext";
import { API_URL, supabase } from "../lib/supabase";
import { apiAuthHeaders } from "../lib/apiAuth";
import { DEMO_USER_ID } from "../lib/demoUser";
import {
  acceptRoutineTracking,
  getRoutineSnapshot,
  isRoutineTrackingAccepted,
  saveRoutineSnapshot,
} from "../lib/routineTracking";
import RoutineStepChoices from "../components/RoutineStepChoices";
import { applyChosenOptionIds, getChosenOption, withResolvedChoices } from "../lib/routineStepChoices";
import { friendlyRoutineTitle } from "../lib/routineDisplay";
import ThemePatternOverlay from "../components/ThemePatternOverlay";
import AiDisclaimer from "../components/AiDisclaimer";
import { useTranslation } from "react-i18next";
import { ingestDailyTrackingEvent } from "../lib/dailyTracking";
import {
  Sparkles, PlusCircle, CloudSun, Droplets, Sun, Thermometer,
  Calendar, ArrowRight, Leaf, AlertTriangle, Heart, Apple,
  Droplet, Moon, MessageCircle, ClipboardCheck, Info,
  CalendarDays, Activity,
} from "lucide-react";

// Week day labels come from i18n (dashboard.weekDays)

/**
 * Rutin metninde geçen akşam / planda sınırlı aktifler için tek satırlık sabah uyarısı.
 * Genel “dikkat / kesinlik” eğitimi göstermiyoruz; motor zaten uygular.
 */
function computeEveningActivesMorningHints(routine) {
  if (!Array.isArray(routine) || routine.length === 0) return [];
  const blob = routine
    .map((r) => `${r.action || ""} ${r.detail || ""}`)
    .join(" ")
    .toLowerCase();

  const rules = [
    {
      id: "retinoid",
      test: () =>
        /\bretinol\b|retinal|adapalen|adapalene|tretinoin|retinoid/.test(blob),
      text: "Retinoid (retinol, retinal, adapalen vb.) rutininde: sabah kullanmayın.",
    },
    {
      id: "bakuchiol",
      test: () => /bakuchiol/.test(blob),
      text: "Bakuchiol rutininde: sabah kullanmayın.",
    },
    {
      id: "arbutin_leke",
      test: () =>
        /arbutin|alfa[\s-]?arbutin|traneksamik|kojik|hidrokinon/.test(blob),
      text: "Leke odaklı aktif (arbutin, traneksamik vb.) rutininde: sabah kullanmayın.",
    },
    {
      id: "aha",
      test: () => /glikolik|glycolic|laktik|lactic|mandelik|\baha\b/.test(blob),
      text: "AHA (glikolik, laktik vb.) rutininde: sabah kullanmayın.",
    },
    {
      id: "bha",
      test: () => /salisilik|salicylic|\bbha\b/.test(blob),
      text: "BHA (salisilik asit) rutininde: sabah kullanmayın.",
    },
    {
      id: "benzoil",
      test: () => /benzoil\s*peroksit|benzoyl/.test(blob),
      text: "Benzoil peroksit rutininde: sabah kullanmayın.",
    },
    {
      id: "azelaik",
      test: () => /azelaik|azelaic/.test(blob),
      text: "Azelaik asit (tedavi konsantrasyonu) rutininde: sabah kullanmayın.",
    },
  ];

  const seen = new Set();
  const out = [];
  for (const r of rules) {
    if (!r.test()) continue;
    if (seen.has(r.id)) continue;
    seen.add(r.id);
    out.push(r.text);
  }
  return out;
}

/** Backend weekly_days: 0=Pzt … 6=Paz — JS getDay: 0=Paz */
function getTurkeyWeekdayIndex(d = new Date()) {
  const js = d.getDay();
  return js === 0 ? 6 : js - 1;
}

/** detail metninde haftalık sıklık ifadesi var mı? (gece, kez, kere, defa, gün) */
function isWeeklyUsageItem(item) {
  const d = (item.detail || "").toLowerCase();
  return /\bhaftada\s*\d+(?:\s*[-–]\s*\d+)?\s*(?:gece|kez|kere|defa|gün)\b/i.test(d);
}

/** Backend weekly_days yoksa: metindeki N ile tam N gün (Pzt–Paz aralığına yayılım). */
function getDefaultWeeklyDays(detail) {
  const d = (detail || "").toLowerCase();
  const m = d.match(/\bhaftada\s*(\d+)(?:\s*[-–]\s*(\d+))?\s*(?:gece|kez|kere|defa|gün)\b/);
  if (!m) return [];
  const a = parseInt(m[1], 10);
  const b = m[2] ? parseInt(m[2], 10) : null;
  const n = Math.min(b != null ? Math.min(a, b) : a, 7);
  if (n < 1) return [];
  if (n >= 7) return [0, 1, 2, 3, 4, 5, 6];
  if (n === 1) return [0];
  const days = new Set();
  for (let i = 0; i < n; i++) {
    days.add(Math.min(6, Math.max(0, Math.round((i * 6) / (n - 1)))));
  }
  return [...days].sort((x, y) => x - y);
}

export default function Dashboard() {
  const { user } = useAuth();
  const { theme } = useTheme();
  const location = useLocation();
  const navigate = useNavigate();
  const { t, i18n } = useTranslation();
  const uiLocale = (i18n.resolvedLanguage || i18n.language || "tr").toLowerCase();
  const WEEK_DAYS = t("dashboard.weekDays", { returnObjects: true, defaultValue: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"] });
  const fallbackStepTitle = t("dashboard.fallbackStepTitle", { defaultValue: "This step" });
  const prefersLocalized = ((i18n.resolvedLanguage || i18n.language || "tr").toLowerCase().split("-")[0] || "tr") !== "tr";
  const pickAction = (item) => (prefersLocalized ? (item?.action_localized || item?.action) : item?.action);
  const pickDetail = (item) => (prefersLocalized ? (item?.detail_localized || item?.detail) : item?.detail);
  const nav = location.state;
  const uid = user?.id;

  const [fetchedRoutine, setFetchedRoutine] = useState(null);
  const [fetchingDbRoutine, setFetchingDbRoutine] = useState(false);
  const [showPlanExpanded, setShowPlanExpanded] = useState(false);
  const [quickLogMsg, setQuickLogMsg] = useState("");

  const accepted = uid ? isRoutineTrackingAccepted(uid) : false;

  useEffect(() => {
    if (!uid || !supabase || uid === DEMO_USER_ID) return;
    let cancelled = false;
    setFetchingDbRoutine(true);
    (async () => {
      try {
        const { data } = await supabase
          .from("routines")
          .select("active_routine")
          .eq("user_id", uid)
          .eq("is_active", true)
          .maybeSingle();
        if (!cancelled && data?.active_routine?.length) {
          setFetchedRoutine(data.active_routine);
        }
      } finally {
        if (!cancelled) setFetchingDbRoutine(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [uid]);

  // If UI is EN but routine items are stored in TR, enrich them once via backend translation endpoint.
  useEffect(() => {
    if (!prefersLocalized) return;
    if (!uid) return;
    if (!Array.isArray(fetchedRoutine) || fetchedRoutine.length === 0) return;
    const anyMissing = fetchedRoutine.some((it) => !(it?.action_localized || it?.detail_localized));
    if (!anyMissing) return;
    let cancelled = false;
    (async () => {
      try {
        const auth = await apiAuthHeaders();
        const res = await fetch(`${API_URL}/routine/translate_items`, {
          method: "POST",
          headers: { "Content-Type": "application/json", ...auth },
          body: JSON.stringify({ user_id: uid, routine_items: fetchedRoutine }),
        });
        const data = await res.json().catch(() => ({}));
        const items = data?.routine_items;
        if (!cancelled && Array.isArray(items) && items.length) setFetchedRoutine(items);
      } catch {
        /* ignore: fallback to TR fields */
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [prefersLocalized, uid, fetchedRoutine]);

  useEffect(() => {
    if (!uid) return;
    if (!accepted) return;
    const st = location.state;
    if (!st || !Array.isArray(st.routine) || st.routine.length === 0) return;
    const prev = getRoutineSnapshot(uid) || {};
    saveRoutineSnapshot(uid, {
      ...prev,
      routine: st.routine,
      ...(st.checkinResult != null ? { checkinResult: st.checkinResult } : {}),
      ...(st.weather != null ? { weather: st.weather } : {}),
      ...(Array.isArray(st.activePlan) ? { activePlan: st.activePlan } : {}),
    });
  }, [uid, accepted, location.key, location.state]);

  const merged = useMemo(() => {
    const snap = uid ? getRoutineSnapshot(uid) : null;
    const st = nav ?? {};
    let routine = [];
    if (Array.isArray(st.routine) && st.routine.length) {
      routine = st.routine;
    } else if (accepted && fetchedRoutine?.length) {
      routine = fetchedRoutine;
    } else if (snap?.routine?.length) {
      routine = snap.routine;
    } else if (fetchedRoutine?.length) {
      routine = fetchedRoutine;
    }

    return {
      routine,
      weather: st.weather ?? snap?.weather ?? null,
      userName: st.userName ?? snap?.userName ?? user?.user_metadata?.full_name ?? t("common.user", { defaultValue: "User" }),
      photoUrl: st.photoUrl ?? snap?.photoUrl ?? null,
      flowDebug: st.flowDebug ?? snap?.flowDebug ?? null,
      checkinResult: st.checkinResult ?? snap?.checkinResult ?? null,
      safetyAbsoluteRules: st.safetyAbsoluteRules ?? snap?.safetyAbsoluteRules ?? null,
      ruleEnforcementReport: st.ruleEnforcementReport ?? snap?.ruleEnforcementReport ?? null,
      concern: st.concern ?? snap?.concern ?? null,
      assessmentId: st.assessmentId ?? snap?.assessmentId ?? null,
      activePlan: Array.isArray(st.activePlan)
        ? st.activePlan
        : (Array.isArray(snap?.activePlan) ? snap.activePlan : []),
    };
  }, [nav, uid, accepted, fetchedRoutine, user, t]);

  const routine = merged.routine;
  const weather = merged.weather;
  const userName = merged.userName;
  const photoUrl = merged.photoUrl;
  const flowDebug = merged.flowDebug;
  const checkinResult = merged.checkinResult;
  const safetyAbsoluteRules = merged.safetyAbsoluteRules;
  const ruleEnforcementReport = merged.ruleEnforcementReport;
  const activePlan = Array.isArray(merged.activePlan) ? merged.activePlan : [];

  const handleAcceptRoutine = () => {
    if (!uid) return;
    acceptRoutineTracking(uid, {
      routine: applyChosenOptionIds(uid, routine),
      weather,
      userName,
      photoUrl,
      flowDebug,
      safetyAbsoluteRules,
      ruleEnforcementReport,
      concern: merged.concern,
      assessmentId: merged.assessmentId,
      checkinResult: checkinResult || null,
      activePlan: merged.activePlan || [],
    });
    setShowPlanExpanded(false);
    navigate(location.pathname, { replace: true, state: {} });
  };

  /* ─── Routine categorization ─── */
  const productItems = routine.filter((r) =>
    ["Bakım", "Koruma"].includes(r.category) || (!["Zihin", "Yaşam", "Beslenme"].includes(r.category))
  );
  const lifestyleItems = routine.filter((r) => ["Zihin", "Yaşam", "Beslenme"].includes(r.category));

  const morningProducts = useMemo(() => {
    const list = productItems.filter((r) => r.time === "Sabah" || r.time === "sabah");
    return [...list].sort((a, b) => (a.step_order ?? 50) - (b.step_order ?? 50));
  }, [productItems]);
  const eveningProducts = useMemo(() => {
    const list = productItems.filter((r) => r.time === "Akşam" || r.time === "akşam");
    return [...list].sort((a, b) => (a.step_order ?? 50) - (b.step_order ?? 50));
  }, [productItems]);
  const nutritionItems = lifestyleItems.filter((r) => r.category === "Beslenme");
  const dailyBalanceItem = useMemo(
    () => routine.find((r) => String(r.action || "").startsWith("Günlük denge:")) || null,
    [routine],
  );
  const wellnessItems = lifestyleItems.filter(
    (r) => r.category !== "Beslenme" && !String(r.action || "").startsWith("Günlük denge:"),
  );

  /** Zamanı "Günlük" olan yaşam/beslenme/zihin adımları (denge özeti kartında zaten var, tekrar etme). */
  const dailyLifestyleItems = useMemo(() => {
    return lifestyleItems
      .filter((r) => {
        const t = String(r.time || "").toLowerCase();
        if (t !== "günlük" && t !== "gunluk") return false;
        if (String(r.action || "").startsWith("Günlük denge:")) return false;
        return true;
      })
      .sort((a, b) => (a.step_order ?? 50) - (b.step_order ?? 50));
  }, [lifestyleItems]);

  /** Sabah yaşam / zihin (nefes vb.) — ürün sabah listesinde yoktu; takip ekranına eklendi. */
  const wellnessMorningItems = useMemo(() => {
    return wellnessItems
      .filter((r) => {
        const t = String(r.time || "").trim().toLowerCase();
        return t === "sabah" || t === "morning";
      })
      .sort((a, b) => (a.step_order ?? 50) - (b.step_order ?? 50));
  }, [wellnessItems]);

  const wellnessEveningItems = useMemo(() => {
    return wellnessItems
      .filter((r) => {
        const t = String(r.time || "").trim().toLowerCase();
        return t === "akşam" || t === "evening";
      })
      .sort((a, b) => (a.step_order ?? 50) - (b.step_order ?? 50));
  }, [wellnessItems]);

  const eveningMorningHints = useMemo(() => computeEveningActivesMorningHints(routine), [routine]);

  const weeklyItems = useMemo(() => {
    const hasWeeklyDays = (r) => Array.isArray(r.weekly_days) && r.weekly_days.length > 0;
    const list = productItems.filter((r) => hasWeeklyDays(r) || isWeeklyUsageItem(r));
    return list.map((item, i) => ({
      ...item,
      weeklyKey: `${item.action}-${i}`,
      displayDays: Array.isArray(item.weekly_days) && item.weekly_days.length
        ? item.weekly_days
        : getDefaultWeeklyDays(item.detail),
    }));
  }, [productItems]);

  /** Gün gün rutin: her gün (0–6) için o güne özel sabah + akşam adımları. Haftalık maddeler sadece atanmış günlerde. */
  const routineByDay = useMemo(() => {
    const days = {};
    for (let d = 0; d < 7; d++) {
      const morningForDay = morningProducts.filter((item) => {
        const wd = item.weekly_days;
        if (!Array.isArray(wd) || wd.length === 0) return true;
        return wd.includes(d);
      });
      const eveningForDay = eveningProducts.filter((item) => {
        const wd = item.weekly_days;
        if (!Array.isArray(wd) || wd.length === 0) return true;
        return wd.includes(d);
      });
      days[d] = { morning: morningForDay, evening: eveningForDay };
    }
    return days;
  }, [morningProducts, eveningProducts]);

  /** Rutinde kullanılacak maddeler listesi (tekilleştirilmiş, sırayla). */
  const routineIngredientsList = useMemo(() => {
    const seen = new Set();
    const list = [];
    [...morningProducts, ...eveningProducts].forEach((item) => {
      const key = (item.action || "").trim();
      if (key && !seen.has(key)) {
        seen.add(key);
        list.push(key);
      }
    });
    return list;
  }, [morningProducts, eveningProducts]);

  if (!routine.length) {
    if (uid && supabase && uid !== DEMO_USER_ID && fetchingDbRoutine) {
      return (
        <div className={`min-h-screen ${theme.bg} flex items-center justify-center pb-24 relative`}>
          <ThemePatternOverlay pattern={theme.pattern} />
          <div className="w-10 h-10 border-4 border-teal-200 border-t-teal-600 rounded-full animate-spin relative z-[1]" />
        </div>
      );
    }
    return (
      <div className={`min-h-screen ${theme.bg} pb-24 relative`}>
        <ThemePatternOverlay pattern={theme.pattern} />
        <div className="max-w-lg mx-auto px-4 py-16 text-center relative z-[1]">
          {nav?.flashNeedAccept && (
            <div className="mb-4 text-left card !p-3 border-amber-200 bg-amber-50/80 text-sm text-amber-900">
              {t("dashboard.acceptHint")}
            </div>
          )}
          <div className="w-20 h-20 rounded-3xl flex items-center justify-center mx-auto mb-6 shadow-xl"
            style={{ background: `linear-gradient(135deg, ${theme.accent}, ${theme.primary})` }}>
            <Leaf className="w-10 h-10 text-white" />
          </div>
          <h1 className="text-2xl font-bold text-gray-900 mb-2">{t("dashboard.noAnalyzeTitle", { name: userName })}</h1>
          <p className="text-gray-500 mb-6 max-w-sm mx-auto">{t("dashboard.noAnalyzeDesc")}</p>
          <div className="space-y-3">
            <Link to="/dashboard/analyze" className="btn-primary inline-flex !px-8 !py-4 !text-lg group w-full justify-center"
              style={{ backgroundColor: theme.primary }}>
              <PlusCircle className="w-5 h-5" /> {t("dashboard.startAnalyze")} <ArrowRight className="w-5 h-5" />
            </Link>
            <Link to="/dashboard/chat" className="btn-secondary inline-flex !px-8 !py-3 w-full justify-center"
              style={{ borderColor: theme.primaryLight, color: theme.primary }}>
              <MessageCircle className="w-5 h-5" /> {t("dashboard.chatWithAi")}
            </Link>
          </div>
        </div>
      </div>
    );
  }

  const trackingMode = accepted && routine.length > 0 && !showPlanExpanded;
  const showDailyCheckIn = accepted && routine.length > 0;
  const showAcceptBar = !accepted && routine.length > 0;

  const todayIdx = getTurkeyWeekdayIndex();
  const todayPlan = routineByDay[todayIdx] || { morning: [], evening: [] };

  const handleQuickLog = async (kind) => {
    if (!uid) return;
    let type;
    const payload = {};
    if (kind === "spf") {
      type = "spf_refresh";
      payload.n = 1;
    } else if (kind === "morning") {
      type = "routine_completed_block";
      payload.morning = true;
    } else {
      type = "routine_completed_block";
      payload.evening = true;
    }
    const r = await ingestDailyTrackingEvent(uid, type, payload);
    if (r.ok && !r.skipped) {
      setQuickLogMsg(t("dashboard.quickLogged"));
      window.setTimeout(() => setQuickLogMsg(""), 2200);
    }
  };

  if (trackingMode) {
    return (
      <div className={`min-h-screen ${theme.bg} pb-24 relative`}>
        <ThemePatternOverlay pattern={theme.pattern} />
        <div className="max-w-2xl mx-auto px-4 py-8 relative z-[1]">
          <div className="mb-6">
            <h1 className="text-2xl font-bold text-gray-900">{t("dashboard.trackingTitle")}</h1>
            <p className="text-gray-500 mt-1 text-sm">
              {new Date().toLocaleDateString(uiLocale, { weekday: "long", year: "numeric", month: "long", day: "numeric" })}
            </p>
            <p className="text-sm text-gray-600 mt-2">{t("dashboard.helloToday", { name: userName })}</p>
            <AiDisclaimer className="mt-2" />
          </div>

          <Link
            to="/dashboard/checkin"
            className="card mb-5 flex items-center gap-3 hover:shadow-md transition-shadow cursor-pointer group"
            style={{
              borderColor: theme.primaryLight,
              background: `linear-gradient(135deg, ${theme.primaryLight}40, white)`,
            }}
          >
            <div
              className="w-12 h-12 rounded-xl flex items-center justify-center shrink-0"
              style={{ backgroundColor: theme.primary }}
            >
              <ClipboardCheck className="w-6 h-6 text-white" />
            </div>
            <div className="flex-1">
              <h3 className="text-base font-bold text-gray-800">{t("dashboard.dailyCheckinTitle")}</h3>
              <p className="text-xs text-gray-500">{t("dashboard.dailyCheckinSubtitle")}</p>
            </div>
            <ArrowRight className="w-5 h-5 text-gray-400 group-hover:translate-x-1 transition-transform" />
          </Link>

          <div className="card mb-4 !p-3">
            <p className="text-xs font-bold text-gray-800 mb-0.5">{t("dashboard.quickLogTitle")}</p>
            <p className="text-[10px] text-gray-500 mb-2 leading-relaxed">{t("dashboard.quickLogHint")}</p>
            <div className="flex flex-wrap gap-2">
              <button
                type="button"
                onClick={() => handleQuickLog("spf")}
                className="text-[11px] font-semibold px-3 py-1.5 rounded-xl border border-amber-200 bg-amber-50 text-amber-900"
              >
                <Sun className="w-3.5 h-3.5 inline mr-1" />
                {t("dashboard.quickSpf")}
              </button>
              <button
                type="button"
                onClick={() => handleQuickLog("morning")}
                className="text-[11px] font-semibold px-3 py-1.5 rounded-xl border border-gray-200 bg-white text-gray-700"
              >
                {t("dashboard.quickMorning")}
              </button>
              <button
                type="button"
                onClick={() => handleQuickLog("evening")}
                className="text-[11px] font-semibold px-3 py-1.5 rounded-xl border border-gray-200 bg-white text-gray-700"
              >
                {t("dashboard.quickEvening")}
              </button>
            </div>
            {quickLogMsg ? (
              <p className="text-[10px] text-emerald-700 mt-2 font-medium">{quickLogMsg}</p>
            ) : null}
          </div>

          {checkinResult && checkinResult.ai_note && (
            <div className="card mb-5 border-l-4" style={{ borderLeftColor: theme.primary }}>
              <div className="flex items-start gap-3">
                <Sparkles className="w-5 h-5 shrink-0 mt-0.5" style={{ color: theme.primary }} />
                <div>
                  <h3 className="text-xs font-bold text-gray-700 mb-1">{t("dashboard.lastCheckinNoteTitle")}</h3>
                  <p className="text-sm text-gray-600 leading-relaxed">{checkinResult.ai_note}</p>
                </div>
              </div>
            </div>
          )}

          <DailyBalanceCard item={dailyBalanceItem} flowDebug={flowDebug} theme={theme} />

          <div className="card mb-4 overflow-hidden">
            <div
              className="px-3 py-2 border-b border-gray-100 font-bold text-gray-800 text-sm flex items-center gap-2"
              style={{ backgroundColor: theme.primary + "12" }}
            >
              <CalendarDays className="w-4 h-4" style={{ color: theme.primary }} />
              {t("dashboard.todayTitle")} — {WEEK_DAYS[todayIdx]}
            </div>
            <div className="p-3 space-y-4">
              {todayPlan.morning.length > 0 && (
                <div>
                  <div className="flex items-center gap-1.5 mb-1.5 text-xs font-semibold text-gray-600">☀️ {t("dashboard.morning")}</div>
                  <div className="space-y-1.5">
                    {todayPlan.morning.map((item, i) => (
                      <ProductStep key={`t-m-${i}`} item={item} step={i + 1} theme={theme} />
                    ))}
                  </div>
                </div>
              )}
              {wellnessMorningItems.length > 0 && (
                <div>
                  <div className="flex items-center gap-1.5 mb-1.5 text-xs font-semibold text-gray-600">
                    ☀️ {t("dashboard.morning")} — {t("dashboard.lifestyleSuffix")}
                  </div>
                  <div className="space-y-0.5">
                    {wellnessMorningItems.map((item, i) => (
                      <RoutineLine key={`t-wm-${i}`} item={item} pickAction={pickAction} fallbackTitle={fallbackStepTitle} />
                    ))}
                  </div>
                </div>
              )}
              {todayPlan.evening.length > 0 && (
                <div>
                  <div className="flex items-center gap-1.5 mb-1.5 text-xs font-semibold text-gray-600">🌙 {t("dashboard.evening")}</div>
                  <div className="space-y-1.5">
                    {todayPlan.evening.map((item, i) => (
                      <ProductStep key={`t-e-${i}`} item={item} step={i + 1} theme={theme} />
                    ))}
                  </div>
                </div>
              )}
              {wellnessEveningItems.length > 0 && (
                <div>
                  <div className="flex items-center gap-1.5 mb-1.5 text-xs font-semibold text-gray-600">
                    🌙 {t("dashboard.evening")} — {t("dashboard.lifestyleSuffix")}
                  </div>
                  <div className="space-y-0.5">
                    {wellnessEveningItems.map((item, i) => (
                      <RoutineLine key={`t-we-${i}`} item={item} pickAction={pickAction} fallbackTitle={fallbackStepTitle} />
                    ))}
                  </div>
                </div>
              )}
              {dailyLifestyleItems.length > 0 && (
                <div>
                  <div className="flex items-center gap-1.5 mb-1.5 text-xs font-semibold text-gray-600">📌 {t("dashboard.allDay")}</div>
                  <div className="space-y-0.5">
                    {dailyLifestyleItems.map((item, i) => (
                      <RoutineLine key={`t-d-${i}`} item={item} pickAction={pickAction} fallbackTitle={fallbackStepTitle} />
                    ))}
                  </div>
                </div>
              )}
              {!todayPlan.morning.length &&
                !todayPlan.evening.length &&
                !dailyLifestyleItems.length &&
                !wellnessMorningItems.length &&
                !wellnessEveningItems.length && (
                <p className="text-sm text-gray-500">{t("dashboard.noPlannedSteps")}</p>
              )}
            </div>
          </div>

          {weeklyItems.length > 0 && (
            <div className="card mb-5 !p-3">
              <p className="text-xs font-bold text-gray-800 mb-2">{t("dashboard.weeklyTitle")}</p>
              <div className="space-y-2">
                {weeklyItems.slice(0, 4).map((item) => (
                  <div key={item.weeklyKey} className="text-[12px] text-gray-600">
                    <span className="font-semibold text-gray-800">{friendlyRoutineTitle(pickAction(item), fallbackStepTitle)}</span>
                    <span className="text-gray-500">
                      {" · "}
                      {(item.displayDays || []).length
                        ? (item.displayDays || []).map((i) => WEEK_DAYS[i]).join(", ")
                        : "—"}
                    </span>
                  </div>
                ))}
              </div>
            </div>
          )}

          {weather?.temperature && (
            <div className="card mb-5 bg-gradient-to-br from-blue-50 to-cyan-50 border-blue-100 !p-3">
              <div className="flex items-center gap-2 text-xs font-bold text-gray-800">
                <CloudSun className="w-4 h-4 text-blue-500" />
                {t("dashboard.weatherTitle")} — {weather.temperature}°C · UV {weather.uv_index}
              </div>
            </div>
          )}

          <button
            type="button"
            onClick={() => setShowPlanExpanded(true)}
            className="btn-secondary w-full mb-3"
            style={{ borderColor: theme.primaryLight, color: theme.primary }}
          >
            Tüm haftayı, detayları ve yaşam önerilerini göster
          </button>
          <Link
            to="/dashboard/analyze?photo=1"
            className="btn-secondary w-full !mt-0 mb-2 inline-flex justify-center text-sm"
            style={{ borderColor: theme.primaryLight, color: theme.primary }}
          >
            <PlusCircle className="w-5 h-5" /> Fotoğraf yükle (hızlı)
          </Link>
          <Link
            to="/dashboard/analyze"
            className="btn-secondary w-full !mt-0 inline-flex justify-center"
            style={{ borderColor: theme.primaryLight, color: theme.primary }}
          >
            <PlusCircle className="w-5 h-5" /> Yeni analiz
          </Link>
        </div>
      </div>
    );
  }

  return (
    <div className={`min-h-screen ${theme.bg} pb-24 relative`}>
      <ThemePatternOverlay pattern={theme.pattern} />
      <div className="max-w-2xl mx-auto px-4 py-8 relative z-[1]">
        {/* Header */}
        <div className="mb-6">
          {nav?.flashNeedAccept && (
            <div className="mb-4 card !p-3 border-amber-200 bg-amber-50/80 text-sm text-amber-900">
              {t("dashboard.acceptHint")}
            </div>
          )}
          <h1 className="text-2xl font-bold text-gray-900">
            {t("dashboard.myRoutineTitle", { name: userName })}{" "}
            <Sparkles className="w-5 h-5 inline" style={{ color: theme.accent }} />
          </h1>
          <p className="text-gray-500 mt-1 text-sm">
            {new Date().toLocaleDateString(uiLocale, { weekday: "long", year: "numeric", month: "long", day: "numeric" })}
          </p>
          <AiDisclaimer className="mt-2" />
          {accepted && showPlanExpanded && (
            <button
              type="button"
              onClick={() => setShowPlanExpanded(false)}
              className="mt-3 text-sm font-semibold underline-offset-2 hover:underline"
              style={{ color: theme.primary }}
            >
              {t("dashboard.backToTracking")}
            </button>
          )}
          {showAcceptBar && (
            <div
              className="mt-4 card !p-4 border-2"
              style={{ borderColor: theme.primaryLight, background: `${theme.primaryLight}18` }}
            >
              <p className="text-sm text-gray-800 font-medium mb-3">
                {t("dashboard.acceptBanner")}
              </p>
              <button
                type="button"
                onClick={handleAcceptRoutine}
                className="w-full py-3 rounded-xl text-white font-semibold shadow-md"
                style={{ backgroundColor: theme.primary }}
              >
                {t("dashboard.acceptCta")}
              </button>
            </div>
          )}
          {flowDebug && (
            <div className="mt-2 flex flex-wrap gap-1.5 text-[10px]">
              <span className="px-2 py-0.5 rounded-full" style={{ backgroundColor: theme.primaryLight, color: theme.primaryDark }}>{flowDebug.age_group}</span>
              <span className="px-2 py-0.5 rounded-full" style={{ backgroundColor: theme.primaryLight, color: theme.primaryDark }}>{flowDebug.skin_type}</span>
              <span className="px-2 py-0.5 rounded-full" style={{ backgroundColor: theme.primaryLight, color: theme.primaryDark }}>{flowDebug.severity}</span>
              {flowDebug.risk_info && (
                <span className={`px-2 py-0.5 rounded-full ${
                  flowDebug.risk_info.level === "crisis" ? "bg-red-100 text-red-700" :
                  flowDebug.risk_info.level === "high" ? "bg-orange-100 text-orange-700" :
                  flowDebug.risk_info.level === "moderate" ? "bg-yellow-100 text-yellow-700" :
                  "bg-green-100 text-green-700"
                }`}>
                  {t("dashboard.riskPrefix")}:{" "}
                  {prefersLocalized
                    ? t(`dashboard.riskLevels.${flowDebug.risk_info.level || "normal"}`)
                    : (flowDebug.risk_info.label || flowDebug.risk_info.level)}
                </span>
              )}
            </div>
          )}
        </div>

        {eveningMorningHints.length > 0 && (
          <div className="card mb-5 border-amber-200 bg-amber-50/60">
            <div className="flex items-start gap-3">
              <AlertTriangle className="w-5 h-5 text-amber-600 shrink-0 mt-0.5" />
              <div className="min-w-0">
                <p className="text-sm font-bold text-amber-950 mb-2">{t("dashboard.morningUsageTitle")}</p>
                <ul className="text-sm text-gray-800 space-y-1.5 list-disc list-inside">
                  {eveningMorningHints.map((line, i) => (
                    <li key={i}>{line}</li>
                  ))}
                </ul>
              </div>
            </div>
          </div>
        )}

        <DailyBalanceCard item={dailyBalanceItem} flowDebug={flowDebug} theme={theme} />

        {routineIngredientsList.length > 0 && (
          <details className="card mb-4 !p-3">
            <summary className="cursor-pointer text-sm font-semibold text-gray-800">
              {t("dashboard.productListTitle")}
            </summary>
            <div className="flex flex-wrap gap-1.5 mt-3">
              {routineIngredientsList.map((name, i) => (
                <span
                  key={i}
                  className="inline-flex items-center px-2.5 py-1 rounded-lg text-[11px] font-medium bg-gray-50 text-gray-700 border border-gray-100"
                >
                  {friendlyRoutineTitle(name, name)}
                </span>
              ))}
            </div>
          </details>
        )}

        {/* Daily Check-in — yalnız rutin kabul edildikten sonra */}
        {showDailyCheckIn && (
          <Link to="/dashboard/checkin"
            className="card mb-5 flex items-center gap-3 hover:shadow-md transition-shadow cursor-pointer group"
            style={{ borderColor: theme.primaryLight, background: `linear-gradient(135deg, ${theme.primaryLight}40, white)` }}>
            <div className="w-10 h-10 rounded-xl flex items-center justify-center shrink-0"
              style={{ backgroundColor: theme.primary }}>
              <ClipboardCheck className="w-5 h-5 text-white" />
            </div>
            <div className="flex-1">
              <h3 className="text-sm font-bold text-gray-800">{t("dashboard.dailyCheckinTitle")}</h3>
              <p className="text-xs text-gray-500">{t("dashboard.feelsTodayHint")}</p>
            </div>
            <ArrowRight className="w-5 h-5 text-gray-400 group-hover:translate-x-1 transition-transform" />
          </Link>
        )}

        {/* Check-in Result Alert */}
        {showDailyCheckIn && checkinResult && checkinResult.ai_note && (
          <div className="card mb-5 border-l-4" style={{ borderLeftColor: theme.primary }}>
            <div className="flex items-start gap-3">
              <Sparkles className="w-5 h-5 shrink-0 mt-0.5" style={{ color: theme.primary }} />
              <div>
                <h3 className="text-xs font-bold text-gray-700 mb-1">{t("dashboard.lastCheckinNoteTitle")}</h3>
                <p className="text-sm text-gray-600 leading-relaxed">{checkinResult.ai_note}</p>
                {checkinResult.changes && checkinResult.changes.length > 0 && (
                  <div className="mt-2 flex items-center gap-1.5 text-xs text-amber-600">
                    <Info className="w-3.5 h-3.5" />
                    <span>{t("checkin.changesCount", { count: checkinResult.changes.length })}</span>
                  </div>
                )}
              </div>
            </div>
          </div>
        )}

        {/* Weather */}
        {weather?.temperature && (
          <div className="card mb-5 bg-gradient-to-br from-blue-50 to-cyan-50 border-blue-100">
            <div className="flex items-center gap-2 mb-3"><CloudSun className="w-4 h-4 text-blue-500" /><h2 className="font-bold text-gray-900 text-xs">{t("dashboard.weatherTitle")}</h2></div>
            <div className="grid grid-cols-3 gap-2">
              <div className="bg-white/70 rounded-xl p-2.5 text-center"><Thermometer className="w-4 h-4 text-orange-500 mx-auto mb-0.5" /><p className="text-base font-bold text-gray-800">{weather.temperature}°C</p></div>
              <div className="bg-white/70 rounded-xl p-2.5 text-center"><Sun className="w-4 h-4 text-amber-500 mx-auto mb-0.5" /><p className="text-base font-bold text-gray-800">{weather.uv_index}</p><p className="text-[10px] text-gray-500">UV</p></div>
              <div className="bg-white/70 rounded-xl p-2.5 text-center"><Droplets className="w-4 h-4 text-blue-500 mx-auto mb-0.5" /><p className="text-base font-bold text-gray-800">%{weather.humidity}</p></div>
            </div>
            {/* Open-Meteo verisi CC BY 4.0 lisanslıdır: kaynak belirtilir. */}
            <p className="text-[10px] text-gray-400 mt-2">
              {t("dashboard.weatherAttribution")}{" "}
              <a href="https://open-meteo.com/" target="_blank" rel="noopener noreferrer" className="underline">Open-Meteo.com</a>
            </p>
          </div>
        )}

        {activePlan.length > 0 && (
          <details className="card mb-4 !p-3">
            <summary className="cursor-pointer text-sm font-semibold text-gray-800">
              {t("dashboard.activePlanTitle")}
            </summary>
            <ul className="space-y-2 mt-3">
              {activePlan.map((p, i) => {
                const whenKey =
                  p?.when === "morning"
                    ? "dashboard.activePlanWhenMorning"
                    : p?.when === "evening"
                      ? "dashboard.activePlanWhenEvening"
                      : "dashboard.activePlanWhenBoth";
                const name = p?.name_tr || p?.name || p?.active || "";
                return (
                  <li key={`${p?.active || "active"}-${i}`} className="flex items-baseline justify-between gap-2 text-sm">
                    <span className="font-medium text-gray-900">{name}</span>
                    <span className="text-[11px] text-gray-500 shrink-0">{t(whenKey)}</span>
                  </li>
                );
              })}
            </ul>
          </details>
        )}

        <SectionHeader icon="🧴" title={t("dashboard.routineByDayTitle")} subtitle={t("dashboard.routineByDaySubtitle")} color={theme.primary} />

        <details className="card mb-4 !p-3">
          <summary className="cursor-pointer text-sm font-semibold text-gray-800">
            {t("dashboard.howToChooseTitle")}
          </summary>
          <p className="text-xs text-gray-600 mt-2 leading-relaxed">{t("dashboard.howToChooseDesc")}</p>
        </details>

        {(dailyLifestyleItems.length > 0 || wellnessMorningItems.length > 0 || wellnessEveningItems.length > 0) && (
          <div className="card mb-4 overflow-hidden">
            <div
              className="px-3 py-2 border-b border-gray-100 font-bold text-gray-800 text-sm flex items-center gap-2"
              style={{ backgroundColor: theme.primary + "10" }}
            >
              <Leaf className="w-4 h-4" style={{ color: theme.primary }} />
              {t("dashboard.everyDayAllDayTitle")}
            </div>
            <div className="p-3 space-y-2">
              {wellnessMorningItems.map((item, i) => (
                <RoutineLine key={`all-wm-${i}`} item={item} pickAction={pickAction} fallbackTitle={fallbackStepTitle} />
              ))}
              {wellnessEveningItems.map((item, i) => (
                <RoutineLine key={`all-we-${i}`} item={item} pickAction={pickAction} fallbackTitle={fallbackStepTitle} />
              ))}
              {dailyLifestyleItems.map((item, i) => (
                <RoutineLine key={`all-days-${i}`} item={item} pickAction={pickAction} fallbackTitle={fallbackStepTitle} />
              ))}
            </div>
          </div>
        )}

        {WEEK_DAYS.map((dayLabel, dayIndex) => {
          const { morning, evening } = routineByDay[dayIndex] || { morning: [], evening: [] };
          if (!morning.length && !evening.length) return null;
          return (
            <div key={dayIndex} className="card mb-4 overflow-hidden">
              <div className="px-3 py-2 border-b border-gray-100 font-bold text-gray-800 text-sm flex items-center gap-2" style={{ backgroundColor: theme.primary + "12" }}>
                <CalendarDays className="w-4 h-4" style={{ color: theme.primary }} />
                {dayLabel}
              </div>
              <div className="p-3 space-y-4">
                {morning.length > 0 && (
                  <div>
                    <div className="flex items-center gap-1.5 mb-1.5 text-xs font-semibold text-gray-600">☀️ {t("dashboard.morning")}</div>
                    <div className="space-y-1.5">
                      {morning.map((item, i) => (
                        <ProductStep key={`${dayIndex}-m-${i}`} item={item} step={i + 1} theme={theme} />
                      ))}
                    </div>
                  </div>
                )}
                {evening.length > 0 && (
                  <div>
                    <div className="flex items-center gap-1.5 mb-1.5 text-xs font-semibold text-gray-600">🌙 {t("dashboard.evening")}</div>
                    <div className="space-y-1.5">
                      {evening.map((item, i) => (
                        <ProductStep key={`${dayIndex}-e-${i}`} item={item} step={i + 1} theme={theme} />
                      ))}
                    </div>
                  </div>
                )}
              </div>
            </div>
          );
        })}

        {/* Haftalık kullanım: hangi günlerde seyrek/güçlü adımlar */}
        {weeklyItems.length > 0 && (
          <>
            <div className="flex items-center gap-2.5 mb-3 mt-2">
              <div className="w-8 h-8 rounded-xl flex items-center justify-center" style={{ backgroundColor: theme.primary + "20" }}>
                <CalendarDays className="w-4 h-4" style={{ color: theme.primary }} />
              </div>
              <div>
                    <h2 className="text-base font-bold text-gray-900">{t("dashboard.weeklyTitle")}</h2>
                    <p className="text-[10px] text-gray-500">{t("dashboard.weeklyHint")}</p>
              </div>
            </div>
            <div className="space-y-4 mb-4">
              {weeklyItems.map((item) => (
                <WeeklyRoutineItem
                  key={item.weeklyKey}
                  item={item}
                  theme={theme}
                  weekDays={WEEK_DAYS}
                  pickAction={pickAction}
                  pickDetail={pickDetail}
                />
              ))}
            </div>
          </>
        )}

        {/* ═══ Yaşamsal Destekler ═══ */}
        <SectionHeader icon="🌿" title={t("dashboard.lifestyleSupportsTitle")} subtitle={t("dashboard.lifestyleSupportsSubtitle")} color="#16a34a" />

        {/* Nutrition */}
        {nutritionItems.length > 0 && (
          <div className="mb-4">
            <div className="flex items-center gap-2 mb-2"><Apple className="w-4 h-4 text-green-600" /><h3 className="text-sm font-bold text-gray-700">{t("dashboard.nutritionTitle")}</h3></div>
            <div className="space-y-2">
              {nutritionItems.map((item, i) => <LifestyleCard key={`n-${i}`} item={item} />)}
            </div>
          </div>
        )}

        {/* Water & Sleep - always show */}
        <div className="grid grid-cols-2 gap-3 mb-4">
          <div className="card !p-4 border-blue-100 bg-blue-50/30">
            <Droplet className="w-5 h-5 text-blue-500 mb-1" />
            <h4 className="font-bold text-gray-900 text-xs">Su</h4>
            <p className="text-[11px] text-gray-600 mt-1">Günde en az 2L su iç. Cildin nemine doğrudan etki eder.</p>
          </div>
          <div className="card !p-4 border-indigo-100 bg-indigo-50/30">
            <Moon className="w-5 h-5 text-indigo-500 mb-1" />
            <h4 className="font-bold text-gray-900 text-xs">Uyku</h4>
            <p className="text-[11px] text-gray-600 mt-1">7-8 saat uyku hedefle. Cilt gece kendini onarır.</p>
          </div>
        </div>

        {/* Wellness */}
        {wellnessItems.length > 0 && (
          <div className="mb-4">
            <div className="flex items-center gap-2 mb-2"><Heart className="w-4 h-4 text-purple-600" /><h3 className="text-sm font-bold text-gray-700">{t("dashboard.mindMovementTitle")}</h3></div>
            <div className="space-y-2">
              {wellnessItems.map((item, i) => <LifestyleCard key={`w-${i}`} item={item} />)}
            </div>
          </div>
        )}

        {/* Photo */}
        {photoUrl && (
          <div className="card mb-5">
            <div className="flex items-center gap-2 mb-3"><Calendar className="w-4 h-4" style={{ color: theme.primary }} /><h2 className="font-bold text-gray-900 text-xs">İlerleme Takibi</h2></div>
            <div className="relative rounded-2xl overflow-hidden">
              <img src={photoUrl} alt="" className="w-full h-40 object-cover" />
              <div className="absolute inset-0 bg-gradient-to-t from-black/40 to-transparent" />
              <div className="absolute bottom-2 left-2 flex items-center gap-2">
                <div
                  className="text-white px-2 py-0.5 rounded-full text-[10px] font-bold"
                  style={{ backgroundColor: theme.primary }}
                >
                  {t("dashboard.dayLabel", { n: 1 })}
                </div>
                <span className="text-white/80 text-[10px]">{new Date().toLocaleDateString(uiLocale)}</span>
              </div>
            </div>
          </div>
        )}

        <Link to="/dashboard/analyze" className="btn-secondary w-full !mt-4" style={{ borderColor: theme.primaryLight, color: theme.primary }}>
          <PlusCircle className="w-5 h-5" /> {t("dashboard.newAnalyzeCta")}
        </Link>
      </div>
    </div>
  );
}

/** flow_debug veya başlık metninden seviye (kart rengi için) */
function dailyBalanceLevel(item, flowDebug) {
  const fromDebug = flowDebug?.risk_info?.level;
  if (fromDebug) return fromDebug;
  const a = (item?.action || "").toLowerCase();
  if (a.includes("kriz")) return "crisis";
  if (a.includes("yüksek")) return "high";
  if (a.includes("orta")) return "moderate";
  return "normal";
}

function DailyBalanceCard({ item, flowDebug, theme }) {
  if (!item) return null;
  // daily balance card can render outside the main component scope; pick localized fields here too
  // (backend keeps TR source in action/detail, adds *_localized for selected language)
  // eslint-disable-next-line react-hooks/rules-of-hooks
  const { i18n, t } = useTranslation();
  const prefersLocalized =
    ((i18n.resolvedLanguage || i18n.language || "tr").toLowerCase().split("-")[0] || "tr") !== "tr";
  const action = prefersLocalized ? (item.action_localized || item.action) : item.action;
  const detail = prefersLocalized ? (item.detail_localized || item.detail) : item.detail;
  const level = dailyBalanceLevel(item, flowDebug);
  const borderBg =
    level === "crisis"
      ? "border-red-200 bg-red-50/60"
      : level === "high"
        ? "border-orange-200 bg-orange-50/50"
        : level === "moderate"
          ? "border-amber-200 bg-amber-50/45"
          : "border-teal-200 bg-teal-50/40";
  const pill =
    level === "crisis"
      ? "bg-red-100 text-red-800"
      : level === "high"
        ? "bg-orange-100 text-orange-800"
        : level === "moderate"
          ? "bg-amber-100 text-amber-900"
          : "bg-teal-100 text-teal-900";

  return (
    <div className={`card mb-5 border-2 ${borderBg} !p-4`}>
      <div className="flex items-start gap-3">
        <div
          className="w-10 h-10 rounded-xl flex items-center justify-center shrink-0"
          style={{ backgroundColor: theme.primary + "25" }}
        >
          <Activity className="w-5 h-5" style={{ color: theme.primary }} />
        </div>
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-2 gap-y-1 mb-1">
            <h3 className="text-sm font-bold text-gray-900">{t("dashboard.dailyBalanceTitle")}</h3>
            <span className={`text-[10px] font-semibold px-2 py-0.5 rounded-full ${pill}`}>
              {(() => {
                const lv = flowDebug?.risk_info?.level;
                if (prefersLocalized && lv) return t(`dashboard.riskLevels.${lv}`);
                return flowDebug?.risk_info?.label || (action || "").replace(/^Günlük denge:\s*/i, "").trim() || "—";
              })()}
            </span>
          </div>
          <p className="text-xs text-gray-700 leading-relaxed">{detail}</p>
        </div>
      </div>
    </div>
  );
}

/* ─── Sub-components ─── */
function SectionHeader({ icon, title, subtitle, color, className = "" }) {
  return (
    <div className={`flex items-center gap-2.5 mb-3 mt-6 first:mt-0 ${className}`.trim()}>
      <div className="w-8 h-8 rounded-xl flex items-center justify-center text-lg" style={{ backgroundColor: color + "15" }}>{icon}</div>
      <div>
        <h2 className="text-base font-bold text-gray-900">{title}</h2>
        <p className="text-[10px] text-gray-500">{subtitle}</p>
      </div>
    </div>
  );
}

function RoutineLine({ item, pickAction, fallbackTitle }) {
  return (
    <div className="flex items-start gap-2 py-1">
      <span className="text-base leading-none shrink-0">{item.icon || "•"}</span>
      <p className="text-sm text-gray-800 leading-snug">
        {friendlyRoutineTitle(pickAction(item), fallbackTitle)}
      </p>
    </div>
  );
}

function WeeklyRoutineItem({ item, theme, weekDays, pickAction, pickDetail }) {
  const { user } = useAuth();
  const { t } = useTranslation();
  const uid = user?.id;
  const resolved = withResolvedChoices(item);
  const [chosenId, setChosenId] = useState(() => getChosenOption(uid, resolved)?.id || null);
  const [showDetail, setShowDetail] = useState(false);
  const chosen = (resolved.choices || []).find((c) => c.id === chosenId);
  const title = friendlyRoutineTitle(chosen?.action || pickAction(item));
  const hasStructuredChoices = Array.isArray(resolved.choices) && resolved.choices.length >= 2;
  const detail = pickDetail(item);
  return (
    <div className="rounded-2xl border border-gray-100 bg-white px-3 py-3 space-y-2.5">
      <div>
        <h4 className="font-semibold text-gray-900 text-sm leading-snug">{title}</h4>
        {hasStructuredChoices ? (
          <RoutineStepChoices
            item={resolved}
            userId={uid}
            theme={theme}
            selectedId={chosenId}
            onChange={setChosenId}
          />
        ) : null}
        {detail ? (
          <>
            <button
              type="button"
              onClick={() => setShowDetail((v) => !v)}
              className="mt-1 text-[11px] font-medium text-gray-500"
            >
              {showDetail ? t("common.hide") : t("dashboard.stepHow")}
            </button>
            {showDetail ? <p className="text-xs text-gray-600 mt-1 leading-relaxed">{detail}</p> : null}
          </>
        ) : null}
      </div>
      <div className="flex items-center gap-1 flex-wrap">
        {weekDays.map((label, dayIndex) => {
          const selected = (item.displayDays || []).includes(dayIndex);
          return (
            <span
              key={dayIndex}
              className={`min-w-[2.25rem] py-1.5 rounded-lg text-[11px] font-medium text-center inline-block ${
                selected ? "text-white" : "text-gray-400 bg-gray-50"
              }`}
              style={selected ? { backgroundColor: theme.primary } : {}}
            >
              {label}
            </span>
          );
        })}
      </div>
    </div>
  );
}

function ProductStep({ item, theme, step }) {
  const [showDetail, setShowDetail] = useState(false);
  const { user } = useAuth();
  const uid = user?.id;
  const { t, i18n } = useTranslation();
  const prefersLocalized = ((i18n.resolvedLanguage || i18n.language || "tr").toLowerCase().split("-")[0] || "tr") !== "tr";
  const pickAction = (it) => (prefersLocalized ? (it?.action_localized || it?.action) : it?.action);
  const pickDetail = (it) => (prefersLocalized ? (it?.detail_localized || it?.detail) : it?.detail);
  const resolved = withResolvedChoices(item);
  const [chosenId, setChosenId] = useState(() => getChosenOption(uid, resolved)?.id || null);
  const chosen = (resolved.choices || []).find((c) => c.id === chosenId);
  const displayAction = chosen
    ? (prefersLocalized ? (chosen.action_localized || chosen.action) : chosen.action)
    : pickAction(item);
  const title = friendlyRoutineTitle(displayAction, t("dashboard.fallbackStepTitle", { defaultValue: "This step" }));
  const hasStructuredChoices = Array.isArray(resolved.choices) && resolved.choices.length >= 2;
  const isSkincare = item.category === "Bakım" || item.category === "Koruma";
  const usageRaw = item.usage != null ? String(item.usage).trim() : "";
  const so = item.step_order ?? 50;
  const usage =
    usageRaw ||
    (isSkincare
      ? so <= 15
        ? t("dashboard.defaultUsage.cleanser")
        : so <= 25
          ? t("dashboard.defaultUsage.serum")
          : so <= 35
            ? t("dashboard.defaultUsage.moisturizer")
            : so >= 40
              ? t("dashboard.defaultUsage.sunscreen")
              : t("dashboard.defaultUsage.generic")
      : "");
  const detailText = pickDetail(item);
  const hasContent = Boolean(detailText || usage);
  const showNumber = step != null && step !== undefined;
  return (
    <div className="flex items-start gap-3 rounded-2xl bg-white/90 border border-gray-100 px-3 py-2.5">
      {showNumber ? (
        <div
          className="w-7 h-7 rounded-lg flex items-center justify-center text-[11px] font-bold text-white shrink-0 mt-0.5"
          style={{ backgroundColor: theme.primary }}
        >
          {step}
        </div>
      ) : (
        <span className="text-base shrink-0 mt-0.5">{item.icon || "🧴"}</span>
      )}
      <div className="flex-1 min-w-0">
        <h4 className="font-semibold text-gray-900 text-sm leading-snug">{title}</h4>
        {hasStructuredChoices ? (
          <RoutineStepChoices
            item={resolved}
            userId={uid}
            theme={theme}
            selectedId={chosenId}
            onChange={setChosenId}
          />
        ) : null}
        <div className="mt-1 flex items-center gap-3">
          {hasContent && (
            <button
              type="button"
              onClick={() => setShowDetail((v) => !v)}
              className="text-[11px] font-medium py-1"
              style={{ color: theme.primary }}
            >
              {showDetail ? t("common.hide") : t("dashboard.stepHow")}
            </button>
          )}
          {isSkincare && (
            <Link
              to={`/dashboard/chat?q=${encodeURIComponent(t("dashboard.askRebiQuestion", { step: title }))}`}
              className="inline-flex items-center gap-1 text-[11px] font-medium text-gray-500 hover:text-gray-700 py-1"
            >
              <MessageCircle className="w-3 h-3" />
              {t("dashboard.askRebi")}
            </Link>
          )}
        </div>
        {showDetail && (
          <div className="text-xs text-gray-600 mt-1 space-y-1.5 leading-relaxed">
            {detailText ? <p>{detailText}</p> : null}
            {usage ? <p>{usage}</p> : null}
          </div>
        )}
      </div>
    </div>
  );
}

function LifestyleCard({ item }) {
  const [showDetail, setShowDetail] = useState(false);
  const { t, i18n } = useTranslation();
  const prefersLocalized = ((i18n.resolvedLanguage || i18n.language || "tr").toLowerCase().split("-")[0] || "tr") !== "tr";
  const pickAction = (it) => (prefersLocalized ? (it?.action_localized || it?.action) : it?.action);
  const pickDetail = (it) => (prefersLocalized ? (it?.detail_localized || it?.detail) : it?.detail);
  return (
    <div className="card !p-3 border-green-100 bg-green-50/20">
      <div className="flex items-start gap-3">
        <span className="text-lg shrink-0">{item.icon || "🌿"}</span>
        <div className="flex-1 min-w-0">
          <h4 className="font-bold text-gray-900 text-xs">{pickAction(item)}</h4>
          {pickDetail(item) && (
            <>
              <button
                type="button"
                onClick={() => setShowDetail((v) => !v)}
                className="mt-1 text-[11px] font-medium rounded-lg px-2 py-0.5 border border-green-200 text-green-700"
              >
                {showDetail ? t("common.hide") : t("dashboard.lifestyleThisItem")}
              </button>
              {showDetail && (
                <p className="text-[11px] text-gray-500 mt-1.5 leading-relaxed">{pickDetail(item)}</p>
              )}
            </>
          )}
        </div>
      </div>
    </div>
  );
}
