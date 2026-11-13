export const UNDEREYE_COLOR_KEYS = ["unsure", "brown", "purple", "both"];
export const UNDEREYE_PUFF_KEYS = ["none", "sometimes", "often", "all_day"];

/** Şiddet testindeki seçenek sırası → motorun beklediği göz altı görünümü. */
export function undereyeLookFromPicks(picks) {
  if (!picks || (picks.color == null && picks.puffiness == null)) return null;
  const color = UNDEREYE_COLOR_KEYS[picks.color] || "unsure";
  const puffiness = UNDEREYE_PUFF_KEYS[picks.puffiness] || "none";
  return { color, puffiness };
}
