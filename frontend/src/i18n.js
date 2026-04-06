import i18n from "i18next";
import LanguageDetector from "i18next-browser-languagedetector";
import { initReactI18next } from "react-i18next";

import tr from "./locales/tr/common.json";
import en from "./locales/en/common.json";
import es from "./locales/es/common.json";
import de from "./locales/de/common.json";
import it from "./locales/it/common.json";
import fr from "./locales/fr/common.json";
import pt from "./locales/pt/common.json";
import ar from "./locales/ar/common.json";
import az from "./locales/az/common.json";

export const SUPPORTED_LANGS = ["tr", "en", "es", "de", "it", "fr", "pt", "ar", "az"];

const resources = {
  tr: { common: tr },
  en: { common: en },
  es: { common: es },
  de: { common: de },
  it: { common: it },
  fr: { common: fr },
  pt: { common: pt },
  ar: { common: ar },
  az: { common: az },
};

function applyDocumentDir(lang) {
  const isRtl = lang === "ar";
  try {
    document.documentElement.setAttribute("dir", isRtl ? "rtl" : "ltr");
    document.documentElement.setAttribute("lang", lang || "en");
  } catch {
    /* ignore */
  }
}

i18n
  .use(LanguageDetector)
  .use(initReactI18next)
  .init({
    resources,
    ns: ["common"],
    defaultNS: "common",
    supportedLngs: SUPPORTED_LANGS,
    fallbackLng: "en",
    interpolation: { escapeValue: false },
    detection: {
      order: ["localStorage", "navigator"],
      lookupLocalStorage: "rebi-lang",
      caches: ["localStorage"],
    },
    react: { useSuspense: false },
  });

applyDocumentDir(i18n.resolvedLanguage || i18n.language);
i18n.on("languageChanged", (lng) => applyDocumentDir(lng));

export default i18n;

