/**
 * FaceConcernMap v4 - Minimal, gender-neutral, medical-grade face diagram.
 * No hair, no gender features. Clean wireframe with interactive zone buttons.
 */
import { useState } from "react";

const CONCERN_DEFS = {
  acne: { label: "Sivilce", color: "#ef4444", bg: "bg-red-500", ring: "ring-red-200", light: "bg-red-50", text: "text-red-700", dotClass: "bg-red-400" },
  aging: { label: "Kırışıklık", color: "#8b5cf6", bg: "bg-violet-500", ring: "ring-violet-200", light: "bg-violet-50", text: "text-violet-700", dotClass: "bg-violet-400" },
  dryness: { label: "Kuruluk", color: "#f59e0b", bg: "bg-amber-500", ring: "ring-amber-200", light: "bg-amber-50", text: "text-amber-700", dotClass: "bg-amber-400" },
  pigmentation: { label: "Leke", color: "#92400e", bg: "bg-amber-800", ring: "ring-amber-300", light: "bg-amber-50", text: "text-amber-900", dotClass: "bg-amber-700" },
  sensitivity: { label: "Hassasiyet", color: "#ec4899", bg: "bg-pink-500", ring: "ring-pink-200", light: "bg-pink-50", text: "text-pink-700", dotClass: "bg-pink-400" },
};

const ZONES = [
  { id: "forehead", label: "Alın", x: 50, y: 20, concerns: ["acne", "aging", "dryness", "pigmentation", "sensitivity"] },
  { id: "temples", label: "Şakak", x: 15, y: 32, concerns: ["acne", "aging", "sensitivity"] },
  { id: "undereye", label: "Göz Altı", x: 35, y: 42, concerns: ["aging", "pigmentation", "sensitivity", "dryness"] },
  { id: "nose", label: "Burun", x: 50, y: 50, concerns: ["acne", "dryness", "sensitivity"] },
  { id: "left_cheek", label: "Sol Yanak", x: 22, y: 57, concerns: ["acne", "aging", "dryness", "pigmentation", "sensitivity"] },
  { id: "right_cheek", label: "Sağ Yanak", x: 78, y: 57, concerns: ["acne", "aging", "dryness", "pigmentation", "sensitivity"] },
  { id: "lips", label: "Dudak", x: 50, y: 68, concerns: ["dryness", "aging", "sensitivity"] },
  { id: "chin", label: "Çene", x: 50, y: 82, concerns: ["acne", "aging", "dryness", "sensitivity"] },
];

export default function FaceConcernMap({ zoneMap, onChange }) {
  const [activeZone, setActiveZone] = useState(null);

  const toggleConcern = (zoneId, concernId) => {
    const current = zoneMap[zoneId] || [];
    const updated = current.includes(concernId)
      ? current.filter((c) => c !== concernId)
      : [...current, concernId];
    onChange({ ...zoneMap, [zoneId]: updated });
  };

  const totalSelections = Object.values(zoneMap).flat().length;
  const activeZoneData = ZONES.find((z) => z.id === activeZone);

  return (
    <div className="space-y-4">
      <div className="flex justify-center">
        <div className="relative" style={{ width: 240, height: 300 }}>
          {/* Clean minimal face outline - no gender, no hair */}
          <svg width="240" height="300" viewBox="0 0 240 300" className="absolute inset-0 pointer-events-none">
            <defs>
              <linearGradient id="faceFill4" x1="120" y1="20" x2="120" y2="280" gradientUnits="userSpaceOnUse">
                <stop offset="0%" stopColor="#f8f4f0" />
                <stop offset="100%" stopColor="#f0ebe5" />
              </linearGradient>
            </defs>

            {/* Face oval */}
            <ellipse cx="120" cy="145" rx="88" ry="115"
              fill="url(#faceFill4)" stroke="#e0d5ca" strokeWidth="1.5" />

            {/* Subtle zone divider lines */}
            <line x1="32" y1="120" x2="208" y2="120" stroke="#e8ddd2" strokeWidth="0.5" strokeDasharray="4 4" opacity="0.5" />
            <line x1="52" y1="180" x2="188" y2="180" stroke="#e8ddd2" strokeWidth="0.5" strokeDasharray="4 4" opacity="0.5" />
            <line x1="120" y1="35" x2="120" y2="255" stroke="#e8ddd2" strokeWidth="0.5" strokeDasharray="4 4" opacity="0.3" />

            {/* Eyes - simple almond shapes */}
            <ellipse cx="82" cy="120" rx="16" ry="7" fill="none" stroke="#c8bdb0" strokeWidth="1" />
            <ellipse cx="158" cy="120" rx="16" ry="7" fill="none" stroke="#c8bdb0" strokeWidth="1" />
            <circle cx="82" cy="120" r="3.5" fill="#c8bdb0" />
            <circle cx="158" cy="120" r="3.5" fill="#c8bdb0" />

            {/* Nose - simple line */}
            <path d="M 120 130 L 120 152 M 112 155 Q 120 160 128 155" stroke="#d0c4b5" strokeWidth="1" fill="none" strokeLinecap="round" />

            {/* Mouth - simple curve */}
            <path d="M 102 192 Q 120 200 138 192" stroke="#d0c4b5" strokeWidth="1" fill="none" strokeLinecap="round" />

            {/* Zone labels */}
            {ZONES.map((z) => {
              const cs = zoneMap[z.id] || [];
              if (cs.length === 0 && activeZone !== z.id) return null;
              return null;
            })}
          </svg>

          {/* Interactive zone buttons */}
          {ZONES.map((zone) => {
            const cs = zoneMap[zone.id] || [];
            const isActive = activeZone === zone.id;
            const hasSelection = cs.length > 0;
            const color = hasSelection ? CONCERN_DEFS[cs[0]]?.color : null;

            return (
              <button key={zone.id}
                onClick={() => setActiveZone(isActive ? null : zone.id)}
                aria-label={zone.label}
                title={zone.label}
                className="absolute -translate-x-1/2 -translate-y-1/2 z-10 flex flex-col items-center gap-0.5 group"
                style={{ left: `${zone.x}%`, top: `${zone.y}%` }}
              >
                {/* Circle */}
                <div className={`flex items-center justify-center rounded-full transition-all duration-200 ${
                  isActive
                    ? "w-9 h-9 bg-teal-500 shadow-lg shadow-teal-200 scale-110"
                    : hasSelection
                    ? "w-8 h-8 shadow-md"
                    : "w-7 h-7 bg-white border-2 border-dashed border-gray-300 group-hover:border-teal-400 group-hover:bg-teal-50 group-hover:scale-110"
                }`}
                  style={hasSelection && !isActive ? {
                    backgroundColor: color + "20",
                    border: `2px solid ${color}`,
                  } : {}}
                >
                  {isActive ? (
                    <span className="text-white text-[10px] font-bold">{zone.label.charAt(0)}</span>
                  ) : hasSelection ? (
                    <div className="flex gap-0.5">
                      {cs.slice(0, 3).map((c) => (
                        <span key={c} className={`w-2 h-2 rounded-full ${CONCERN_DEFS[c]?.dotClass}`} />
                      ))}
                    </div>
                  ) : (
                    <span className="text-gray-400 text-[10px]">+</span>
                  )}
                </div>
                {/* Label */}
                <span className={`text-[9px] font-medium leading-none transition-opacity ${
                  isActive ? "text-teal-600 opacity-100" : hasSelection ? "opacity-70" : "opacity-0 group-hover:opacity-60"
                }`} style={hasSelection && !isActive ? { color } : {}}>
                  {zone.label}
                </span>
              </button>
            );
          })}

          {/* Animated guide pulse */}
          {totalSelections === 0 && !activeZone && (
            <div className="absolute -translate-x-1/2 -translate-y-1/2 w-7 h-7 rounded-full bg-teal-400/15 animate-ping pointer-events-none"
              style={{ left: "50%", top: "20%" }} />
          )}
        </div>
      </div>

      {/* Hint */}
      {totalSelections === 0 && !activeZone && (
        <p className="text-center text-xs text-gray-400 flex items-center justify-center gap-1.5">
          <span className="w-5 h-5 border-2 border-dashed border-gray-300 rounded-full inline-flex items-center justify-center text-[8px] text-gray-400">+</span>
          Yüz üzerindeki noktalara dokunarak sorunlarını işaretle
        </p>
      )}

      {/* Zone detail panel */}
      {activeZone && activeZoneData && (
        <div className="bg-white rounded-2xl border border-gray-100 p-4 shadow-lg shadow-black/5 space-y-3">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <div className="w-7 h-7 bg-teal-50 rounded-lg flex items-center justify-center">
                <span className="text-teal-600 text-xs font-bold">{activeZoneData.label.charAt(0)}</span>
              </div>
              <div>
                <h4 className="font-semibold text-gray-900 text-sm">{activeZoneData.label}</h4>
                <p className="text-[10px] text-gray-400">Bu bölgede ne sorunun var?</p>
              </div>
            </div>
            <button onClick={() => setActiveZone(null)}
              className="w-6 h-6 rounded-full bg-gray-100 flex items-center justify-center text-gray-400 hover:bg-gray-200 text-[10px]">✕</button>
          </div>
          <div className="flex flex-wrap gap-2">
            {activeZoneData.concerns.map((cId) => {
              const def = CONCERN_DEFS[cId];
              const isOn = (zoneMap[activeZone] || []).includes(cId);
              return (
                <button key={cId} onClick={() => toggleConcern(activeZone, cId)}
                  className={`flex items-center gap-1.5 px-3 py-2 rounded-xl text-xs font-medium transition-all border-2 ${
                    isOn
                      ? `${def.light} ${def.text} shadow-sm`
                      : "bg-gray-50 text-gray-500 border-gray-200 hover:border-gray-300"
                  }`}
                  style={isOn ? { borderColor: def.color + "50" } : {}}>
                  <span className={`w-2 h-2 rounded-full ${isOn ? def.dotClass : "bg-gray-300"}`} />
                  {def.label}
                </button>
              );
            })}
          </div>
        </div>
      )}

      {/* Selection chips */}
      {totalSelections > 0 && (
        <div className="space-y-2">
          <div className="flex items-center justify-between">
            <p className="text-xs font-medium text-gray-500">Seçimlerin</p>
            <button onClick={() => onChange({})} className="text-[10px] text-gray-400 hover:text-red-500">Temizle</button>
          </div>
          <div className="flex flex-wrap gap-1.5">
            {ZONES.filter((z) => (zoneMap[z.id] || []).length > 0).map((z) =>
              (zoneMap[z.id] || []).map((cId) => {
                const def = CONCERN_DEFS[cId];
                return (
                  <span key={`${z.id}-${cId}`}
                    className={`inline-flex items-center gap-1 px-2 py-1 rounded-full text-[10px] font-medium ${def.light} ${def.text}`}
                    style={{ borderLeft: `3px solid ${def.color}` }}>
                    {z.label} · {def.label}
                  </span>
                );
              })
            )}
          </div>
        </div>
      )}
    </div>
  );
}
