import { API_URL } from "./supabase";

const TIMEOUT_MS = 2500;

async function fetchJson(url, opts) {
  const ctrl = new AbortController();
  const t = window.setTimeout(() => ctrl.abort(), TIMEOUT_MS);
  try {
    const res = await fetch(url, { ...opts, signal: ctrl.signal });
    return await res.json().catch(() => ({}));
  } finally {
    window.clearTimeout(t);
  }
}

/** True if this client IP already completed the intro (server). Fail-open: false. */
export async function introSeenOnIp() {
  try {
    const data = await fetchJson(`${API_URL}/intro/seen`);
    return Boolean(data?.seen);
  } catch {
    return false;
  }
}

export async function markIntroSeenOnIp() {
  try {
    await fetchJson(`${API_URL}/intro/seen`, { method: "POST" });
  } catch {
    /* offline / API yok: tarayıcı kaydı yeter */
  }
}
