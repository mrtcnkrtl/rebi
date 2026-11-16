/**
 * dose_key → kısa eğitim metni (i18n store.actives.*).
 * Katalogdaki tüm maddeler için aynı desen.
 */
export function activeInfoKey(doseKey) {
  const key = String(doseKey || "").trim();
  if (!key) return null;
  return `store.actives.${key}`;
}

export function activeInfoText(t, doseKey) {
  const path = activeInfoKey(doseKey);
  if (!path || typeof t !== "function") return "";
  const text = t(path, { defaultValue: "" });
  if (!text || text === path) return "";
  return String(text).trim();
}
