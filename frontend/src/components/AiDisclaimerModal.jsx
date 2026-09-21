import { useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import { Sparkles } from "lucide-react";

/** Yapay zekâ beyanı: cihaz başına bir kez onaylanan açılır kutu. */
const ACK_KEY = "rebi-ai-disclaimer-ack-v1";

export default function AiDisclaimerModal() {
  const { t } = useTranslation();
  const [open, setOpen] = useState(false);

  useEffect(() => {
    try {
      setOpen(localStorage.getItem(ACK_KEY) !== "1");
    } catch {
      setOpen(true);
    }
  }, []);

  if (!open) return null;

  const dismiss = () => {
    try {
      localStorage.setItem(ACK_KEY, "1");
    } catch {
      /* localStorage kapalıysa kutu yalnızca bu oturumda kapanır */
    }
    setOpen(false);
  };

  return (
    <div className="fixed inset-0 z-[70] flex items-end md:items-center justify-center px-4 pt-8 pb-[max(16px,env(safe-area-inset-bottom))]">
      <div className="absolute inset-0 bg-slate-950/60 backdrop-blur-sm" aria-hidden="true" />
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby="ai-disclaimer-title"
        className="relative w-full max-w-sm rounded-3xl bg-white border border-teal-100 shadow-2xl p-6 text-center"
      >
        <div className="w-12 h-12 rounded-2xl bg-teal-600 text-white flex items-center justify-center mx-auto mb-4 shadow-lg shadow-teal-600/20">
          <Sparkles className="w-6 h-6" />
        </div>
        <h2 id="ai-disclaimer-title" className="text-lg font-black text-gray-900">
          {t("common.aiDisclaimerTitle")}
        </h2>
        <p className="text-sm text-gray-600 leading-relaxed mt-2">
          {t("common.aiDisclaimer")}
        </p>
        <button
          type="button"
          onClick={dismiss}
          className="btn-primary w-full justify-center !mt-6"
        >
          {t("common.aiDisclaimerAck")}
        </button>
      </div>
    </div>
  );
}
