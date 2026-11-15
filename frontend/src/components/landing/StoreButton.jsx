import { useTranslation } from "react-i18next";
import { ArrowUpRight } from "lucide-react";
import { Slab } from "./Slab";
import { AppleGlyph, PlayGlyph } from "./StoreGlyphs";

/**
 * Büyük mağaza düğmesi. `tone="ink"` açık zeminde, `tone="cream"` koyu zeminde kullanılır.
 * Soldaki simge kalınlığı olan bir levhadır; fareyle birlikte döner, üstüne gelince öne çıkar.
 */
export default function StoreButton({ store, tone = "ink", className = "" }) {
  const { t } = useTranslation();
  const Glyph = store.id === "android" ? PlayGlyph : AppleGlyph;
  const top = t(store.topKey);

  return (
    <a
      href={store.url}
      target="_blank"
      rel="noopener noreferrer"
      aria-label={`${top}: ${store.name}`}
      className={`store-btn store-btn--${tone} ${className}`}
    >
      <span className="store-btn__scene" aria-hidden="true">
        <span className="scene-3d__tilt">
          <span className="store-btn__pose">
            <Slab
              tone={tone === "ink" ? "cream" : "ink"}
              depth={12}
              radius={18}
              lift={10}
              style={{ width: 60, height: 60 }}
            >
              <Glyph style={{ width: 30, height: 30, marginLeft: store.id === "android" ? 3 : 0 }} />
            </Slab>
          </span>
        </span>
      </span>
      <span className="flex min-w-0 flex-1 flex-col leading-tight">
        <span className="text-[13px] font-medium opacity-80">{top}</span>
        <span className="text-[26px] font-bold tracking-tight">{store.name}</span>
      </span>
      <ArrowUpRight className="h-5 w-5 shrink-0 opacity-70" aria-hidden="true" />
    </a>
  );
}
