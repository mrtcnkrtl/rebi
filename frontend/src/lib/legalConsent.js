/** Sürümlü KVKK + açık rıza kaydı. Asıl kanıt backend tablosundadır. */

import { API_URL } from "./supabase";
import { apiAuthHeaders } from "./apiAuth";

export const LEGAL_CONSENT_VERSION = "v2";

function storageKey(userId) {
  return `rebi_legal_consent_${LEGAL_CONSENT_VERSION}_${userId}`;
}

export function saveLegalConsent(userId, acceptedAt, permissions = {}) {
  if (!userId) return;
  try {
    localStorage.setItem(
      storageKey(userId),
      JSON.stringify({
        version: LEGAL_CONSENT_VERSION,
        kvkk: true,
        riza: true,
        ai: permissions.ai === true,
        location: permissions.location === true,
        photo: permissions.photo === true,
        acceptedAt: acceptedAt || new Date().toISOString(),
      })
    );
  } catch {
    /* ignore quota */
  }
}

export async function recordLegalConsent(userId, permissions = {}) {
  if (!userId) throw new Error("Rıza kaydı için kullanıcı oturumu bulunamadı.");
  const auth = await apiAuthHeaders();
  const response = await fetch(`${API_URL}/legal-consent/accept`, {
    method: "POST",
    headers: { "Content-Type": "application/json", ...auth },
    body: JSON.stringify({
      user_id: userId,
      document_version: LEGAL_CONSENT_VERSION,
      kvkk_accepted: true,
      explicit_consent_accepted: true,
      ai_processing_accepted: permissions.ai === true,
      location_processing_accepted: permissions.location === true,
      photo_processing_accepted: permissions.photo === true,
    }),
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(data?.detail || "Rıza kaydı oluşturulamadı.");
  }
  saveLegalConsent(userId, data?.accepted_at, permissions);
  return data;
}

export function hasLocalPrivacyPermission(userId, permission) {
  if (!userId) return false;
  try {
    const raw = localStorage.getItem(storageKey(userId));
    const parsed = raw ? JSON.parse(raw) : null;
    return parsed?.version === LEGAL_CONSENT_VERSION && parsed?.[permission] === true;
  } catch {
    return false;
  }
}

/*
 * Google ile giriş sayfadan ayrılıp geri döner: girişten önce işaretlenen onaylar dönüşe kadar aynı sekmede
 * (sessionStorage) bekler, oturum açılınca sunucuya yazılır. Yazılamazsa sorun değil: rızası olmayan oturumda
 * yapay zekâ uçları 403 döner ve rıza kutusu açılır (ConsentRecoveryModal).
 */
const PENDING_OAUTH_CONSENT_KEY = "rebi_pending_oauth_consent";
const PENDING_OAUTH_CONSENT_TTL_MS = 30 * 60 * 1000;

export function stashPendingConsent(permissions = {}) {
  try {
    sessionStorage.setItem(
      PENDING_OAUTH_CONSENT_KEY,
      JSON.stringify({
        location: permissions.location === true,
        photo: permissions.photo === true,
        at: Date.now(),
      })
    );
  } catch {
    /* gizli sekme / depolama kapalı: rıza kutusu yedek */
  }
}

export async function flushPendingConsent(userId) {
  if (!userId) return false;
  let pending = null;
  try {
    const raw = sessionStorage.getItem(PENDING_OAUTH_CONSENT_KEY);
    if (!raw) return false;
    sessionStorage.removeItem(PENDING_OAUTH_CONSENT_KEY);
    pending = JSON.parse(raw);
  } catch {
    return false;
  }
  if (!pending || Date.now() - (pending.at || 0) > PENDING_OAUTH_CONSENT_TTL_MS) return false;
  try {
    await recordLegalConsent(userId, { ai: true, location: pending.location, photo: pending.photo });
    return true;
  } catch {
    return false;
  }
}
