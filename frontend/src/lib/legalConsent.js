/** Giriş/kayıtta verilen KVKK + açık rıza onayı (cihazda hatırlanır). */

export const LEGAL_CONSENT_VERSION = "v1";
const STORAGE_KEY = "rebi_legal_consent_v1";

export function hasLegalConsent() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return false;
    const parsed = JSON.parse(raw);
    return parsed?.version === LEGAL_CONSENT_VERSION && parsed?.kvkk === true && parsed?.riza === true;
  } catch {
    return false;
  }
}

export function saveLegalConsent() {
  try {
    localStorage.setItem(
      STORAGE_KEY,
      JSON.stringify({
        version: LEGAL_CONSENT_VERSION,
        kvkk: true,
        riza: true,
        acceptedAt: new Date().toISOString(),
      })
    );
  } catch {
    /* ignore quota */
  }
}

export function legalConsentMetadata() {
  return {
    kvkk_accepted: true,
    riza_accepted: true,
    legal_consent_version: LEGAL_CONSENT_VERSION,
    legal_accepted_at: new Date().toISOString(),
  };
}
