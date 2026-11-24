import { useState } from "react";
import { Link, useLocation, useNavigate } from "react-router-dom";
import { useTranslation } from "react-i18next";
import { AlertCircle, ArrowRight, Info, KeyRound, LoaderCircle, MailWarning, ShieldCheck, Smartphone, TriangleAlert } from "lucide-react";
import { supabase } from "../lib/supabase";
import { APP_DEEP_LINK, classifyConfirmError, isMobileBrowser } from "../lib/emailConfirm";
import { MIN_PASSWORD_LENGTH, isWeakPasswordError, parseResetParams, validateNewPassword } from "../lib/passwordReset";

/**
 * Parola sıfırlama: e-postadaki düğme buraya gelir (`/auth/reset?token_hash=…&type=recovery`).
 * Açılışta istek atılmaz; token yalnızca "Devam et"e dokununca doğrulanır (bağlantı tarayıcıları tüketemesin diye).
 * Doğrulanınca oturum açılır ve yeni parola yazılır. Uygulamada aynı e-postadaki 6 haneli kod kullanılır.
 */
export default function ResetPassword() {
  const { t } = useTranslation();
  const location = useLocation();
  const navigate = useNavigate();
  const params = parseResetParams(location.search);
  // idle → verifying → form → saving → done | expired | failed
  const [phase, setPhase] = useState("idle");
  const [failure, setFailure] = useState("other");
  const [password, setPassword] = useState("");
  const [repeat, setRepeat] = useState("");
  const [formError, setFormError] = useState("");
  const [email, setEmail] = useState("");
  const [sending, setSending] = useState(false);
  const [sendNote, setSendNote] = useState("");
  const [sendError, setSendError] = useState("");
  const mobile = isMobileBrowser(typeof navigator === "undefined" ? "" : navigator.userAgent);

  const verify = async () => {
    if (!params || !supabase) return;
    setPhase("verifying");
    const { error } = await supabase.auth.verifyOtp({ token_hash: params.tokenHash, type: "recovery" });
    if (error) {
      const kind = classifyConfirmError(error);
      setFailure(kind);
      setPhase(kind === "expired" ? "expired" : "failed");
      return;
    }
    // Token tüketildi: adres çubuğunda ve geçmişte durmasın.
    window.history.replaceState(null, "", location.pathname);
    setPhase("form");
  };

  const save = async (e) => {
    e.preventDefault();
    const invalid = validateNewPassword(password, repeat);
    if (invalid) {
      setFormError(invalid === "short" ? t("authReset.errShort", { n: MIN_PASSWORD_LENGTH }) : t("authReset.errMismatch"));
      return;
    }
    setFormError("");
    setPhase("saving");
    const { error } = await supabase.auth.updateUser({ password });
    if (error) {
      setPhase("form");
      const kind = classifyConfirmError(error);
      setFormError(
        isWeakPasswordError(error) ? t("authReset.errWeak") : kind === "network" ? t("authConfirm.errNetwork") : t("authReset.errSave"),
      );
      return;
    }
    setPassword("");
    setRepeat("");
    setPhase("done");
  };

  const requestNew = async (e) => {
    e.preventDefault();
    if (!supabase || !email.trim()) return;
    setSending(true);
    setSendNote("");
    setSendError("");
    const { error } = await supabase.auth.resetPasswordForEmail(email.trim());
    setSending(false);
    if (!error) {
      setSendNote(t("authReset.resendSent"));
      return;
    }
    const kind = classifyConfirmError(error);
    setSendError(kind === "rate" ? t("authConfirm.errRate") : kind === "network" ? t("authConfirm.errNetwork") : t("authConfirm.errResend"));
  };

  let icon = <KeyRound className="w-8 h-8 text-white" />;
  let tone = "from-teal-500 to-teal-600 shadow-teal-500/20";
  let title = t("authReset.readyTitle");
  let body = t("authReset.readyBody");
  if (!params || !supabase) {
    icon = <MailWarning className="w-8 h-8 text-white" />;
    tone = "from-amber-500 to-amber-600 shadow-amber-500/20";
    title = t("authReset.missingTitle");
    body = t("authReset.missingBody");
  } else if (phase === "form" || phase === "saving") {
    title = t("authReset.formTitle");
    body = t("authReset.formBody");
  } else if (phase === "done") {
    icon = <ShieldCheck className="w-8 h-8 text-white" />;
    title = t("authReset.doneTitle");
    body = t("authReset.doneBody");
  } else if (phase === "expired") {
    icon = <TriangleAlert className="w-8 h-8 text-white" />;
    tone = "from-amber-500 to-amber-600 shadow-amber-500/20";
    title = t("authReset.expiredTitle");
    body = t("authReset.expiredBody");
  } else if (phase === "failed") {
    icon = <TriangleAlert className="w-8 h-8 text-white" />;
    tone = "from-red-500 to-red-600 shadow-red-500/20";
    title = t("authReset.failedTitle");
    body = failure === "network" ? t("authConfirm.errNetwork") : failure === "rate" ? t("authConfirm.errRate") : t("authReset.failedBody");
  }

  const showRequestForm = !params || !supabase || phase === "expired";

  return (
    <div className="min-h-screen bg-gradient-to-b from-teal-50 to-white flex items-center justify-center px-4 py-12">
      <div className="w-full max-w-md">
        <div className="text-center mb-8">
          <div className={`w-16 h-16 bg-gradient-to-br ${tone} rounded-2xl flex items-center justify-center mx-auto mb-4 shadow-xl`}>{icon}</div>
          <h1 className="text-2xl font-bold text-gray-900">{title}</h1>
          <p className="text-gray-600 mt-2 leading-relaxed" role="status">
            {body}
          </p>
        </div>

        <div className="card space-y-3">
          {params && supabase && (phase === "idle" || phase === "verifying") && (
            <>
              <button type="button" onClick={verify} disabled={phase === "verifying"} className="btn-primary w-full">
                {phase === "verifying" ? (
                  <>
                    <LoaderCircle className="w-5 h-5 animate-spin" />
                    {t("authReset.verifying")}
                  </>
                ) : (
                  <>
                    {t("authReset.continue")}
                    <ArrowRight className="w-5 h-5" />
                  </>
                )}
              </button>
              <p className="flex items-start gap-2 text-sm text-gray-500">
                <Info className="w-4 h-4 shrink-0 mt-0.5" />
                {t("authReset.readyHint")}
              </p>
            </>
          )}

          {(phase === "form" || phase === "saving") && (
            <form onSubmit={save} className="space-y-3" noValidate>
              <label htmlFor="reset-password" className="block text-sm font-medium text-gray-700">
                {t("authReset.newPassword")}
              </label>
              <input
                id="reset-password"
                type="password"
                autoComplete="new-password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                className="input-field"
                minLength={MIN_PASSWORD_LENGTH}
                required
              />
              <label htmlFor="reset-password-repeat" className="block text-sm font-medium text-gray-700">
                {t("authReset.repeatPassword")}
              </label>
              <input
                id="reset-password-repeat"
                type="password"
                autoComplete="new-password"
                value={repeat}
                onChange={(e) => setRepeat(e.target.value)}
                className="input-field"
                required
              />
              {formError && (
                <div className="flex items-start gap-2 bg-red-50 text-red-600 p-3 rounded-xl text-sm" role="alert">
                  <AlertCircle className="w-4 h-4 shrink-0 mt-0.5" />
                  <span>{formError}</span>
                </div>
              )}
              <button type="submit" disabled={phase === "saving"} className="btn-primary w-full">
                {phase === "saving" && <LoaderCircle className="w-5 h-5 animate-spin" />}
                {t("authReset.save")}
              </button>
            </form>
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
            </>
          )}

          {phase === "failed" && (
            <button type="button" onClick={verify} className="btn-primary w-full">
              {t("authConfirm.retry")}
            </button>
          )}

          {showRequestForm && (
            <form onSubmit={requestNew} className="space-y-3">
              <label htmlFor="reset-email" className="block text-sm font-medium text-gray-700">
                {t("authReset.requestLabel")}
              </label>
              <input
                id="reset-email"
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
                disabled={sending || !email.trim()}
                className="w-full py-3 rounded-2xl border-2 border-teal-600 text-teal-700 font-semibold hover:bg-teal-50 disabled:opacity-50 min-h-[48px] flex items-center justify-center gap-2"
              >
                {sending && <LoaderCircle className="w-5 h-5 animate-spin" />}
                {t("authReset.requestButton")}
              </button>
              {sendNote && (
                <div className="flex items-start gap-2 bg-teal-50 text-teal-900 p-3 rounded-xl text-sm border border-teal-100" role="status">
                  <Info className="w-4 h-4 shrink-0 mt-0.5" />
                  <span>{sendNote}</span>
                </div>
              )}
              {sendError && (
                <div className="flex items-start gap-2 bg-red-50 text-red-600 p-3 rounded-xl text-sm" role="alert">
                  <AlertCircle className="w-4 h-4 shrink-0 mt-0.5" />
                  <span>{sendError}</span>
                </div>
              )}
            </form>
          )}

          <Link to="/auth" className="block text-center text-teal-600 font-semibold hover:underline pt-1">
            {t("authConfirm.goLogin")}
          </Link>
        </div>
      </div>
    </div>
  );
}
