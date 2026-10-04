/**
 * Rıza kaydı olmayan oturumlarda yapay zekâ uçları 403 döner. O durumda
 * kullanıcıyı çıkışa zorlamak yerine onay kutusunu açarız.
 */

const EVENT_NAME = "rebi:consent-required";

export function isConsentError(status, data) {
  if (status !== 403) return false;
  return String(data?.detail || "").includes("izni gerekli");
}

export function requestConsentRecovery() {
  try {
    window.dispatchEvent(new Event(EVENT_NAME));
  } catch {
    /* tarayıcı olay desteklemiyorsa sessiz geç */
  }
}

export function onConsentRecoveryRequest(handler) {
  window.addEventListener(EVENT_NAME, handler);
  return () => window.removeEventListener(EVENT_NAME, handler);
}
