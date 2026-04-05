/** Kalıcı rutin takibi: kullanıcı rutini kabul edince snapshot + bayrak. */

export function trackAcceptedKey(userId) {
  return `rebi_track_accepted_${userId}`;
}

export function trackSnapshotKey(userId) {
  return `rebi_track_snapshot_${userId}`;
}

export function isRoutineTrackingAccepted(userId) {
  if (!userId) return false;
  try {
    return localStorage.getItem(trackAcceptedKey(userId)) === "1";
  } catch {
    return false;
  }
}

export function getRoutineSnapshot(userId) {
  if (!userId) return null;
  try {
    const raw = localStorage.getItem(trackSnapshotKey(userId));
    if (!raw) return null;
    const parsed = JSON.parse(raw);
    return typeof parsed === "object" && parsed ? parsed : null;
  } catch {
    return null;
  }
}

/** Mevcut snapshot ile birleştirir (routine ve check-in sonrası güncelleme için). */
export function saveRoutineSnapshot(userId, partial) {
  if (!userId) return;
  try {
    const prev = getRoutineSnapshot(userId) || {};
    const next = { ...prev, ...partial, updatedAt: Date.now() };
    localStorage.setItem(trackSnapshotKey(userId), JSON.stringify(next));
  } catch {
    /* ignore quota */
  }
}

/** Rutini kabul: tam dashboard meta + rutin satırı. */
export function acceptRoutineTracking(userId, snapshot) {
  if (!userId) return;
  const prev = getRoutineSnapshot(userId) || {};
  const merged = {
    ...snapshot,
    /** İlk kabul zamanı (profil: hedef gün / yolculuk süresi). */
    acceptedAt: typeof prev.acceptedAt === "number" ? prev.acceptedAt : Date.now(),
    updatedAt: Date.now(),
  };
  saveRoutineSnapshot(userId, merged);
  try {
    localStorage.setItem(trackAcceptedKey(userId), "1");
  } catch {
    /* ignore */
  }
}

/** İlk analiz tamamlandıysa (kayıtlı rutin veya kabul bayrağı) uzun sihirbaz göstermeyi atla. */
export function hasCompletedOnboarding(userId) {
  if (!userId) return false;
  if (isRoutineTrackingAccepted(userId)) return true;
  const s = getRoutineSnapshot(userId);
  return Array.isArray(s?.routine) && s.routine.length > 0;
}
