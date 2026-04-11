import { useState, useLayoutEffect, useEffect, useRef, useCallback } from "react";
import { useTranslation } from "react-i18next";
import { Leaf, Sparkles } from "lucide-react";

const DONE_APP = "rebi-splash-app-v1";
const TS_APP = "rebi-splash-app-ts";
const DONE_CHAT = "rebi-splash-chat-v1";

function readTips(t, key) {
  const raw = t(key, { returnObjects: true });
  return Array.isArray(raw) ? raw.filter((x) => typeof x === "string" && x.trim()) : [];
}

/**
 * scope=app: ilk site açılışı (oturum başına bir kez)
 * scope=chat: Rebi sohbet ekranına giriş (app splash’ten hemen sonra değilse)
 */
export default function RebiIntroSplash({ scope = "app", accentColor = "#0d9488", primaryColor = "#0f766e" }) {
  const { t } = useTranslation();
  const [show, setShow] = useState(false);
  const [tipIndex, setTipIndex] = useState(0);
  const timerRef = useRef(null);
  const tips = readTips(t, scope === "app" ? "intro.appTips" : "intro.chatTips");
  const title = scope === "app" ? t("intro.appTitle") : t("intro.chatTitle");
  const subtitle = scope === "app" ? t("intro.appSubtitle") : t("intro.chatSubtitle");

  const dismiss = useCallback(() => {
    if (timerRef.current) {
      clearTimeout(timerRef.current);
      timerRef.current = null;
    }
    if (scope === "app") {
      sessionStorage.setItem(DONE_APP, "1");
      sessionStorage.setItem(TS_APP, String(Date.now()));
    } else {
      sessionStorage.setItem(DONE_CHAT, "1");
    }
    setShow(false);
  }, [scope]);

  useLayoutEffect(() => {
    const doneKey = scope === "app" ? DONE_APP : DONE_CHAT;
    if (sessionStorage.getItem(doneKey)) {
      return;
    }
    if (scope === "chat") {
      const ts = sessionStorage.getItem(TS_APP);
      if (ts && Date.now() - Number(ts) < 11000) {
        return;
      }
    }
    const ms = scope === "app" ? 3200 : 2200;
    const raf = requestAnimationFrame(() => {
      setShow(true);
      timerRef.current = window.setTimeout(() => dismiss(), ms);
    });
    return () => {
      cancelAnimationFrame(raf);
      if (timerRef.current) {
        clearTimeout(timerRef.current);
        timerRef.current = null;
      }
    };
  }, [scope, dismiss]);

  useEffect(() => {
    if (!show || tips.length === 0) return;
    const id = window.setInterval(() => {
      setTipIndex((i) => (i + 1) % tips.length);
    }, 720);
    return () => clearInterval(id);
  }, [show, tips.length]);

  if (!show) return null;

  const tip = tips.length ? tips[tipIndex % tips.length] : t("intro.fallbackTip");

  const wrap =
    scope === "app"
      ? "fixed inset-0 z-[200] flex flex-col items-center justify-center px-6 py-10"
      : "absolute inset-0 z-[35] flex flex-col items-center justify-center px-5 py-8";

  return (
    <div
      className={`${wrap} bg-gradient-to-b from-teal-50/98 via-white/95 to-sky-50/90 backdrop-blur-md`}
      role="dialog"
      aria-modal="true"
      aria-labelledby="rebi-intro-title"
    >
      <div
        className="absolute inset-0 pointer-events-none opacity-[0.35]"
        style={{
          backgroundImage:
            "radial-gradient(circle at 20% 20%, rgba(45,212,191,0.35) 0%, transparent 45%), radial-gradient(circle at 80% 75%, rgba(125,211,252,0.3) 0%, transparent 40%)",
        }}
      />

      <div className="relative w-full max-w-md text-center">
        <div
          className="mx-auto mb-5 w-16 h-16 rounded-2xl flex items-center justify-center shadow-xl shadow-teal-500/25 animate-pulse"
          style={{ background: `linear-gradient(135deg, ${accentColor}, ${primaryColor})` }}
        >
          <Leaf className="w-8 h-8 text-white" />
        </div>

        <div className="inline-flex items-center gap-1.5 text-[11px] font-semibold uppercase tracking-wider text-teal-700/80 mb-2">
          <Sparkles className="w-3.5 h-3.5" />
          Rebi
        </div>
        <h2 id="rebi-intro-title" className="text-xl font-bold text-gray-900 leading-snug">
          {title}
        </h2>
        <p className="text-sm text-gray-600 mt-2 leading-relaxed">{subtitle}</p>

        <div className="mt-8 min-h-[5.5rem] flex items-center justify-center">
          <div
            key={tipIndex}
            className="w-full rounded-2xl border border-teal-100/80 bg-white/90 px-4 py-3.5 text-left shadow-md shadow-teal-900/5 animate-[rebiIntroCard_0.55s_ease-out_both]"
          >
            <p className="text-sm text-gray-800 leading-relaxed">{tip}</p>
          </div>
        </div>

        {tips.length > 1 && (
          <div className="flex justify-center gap-1.5 mt-4">
            {tips.map((_, i) => (
              <span
                key={i}
                className={`h-1.5 rounded-full transition-all duration-300 ${
                  i === tipIndex % tips.length ? "w-6 bg-teal-600" : "w-1.5 bg-teal-200"
                }`}
              />
            ))}
          </div>
        )}

        <button
          type="button"
          onClick={dismiss}
          className="mt-8 text-sm font-semibold text-teal-700 hover:text-teal-900 underline-offset-4 hover:underline"
        >
          {t("intro.skip")}
        </button>
      </div>

      <style>{`
        @keyframes rebiIntroCard {
          from { opacity: 0; transform: translateY(10px); }
          to { opacity: 1; transform: translateY(0); }
        }
      `}</style>
    </div>
  );
}
