import { supabase } from "./supabase";

/**
 * FastAPI çağrılarında kullanılmak üzere Authorization başlığı.
 * SUPABASE_JWT_SECRET açıkken backend Bearer token bekler.
 */
export async function apiAuthHeaders() {
  if (!supabase) return {};
  let {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session?.access_token) {
    const { data } = await supabase.auth.refreshSession();
    session = data.session;
  }
  if (!session?.access_token) return {};
  return { Authorization: `Bearer ${session.access_token}` };
}
