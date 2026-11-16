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
