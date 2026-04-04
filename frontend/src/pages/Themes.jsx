import { useTheme } from "../context/ThemeContext";
import { Check, Sparkles } from "lucide-react";

const patternPreviews = {
  "": null,
  hearts: (
    <div className="absolute inset-0 overflow-hidden opacity-20 pointer-events-none">
      {[...Array(8)].map((_, i) => (
        <span key={i} className="absolute text-pink-400" style={{
          fontSize: `${12 + Math.random() * 16}px`,
          left: `${Math.random() * 90}%`, top: `${Math.random() * 90}%`,
          transform: `rotate(${Math.random() * 30 - 15}deg)`,
        }}>&#10084;</span>
      ))}
    </div>
  ),
  leaves: (
    <div className="absolute inset-0 overflow-hidden opacity-20 pointer-events-none">
      {[...Array(6)].map((_, i) => (
        <span key={i} className="absolute text-green-500" style={{
          fontSize: `${12 + Math.random() * 14}px`,
          left: `${Math.random() * 90}%`, top: `${Math.random() * 90}%`,
          transform: `rotate(${Math.random() * 60 - 30}deg)`,
        }}>{["🌿", "🍃", "🌱"][i % 3]}</span>
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
      {[...Array(5)].map((_, i) => (
        <span key={i} className="absolute" style={{
          fontSize: `${10 + Math.random() * 12}px`,
          left: `${Math.random() * 85}%`, top: `${Math.random() * 85}%`,
          transform: `rotate(${Math.random() * 20 - 10}deg)`,
        }}>{["🐱", "🐾", "😺", "🐈"][i % 4]}</span>
      ))}
    </div>
  ),
};

export default function Themes() {
  const { theme, themeId, setThemeId, themes } = useTheme();

  return (
    <div className={`min-h-screen ${theme.bg} pb-24`}>
      <div className="max-w-lg mx-auto px-4 py-8">
        <div className="mb-6">
          <h2 className="text-2xl font-bold text-gray-900 flex items-center gap-2">
            <Sparkles className="w-6 h-6" style={{ color: theme.primary }} />
            Tema Seç
          </h2>
          <p className="text-gray-500 text-sm mt-1">Uygulamanın görünümünü kişiselleştir.</p>
        </div>

        <div className="grid grid-cols-2 gap-3">
          {Object.values(themes).map((t) => {
            const isActive = themeId === t.id;
            return (
              <button
                key={t.id}
                onClick={() => setThemeId(t.id)}
                className={`relative rounded-2xl border-2 overflow-hidden transition-all ${
                  isActive ? "ring-2 ring-offset-2 scale-[1.02]" : "hover:scale-[1.01]"
                }`}
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
                    <div className="h-2 w-12 rounded-full" style={{ backgroundColor: t.primary, opacity: 0.7 }} />
                    <div className="h-1.5 w-16 rounded-full bg-gray-300/50" />
                    <div className="flex gap-1 mt-2">
                      <div className="h-5 w-5 rounded-lg" style={{ backgroundColor: t.primary, opacity: 0.5 }} />
                      <div className="h-5 flex-1 rounded-lg bg-white/60" />
                    </div>
                    <div className="h-6 rounded-lg" style={{ backgroundColor: t.primary, opacity: 0.3 }} />
                  </div>
                  {isActive && (
                    <div className="absolute top-2 right-2 w-6 h-6 rounded-full flex items-center justify-center text-white"
                      style={{ backgroundColor: t.primary }}>
                      <Check className="w-4 h-4" />
                    </div>
                  )}
                </div>
                {/* Label */}
                <div className="px-3 py-2.5 bg-white">
                  <p className="text-xs font-semibold text-gray-900">{t.emoji} {t.label}</p>
                </div>
              </button>
            );
          })}
        </div>

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
