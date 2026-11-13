/** Giriş sonrası yönlendirme yalnızca uygulama içi bir yol olabilir. */

export function safeNext(raw) {
  const fallback = "/dashboard";
  if (typeof raw !== "string") return fallback;
  let path = raw.trim();
  if (!path) return fallback;
  try {
    path = decodeURIComponent(path);
  } catch {
    return fallback;
  }
  if (!path.startsWith("/") || path.startsWith("//") || path.startsWith("/\\")) return fallback;
  if (path.includes("\\") || path.includes("://")) return fallback;
  for (let i = 0; i < path.length; i += 1) {
    const code = path.charCodeAt(i);
    if (code <= 31 || code === 127) return fallback;
  }
  return path;
}
