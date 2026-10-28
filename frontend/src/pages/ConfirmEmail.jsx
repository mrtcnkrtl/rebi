import { useState } from "react";
import { Link, useLocation, useNavigate } from "react-router-dom";
import { useTranslation } from "react-i18next";
import {
  AlertCircle,
  ArrowRight,
  Info,
  Leaf,
  LoaderCircle,
  MailCheck,
  MailWarning,
  Smartphone,
  TriangleAlert,
} from "lucide-react";
import { supabase } from "../lib/supabase";
import {
  APP_DEEP_LINK,
  classifyConfirmError,
  isMobileBrowser,
  parseConfirmParams,
} from "../lib/emailConfirm";

/**
 * E-posta onayı: e-postadaki düğme buraya gelir (`/auth/confirm?token_hash=…&type=signup`).
 * Sayfa açılırken hiçbir istek atılmaz; Supabase'in tek kullanımlık token'ı yalnızca kullanıcı
 * "E-postamı onayla"ya dokununca doğrulanır (bağlantı tarayıcıları token'ı tüketemesin diye).
 */
export default function ConfirmEmail() {
  const { t } = useTranslation();
  const location = useLocation();
  const navigate = useNavigate();
  const params = parseConfirmParams(location.search);
  // idle → verifying → done | expired | failed
  const [phase, setPhase] = useState("idle");
  const [failure, setFailure] = useState("other");
  const [email, setEmail] = useState("");
  const [resending, setResending] = useState(false);
  const [resendNote, setResendNote] = useState("");
  const [resendError, setResendError] = useState("");
  const mobile = isMobileBrowser(typeof navigator === "undefined" ? "" : navigator.userAgent);

  const verify = async () => {
    if (!params || !supabase) return;
    setPhase("verifying");
    const { error } = await supabase.auth.verifyOtp({ token_hash: params.tokenHash, type: params.type });
    if (error) {
      const kind = classifyConfirmError(error);
      setFailure(kind);
      setPhase(kind === "expired" ? "expired" : "failed");
      return;
    }
    // Token tüketildi: adres çubuğunda ve geçmişte durmasın.
    window.history.replaceState(null, "", location.pathname);
    setPhase("done");
  };

  const resend = async (e) => {
    e.preventDefault();
    if (!supabase || !email.trim()) return;
    setResending(true);
    setResendNote("");
    setResendError("");
    const { error } = await supabase.auth.resend({ type: "signup", email: email.trim() });
    setResending(false);
    if (!error) {
      setResendNote(t("authConfirm.resendSent"));
      return;
    }
    const kind = classifyConfirmError(error);
    setResendError(
      kind === "rate" ? t("authConfirm.errRate") : kind === "network" ? t("authConfirm.errNetwork") : t("authConfirm.errResend"),
    );
  };

  let icon = <MailCheck className="w-8 h-8 text-white" />;
  let tone = "from-teal-500 to-teal-600 shadow-teal-500/20";
  let title = t("authConfirm.readyTitle");
  let body = t("authConfirm.readyBody");
  if (!params || !supabase) {
    icon = <MailWarning className="w-8 h-8 text-white" />;
    tone = "from-amber-500 to-amber-600 shadow-amber-500/20";
    title = t("authConfirm.missingTitle");
    body = t("authConfirm.missingBody");
  } else if (phase === "done") {
    title = t("authConfirm.doneTitle");
    body = t("authConfirm.doneBody");
  } else if (phase === "expired") {
    icon = <TriangleAlert className="w-8 h-8 text-white" />;
    tone = "from-amber-500 to-amber-600 shadow-amber-500/20";
    title = t("authConfirm.expiredTitle");
    body = t("authConfirm.expiredBody");
  } else if (phase === "failed") {
    icon = <TriangleAlert className="w-8 h-8 text-white" />;
    tone = "from-red-500 to-red-600 shadow-red-500/20";
    title = t("authConfirm.failedTitle");
    body = failure === "network" ? t("authConfirm.errNetwork") : failure === "rate" ? t("authConfirm.errRate") : t("authConfirm.failedBody");
  }

  return (
    <div className="min-h-screen bg-gradient-to-b from-teal-50 to-white flex items-center justify-center px-4 py-12">
      <div className="w-full max-w-md">
        <div className="text-center mb-8">
          <div className={`w-16 h-16 bg-gradient-to-br ${tone} rounded-2xl flex items-center justify-center mx-auto mb-4 shadow-xl`}>
            {icon}
          </div>
          <h1 className="text-2xl font-bold text-gray-900">{title}</h1>
          <p className="text-gray-600 mt-2 leading-relaxed" role="status">
            {body}
          </p>
        </div>

        <div className="card space-y-3">
          {(!params || !supabase) && (
            <Link to="/auth" className="btn-primary w-full">
              {t("authConfirm.goLogin")}
              <ArrowRight className="w-5 h-5" />
            </Link>
          )}

          {params && supabase && (phase === "idle" || phase === "verifying") && (
            <>
              <button type="button" onClick={verify} disabled={phase === "verifying"} className="btn-primary w-full">
                {phase === "verifying" ? (
                  <>
                    <LoaderCircle className="w-5 h-5 animate-spin" />
                    {t("authConfirm.verifying")}
                  </>
                ) : (
                  <>
                    {t("authConfirm.confirmButton")}
                    <ArrowRight className="w-5 h-5" />
                  </>
                )}
              </button>
              <p className="flex items-start gap-2 text-sm text-gray-500">
                <Info className="w-4 h-4 shrink-0 mt-0.5" />
                {t("authConfirm.readyHint")}
              </p>
            </>
          )}

          {phase === "done" && (
            <>
              {mobile && (
                <a href={APP_DEEP_LINK} className="btn-primary w-full">
                  <Smartphone className="w-5 h-5" />
                  {t("authConfirm.openApp")}
                </a>
              )}
              <button
                type="button"
                onClick={() => navigate("/dashboard")}
                className={mobile ? "w-full py-3 rounded-2xl border-2 border-gray-200 font-semibold text-gray-700 hover:bg-gray-50 min-h-[48px]" : "btn-primary w-full"}
              >
                {t("authConfirm.continueWeb")}
              </button>
              {mobile && (
                <p className="flex items-start gap-2 text-sm text-gray-500">
                  <Info className="w-4 h-4 shrink-0 mt-0.5" />
                  {t("authConfirm.appHint")}
                </p>
              )}
            </>
          )}

          {phase === "expired" && (
            <>
              <Link to="/auth" className="btn-primary w-full">
                {t("authConfirm.goLogin")}
                <ArrowRight className="w-5 h-5" />
              </Link>
              <form onSubmit={resend} className="pt-3 mt-1 border-t border-gray-100 space-y-3">
                <label htmlFor="confirm-email" className="block text-sm font-medium text-gray-700">
                  {t("authConfirm.resendLabel")}
                </label>
                <input
                  id="confirm-email"
                  type="email"
                  autoComplete="email"
                  required
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  className="input-field"
                  placeholder="ornek@email.com"
                />
                <button
                  type="submit"
                  disabled={resending || !email.trim()}
                  className="w-full py-3 rounded-2xl border-2 border-teal-600 text-teal-700 font-semibold hover:bg-teal-50 disabled:opacity-50 min-h-[48px] flex items-center justify-center gap-2"
                >
                  {resending && <LoaderCircle className="w-5 h-5 animate-spin" />}
                  {t("authConfirm.resendButton")}
                </button>
                {resendNote && (
                  <div className="flex items-start gap-2 bg-teal-50 text-teal-900 p-3 rounded-xl text-sm border border-teal-100" role="status">
                    <Info className="w-4 h-4 shrink-0 mt-0.5" />
                    <span>{resendNote}</span>
                  </div>
                )}
                {resendError && (
                  <div className="flex items-start gap-2 bg-red-50 text-red-600 p-3 rounded-xl text-sm" role="alert">
                    <AlertCircle className="w-4 h-4 shrink-0 mt-0.5" />
                    <span>{resendError}</span>
                  </div>
                )}
              </form>
            </>
          )}

          {phase === "failed" && (
            <>
              <button type="button" onClick={verify} className="btn-primary w-full">
                {t("authConfirm.retry")}
              </button>
              <Link to="/auth" className="block text-center text-teal-600 font-semibold hover:underline pt-1">
                {t("authConfirm.goLogin")}
              </Link>
            </>
          )}
        </div>
      </div>
    </div>
  );
}
