/** Mağaza adresleri (docs/MOBIL-MAGAZA-VARLIKLARI.md). Tek yerde durur; ana sayfa, menü ve /indir aynı adresi kullanır. */
export const APP_STORE_URL = "https://apps.apple.com/app/id6566180620";
export const PLAY_STORE_URL = "https://play.google.com/store/apps/details?id=com.rebiovil.mobile";

export const STORES = {
  ios: { id: "ios", url: APP_STORE_URL, name: "App Store", topKey: "landing.storeIosTop" },
  android: { id: "android", url: PLAY_STORE_URL, name: "Google Play", topKey: "landing.storeAndroidTop" },
};

/** Ziyaretçinin cihazı: "ios" | "android" | "desktop". iPadOS kendini Mac olarak tanıtır; dokunmatik Mac'i iPad sayarız. */
export function detectPlatform() {
  if (typeof navigator === "undefined") return "desktop";
  const ua = navigator.userAgent || "";
  if (/android/i.test(ua)) return "android";
  if (/iPhone|iPad|iPod/i.test(ua)) return "ios";
  if (/Macintosh/i.test(ua) && navigator.maxTouchPoints > 1) return "ios";
  return "desktop";
}

/** Ziyaretçinin kendi mağazası önce gelir; masaüstünde App Store, Google Play sırası. */
export function orderedStores(platform = detectPlatform()) {
  return platform === "android" ? [STORES.android, STORES.ios] : [STORES.ios, STORES.android];
}
