import { useState, useLayoutEffect, useEffect, useRef, useCallback } from "react";
import { useTranslation } from "react-i18next";
import { Leaf, Sparkles } from "lucide-react";

/** v3: uzun süre + bilimsel kaynak vurgulu metinler */
const DONE_APP = "rebi-splash-app-v3";
const TS_APP = "rebi-splash-app-ts";
const DONE_CHAT = "rebi-splash-chat-v3";

/** Uzun “şov” — alt başlık ve ipuçlarının rahat okunması için */
const DURATION_APP_MS = 36000;
const DURATION_CHAT_MS = 24000;
const TIP_INTERVAL_APP_MS = 7000;
const TIP_INTERVAL_CHAT_MS = 6200;
/** App şovu bittikten sonra bu süre içinde chat şovu gösterme */
const CHAT_DEBOUNCE_AFTER_APP_MS = 55000;

function readTips(t, key) {
  const raw = t(key, { returnObjects: true });
  return Array.isArray(raw) ? raw.filter((x) => typeof x === "string" && x.trim()) : [];
}

/**
 * scope=app: ilk site açılışı (oturum başına bir kez) — sinematik, büyük tip
 * scope=chat: Rebi sohbet — app şovundan hemen sonra değilse
 */
export default function RebiIntroSplash({ scope = "app", accentColor = "#0d9488", primaryColor = "#0f766e" }) {
  const { t } = useTranslation();
  const [show, setShow] = useState(false);
  const [tipIndex, setTipIndex] = useState(0);
  const [progress, setProgress] = useState(0);
  const timerRef = useRef(null);
  const progressRef = useRef(null);
  const startedAtRef = useRef(0);
  const tips = readTips(t, scope === "app" ? "intro.appTips" : "intro.chatTips");
  const title = scope === "app" ? t("intro.appTitle") : t("intro.chatTitle");
  const subtitle = scope === "app" ? t("intro.appSubtitle") : t("intro.chatSubtitle");
  const totalMs = scope === "app" ? DURATION_APP_MS : DURATION_CHAT_MS;
  const tipMs = scope === "app" ? TIP_INTERVAL_APP_MS : TIP_INTERVAL_CHAT_MS;

  const dismiss = useCallback(() => {
    if (timerRef.current) {
      clearTimeout(timerRef.current);
      timerRef.current = null;
    }
    if (progressRef.current) {
      clearInterval(progressRef.current);
      progressRef.current = null;
    }
    if (scope === "app") {
      sessionStorage.setItem(DONE_APP, "1");
      sessionStorage.setItem(TS_APP, String(Date.now()));
    } else {
      sessionStorage.setItem(DONE_CHAT, "1");
    }
    setShow(false);
    setProgress(100);
  }, [scope]);

  useLayoutEffect(() => {
    const doneKey = scope === "app" ? DONE_APP : DONE_CHAT;
    if (sessionStorage.getItem(doneKey)) {
      return;
    }
    if (scope === "chat") {
      const ts = sessionStorage.getItem(TS_APP);
      if (ts && Date.now() - Number(ts) < CHAT_DEBOUNCE_AFTER_APP_MS) {
        return;
      }
    }
    const raf = requestAnimationFrame(() => {
      setShow(true);
      startedAtRef.current = Date.now();
      setProgress(0);
      timerRef.current = window.setTimeout(() => dismiss(), totalMs);
      progressRef.current = window.setInterval(() => {
        const elapsed = Date.now() - startedAtRef.current;
        setProgress(Math.min(100, (elapsed / totalMs) * 100));
      }, 48);
    });
    return () => {
      cancelAnimationFrame(raf);
      if (timerRef.current) {
        clearTimeout(timerRef.current);
        timerRef.current = null;
      }
      if (progressRef.current) {
        clearInterval(progressRef.current);
        progressRef.current = null;
      }
    };
  }, [scope, dismiss, totalMs]);

  useEffect(() => {
    if (!show || tips.length === 0) return;
    const id = window.setInterval(() => {
      setTipIndex((i) => (i + 1) % tips.length);
    }, tipMs);
    return () => clearInterval(id);
  }, [show, tips.length, tipMs]);

  if (!show) return null;

  const tip = tips.length ? tips[tipIndex % tips.length] : t("intro.fallbackTip");

  const wrap =
    scope === "app"
      ? "fixed inset-0 z-[200] flex flex-col items-center justify-center px-5 sm:px-10 py-6 sm:py-12 overflow-hidden"
      : "absolute inset-0 z-[35] flex flex-col items-center justify-center px-4 sm:px-8 py-6 overflow-hidden";

  const maxW = scope === "app" ? "max-w-4xl lg:max-w-5xl" : "max-w-3xl lg:max-w-4xl";

  return (
    <div
      className={`${wrap} bg-gradient-to-br from-teal-950 via-teal-900 to-slate-950 text-white`}
      role="dialog"
      aria-modal="true"
      aria-labelledby="rebi-intro-title"
    >
      {/* Hareketli ışık küreleri */}
      <div className="absolute inset-0 pointer-events-none overflow-hidden" aria-hidden="true">
        <div
          className="absolute -left-1/4 -top-1/4 w-[85vw] h-[85vw] max-w-[720px] max-h-[720px] rounded-full opacity-40 blur-[100px] rebi-orb-a"
          style={{ background: `radial-gradient(circle, ${accentColor} 0%, transparent 70%)` }}
        />
        <div
          className="absolute -right-1/4 bottom-0 w-[80vw] h-[80vw] max-w-[640px] max-h-[640px] rounded-full opacity-35 blur-[90px] rebi-orb-b"
          style={{ background: `radial-gradient(circle, ${primaryColor} 0%, transparent 68%)` }}
        />
        <div className="absolute inset-0 bg-[url('data:image/svg+xml,%3Csvg width=\'60\' height=\'60\' viewBox=\'0 0 60 60\' xmlns=\'http://www.w3.org/2000/svg\'%3E%3Cg fill=\'none\' fill-rule=\'evenodd\'%3E%3Cg fill=\'%23ffffff\' fill-opacity=\'0.06\'%3E%3Cpath d=\'M36 34v-4h-2v4h-4v2h4v4h2v-4h4v-2h-4zm0-30V0h-2v4h-4v2h4v4h2V6h4V4h-4zM6 34v-4H4v4H0v2h4v4h2v-4h4v-2H6zM6 4V0H4v4H0v2h4v4h2V6h4V4H6z\'/%3E%3C/g%3E%3C/g%3E%3C/svg%3E')] opacity-30" />
      </div>

      {/* Alt ilerleme çubuğu */}
      <div className="absolute bottom-0 left-0 right-0 h-1.5 bg-white/10">
        <div
          className="h-full bg-gradient-to-r from-teal-300 via-emerald-200 to-cyan-300 transition-[width] duration-100 ease-linear shadow-[0_0_20px_rgba(94,234,212,0.5)]"
          style={{ width: `${progress}%` }}
        />
      </div>

      <div
        className={`relative w-full ${maxW} mx-auto text-center flex flex-col items-center justify-center min-h-[55vh] sm:min-h-0 rebi-intro-hero`}
      >
        <div
          className="mb-8 sm:mb-10 w-28 h-28 sm:w-36 sm:h-36 rounded-[2rem] sm:rounded-[2.25rem] flex items-center justify-center shadow-2xl rebi-logo-breathe border border-white/20"
          style={{
            background: `linear-gradient(145deg, ${accentColor}, ${primaryColor})`,
            boxShadow: `0 25px 80px -12px ${primaryColor}66, 0 0 0 1px rgba(255,255,255,0.12) inset`,
          }}
        >
          <Leaf className="w-14 h-14 sm:w-[4.5rem] sm:h-[4.5rem] text-white drop-shadow-md" strokeWidth={1.75} />
        </div>

        <div className="inline-flex items-center gap-2 text-sm sm:text-base font-bold uppercase tracking-[0.25em] text-teal-200/90 mb-4">
          <Sparkles className="w-5 h-5 sm:w-6 sm:h-6 text-amber-200 animate-pulse" />
          REBI
        </div>

        <h2
          id="rebi-intro-title"
          className="text-4xl sm:text-5xl md:text-6xl lg:text-7xl font-black leading-[1.05] tracking-tight text-white drop-shadow-lg px-2"
        >
          {title}
        </h2>
        <p className="text-lg sm:text-xl md:text-2xl text-teal-100/90 mt-5 sm:mt-6 max-w-2xl mx-auto leading-relaxed font-medium px-2">
          {subtitle}
        </p>

        <div className="mt-10 sm:mt-14 w-full flex items-center justify-center px-1 sm:px-4">
          <div
            key={tipIndex}
            className="w-full rounded-3xl border-2 border-white/20 bg-white/10 backdrop-blur-xl px-6 py-8 sm:px-10 sm:py-10 md:px-12 md:py-12 text-left shadow-2xl shadow-black/40 rebi-intro-card"
          >
            <p className="text-xl sm:text-2xl md:text-3xl lg:text-4xl leading-snug sm:leading-tight text-white font-semibold tracking-tight">
              {tip}
            </p>
          </div>
        </div>

        {tips.length > 1 && (
          <div className="flex justify-center gap-2 sm:gap-2.5 mt-8">
            {tips.map((_, i) => (
              <span
                key={i}
                className={`h-2 sm:h-2.5 rounded-full transition-all duration-500 ease-out ${
                  i === tipIndex % tips.length ? "w-10 sm:w-14 bg-white shadow-lg shadow-white/30" : "w-2 sm:w-2.5 bg-white/25"
                }`}
              />
            ))}
          </div>
        )}

        <button
          type="button"
          onClick={dismiss}
          className="mt-10 sm:mt-12 text-base sm:text-lg font-bold text-teal-100 hover:text-white px-8 py-3.5 rounded-full border-2 border-white/30 hover:border-white/60 bg-white/5 hover:bg-white/10 transition-all duration-300"
        >
          {t("intro.skip")}
        </button>
      </div>

      <style>{`
        @keyframes rebiIntroCard {
          from { opacity: 0; transform: translateY(28px) scale(0.97); }
          to { opacity: 1; transform: translateY(0) scale(1); }
        }
        @keyframes rebiIntroHero {
          from { opacity: 0; transform: translateY(24px); }
          to { opacity: 1; transform: translateY(0); }
        }
        @keyframes rebiLogoBreathe {
          0%, 100% { transform: scale(1); }
          50% { transform: scale(1.04); }
        }
        @keyframes rebiOrbA {
          0%, 100% { transform: translate(0, 0) scale(1); }
          50% { transform: translate(8%, 6%) scale(1.08); }
        }
        @keyframes rebiOrbB {
          0%, 100% { transform: translate(0, 0) scale(1); }
          50% { transform: translate(-6%, -4%) scale(1.06); }
        }
        .rebi-intro-card {
          animation: rebiIntroCard 1.1s cubic-bezier(0.22, 1, 0.36, 1) both;
        }
        .rebi-intro-hero {
          animation: rebiIntroHero 1.15s cubic-bezier(0.22, 1, 0.36, 1) both;
        }
        .rebi-logo-breathe {
          animation: rebiLogoBreathe 6.5s ease-in-out infinite;
        }
        .rebi-orb-a {
          animation: rebiOrbA 38s ease-in-out infinite;
        }
        .rebi-orb-b {
          animation: rebiOrbB 44s ease-in-out infinite;
        }
      `}</style>
    </div>
  );
}
