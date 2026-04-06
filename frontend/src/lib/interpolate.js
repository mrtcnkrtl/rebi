/** Basit {{anahtar}} yer tutucu değişimi (i18n dışı JSON metinleri için). */
export function interpolate(str, vars) {
  if (str == null || str === "") return "";
  return String(str).replace(/\{\{(\w+)\}\}/g, (_, k) =>
    vars[k] != null ? String(vars[k]) : ""
  );
}
