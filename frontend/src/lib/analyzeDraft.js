/**
 * Analiz sihirbazının yarım kalan cevapları (mobil karşılığı: `mobile/lib/core/analyze_draft.dart`).
 *
 * Kullanıcı sekmeyi kapatırsa, yenilerse ya da yanlışlıkla başa dönerse cevaplar kaybolmasın diye
 * tarayıcıda tutulur; rutin üretilince silinir. Fotoğraf saklanmaz (dosya nesnesi taşınamaz).
 */

export function analyzeDraftKey(userId) {
  return `rebi_analyze_draft_${userId}`;
}

/** Taslak bu süreden eskiyse sorulmaz (cevaplar bayatlar, cilt değişir). */
export const ANALYZE_DRAFT_MAX_AGE_MS = 14 * 24 * 60 * 60 * 1000;

export function getAnalyzeDraft(userId) {
  if (!userId) return null;
  let parsed;
  try {
    const raw = localStorage.getItem(analyzeDraftKey(userId));
    if (!raw) return null;
    parsed = JSON.parse(raw);
  } catch {
    return null;
  }
  if (!parsed || typeof parsed !== "object") return null;
  if (typeof parsed.savedAt !== "number") return null;
  const age = Date.now() - parsed.savedAt;
  if (age < 0 || age > ANALYZE_DRAFT_MAX_AGE_MS) return null;
  const answers = parsed.answers;
  if (!answers || typeof answers !== "object" || !Object.keys(answers).length) return null;
  return parsed;
}

export function saveAnalyzeDraft(userId, { step, step3Section, stressTest, answers }) {
  if (!userId) return;
  try {
    localStorage.setItem(
      analyzeDraftKey(userId),
      JSON.stringify({ savedAt: Date.now(), step, step3Section, stressTest, answers })
    );
  } catch {
    /* kota dolu / erişilemez: taslak tutulamaz, sihirbaz yine çalışır */
  }
}

export function clearAnalyzeDraft(userId) {
  if (!userId) return;
  try {
    localStorage.removeItem(analyzeDraftKey(userId));
  } catch {
    /* ignore */
  }
}

/** Sunucudaki son analizi (`GET /me/assessment/last`) sihirbazın cevap biçimine çevirir. */
export function draftAnswersFromAssessment(last) {
  const l = (last && last.lifestyle_data) || {};
  const strList = (v) => (Array.isArray(v) ? v.filter((x) => typeof x === "string") : []);

  const rows = Array.isArray(l.concerns) ? l.concerns.filter((r) => r && typeof r === "object") : [];
  const concerns = [];
  const concernZones = {};
  const concernTimeline = {};
  for (const row of rows) {
    const id = typeof row.id === "string" ? row.id : "";
    if (!id || concerns.includes(id)) continue;
    concerns.push(id);
    // Motor bölgeleri sol/sağ yanak olarak açar; sihirbazda tek "yanak" seçeneği var.
    const zones = [];
    for (const z of strList(row.zones)) {
      const zone = z === "left_cheek" || z === "right_cheek" ? "cheeks" : z;
      if (!zones.includes(zone)) zones.push(zone);
    }
    if (zones.length) concernZones[id] = zones;
    const fields = {};
    for (const f of ["duration", "frequency", "note"]) {
      if (typeof row[f] === "string") fields[f] = row[f];
    }
    if (Object.keys(fields).length) concernTimeline[id] = fields;
  }
  if (!concerns.length && last?.concern) concerns.push(last.concern);

  return {
    name: last?.full_name || "",
    age: last?.age == null ? "" : String(last.age),
    gender: last?.gender || (typeof l.gender === "string" ? l.gender : ""),
    // Döngü evresi son adet tarihinden hesaplanıyor ve tarih saklanmıyor: yalnız tarih
    // gerektirmeyen durumlar taşınır, düzenli/düzensiz döngü yeniden sorulur.
    hormonalStatus: l.cycle_phase === "menopause" ? "menopause" : l.is_pregnant === true ? "pregnant" : "",
    skinType: typeof l.skin_type === "string" ? l.skin_type : "",
    concerns,
    concernZones,
    concernTimeline,
    triggers: strList(l.triggers),
    pastTreatments: strList(l.past_treatments),
    expectations: strList(l.expectations),
    nutrition: l.nutrition && typeof l.nutrition === "object" ? l.nutrition : undefined,
    waterIntake: l.water_intake,
    sleepHours: l.sleep_hours,
    smokingPerDay: l.smoking_per_day,
    smokingYears: l.smoking_years,
    alcoholFreq: l.alcohol_frequency,
    alcoholAmt: l.alcohol_amount,
    makeupFreq: l.makeup_frequency,
    makeupRemoval: l.makeup_removal,
    activesExperience: l.actives_experience,
    activesTolerance: l.actives_tolerance && typeof l.actives_tolerance === "object" ? l.actives_tolerance : undefined,
    specialFlags: l.special_flags && typeof l.special_flags === "object" ? l.special_flags : undefined,
  };
}
