import { useEffect, useMemo } from "react";
import { useTranslation } from "react-i18next";
import { SUPPORTED_LANGS } from "../i18n";

const LABELS = {
  tr: "Türkçe",
  en: "English",
  es: "Español",
  de: "Deutsch",
  it: "Italiano",
  fr: "Français",
  pt: "Português",
  ar: "العربية",
  az: "Azərbaycanca",
};

export default function LanguageSelect({ className = "" }) {
  const { i18n, t } = useTranslation();

  const options = useMemo(
    () =>
      SUPPORTED_LANGS.map((lng) => ({
        id: lng,
        label: LABELS[lng] || lng,
      })),
    [],
  );

  useEffect(() => {
    // Ensure localStorage key stays consistent with detector
    try {
      if (i18n.language) localStorage.setItem("rebi-lang", i18n.language);
    } catch {
      /* ignore */
    }
  }, [i18n.language]);

  return (
    <label className={`flex items-center gap-2 ${className}`.trim()}>
      <span className="text-[11px] font-semibold text-gray-500">{t("lang.label")}</span>
      <select
        value={(i18n.resolvedLanguage || i18n.language || "en").toLowerCase().split("-")[0]}
        onChange={(e) => {
          const lng = e.target.value;
          try {
            localStorage.setItem("rebi-lang", lng);
          } catch {
            /* ignore */
          }
          i18n.changeLanguage(lng);
        }}
        className="text-[11px] font-semibold px-2 py-1 rounded-lg border border-gray-200 bg-white text-gray-700"
      >
        {options.map((o) => (
          <option key={o.id} value={o.id}>
            {o.label}
          </option>
        ))}
      </select>
    </label>
  );
}

