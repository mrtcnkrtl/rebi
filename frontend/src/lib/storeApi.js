import { API_URL } from "./supabase";

/** Vitrin listesi / detay. Auth gerekmez. */
export async function fetchStoreProducts(params = {}) {
  const q = new URLSearchParams();
  for (const [k, v] of Object.entries(params)) {
    if (v != null && v !== "") q.set(k, String(v));
  }
  const qs = q.toString();
  const res = await fetch(`${API_URL}/store/products${qs ? `?${qs}` : ""}`);
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.detail || "store_list_failed");
  return data;
}

export async function fetchStoreProduct(slug) {
  const res = await fetch(`${API_URL}/store/products/${encodeURIComponent(slug)}`);
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.detail || "store_detail_failed");
  return data;
}

export function productLabel(product, lang = "tr") {
  if (!product) return "";
  const en = String(lang || "tr").startsWith("en");
  return (en ? product.name_en : product.name_tr) || product.name_tr || product.slug;
}

export function productSummary(product, lang = "tr") {
  if (!product) return "";
  const en = String(lang || "tr").startsWith("en");
  return (en ? product.summary_en : product.summary_tr) || product.summary_tr || "";
}

/** İlk stok görseli; yoksa visual’dan /store/{visual}.svg üretir. */
export function productImage(product, lang = "tr") {
  if (!product) return null;
  const en = String(lang || "tr").startsWith("en");
  const first = Array.isArray(product.images) ? product.images[0] : null;
  if (first?.url) {
    return {
      url: first.url,
      alt: (en ? first.alt_en : first.alt_tr) || productLabel(product, lang),
    };
  }
  if (product.visual) {
    return {
      url: `/store/${product.visual}.svg`,
      alt: productLabel(product, lang),
    };
  }
  return null;
}

/** Fiyat kuruştan; yoksa null (UI “yakında” gösterir). */
export function formatPrice(product, lang = "tr") {
  const minor = product?.price_minor;
  if (typeof minor !== "number" || minor <= 0) return null;
  const amount = minor / 100;
  const locale = String(lang || "tr").startsWith("en") ? "en-TR" : "tr-TR";
  const currency = product.currency || "TRY";
  try {
    return new Intl.NumberFormat(locale, { style: "currency", currency, maximumFractionDigits: 0 }).format(amount);
  } catch {
    return `₺${amount.toFixed(0)}`;
  }
}

export const TYPE_I18N = {
  cleanser: "store.typeCleanser",
  toner: "store.typeToner",
  serum: "store.typeSerum",
  moisturizer: "store.typeMoisturizer",
  sunscreen: "store.typeSunscreen",
  mask: "store.typeMask",
  other: "store.typeOther",
};
