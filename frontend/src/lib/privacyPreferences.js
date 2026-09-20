import { API_URL } from "./supabase";
import { apiAuthHeaders } from "./apiAuth";

async function request(path, options = {}) {
  const auth = await apiAuthHeaders();
  const response = await fetch(`${API_URL}${path}`, {
    ...options,
    headers: {
      ...(options.body ? { "Content-Type": "application/json" } : {}),
      ...auth,
      ...(options.headers || {}),
    },
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(data?.detail || "Gizlilik tercihi işlemi başarısız.");
  return data;
}

export function getPrivacyPreferences(userId) {
  return request(`/privacy-preferences?user_id=${encodeURIComponent(userId)}`);
}

export function updatePrivacyPreferences(userId, { location, photo }) {
  return request("/privacy-preferences", {
    method: "POST",
    body: JSON.stringify({
      user_id: userId,
      ai_processing_allowed: true,
      location_processing_allowed: Boolean(location),
      photo_processing_allowed: Boolean(photo),
    }),
  });
}
