/**
 * Kullanıcının kendi rutin düzenlemeleri (sunucu: `backend/routine_edits.py`,
 * mobil: `mobile/lib/core/routine_edits.dart`).
 *
 * Rebi'nin ürettiği adımların metni istemciden değiştirilemez. Kullanıcı iki şey yapar:
 * yapmayacağı adımı plandan çıkarır (silinmez, geri alınabilir) ve kendi adımını ekler
 * (`source: "user"`; Rebi'nin önerisi gibi gösterilmez).
 */

import { API_URL } from "./supabase";
import { apiAuthHeaders } from "./apiAuth";
import { formatApiErrorDetail } from "./apiErrors";

/** Kullanıcı en çok bu kadar kendi adımını ekleyebilir (sunucu da aynı sayıda keser). */
export const MAX_USER_STEPS = 10;
export const MAX_USER_STEP_ACTION_CHARS = 90;
export const MAX_USER_STEP_DETAIL_CHARS = 240;

/** Kullanıcının kendi adımına verilebilecek zamanlar (sunucu `_USER_TIMES`). */
export const USER_STEP_TIMES = ["Sabah", "Akşam", "Günlük"];

/** Bir adımın kalıcı kimliği — sunucudaki `step_key` ile aynı kural. */
export function routineStepKey(item) {
  const time = String(item?.time ?? "").trim();
  const order = item?.step_order == null ? "" : String(item.step_order);
  const action = String(item?.action ?? "").trim();
  return `${time}|${order}|${action}`;
}

export function isUserStep(item) {
  return String(item?.source ?? "") === "user";
}

export function isSkippedByUser(item) {
  return item?.skipped_by_user === true;
}

/**
 * Kullanıcının plandan çıkardığı adımlar hiçbir görünüme girmez. Sunucu da bunları
 * `/today/plan` ve `/me/snapshot` yanıtlarından ayıklar; bu süzgeç tarayıcıdaki eski
 * kopyalar ve çevrimdışı durumlar için ikinci güvencedir.
 */
export function activeRoutineItems(items) {
  return (Array.isArray(items) ? items : []).filter((i) => !isSkippedByUser(i));
}

export function splitUserEdits(items) {
  const rows = Array.isArray(items) ? items : [];
  return {
    active: rows.filter((i) => !isSkippedByUser(i)),
    skipped: rows.filter(isSkippedByUser),
  };
}

function normalizeUserStep(item) {
  return {
    action: String(item?.action ?? ""),
    time: USER_STEP_TIMES.includes(item?.time) ? item.time : "Sabah",
    detail: String(item?.detail ?? ""),
  };
}

/** `GET /routine/active`: yürürlükteki rutin + kullanıcının çıkardıkları. */
export async function fetchRoutineWithSkipped(userId) {
  const auth = await apiAuthHeaders();
  const res = await fetch(`${API_URL}/routine/active?user_id=${encodeURIComponent(userId)}`, { headers: auth });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) return null;
  return {
    routine: Array.isArray(data.routine) ? data.routine : [],
    skipped: Array.isArray(data.skipped_steps) ? data.skipped_steps : [],
  };
}

/**
 * `PUT /routine/active`. [hidden] her zaman tam listedir: listede olmayan adımın işareti
 * kalkar, yani aynı çağrı hem çıkarmayı hem geri almayı anlatır.
 */
export async function saveRoutineEdits(userId, { hidden, added }) {
  const auth = await apiAuthHeaders();
  const res = await fetch(`${API_URL}/routine/active`, {
    method: "PUT",
    headers: { "Content-Type": "application/json", ...auth },
    body: JSON.stringify({
      user_id: userId,
      hidden: Array.from(hidden || []),
      added: (added || []).slice(0, MAX_USER_STEPS).map(normalizeUserStep),
    }),
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) return { error: formatApiErrorDetail(data) || `HTTP ${res.status}` };
  return {
    result: {
      routine: Array.isArray(data.routine) ? data.routine : [],
      skipped: Array.isArray(data.skipped_steps) ? data.skipped_steps : [],
    },
  };
}
