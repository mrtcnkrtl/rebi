/**
 * SkinTypeVisual — texture previews + guide (labels from locale analyzeWizard pack).
 */
import { useMemo, useState } from "react";
import { ChevronDown, HelpCircle } from "lucide-react";
import { useAnalyzeWizardPack } from "../lib/localePacks";

const SKIN_ORDER = ["oily", "dry", "combination", "normal", "sensitive"];

const skinTextureBase = [
  {
    id: "oily",
    activeBorder: "border-amber-400",
    activeRing: "ring-amber-100",
    textureStyle: {
      background: "linear-gradient(135deg, #fef3c7 0%, #fde68a 40%, #fef9c3 60%, #fde68a 100%)",
      boxShadow: "inset 0 0 20px rgba(251,191,36,0.15), inset 0 1px 0 rgba(255,255,255,0.6)",
    },
    textureOverlay: (
      <>
        <div className="absolute inset-0 opacity-40" style={{ background: "radial-gradient(circle at 30% 40%, rgba(255,255,255,0.8) 0%, transparent 40%), radial-gradient(circle at 70% 60%, rgba(255,255,255,0.6) 0%, transparent 35%), radial-gradient(circle at 50% 30%, rgba(255,255,255,0.5) 0%, transparent 30%)" }} />
        {[35, 50, 65, 42, 58].map((x, i) => (
          <div key={i} className="absolute w-1 h-1 rounded-full bg-amber-300/40" style={{ left: `${x}%`, top: `${[30, 50, 40, 65, 70][i]}%` }} />
        ))}
      </>
    ),
  },
  {
    id: "dry",
    activeBorder: "border-orange-400",
    activeRing: "ring-orange-100",
    textureStyle: {
      background: "linear-gradient(135deg, #fef3e2 0%, #fde8d0 50%, #f5dcc0 100%)",
    },
    textureOverlay: (
      <>
        <div className="absolute inset-0 opacity-30" style={{
          backgroundImage: `repeating-linear-gradient(45deg, transparent, transparent 3px, rgba(194,150,110,0.15) 3px, rgba(194,150,110,0.15) 4px),
                            repeating-linear-gradient(-45deg, transparent, transparent 5px, rgba(194,150,110,0.1) 5px, rgba(194,150,110,0.1) 6px)`,
        }} />
        <div className="absolute inset-0 opacity-20" style={{
          backgroundImage: "url(\"data:image/svg+xml,%3Csvg width='20' height='20' xmlns='http://www.w3.org/2000/svg'%3E%3Cpath d='M0 10 Q5 8 10 10 Q15 12 20 10' fill='none' stroke='%23c2966e' stroke-width='0.5'/%3E%3C/svg%3E\")",
          backgroundSize: "20px 20px",
        }} />
      </>
    ),
  },
  {
    id: "combination",
    activeBorder: "border-violet-400",
    activeRing: "ring-violet-100",
    textureStyle: {
      background: "linear-gradient(to right, #fef3e2 0%, #fef3e2 30%, #fef9c3 40%, #fef9c3 60%, #fef3e2 70%, #fef3e2 100%)",
    },
    textureOverlay: (
      <>
        <div className="absolute top-0 left-1/2 -translate-x-1/2 w-1/3 h-full opacity-30" style={{
          background: "linear-gradient(180deg, rgba(251,191,36,0.3) 0%, rgba(251,191,36,0.15) 100%)",
        }} />
        <div className="absolute inset-0 opacity-15" style={{
          backgroundImage: `repeating-linear-gradient(45deg, transparent, transparent 6px, rgba(194,150,110,0.12) 6px, rgba(194,150,110,0.12) 7px)`,
          maskImage: "linear-gradient(to right, black 0%, black 25%, transparent 35%, transparent 65%, black 75%, black 100%)",
          WebkitMaskImage: "linear-gradient(to right, black 0%, black 25%, transparent 35%, transparent 65%, black 75%, black 100%)",
        }} />
        <div className="absolute left-1/2 -translate-x-1/2 top-1 text-[8px] font-semibold text-amber-500/50 tracking-wider">T</div>
      </>
    ),
  },
  {
    id: "normal",
    activeBorder: "border-emerald-400",
    activeRing: "ring-emerald-100",
    textureStyle: {
      background: "linear-gradient(135deg, #fef8f0 0%, #fdf2e9 50%, #fef8f0 100%)",
      boxShadow: "inset 0 1px 0 rgba(255,255,255,0.7)",
    },
    textureOverlay: (
      <div className="absolute inset-0 opacity-30" style={{
        background: "radial-gradient(circle at 50% 50%, rgba(255,255,255,0.4) 0%, transparent 70%)",
      }} />
    ),
  },
  {
    id: "sensitive",
    activeBorder: "border-pink-400",
    activeRing: "ring-pink-100",
    textureStyle: {
      background: "linear-gradient(135deg, #fef2f2 0%, #fce7e7 50%, #fef2f2 100%)",
    },
    textureOverlay: (
      <div className="absolute inset-0 opacity-30" style={{
        background: "radial-gradient(circle at 30% 40%, rgba(239,68,68,0.2) 0%, transparent 50%), radial-gradient(circle at 70% 60%, rgba(239,68,68,0.15) 0%, transparent 45%), radial-gradient(circle at 50% 70%, rgba(239,68,68,0.1) 0%, transparent 40%)",
      }} />
    ),
  },
];

export default function SkinTypeVisual({ value, onChange }) {
  const pack = useAnalyzeWizardPack();
  const sp = pack.skinPicker || {};
  const [showGuide, setShowGuide] = useState(false);

  const skinTypes = useMemo(() => {
    const byId = Object.fromEntries(skinTextureBase.map((b) => [b.id, b]));
    return SKIN_ORDER.map((id) => {
      const base = byId[id];
      const labels = sp[id] || {};
      return {
        ...base,
        label: labels.label || id,
        desc: labels.desc || "",
      };
    });
  }, [sp]);

  const guideSteps = useMemo(
    () => [
      {
        title: sp.morningTitle,
        desc: sp.morningDesc,
        signKey: "morningSign",
      },
      {
        title: sp.tissueTitle,
        desc: sp.tissueDesc,
        signKey: "tissueSign",
      },
    ],
    [sp]
  );

  return (
    <div className="space-y-3">
      <div className="grid grid-cols-1 gap-2">
        {skinTypes.map((st) => {
          const isActive = value === st.id;
          return (
            <button key={st.id} type="button" onClick={() => onChange(st.id)}
              className={`relative flex items-center gap-3 p-2.5 rounded-2xl border-2 text-left transition-all duration-200 ${
                isActive
                  ? `${st.activeBorder} ring-2 ${st.activeRing}`
                  : "border-gray-200 hover:border-gray-300"
              }`}>
              <div className="relative shrink-0 w-14 h-14 rounded-xl overflow-hidden" style={st.textureStyle}>
                {st.textureOverlay}
              </div>
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-1.5">
                  <span className={`font-semibold text-sm ${isActive ? "text-gray-900" : "text-gray-700"}`}>{st.label}</span>
                  {isActive && (
                    <svg className="w-4 h-4 text-teal-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2.5} d="M5 13l4 4L19 7" />
                    </svg>
                  )}
                </div>
                <p className="text-[11px] text-gray-500 mt-0.5 leading-tight">{st.desc}</p>
              </div>
            </button>
          );
        })}
      </div>

      <button type="button" onClick={() => setShowGuide(!showGuide)}
        className="w-full flex items-center justify-center gap-1.5 py-2 text-xs text-teal-600 hover:text-teal-700 transition-colors">
        <HelpCircle className="w-3.5 h-3.5" />
        <span>{showGuide ? sp.guideClose : sp.guideOpen}</span>
        <ChevronDown className={`w-3 h-3 transition-transform ${showGuide ? "rotate-180" : ""}`} />
      </button>

      {showGuide && (
        <div className="bg-teal-50/50 rounded-2xl p-4 space-y-4 border border-teal-100">
          <h4 className="font-bold text-gray-900 text-sm flex items-center gap-2">
            <HelpCircle className="w-4 h-4 text-teal-600" />
            {sp.guideTitle}
          </h4>

          {guideSteps.map((step, si) => {
            const signs = sp[step.signKey] || {};
            return (
              <div key={si} className="space-y-2">
                <div className="flex items-center gap-2">
                  <span className="w-5 h-5 bg-teal-500 text-white rounded-full flex items-center justify-center text-[10px] font-bold shrink-0">{si + 1}</span>
                  <p className="text-xs font-semibold text-gray-800">{step.title}</p>
                </div>
                <p className="text-[11px] text-gray-500 ml-7">{step.desc}</p>
                <div className="ml-7 space-y-1">
                  {SKIN_ORDER.map((kid) => (
                    <div key={kid} className="flex items-start gap-2 text-[11px]">
                      <span className="font-semibold text-gray-700 w-14 shrink-0">{(sp[kid]?.label || kid)}:</span>
                      <span className="text-gray-500">{signs[kid]}</span>
                    </div>
                  ))}
                </div>
              </div>
            );
          })}

          <div className="bg-white rounded-xl p-3 text-[11px] text-gray-500">
            {sp.tipLine}
          </div>
        </div>
      )}
    </div>
  );
}
