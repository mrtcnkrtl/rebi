/** Rebi Plus ön bilgilendirme ve mesafeli satış onayı. Kanıt backend tablosundadır. */

import { API_URL } from "./supabase";
import { apiAuthHeaders } from "./apiAuth";

export const SALES_CONSENT_VERSION = "v1";

export async function recordSalesConsent(userId) {
  if (!userId) throw new Error("Ödeme onayı için kullanıcı oturumu bulunamadı.");
  const auth = await apiAuthHeaders();
  const response = await fetch(`${API_URL}/sales-consent/accept`, {
    method: "POST",
    headers: { "Content-Type": "application/json", ...auth },
    body: JSON.stringify({
      user_id: userId,
      document_version: SALES_CONSENT_VERSION,
      pre_info_accepted: true,
      distance_contract_accepted: true,
    }),
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(data?.detail || "Ödeme onayı kaydedilemedi.");
  }
  return data;
}
