import { useState } from "react";
import { useLocation, useNavigate } from "react-router-dom";
import { useAuth } from "../context/AuthContext";
import { Leaf, Mail, Lock, User, Eye, EyeOff, ArrowRight, AlertCircle, Info } from "lucide-react";
import { useTranslation } from "react-i18next";
import LegalConsentFields from "../components/LegalConsentFields";
import { recordLegalConsent, stashPendingConsent } from "../lib/legalConsent";
import { safeNext } from "../lib/safeNext";

/** Google'dan hatayla dönüldüyse (vazgeçildi, hesap reddedildi) Supabase nedeni adrese yazar. */
function oauthErrorInUrl() {
  if (typeof window === "undefined") return false;
  const query = new URLSearchParams(window.location.search || "");
  const hash = new URLSearchParams((window.location.hash || "").replace(/^#/, ""));
  return Boolean(query.get("error") || hash.get("error"));
}

function GoogleLogo() {
  return (
    <svg viewBox="0 0 48 48" className="w-5 h-5 shrink-0" aria-hidden="true">
      <path fill="#EA4335" d="M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z" />
      <path fill="#4285F4" d="M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z" />
      <path fill="#FBBC05" d="M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z" />
      <path fill="#34A853" d="M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z" />
    </svg>
  );
}

export default function Auth() {
  const { t } = useTranslation();
  const [mode, setMode] = useState("login");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [fullName, setFullName] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(() => (oauthErrorInUrl() ? t("auth.googleFailed") : ""));
  const [googleLoading, setGoogleLoading] = useState(false);
  const [infoMessage, setInfoMessage] = useState("");
  const [kvkkOk, setKvkkOk] = useState(false);
  const [rizaOk, setRizaOk] = useState(false);
  const [locationOk, setLocationOk] = useState(false);
  const [photoOk, setPhotoOk] = useState(false);
  const { signIn, signUp, signInWithGoogle, signOut } = useAuth();
  const navigate = useNavigate();
  const location = useLocation();
  const next = safeNext(new URLSearchParams(location.search || "").get("next"));

  /** Onaylar burada da şart (e-posta ile aynı); dönüşte AuthContext sunucuya yazar. */
  const handleGoogle = async () => {
    setError("");
    setInfoMessage("");
    if (!kvkkOk || !rizaOk) {
      setError(t("auth.legalRequired"));
      return;
    }
    setGoogleLoading(true);
    stashPendingConsent({ location: locationOk, photo: photoOk });
    const { error: oauthError } = await signInWithGoogle(next);
    if (oauthError) {
      setError(t("auth.googleFailed"));
      setGoogleLoading(false);
    }
    // Başarılıysa sayfa Google'a gider; yükleniyor durumu ayrılana kadar kalır.
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    setError("");
    setInfoMessage("");
    setLoading(true);

    if (!kvkkOk || !rizaOk) {
      setError(t("auth.legalRequired"));
      setLoading(false);
      return;
    }

    try {
      if (mode === "login") {
        const { data, error } = await signIn(email, password);
        if (error) throw error;
        try {
          await recordLegalConsent(data?.user?.id, {
            ai: true,
            location: locationOk,
            photo: photoOk,
          });
        } catch (consentError) {
          await signOut();
          throw consentError;
        }
        navigate(next);
      } else {
        const { data, error, needsEmailConfirmation } = await signUp(
          email,
          password,
          fullName
        );
        if (error) throw error;
        if (needsEmailConfirmation) {
          setError("");
          setMode("login");
          setInfoMessage(
            "Kayıt alındı. E-postandaki onay linkine tıkladıktan sonra giriş yapabilirsin. Posta gelmediyse spam klasörüne bak."
          );
          return;
        }
        try {
          await recordLegalConsent(data?.user?.id, {
            ai: true,
            location: locationOk,
            photo: photoOk,
          });
        } catch (consentError) {
          await signOut();
          throw consentError;
        }
        navigate(next);
      }
    } catch (err) {
      const raw = err?.message || String(err);
      const lower = String(raw || "").toLowerCase();
      const isNetwork =
        raw === "Failed to fetch" ||
        raw.includes("NetworkError") ||
        err?.name === "TypeError";
      if (isNetwork) {
        setError(
          "Sunucuya bağlanılamadı (Failed to fetch). Kontrol et: internet / VPN; " +
            "Supabase Dashboard → Project Settings → API ile .env içindeki VITE_SUPABASE_URL ve VITE_SUPABASE_ANON_KEY aynı mı; " +
            ".env değiştirdiysen `npm run dev` sunucusunu durdurup yeniden başlat. " +
            "Ayrıntı için tarayıcıda F12 → Ağ (Network) sekmesi."
        );
      } else if (
        lower.includes("rate limit") ||
        lower.includes("too many") ||
        lower.includes("exceeded") ||
        lower.includes("quota") ||
        lower.includes("429")
      ) {
        setError(
          "Kısa süre içinde çok fazla deneme yapıldığı için geçici olarak sınır aşıldı. " +
            "1-2 dakika bekleyip tekrar dener misin? Devam ederse VPN / kurumsal ağ kullanıyorsan kapatıp dene."
        );
      } else {
        setError(raw || "Bir hata oluştu");
      }
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen bg-gradient-to-b from-teal-50 to-white flex items-center justify-center px-4 py-12">
      <div className="w-full max-w-md">
        {/* Logo */}
        <div className="text-center mb-8">
          <div className="w-16 h-16 bg-gradient-to-br from-teal-500 to-teal-600 rounded-2xl flex items-center justify-center mx-auto mb-4 shadow-xl shadow-teal-500/20">
            <Leaf className="w-8 h-8 text-white" />
          </div>
          <h1 className="text-2xl font-bold text-gray-900">
            {mode === "login" ? t("auth.welcome") : t("auth.createAccount")}
          </h1>
          <p className="text-gray-500 mt-1">
            {mode === "login"
              ? t("auth.loginToAccount")
              : t("auth.createFreeAccount")}
          </p>
        </div>

        {/* Card */}
        <div className="card">
          {infoMessage && (
            <div className="flex items-start gap-2 bg-teal-50 text-teal-900 p-3 rounded-xl mb-4 text-sm border border-teal-100">
              <Info className="w-4 h-4 shrink-0 mt-0.5" />
              <span>{infoMessage}</span>
            </div>
          )}
          {error && (
            <div className="flex items-center gap-2 bg-red-50 text-red-600 p-3 rounded-xl mb-4 text-sm">
              <AlertCircle className="w-4 h-4 shrink-0" />
              {error}
            </div>
          )}

          <form onSubmit={handleSubmit} className="space-y-4">
            {mode === "signup" && (
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1.5">
                  {t("auth.fullName")}
                </label>
                <div className="relative">
                  <User className="absolute left-3.5 top-1/2 -translate-y-1/2 w-5 h-5 text-gray-400" />
                  <input
                    type="text"
                    value={fullName}
                    onChange={(e) => setFullName(e.target.value)}
                    className="input-field !pl-11"
                    placeholder="Adın Soyadın"
                    required
                  />
                </div>
              </div>
            )}

            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1.5">
                {t("auth.email")}
              </label>
              <div className="relative">
                <Mail className="absolute left-3.5 top-1/2 -translate-y-1/2 w-5 h-5 text-gray-400" />
                <input
                  type="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  className="input-field !pl-11"
                  placeholder="ornek@email.com"
                  required
                />
              </div>
            </div>

            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1.5">
                {t("auth.password")}
              </label>
              <div className="relative">
                <Lock className="absolute left-3.5 top-1/2 -translate-y-1/2 w-5 h-5 text-gray-400" />
                <input
                  type={showPassword ? "text" : "password"}
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  className="input-field !pl-11 !pr-11"
                  placeholder="••••••••"
                  required
                  minLength={6}
                />
                <button
                  type="button"
                  onClick={() => setShowPassword(!showPassword)}
                  className="absolute right-3.5 top-1/2 -translate-y-1/2 text-gray-400 hover:text-gray-600"
                >
                  {showPassword ? (
                    <EyeOff className="w-5 h-5" />
                  ) : (
                    <Eye className="w-5 h-5" />
                  )}
                </button>
              </div>
            </div>

            <LegalConsentFields
              kvkk={kvkkOk}
              riza={rizaOk}
              location={locationOk}
              photo={photoOk}
              onKvkk={setKvkkOk}
              onRiza={setRizaOk}
              onLocation={setLocationOk}
              onPhoto={setPhotoOk}
            />

            <button
              type="submit"
              disabled={loading || !kvkkOk || !rizaOk}
              className="btn-primary w-full !mt-6"
            >
              {loading ? (
                <div className="w-5 h-5 border-2 border-white/30 border-t-white rounded-full animate-spin" />
              ) : (
                <>
                  {mode === "login" ? t("auth.login") : t("auth.signup")}
                  <ArrowRight className="w-5 h-5" />
                </>
              )}
            </button>
          </form>

          <div className="flex items-center gap-3 my-5" aria-hidden="true">
            <div className="h-px flex-1 bg-gray-200" />
            <span className="text-xs font-medium text-gray-400">{t("auth.or")}</span>
            <div className="h-px flex-1 bg-gray-200" />
          </div>

          <button
            type="button"
            onClick={handleGoogle}
            disabled={loading || googleLoading || !kvkkOk || !rizaOk}
            className="w-full flex items-center justify-center gap-3 rounded-xl border border-gray-300 bg-white px-4 py-3 font-semibold text-gray-800 transition hover:bg-gray-50 disabled:opacity-50 disabled:cursor-not-allowed"
          >
            {googleLoading ? (
              <div className="w-5 h-5 border-2 border-gray-300 border-t-gray-700 rounded-full animate-spin" />
            ) : (
              <>
                <GoogleLogo />
                {t("auth.google")}
              </>
            )}
          </button>

          <p className="text-center text-sm text-gray-500 mt-6">
            {mode === "login" ? (
              <>
                {t("auth.haveNoAccount")}{" "}
                <button
                  onClick={() => { setMode("signup"); setError(""); setInfoMessage(""); }}
                  className="text-teal-600 font-semibold hover:underline"
                >
                  {t("auth.signup")}
                </button>
              </>
            ) : (
              <>
                {t("auth.haveAccount")}{" "}
                <button
                  onClick={() => { setMode("login"); setError(""); setInfoMessage(""); }}
                  className="text-teal-600 font-semibold hover:underline"
                >
                  {t("auth.login")}
                </button>
              </>
            )}
          </p>
        </div>
      </div>
    </div>
  );
}
