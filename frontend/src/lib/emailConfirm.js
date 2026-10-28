/**
 * E-posta onay sayfasının (`/auth/confirm`) yardımcıları.
 *
 * Onay e-postasındaki düğme doğrudan Supabase'in `/auth/v1/verify` adresine değil bu sayfaya gider. Nedeni:
 * Supabase'in bağlantısı tek kullanımlıktır ve ilk GET isteğinde tüketilir; Gmail/Outlook/antivirüs gibi
 * bağlantı tarayıcıları e-postadaki bağlantıyı önceden açtığı için kullanıcı tıkladığında `otp_expired` çıkıyordu.
 * Bu sayfa açılınca hiçbir istek atmaz; token yalnızca kullanıcı düğmeye dokununca doğrulanır.
 */

/** Sayfanın doğrulayabildiği e-posta bağlantısı türleri (parola sıfırlama için web'de ekran yok). */
export const CONFIRM_TYPES = ["signup", "email"];

/** Uygulamayı açan derin bağlantı (`AndroidManifest.xml` / `Info.plist` ile aynı olmalı). */
export const APP_DEEP_LINK = "com.rebiovil.rebi://auth-callback?confirmed=1";

/** `?token_hash=…&type=…` → doğrulanabilir parametreler ya da null (eksik / desteklenmeyen tür). */
export function parseConfirmParams(search) {
  const q = new URLSearchParams(search || "");
  const tokenHash = (q.get("token_hash") || "").trim();
  const type = (q.get("type") || "signup").trim().toLowerCase();
  if (!tokenHash || !CONFIRM_TYPES.includes(type)) return null;
  return { tokenHash, type };
}

/**
 * Doğrulama / yeniden gönderme hatasını ekranın göstereceği türe çevirir:
 * `expired` (kullanılmış ya da süresi dolmuş), `rate` (çok sık deneme), `network`, `other`.
 */
export function classifyConfirmError(err) {
  const code = String(err?.code || err?.error_code || "").toLowerCase();
  const msg = String(err?.message || err || "").toLowerCase();
  // "Email link is invalid or has expired" (otp_expired) ve eski "Token has expired or is invalid".
  if (code === "otp_expired" || msg.includes("invalid or has expired") || msg.includes("expired or is invalid")) {
    return "expired";
  }
  if (code.includes("rate_limit") || msg.includes("rate limit") || msg.includes("too many") || msg.includes("once every") || msg.includes("429")) {
    return "rate";
  }
  if (msg.includes("failed to fetch") || msg.includes("networkerror") || msg.includes("network request failed") || err?.name === "TypeError") {
    return "network";
  }
  return "other";
}

/** Telefon tarayıcısı mı (uygulamayı açma düğmesi yalnızca orada anlamlı). */
export function isMobileBrowser(userAgent) {
  return /Android|iPhone|iPad|iPod/i.test(userAgent || "");
}
