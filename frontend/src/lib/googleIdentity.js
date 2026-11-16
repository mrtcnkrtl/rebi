/**
 * Google Identity Services (GIS) ile tarayıcıda kalan Google girişi.
 *
 * Supabase'in yönlendirmeli OAuth akışında Google hesap seçme ekranı "<proje>.supabase.co uygulamasına devam
 * edin" der. GIS penceresi ise sitenin kendi adresini (rebiovil.com) ve Google Cloud'daki uygulama adını gösterir;
 * dönen kimlik belgesi (ID token) Supabase'e `signInWithIdToken` ile verilir.
 *
 * Pencere gösterilemezse (üçüncü taraf çerezleri / FedCM kapalı, Google'ın bekleme süresi, betik yüklenemedi)
 * `{ fallback: true }` döner ve çağıran eski yönlendirmeli akışa geçer.
 */

export const GOOGLE_WEB_CLIENT_ID =
  import.meta.env.VITE_GOOGLE_CLIENT_ID ||
  "298921260735-4eon5rievvv859s5lksqs4au2iav0vvl.apps.googleusercontent.com";

const GIS_SRC = "https://accounts.google.com/gsi/client";
let scriptPromise = null;

function loadGis() {
  if (typeof window === "undefined") return Promise.reject(new Error("no-window"));
  if (window.google?.accounts?.id) return Promise.resolve(window.google.accounts.id);
  if (!scriptPromise) {
    scriptPromise = new Promise((resolve, reject) => {
      const s = document.createElement("script");
      s.src = GIS_SRC;
      s.async = true;
      s.defer = true;
      s.onload = () => (window.google?.accounts?.id ? resolve(window.google.accounts.id) : reject(new Error("gis-missing")));
      s.onerror = () => reject(new Error("gis-load"));
      document.head.appendChild(s);
    }).catch((e) => {
      scriptPromise = null;
      throw e;
    });
  }
  return scriptPromise;
}

function randomNonce() {
  const bytes = new Uint8Array(16);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
}

async function sha256Hex(text) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, "0")).join("");
}

/** Kullanıcının kendi kapattığı durumlar: hata değildir, yönlendirmeli akışa da geçilmez. */
const USER_CLOSED = new Set(["user_cancel", "tap_outside", "cancel_called"]);

/**
 * GIS penceresini açar.
 * @returns {Promise<{ idToken: string, nonce: string } | { canceled: true } | { fallback: true, reason: string }>}
 */
export async function promptGoogleIdToken() {
  if (!GOOGLE_WEB_CLIENT_ID || typeof crypto?.subtle?.digest !== "function") {
    return { fallback: true, reason: "unsupported" };
  }
  let gis;
  try {
    gis = await loadGis();
  } catch (e) {
    return { fallback: true, reason: e?.message || "gis-load" };
  }
  const nonce = randomNonce();
  // Google belgeye özetlenmiş değeri yazar; Supabase ham değeri alıp karşılaştırır.
  const hashedNonce = await sha256Hex(nonce);

  const startedAt = Date.now();
  return new Promise((resolve) => {
    let settled = false;
    const done = (value) => {
      if (settled) return;
      settled = true;
      clearTimeout(guard);
      resolve(value);
    };
    // Google hiç haber vermezse düğme sonsuza dek "yükleniyor"da kalmasın.
    const guard = setTimeout(() => done({ canceled: true }), 120000);
    gis.initialize({
      client_id: GOOGLE_WEB_CLIENT_ID,
      nonce: hashedNonce,
      callback: (response) =>
        response?.credential ? done({ idToken: response.credential, nonce }) : done({ fallback: true, reason: "no-credential" }),
      auto_select: false,
      cancel_on_tap_outside: true,
      context: "signin",
      itp_support: true,
      use_fedcm_for_prompt: true,
    });
    gis.prompt((n) => {
      if (n.isNotDisplayed?.()) {
        done({ fallback: true, reason: n.getNotDisplayedReason?.() || "not-displayed" });
      } else if (n.isSkippedMoment?.()) {
        const reason = n.getSkippedReason?.() || "skipped";
        // Çok hızlı "kapatıldı" = pencere hiç görünmedi (Google'ın kapatma sonrası bekleme süresi): kullanıcı
        // düğmeye bastı ama hiçbir şey açılmasın diye yönlendirmeli akışa geçilir.
        const instant = Date.now() - startedAt < 1000;
        done(USER_CLOSED.has(reason) && !instant ? { canceled: true } : { fallback: true, reason });
      } else if (n.isDismissedMoment?.() && n.getDismissedReason?.() !== "credential_returned") {
        done({ canceled: true });
      }
    });
  });
}
