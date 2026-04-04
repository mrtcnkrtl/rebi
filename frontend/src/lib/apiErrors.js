/**
 * FastAPI / Starlette hata gövdesi: { detail: string | { msg }[] | ... }
 */
export function formatApiErrorDetail(data) {
  if (data == null) return "Sunucudan anlamlı bir yanıt alınamadı.";
  const d = data.detail;
  if (typeof d === "string") return d;
  if (Array.isArray(d)) {
    return d
      .map((e) => (typeof e === "string" ? e : e?.msg || e?.message || JSON.stringify(e)))
      .filter(Boolean)
      .join(" ");
  }
  if (d && typeof d === "object" && typeof d.msg === "string") return d.msg;
  if (typeof data.message === "string") return data.message;
  return "İşlem tamamlanamadı. Bir süre sonra tekrar dene.";
}

export function isNetworkError(err) {
  const raw = err?.message || String(err);
  return (
    raw === "Failed to fetch" ||
    raw.includes("NetworkError") ||
    err?.name === "TypeError"
  );
}
