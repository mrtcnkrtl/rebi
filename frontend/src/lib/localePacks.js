import { useMemo } from "react";
import { useTranslation } from "react-i18next";

const analyzeWizardModules = import.meta.glob("../locales/*/analyzeWizard.json", {
  eager: true,
});
const severityTestsModules = import.meta.glob("../locales/*/severityTests.json", {
  eager: true,
});

function pickPack(globMap, lang, fileName) {
  const base = (lang || "en").toLowerCase().split("-")[0];
  const primary = `../locales/${base}/${fileName}`;
  const fallback = `../locales/en/${fileName}`;
  const mod = globMap[primary] || globMap[fallback];
  return mod?.default ?? mod ?? {};
}

export function useAnalyzeWizardPack() {
  const { i18n } = useTranslation();
  return useMemo(
    () => pickPack(analyzeWizardModules, i18n.resolvedLanguage || i18n.language, "analyzeWizard.json"),
    [i18n.resolvedLanguage, i18n.language]
  );
}

export function useSeverityTestsPack() {
  const { i18n } = useTranslation();
  return useMemo(
    () => pickPack(severityTestsModules, i18n.resolvedLanguage || i18n.language, "severityTests.json"),
    [i18n.resolvedLanguage, i18n.language]
  );
}
