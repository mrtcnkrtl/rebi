import { Symbol3D } from "../landing/Slab";
import { concernMeta } from "../../lib/storeConcerns";

/** Sorun etiketi: renkli chip veya 3D sembollü buton. */
export function ConcernBadge({ id, t, className = "" }) {
  const meta = concernMeta(id);
  return (
    <span className={`inline-flex items-center gap-1 rounded-full border px-2.5 py-0.5 text-[11px] font-semibold ${meta.chip} ${className}`}>
      <meta.icon className="h-3 w-3" strokeWidth={2.2} aria-hidden="true" />
      {t(`store.concern.${id}`, { defaultValue: id })}
    </span>
  );
}

export function ConcernFilterButton({ id, active, onClick, t, withSymbol = false }) {
  const meta = concernMeta(id);
  if (withSymbol) {
    return (
      <button
        type="button"
        onClick={onClick}
        className={`flex min-w-[7.5rem] flex-col items-center gap-2 rounded-2xl border px-3 py-3 text-center transition ${
          active ? "border-ink bg-white shadow-[0_6px_0_#062b27]" : "border-rule bg-white/80 hover:border-teal-200"
        }`}
      >
        <span className="scene-3d">
          <span className="scene-3d__tilt">
            <Symbol3D icon={meta.icon} tone={meta.tone} size={48} rotate="rotateY(-16deg) rotateX(10deg)" />
          </span>
        </span>
        <span className="text-xs font-bold text-ink">{t(`store.concern.${id}`)}</span>
      </button>
    );
  }
  return (
    <button
      type="button"
      onClick={onClick}
      className={`inline-flex items-center gap-1.5 rounded-full border px-3.5 py-2 text-sm font-semibold transition ${
        active ? `${meta.chip} ring-2 ring-ink/20` : `${meta.chip} opacity-80 hover:opacity-100`
      }`}
    >
      <meta.icon className="h-3.5 w-3.5" strokeWidth={2.2} aria-hidden="true" />
      {t(`store.concern.${id}`)}
    </button>
  );
}

export function ConcernSymbolRow({ ids, t }) {
  const list = (ids || []).filter(Boolean);
  if (!list.length) return null;
  return (
    <div className="flex flex-wrap gap-4">
      {list.map((id) => {
        const meta = concernMeta(id);
        return (
          <div key={id} className="flex flex-col items-center gap-2">
            <span className="scene-3d">
              <span className="scene-3d__tilt">
                <Symbol3D icon={meta.icon} tone={meta.tone} size={56} />
              </span>
            </span>
            <span className={`rounded-full border px-2.5 py-0.5 text-[11px] font-semibold ${meta.chip}`}>
              {t(`store.concern.${id}`, { defaultValue: id })}
            </span>
          </div>
        );
      })}
    </div>
  );
}

/** Detay sayfası: sorun başına 3D sembol + kısa açıklama. */
export function ConcernDetailList({ ids, t }) {
  const list = (ids || []).filter(Boolean);
  if (!list.length) return null;
  return (
    <ul className="space-y-3">
      {list.map((id) => {
        const meta = concernMeta(id);
        return (
          <li
            key={id}
            className="flex items-start gap-4 rounded-2xl border px-4 py-3"
            style={{ borderColor: `${meta.solid}55`, background: meta.soft }}
          >
            <span className="scene-3d shrink-0 pt-0.5">
              <span className="scene-3d__tilt">
                <Symbol3D icon={meta.icon} tone={meta.tone} size={52} rotate="rotateY(-14deg) rotateX(10deg)" />
              </span>
            </span>
            <div className="min-w-0 flex-1">
              <p className={`inline-flex rounded-full border px-2.5 py-0.5 text-[11px] font-bold ${meta.chip}`}>
                {t(`store.concern.${id}`, { defaultValue: id })}
              </p>
              <p className="mt-1.5 text-sm leading-relaxed text-ink">
                {t(`store.concernHelp.${id}`, { defaultValue: "" })}
              </p>
            </div>
          </li>
        );
      })}
    </ul>
  );
}
