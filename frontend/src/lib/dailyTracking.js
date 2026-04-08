import { DEMO_USER_ID } from "./demoUser";
import { apiAuthHeaders } from "./apiAuth";
import { API_URL } from "./supabase";

const API = API_URL;

/**
 * Gün içi olay: Supabase daily_events (backend ingest). Demo kullanıcıda atlanır.
 */
export async function ingestDailyTrackingEvent(userId, type, payload = {}, source = "web") {
  if (!userId || userId === DEMO_USER_ID) {
    return { ok: true, skipped: true };
  }
  try {
    const auth = await apiAuthHeaders();
    const res = await fetch(`${API}/daily_tracking/ingest`, {
      method: "POST",
      headers: { "Content-Type": "application/json", ...auth },
      body: JSON.stringify({
        user_id: userId,
        type,
        payload: payload && typeof payload === "object" ? payload : {},
        source,
      }),
    });
    const data = await res.json().catch(() => ({}));
    return { ok: res.ok, data };
  } catch {
    return { ok: false };
  }
}
