import { createClient } from "@supabase/supabase-js";

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL || "";
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY || "";

export const supabase = supabaseUrl
  ? createClient(supabaseUrl, supabaseAnonKey)
  : null;

/**
 * API tabanı: build-time VITE_API_URL + güvenlik filesi.
 * Eski production build'lerde localhost gömülüyse canlı domainde istekler ölür; burada düzeltiyoruz.
 */
function computeApiBaseUrl() {
  const raw = (import.meta.env.VITE_API_URL || "").trim().replace(/\/$/, "");
  if (typeof window === "undefined") {
    return raw || "/api";
  }
  const host = window.location.hostname;
  const isLocal =
    host === "localhost" ||
    host === "127.0.0.1" ||
    host === "[::1]" ||
    host.endsWith(".local");
  if (!isLocal) {
    const bad =
      !raw ||
      raw.includes("localhost") ||
      raw.includes("127.0.0.1") ||
      raw.startsWith("http://0.0.0.0");
    if (bad) {
      return `${window.location.origin}/api`;
    }
  }
  return raw || "/api";
}

export const API_URL = computeApiBaseUrl();
