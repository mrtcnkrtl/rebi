/** Seçim kartında maddenin yanında duran üç kelime. Eski kayıtlarda `diff` yoksa kimlikten gelir. */
export const CHOICE_DIFF = {
  alfa_arbutin: "yaygın, iyi tolere",
  hexylresorcinol: "düşük dozda güçlü",
  licorice: "en nazik seçenek",
  niacinamide_txa: "melazmaya güçlü destek",
  nag_niacinamide: "nazik ton eşitleme",
  glycolic: "hızlı, biraz tahriş",
  mandelic: "yavaş, az tahriş",
  pha: "en nazik asit",
  benzoyl: "güçlü ama kurutur",
  sulfur: "nazik, kokusu belirgin",
  azelaic: "akne ve kızarıklık",
  vitamin_c: "en güçlü antioksidan",
  green_tea: "nazik sebum desteği",
  toco_ferulic: "hafif sabah antioksidanı",
  niacinamide: "sebum ve bariyer",
  undereye_vitc: "kahverengi koyuluğa iyi",
  caffeine: "morluk ve şişlik",
  undereye_niacinamide: "ince ciltte nazik",
  undereye_licorice: "nazik pigment açıcı",
  undereye_arbutin: "pigment kaynaklı koyuluk",
  undereye_nag: "düşük dozda nazik",
  mineral: "hassas ciltte güvenli",
  chemical: "hafif, yağlı cilt",
  hybrid: "ince dengeli koruma",
  tinted: "lekeye renkli koruma",
  single: "aynı üründe ikisi",
  sequence: "iki adım sırayla",
};

export function choiceDiff(choice) {
  const fromItem = String(choice?.diff || "").trim();
  if (fromItem) return fromItem;
  return CHOICE_DIFF[choice?.id] || "";
}

/** Dual-option routine steps: persist which path the user picked. */

const STORE_PREFIX = "rebi_step_choices_";

/** Aynı sorunu gören maddeler menü olmaz. */
export function inferRoutineStepChoices() {
  return null;
}

export function withResolvedChoices(item) {
  return item || null;
}

export function stepChoiceKey(item) {
  if (item?.choice_key) return String(item.choice_key);
  const so = item?.step_order ?? "";
  const time = item?.time || "";
  const cat = item?.category || "";
  const ids = Array.isArray(item?.choices)
    ? item.choices.map((c) => c.id).join("|")
    : "";
  return `${time}|${cat}|${so}|${ids}`;
}

export function getStepChoicesStore(userId) {
  try {
    const raw = localStorage.getItem(`${STORE_PREFIX}${userId || "anon"}`);
    if (!raw) return {};
    const parsed = JSON.parse(raw);
    return parsed && typeof parsed === "object" ? parsed : {};
  } catch {
    return {};
  }
}

function writeStepChoicesStore(userId, store) {
  try {
    localStorage.setItem(`${STORE_PREFIX}${userId || "anon"}`, JSON.stringify(store));
  } catch {
    /* quota */
  }
}

export function getChosenOptionId(userId, item) {
  if (!item) return null;
  const stored = getStepChoicesStore(userId)[stepChoiceKey(item)];
  if (stored) return stored;
  return item.chosen_option_id || null;
}

export function getChosenOption(userId, item) {
  const id = getChosenOptionId(userId, item);
  if (!id || !Array.isArray(item?.choices)) return null;
  return item.choices.find((c) => c.id === id) || null;
}

export function persistStepChoice(userId, item, choiceId) {
  const store = getStepChoicesStore(userId);
  const key = stepChoiceKey(item);
  if (!choiceId) delete store[key];
  else store[key] = choiceId;
  writeStepChoicesStore(userId, store);
}

export function applyChosenOptionIds(userId, routine) {
  return (routine || []).map((raw) => {
    const item = withResolvedChoices(raw);
    if (!Array.isArray(item?.choices) || item.choices.length < 2) return item;
    const id = getChosenOptionId(userId, item);
    if (!id) return item;
    return { ...item, chosen_option_id: id };
  });
}
