import i18n from "i18next";
import LanguageDetector from "i18next-browser-languagedetector";
import { initReactI18next } from "react-i18next";

import tr from "./locales/tr/common.json";
import en from "./locales/en/common.json";

// UI dilleri: TR/EN. Diğer diller hazır değil (fallback EN oluyordu ve kafa karıştırıyordu).
export const SUPPORTED_LANGS = ["tr", "en"];

const resources = {
  tr: { common: tr },
  en: { common: en },
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

