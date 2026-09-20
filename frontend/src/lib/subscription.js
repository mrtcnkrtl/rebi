const PLUS_TIERS = new Set([
  "plus",
  "pro",
  "premium",
  "plus_1000",
  "plus_lite",
  "plus_basic",
  "plus_starter",
]);

/** Subscription entitlements must come from server-controlled app_metadata. */
export function userHasRebiPlus(user) {
  const meta = user?.app_metadata || {};
  return meta.rebi_plus === true ||
    PLUS_TIERS.has(String(meta.subscription_tier || "").toLowerCase());
}
