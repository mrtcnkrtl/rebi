/** Dual-option routine steps: persist which path the user picked. */

const STORE_PREFIX = "rebi_step_choices_";
const VEYA_SKIP = /göre|sonra|daha|haftada|gerekirse|hekim|eczane|check-in|sırayla|tek formül|tek formul/i;

function stripTrailingParen(text) {
  return String(text || "").replace(/\s*\([^)]*\)\s*$/, "").trim();
}

function shortLabel(part) {
  return String(part || "").replace(/\s*\([^)]*\)/g, "").trim() || String(part || "").trim();
}

function splitPlus(text) {
  return stripTrailingParen(text)
    .split(/\s*\+\s*/)
    .map((s) => s.trim())
    .filter(Boolean);
}

/** Eski snapshot'larda backend `choices` yoksa aynı kuralla kart üret. */
export function inferRoutineStepChoices(item) {
  if (!item || !["Bakım", "Koruma"].includes(item.category)) return null;
  const action = String(item.action || "").trim();
  if (!action) return null;
  const al = action.toLowerCase();

  if (al.includes("sırayla veya tek formül") || al.includes("sirayla veya tek formul")) {
    const cleaned = action
      .replace(/\s*\((?:sırayla veya tek formül|sirayla veya tek formul)\)\s*/gi, "")
      .trim();
    const parts = splitPlus(cleaned);
    if (parts.length >= 2) {
      const a = shortLabel(parts[0]);
      const b = shortLabel(parts[1]);
      return [
        { id: "single", label: "Tek formül", hint: "İkisini aynı üründe ara.", action: cleaned },
        {
          id: "sequence",
          label: "Sırayla iki adım",
          hint: `Önce ${a}, kuruyunca ${b}.`,
          action: `${parts[0]} → sonra ${parts[1]}`,
        },
      ];
    }
  }

  if (/(3:1:1|\bcef\b|ferulik|tokoferol)/i.test(al)) return null;

  let prefix = "";
  let body = action;
  const colon = action.indexOf(":");
  if (colon >= 0) {
    prefix = `${action.slice(0, colon).trim()}: `;
    body = action.slice(colon + 1).trim();
  }

  const isMoist =
    item.step_order === 30 ||
    item.step_order === 35 ||
    al.startsWith("nemlendirici") ||
    al.startsWith("gece:") ||
    al.startsWith("gece (");
  if (isMoist && body.includes("+")) {
    const parts = splitPlus(body);
    if (parts.length === 2) {
      return [
        {
          id: "opt_a",
          label: shortLabel(parts[0]),
          hint: "Bu içeriği öne alan bir nemlendirici seç.",
          action: prefix + parts[0],
        },
        {
          id: "opt_b",
          label: shortLabel(parts[1]),
          hint: "Bu içeriği öne alan bir nemlendirici seç.",
          action: prefix + parts[1],
        },
      ];
    }
  }

  const isCleanser = item.step_order === 10 || al.includes("temizleme") || al.includes("temizleyici");
  if (isCleanser && /\sveya\s/i.test(body)) {
    if (VEYA_SKIP.test(body)) return null;
    const parts = body.split(/\s+veya\s+/i).map((s) => s.trim()).filter(Boolean);
    if (parts.length === 2) {
      return [
        { id: "opt_a", label: shortLabel(parts[0]), hint: "Bu temizleyiciyi kullan.", action: prefix + parts[0] },
        { id: "opt_b", label: shortLabel(parts[1]), hint: "Bu temizleyiciyi kullan.", action: prefix + parts[1] },
      ];
    }
  }
  return null;
}

export function withResolvedChoices(item) {
  if (!item) return item;
  if (Array.isArray(item.choices) && item.choices.length >= 2) return item;
  const inferred = inferRoutineStepChoices(item);
  if (!inferred) return item;
  const next = { ...item, choices: inferred };
  if (!next.choice_key) next.choice_key = stepChoiceKey(next);
  return next;
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
    if (!Array.isArray(item?.choices) || item.choices.length < 2) return raw;
    const id = getChosenOptionId(userId, item);
    if (!id) return item;
    return { ...item, chosen_option_id: id };
  });
}
