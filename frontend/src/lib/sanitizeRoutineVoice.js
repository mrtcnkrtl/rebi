/** Eski motor usage jargonu — kullanıcıya göstermeden önce temizle (backend ile aynı niyet). */

const LEGACY_USAGE = [
  /Sıklık\/güç hafif düşürüldü:[^.]*\.\s*Tahriş riski azaltıldı\.\s*/gi,
  /Tempo yumuşatıldı:[^.]*\.\s*Bariyer öncelikli\.\s*/gi,
  /Yaşam verilerine göre bu adım geçici duraklatıldı[^.]*\.(?:\s*\([^)]*\))?\s*/gi,
  /Sıklık check-in ile yeniden planlanır\.\s*/gi,
  /Check-in:\s*cilt hissi[^.]*\.\s*/gi,
  /Check-in süreci:\s*beslenme[^.]*\.\s*/gi,
];

function stripPatterns(text, patterns) {
  let d = String(text || "").trim();
  if (!d) return "";
  for (let i = 0; i < 8; i += 1) {
    const prev = d;
    for (const p of patterns) {
      d = d.replace(p, "");
    }
    d = d.replace(/\s{2,}/g, " ").replace(/\s+\./g, ".").replace(/\.{2,}/g, ".").trim();
    if (d === prev) break;
  }
  return d;
}

/** Rutin adımındaki usage alanını kullanıcı diline indirger. */
export function sanitizeRoutineUsage(usage) {
  return stripPatterns(usage, LEGACY_USAGE);
}
