import { useNavigate, Link } from "react-router-dom";
import { useTheme } from "../context/ThemeContext";
import { useAuth } from "../context/AuthContext";
import { Check, Sparkles, Lock } from "lucide-react";
import ThemePatternOverlay from "../components/ThemePatternOverlay";
import { useTranslation } from "react-i18next";

const patternPreviews = {
  "": null,
  hearts: (
    <div className="absolute inset-0 overflow-hidden opacity-20 pointer-events-none">
      {[
        { left: "8%", top: "14%", s: 14, r: -8 },
        { left: "86%", top: "20%", s: 12, r: 12 },
        { left: "24%", top: "44%", s: 11, r: 5 },
        { left: "70%", top: "40%", s: 13, r: -12 },
        { left: "46%", top: "10%", s: 10, r: 0 },
        { left: "14%", top: "78%", s: 12, r: 16 },
        { left: "84%", top: "74%", s: 11, r: -6 },
        { left: "50%", top: "86%", s: 10, r: 8 },
      ].map((p, i) => (
        <span
          key={i}
          className="absolute text-pink-400"
          style={{
            fontSize: p.s,
            left: p.left,
            top: p.top,
            transform: `rotate(${p.r}deg)`,
          }}
        >
          &#10084;
        </span>
      ))}
    </div>
  ),
  leaves: (
    <div className="absolute inset-0 overflow-hidden opacity-20 pointer-events-none">
      {[
        { left: "12%", top: "18%", s: 13, r: -18, c: "🌿" },
        { left: "80%", top: "24%", s: 12, r: 14, c: "🍃" },
        { left: "34%", top: "56%", s: 14, r: 8, c: "🌱" },
        { left: "66%", top: "48%", s: 12, r: -14, c: "🌿" },
        { left: "8%", top: "76%", s: 11, r: 22, c: "🍃" },
        { left: "90%", top: "68%", s: 13, r: -20, c: "🌱" },
      ].map((p, i) => (
        <span
          key={i}
          className="absolute text-green-500"
          style={{
            fontSize: p.s,
            left: p.left,
            top: p.top,
            transform: `rotate(${p.r}deg)`,
          }}
        >
          {p.c}
        </span>
      ))}
    </div>
  ),
  landscape: (
    <div className="absolute inset-0 overflow-hidden pointer-events-none">
      <div className="absolute bottom-0 left-0 right-0 h-1/3 bg-gradient-to-t from-violet-200/30 to-transparent" />
      <span className="absolute bottom-1 left-2 text-[10px] opacity-30">🏔️</span>
      <span className="absolute bottom-1 right-3 text-[10px] opacity-30">🌸</span>
      <span className="absolute top-1 right-2 text-[8px] opacity-20">☁️</span>
    </div>
  ),
  cats: (
    <div className="absolute inset-0 overflow-hidden opacity-20 pointer-events-none">
      {[
        { left: "12%", top: "20%", s: 12, r: -5, c: "🐱" },
        { left: "78%", top: "18%", s: 11, r: 8, c: "🐾" },
        { left: "28%", top: "68%", s: 13, r: 10, c: "😺" },
        { left: "72%", top: "62%", s: 12, r: -8, c: "🐈" },
        { left: "48%", top: "42%", s: 11, r: 0, c: "🐱" },
      ].map((p, i) => (
        <span
          key={i}
          className="absolute"
          style={{
            fontSize: p.s,
            left: p.left,
            top: p.top,
            transform: `rotate(${p.r}deg)`,
          }}
        >
          {p.c}
        </span>
      ))}
    </div>
  ),
  bears: (
    <div className="absolute inset-0 overflow-hidden opacity-20 pointer-events-none">
      {[
        { left: "10%", top: "22%", s: 16, r: -6, c: "🧸" },
        { left: "82%", top: "16%", s: 15, r: 8, c: "🧸" },
        { left: "44%", top: "38%", s: 14, r: 0, c: "🐻" },
        { left: "20%", top: "72%", s: 14, r: 10, c: "🧸" },
        { left: "76%", top: "70%", s: 13, r: -10, c: "🧸" },
      ].map((p, i) => (
        <span
          key={i}
          className="absolute"
          style={{
            fontSize: p.s,
            left: p.left,
            top: p.top,
            transform: `rotate(${p.r}deg)`,
          }}
        >
          {p.c}
        </span>
      ))}
    </div>
  ),
  sunburst: (
    <div
      className="absolute inset-0 pointer-events-none opacity-30"
      style={{
        background: "conic-gradient(from 180deg at 50% 70%, #f0abfc 0deg, transparent 40deg, #fdba74 120deg, transparent 200deg, #e879f9 280deg, transparent 360deg)",
      }}
    />
  ),
  waves: (
    <div className="absolute inset-0 overflow-hidden opacity-25 pointer-events-none">
      <div className="absolute -bottom-2 left-0 right-0 h-16 bg-[repeating-linear-gradient(90deg,transparent,transparent_8px,rgba(14,165,233,0.15)_8px,rgba(14,165,233,0.15)_16px)] rounded-t-full scale-x-150" />
      <div className="absolute bottom-2 left-0 right-0 h-10 bg-[repeating-linear-gradient(90deg,transparent,transparent_6px,rgba(6,182,212,0.2)_6px,rgba(6,182,212,0.2)_14px)] rounded-t-full scale-x-125 opacity-80" />
    </div>
  ),
  stars: (
    <div className="absolute inset-0 overflow-hidden opacity-25 pointer-events-none">
      {[...Array(14)].map((_, i) => (
        <span
          key={i}
          className="absolute text-indigo-400"
          style={{
            fontSize: `${6 + (i % 4) * 3}px`,
            left: `${(i * 17) % 92}%`,
            top: `${(i * 23) % 88}%`,
            opacity: 0.4 + (i % 3) * 0.2,
          }}
        >
          ✦
        </span>
      ))}
    </div>
  ),
};

function userHasRebiPlus(user) {
  if (!user?.user_metadata) return false;
  const m = user.user_metadata;
  if (m.rebi_plus === true) return true;
  return ["plus", "pro", "premium"].includes(String(m.subscription_tier || "").toLowerCase());
}

export default function Themes() {
  const { theme, themeId, setThemeId, themes } = useTheme();
  const { user } = useAuth();
  const navigate = useNavigate();
  const { t } = useTranslation();
  const plus = userHasRebiPlus(user);

  const pickTheme = (t) => {
    if (t.premium && !plus) {
      navigate("/dashboard/subscribe");
      return;
    }
    setThemeId(t.id);
  };

  const previewRadius = (t) =>
    t.shape === "angular" ? "rounded-lg" : "rounded-2xl";

  return (
    <div className={`min-h-screen ${theme.bg} pb-24 relative`}>
      <ThemePatternOverlay pattern={theme.pattern} />
      <div className="max-w-lg mx-auto px-4 py-8 relative z-[1]">
        <div className="mb-6">
          <h2 className="text-2xl font-bold text-gray-900 flex items-center gap-2">
            <Sparkles className="w-6 h-6" style={{ color: theme.primary }} />
            {t("themes.title")}
          </h2>
          <p className="text-gray-500 text-sm mt-1">{t("themes.subtitle")}</p>
        </div>

        <div className="grid grid-cols-2 gap-3">
          {Object.values(themes).map((t) => {
            const isActive = themeId === t.id;
            const locked = t.premium && !plus;
            return (
              <button
                key={t.id}
                type="button"
                onClick={() => pickTheme(t)}
                className={`relative rounded-2xl border-2 overflow-hidden transition-all text-left ${
                  isActive ? "ring-2 ring-offset-2 scale-[1.02]" : "hover:scale-[1.01]"
                } ${locked ? "opacity-95" : ""}`}
                style={{
                  borderColor: isActive ? t.primary : "#e5e7eb",
                  ringColor: t.primary,
                }}
              >
                {/* Preview */}
                <div className="relative h-28 p-3" style={{ background: t.primaryLight }}>
                  {patternPreviews[t.pattern]}
                  {/* Mini UI preview */}
                  <div className="relative z-10 space-y-1.5">
                    <div className={`h-2 w-12 ${previewRadius(t)}`} style={{ backgroundColor: t.primary, opacity: 0.7 }} />
                    <div className={`h-1.5 w-16 ${previewRadius(t)} bg-gray-300/50`} />
                    <div className="flex gap-1 mt-2">
                      <div className={`h-5 w-5 ${previewRadius(t)}`} style={{ backgroundColor: t.primary, opacity: 0.5 }} />
                      <div className={`h-5 flex-1 ${previewRadius(t)} bg-white/60`} />
                    </div>
                    <div className={`h-6 ${previewRadius(t)}`} style={{ backgroundColor: t.primary, opacity: 0.3 }} />
                  </div>
                  {locked && (
                    <div className="absolute inset-0 z-20 bg-white/35 flex items-center justify-center backdrop-blur-[1px]">
                      <span className="flex items-center gap-1 text-[10px] font-bold text-gray-800 bg-white/90 px-2 py-1 rounded-full shadow">
                        <Lock className="w-3 h-3" /> Plus
                      </span>
                    </div>
                  )}
                  {isActive && !locked && (
                    <div className="absolute top-2 right-2 w-6 h-6 rounded-full flex items-center justify-center text-white"
                      style={{ backgroundColor: t.primary }}>
                      <Check className="w-4 h-4" />
                    </div>
                  )}
                </div>
                {/* Label */}
                <div className="px-3 py-2.5 bg-white flex items-center justify-between gap-1">
                  <p className="text-xs font-semibold text-gray-900">{t.emoji} {t.label}</p>
                  {t.premium && (
                    <span className="text-[9px] font-bold uppercase tracking-wide text-amber-700 shrink-0">Plus</span>
                  )}
                </div>
              </button>
            );
          })}
        </div>

        <p className="text-center text-xs text-gray-500 mt-4">
          Rebi Plus için{" "}
          <Link to="/dashboard/subscribe" className="font-semibold underline-offset-2 hover:underline" style={{ color: theme.primary }}>
            abonelik sayfası
          </Link>
          .
        </p>

        {/* Live Preview */}
        <div className="mt-8">
          <h3 className="text-sm font-bold text-gray-700 mb-3">Canlı Önizleme</h3>
          <div className="card space-y-3 relative overflow-hidden" style={{ borderColor: theme.primaryLight }}>
            {patternPreviews[theme.pattern] && (
              <div className="absolute inset-0 pointer-events-none" style={{ opacity: 0.15 }}>
                {patternPreviews[theme.pattern]}
              </div>
            )}
            <div className="relative z-10">
              <div className="flex items-center gap-3 mb-3">
                <div className="w-10 h-10 rounded-2xl flex items-center justify-center text-white"
                  style={{ backgroundColor: theme.primary }}>
                  <Sparkles className="w-5 h-5" />
                </div>
                <div>
                  <p className="font-bold text-sm text-gray-900">Sabah Rutini</p>
                  <p className="text-[11px] text-gray-500">3 adım</p>
                </div>
              </div>
              <div className="space-y-2">
                <div className="flex items-center gap-2 p-2 rounded-xl" style={{ backgroundColor: theme.primaryLight }}>
                  <span>🧴</span>
                  <span className="text-xs font-medium" style={{ color: theme.primaryDark }}>Temizleme</span>
                </div>
                <div className="flex items-center gap-2 p-2 rounded-xl" style={{ backgroundColor: theme.primaryLight }}>
                  <span>💧</span>
                  <span className="text-xs font-medium" style={{ color: theme.primaryDark }}>Nemlendirme</span>
                </div>
              </div>
              <button className="w-full mt-3 py-2.5 rounded-xl text-white text-sm font-medium"
                style={{ backgroundColor: theme.primary }}>
                Rutini Başlat
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
