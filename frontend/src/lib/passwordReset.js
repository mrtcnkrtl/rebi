/**
 * Parola sıfırlama sayfasının (`/auth/reset`) yardımcıları.
 *
 * Sıfırlama e-postasında 6 haneli kod (uygulamaya yazılır) ve bu sayfaya giden bir düğme vardır. Düğme Supabase'in
 * tek kullanımlık `/auth/v1/verify` bağlantısına gitmez: e-posta uygulamaları ve antivirüsler bağlantıyı önceden
 * açıp tüketebildiği için kullanıcı tıkladığında "bağlantı geçersiz" görüyordu. Bu sayfa açılınca hiçbir istek
 * atmaz; token yalnızca kullanıcı "Devam et"e dokununca doğrulanır.
 */

/** `?token_hash=…&type=recovery` → doğrulanabilir parametreler ya da null (eksik / başka tür). */
export function parseResetParams(search) {
  const q = new URLSearchParams(search || "");
  const tokenHash = (q.get("token_hash") || "").trim();
  const type = (q.get("type") || "recovery").trim().toLowerCase();
  if (!tokenHash || type !== "recovery") return null;
  return { tokenHash, type };
}

/** Parola kuralı: uygulamayla ve Supabase ayarıyla aynı (en az 6 karakter). */
export const MIN_PASSWORD_LENGTH = 6;

/**
 * Yeni parola formunun hatası (yoksa ""): `short` (çok kısa) ya da `mismatch` (tekrar aynı değil).
 */
export function validateNewPassword(password, repeat) {
  if ((password || "").length < MIN_PASSWORD_LENGTH) return "short";
  if (password !== repeat) return "mismatch";
  return "";
}

/** Supabase'in parola reddi (zayıf / sızdırılmış / eskisiyle aynı) mı. */
export function isWeakPasswordError(err) {
  const code = String(err?.code || "").toLowerCase();
  const msg = String(err?.message || err || "").toLowerCase();
  return code === "weak_password" || code === "same_password" || msg.includes("weak") || msg.includes("pwned") || msg.includes("should be different");
}
