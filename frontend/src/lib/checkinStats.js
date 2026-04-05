/**
 * Günlük check-in geçmişi (localStorage) — profilde seri ve rutin sadakati için.
 */

import { getRoutineSnapshot } from "./routineTracking";
import { DEMO_USER_ID } from "./demoUser";

export const ROUTINE_STREAK_GOAL_DAYS = 30;

function logKey(userId) {
  return `rebi_checkin_log_${userId}`;
}

/** Başarılı check-in sonrası çağır (aynı gün tekrar gönderilirse güncellenir). */
export function recordCheckInSuccess(userId, { appliedRoutine }) {
  if (!userId || userId === DEMO_USER_ID) return;
  try {
    const today = new Date().toISOString().slice(0, 10);
    const raw = localStorage.getItem(logKey(userId));
    let arr = [];
    if (raw) {
      const p = JSON.parse(raw);
      if (Array.isArray(p)) arr = p;
    }
    arr = arr.filter((x) => x && x.d !== today);
    arr.push({ d: today, applied: Boolean(appliedRoutine) });
    arr.sort((a, b) => String(b.d).localeCompare(String(a.d)));
    if (arr.length > 120) arr = arr.slice(0, 120);
    localStorage.setItem(logKey(userId), JSON.stringify(arr));
  } catch {
    /* ignore */
  }
}

export function getCheckInLog(userId) {
  if (!userId) return [];
  try {
    const raw = localStorage.getItem(logKey(userId));
    if (!raw) return [];
    const p = JSON.parse(raw);
    return Array.isArray(p) ? p.filter((x) => x && typeof x.d === "string") : [];
  } catch {
    return [];
  }
}

function ymdToday() {
  return new Date().toISOString().slice(0, 10);
}

function ymdAddDays(ymd, delta) {
  const [y, m, d] = ymd.split("-").map(Number);
  const dt = new Date(y, m - 1, d);
  dt.setDate(dt.getDate() + delta);
  const yy = dt.getFullYear();
  const mm = String(dt.getMonth() + 1).padStart(2, "0");
  const dd = String(dt.getDate()).padStart(2, "0");
  return `${yy}-${mm}-${dd}`;
}

/** Takvim günü üst üste check-in (bugün veya dün ile başlayabilir). */
export function computeCheckInStreak(log) {
  if (!log.length) return 0;
  const days = new Set(log.map((x) => x.d));
  let start = ymdToday();
  if (!days.has(start)) {
    start = ymdAddDays(start, -1);
    if (!days.has(start)) return 0;
  }
  let streak = 0;
  let cur = start;
  while (days.has(cur)) {
    streak += 1;
    cur = ymdAddDays(cur, -1);
  }
  return streak;
}

export function getProfileRoutineStats(userId) {
  const snap = userId ? getRoutineSnapshot(userId) : null;
  const acceptedAt = snap?.acceptedAt ?? null;
  const log = getCheckInLog(userId);
  const streak = computeCheckInStreak(log);
  const appliedCount = log.filter((x) => x.applied).length;
  const appliedRatePercent =
    log.length > 0 ? Math.round((appliedCount / log.length) * 100) : null;
  const daysSinceAccept =
    typeof acceptedAt === "number" && acceptedAt > 0
      ? Math.max(0, Math.floor((Date.now() - acceptedAt) / 86400000))
      : null;
  const goalProgress = Math.min(100, Math.round((streak / ROUTINE_STREAK_GOAL_DAYS) * 100));

  return {
    streak,
    totalCheckIns: log.length,
    appliedRatePercent,
    goalDays: ROUTINE_STREAK_GOAL_DAYS,
    goalProgress,
    daysSinceAccept,
    hasAcceptedRoutine: Boolean(snap && Array.isArray(snap.routine) && snap.routine.length > 0),
  };
}
