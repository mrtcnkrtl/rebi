const FAMILY_LABELS = {
  retinol: "Retinol",
  bha: "BHA",
  aha: "AHA",
  azelaic: "Azelaik",
  vitamin_c: "C vit.",
  niacinamide: "B3",
  benzoyl: "BP",
  bakuchiol: "Bakuchiol",
  pigment: "Leke",
};

/**
 * Backend `run_flow` structured alanları: strength_pct, frequency_per_week, ramp_stage, active_families
 */
export function StructuredRoutineBadges({ item }) {
  const isRiskSummary =
    (item.action || "").startsWith("Günlük denge:") ||
    ((item.action || "").includes("Günlük denge") && item.category === "Yaşam");
  if (isRiskSummary) return null;

  const fam = Array.isArray(item.active_families) ? item.active_families : [];
  const has =
    item.strength_pct ||
    item.frequency_per_week != null ||
    item.ramp_stage ||
    fam.length > 0;
  if (!has) return null;

  const chips = [];
  if (item.ramp_stage === "starter") {
    chips.push({ key: "ramp", label: "Alıştırma" });
  }
  if (item.strength_pct) {
    chips.push({ key: "pct", label: `%${item.strength_pct}` });
  }
  if (item.frequency_per_week != null && item.frequency_per_week > 0) {
    const n = item.frequency_per_week;
    chips.push({
      key: "freq",
      label: n >= 7 ? "Her gün" : `${n}×/hafta`,
    });
  }
  if (fam.length) {
    const labels = fam.slice(0, 4).map((f) => FAMILY_LABELS[f] || f);
    chips.push({ key: "fam", label: labels.join(" · ") });
  }
  if (!chips.length) return null;

  return (
    <div className="flex flex-wrap gap-1 mt-1.5">
      {chips.map((c) => (
        <span
          key={c.key}
          className="text-[9px] font-medium px-1.5 py-0.5 rounded-md border border-gray-200/90 text-gray-600 bg-white/90"
        >
          {c.label}
        </span>
      ))}
    </div>
  );
}
