/** Remove browser-side personal data associated with one account. */
export function clearUserLocalData(userId) {
  if (!userId) return;
  const keys = [
    `rebi-chat-history_${userId}`,
    `rebi-chat-usage_${userId}`,
    `rebi_track_accepted_${userId}`,
    `rebi_track_snapshot_${userId}`,
    `rebi_checkin_log_${userId}`,
    `rebi_legal_consent_v2_${userId}`,
    `rebi_legal_consent_v1_${userId}`,
  ];
  try {
    for (const key of keys) localStorage.removeItem(key);
    // Remove the legacy non-user-scoped chat key during the transition.
    localStorage.removeItem("rebi-chat-history");
  } catch {
    /* localStorage may be unavailable; server deletion still proceeds. */
  }
}
