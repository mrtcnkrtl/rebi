/** Uzun rutin satırından okunur kısa başlık (INCI ve kimyasal parantezler gizlenir). */
export function friendlyRoutineTitle(action, fallbackTitle = "This step") {
  if (!action) return fallbackTitle;
  let s = String(action)
    .replace(/^⏸️\s*/u, "")
    .replace(/\s*—\s*ARA VER\s*$/iu, "")
    .replace(/\s*—\s*şimdilik kullanma\s*$/iu, "")
    .trim();
  const parts = s.split(/\s*[—–]\s*/).map((p) => p.trim()).filter(Boolean);
  if (parts.length >= 2) {
    const human = cleanTitlePart(parts[1]);
    if (human.length > 0 && human.length < 140) return human;
  }
  return cleanTitlePart(parts[0] || s) || fallbackTitle;
}

function cleanTitlePart(text) {
  return String(text || "")
    .replace(/\s*\(INCI[^)]*\)\s*/gi, " ")
    .replace(/\s*\([^)]*inci:[^)]*\)\s*/gi, " ")
    .replace(/\s+/g, " ")
    .trim();
}
