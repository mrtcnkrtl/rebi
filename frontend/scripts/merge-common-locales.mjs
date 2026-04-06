/**
 * Eksik locale dosyalarını en/common.json ile doldurur (mevcut çeviriler korunur).
 * Çalıştır: node scripts/merge-common-locales.mjs
 */
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const localesDir = path.join(__dirname, "../src/locales");

function deepMergePreferExisting(existing, base) {
  if (base === null || typeof base !== "object" || Array.isArray(base)) {
    return existing !== undefined ? existing : base;
  }
  const out = { ...base };
  for (const k of Object.keys(base)) {
    if (k in existing && existing[k] !== undefined && existing[k] !== null) {
      const ex = existing[k];
      const ba = base[k];
      if (
        typeof ba === "object" &&
        ba !== null &&
        !Array.isArray(ba) &&
        typeof ex === "object" &&
        ex !== null &&
        !Array.isArray(ex)
      ) {
        out[k] = deepMergePreferExisting(ex, ba);
      } else {
        out[k] = ex;
      }
    }
  }
  return out;
}

function readJson(p) {
  return JSON.parse(fs.readFileSync(p, "utf8"));
}

function writeJson(p, obj) {
  fs.writeFileSync(p, JSON.stringify(obj, null, 2) + "\n", "utf8");
}

const enPath = path.join(localesDir, "en/common.json");
const en = readJson(enPath);
const targets = ["es", "de", "it", "fr", "pt", "ar", "tr", "az"];

for (const lng of targets) {
  const p = path.join(localesDir, lng, "common.json");
  if (!fs.existsSync(p)) continue;
  const cur = readJson(p);
  const merged = deepMergePreferExisting(cur, en);
  if (!merged.lang) merged.lang = {};
  merged.lang.az = merged.lang.az || "Azərbaycanca";
  writeJson(p, merged);
}

// en dosyasına lang.az
const enDoc = readJson(enPath);
if (!enDoc.lang) enDoc.lang = {};
enDoc.lang.az = enDoc.lang.az || "Azərbaycanca";
writeJson(enPath, enDoc);

console.log("Merged common.json from en into:", targets.join(", "));
console.log("Added lang.az where missing.");
