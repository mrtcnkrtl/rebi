const STORAGE_KEY = "rebi_store_cart_v1";
const MAX_LINES = 20;
const MAX_QTY = 10;

function readRaw() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

function writeRaw(lines) {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(lines));
  } catch {
    /* quota */
  }
}

/** [{ slug, quantity }] — yalnız slug + adet; fiyat sunucudan gelir. */
export function getCartLines() {
  const merged = new Map();
  for (const item of readRaw()) {
    const slug = typeof item?.slug === "string" ? item.slug : "";
    const qty = Number.isInteger(item?.quantity) ? item.quantity : 0;
    if (!slug || qty < 1) continue;
    merged.set(slug, Math.min(MAX_QTY, (merged.get(slug) || 0) + qty));
    if (merged.size >= MAX_LINES) break;
  }
  return [...merged.entries()].map(([slug, quantity]) => ({ slug, quantity }));
}

export function cartCount(lines = getCartLines()) {
  return lines.reduce((n, line) => n + (line.quantity || 0), 0);
}

export function addToCart(slug, quantity = 1) {
  if (!slug) return getCartLines();
  const lines = getCartLines();
  const hit = lines.find((l) => l.slug === slug);
  if (hit) {
    hit.quantity = Math.min(MAX_QTY, hit.quantity + Math.max(1, quantity));
  } else if (lines.length < MAX_LINES) {
    lines.push({ slug, quantity: Math.min(MAX_QTY, Math.max(1, quantity)) });
  }
  writeRaw(lines);
  return lines;
}

export function setCartQuantity(slug, quantity) {
  let lines = getCartLines().filter((l) => l.slug !== slug);
  if (Number.isInteger(quantity) && quantity >= 1) {
    lines = [...lines, { slug, quantity: Math.min(MAX_QTY, quantity)}];
  }
  writeRaw(lines);
  return lines;
}

export function removeFromCart(slug) {
  const lines = getCartLines().filter((l) => l.slug !== slug);
  writeRaw(lines);
  return lines;
}

export function clearCart() {
  writeRaw([]);
  return [];
}
