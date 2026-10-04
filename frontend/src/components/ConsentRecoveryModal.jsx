import { useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import { ShieldCheck, Loader2 } from "lucide-react";
import { useAuth } from "../context/AuthContext";
import { recordLegalConsent } from "../lib/legalConsent";
import { onConsentRecoveryRequest } from "../lib/consentRecovery";
import LegalConsentFields from "./LegalConsentFields";

/** Rıza kaydı eksik oturumlarda onayı yeniden almak için açılan kutu. */
export default function ConsentRecoveryModal() {
  const { user } = useAuth();
  const { t } = useTranslation();
  const [open, setOpen] = useState(false);
  const [kvkk, setKvkk] = useState(false);
  const [riza, setRiza] = useState(false);
  const [locationOk, setLocationOk] = useState(false);
  const [photoOk, setPhotoOk] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");

  useEffect(() => onConsentRecoveryRequest(() => setOpen(true)), []);

  if (!open || !user?.id) return null;

  const submit = async () => {
    if (!kvkk || !riza || saving) return;
    setSaving(true);
    setError("");
    try {
      await recordLegalConsent(user.id, { ai: true, location: locationOk, photo: photoOk });
      setOpen(false);
    } catch (e) {
      setError(e?.message || t("auth.legalRequired"));
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="fixed inset-0 z-[80] flex items-end md:items-center justify-center px-4 pt-8 pb-[max(16px,env(safe-area-inset-bottom))]">
      <div className="absolute inset-0 bg-slate-950/60 backdrop-blur-sm" aria-hidden="true" />
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby="consent-recovery-title"
        className="relative w-full max-w-md max-h-[85vh] overflow-y-auto rounded-3xl bg-white border border-teal-100 shadow-2xl p-6"
      >
        <div className="w-12 h-12 rounded-2xl bg-teal-600 text-white flex items-center justify-center mb-4 shadow-lg shadow-teal-600/20">
          <ShieldCheck className="w-6 h-6" />
        </div>
        <h2 id="consent-recovery-title" className="text-lg font-black text-gray-900">
          {t("common.consentRecoveryTitle")}
        </h2>
        <p className="text-sm text-gray-600 leading-relaxed mt-2 mb-4">
          {t("common.consentRecoveryBody")}
        </p>

        <LegalConsentFields
          kvkk={kvkk}
          riza={riza}
          location={locationOk}
          photo={photoOk}
          onKvkk={setKvkk}
          onRiza={setRiza}
          onLocation={setLocationOk}
          onPhoto={setPhotoOk}
        />

        {error ? <p className="text-sm text-rose-600 mt-3">{error}</p> : null}

        <button
          type="button"
          onClick={submit}
          disabled={!kvkk || !riza || saving}
          className="btn-primary w-full justify-center !mt-5 disabled:opacity-50"
        >
          {saving ? <Loader2 className="w-4 h-4 animate-spin" /> : null}
          {t("common.consentRecoveryCta")}
        </button>
      </div>
    </div>
  );
}
