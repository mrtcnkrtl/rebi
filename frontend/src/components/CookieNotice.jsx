import { useState } from "react";
import { Link } from "react-router-dom";
import { useTranslation } from "react-i18next";

const ACK_KEY = "rebi-cookie-notice";

function alreadySeen() {
  try {
    return localStorage.getItem(ACK_KEY) === "1";
  } catch {
    return false;
  }
}

/**
 * Çerez bildirimi. Site yalnız zorunlu yerel depolama kullandığı için seçim sunmaz, bilgi verir; kapatılınca bir daha
 * görünmez. Analitik ya da pazarlama çerezi eklenirse buraya "kabul / reddet" seçimi gelmeli ve çerez onaydan önce
 * yerleştirilmemelidir. `raised`: panelde alt menünün üstünde durması için.
 */
export default function CookieNotice({ raised = false }) {
  const { t } = useTranslation();
  const [open, setOpen] = useState(() => !alreadySeen());
  if (!open) return null;

  const close = () => {
    try {
      localStorage.setItem(ACK_KEY, "1");
    } catch {
      /* localStorage kapalıysa bildirim yalnızca bu oturumda kapanır */
    }
    setOpen(false);
  };

  return (
    <div
      role="region"
      aria-label={t("cookie.label")}
      className={`fixed inset-x-3 z-40 mx-auto max-w-3xl rounded-2xl border border-rule bg-white p-4 text-ink shadow-[0_18px_40px_-18px_rgba(6,43,39,0.45)] sm:flex sm:items-center sm:gap-5 sm:p-5 ${
        raised ? "bottom-24 md:bottom-4" : "bottom-3 sm:bottom-4"
      }`}
    >
      <p className="text-sm leading-relaxed text-ink-soft">
        {t("cookie.body")}{" "}
        <Link to="/cerez" className="font-semibold text-teal-700 underline underline-offset-4">
          {t("legal.cookieTitle")}
        </Link>
      </p>
      <button
        type="button"
        onClick={close}
        className="mt-3 inline-flex min-h-[44px] w-full shrink-0 items-center justify-center rounded-xl bg-ink px-5 text-sm font-semibold text-paper transition-colors hover:bg-ink-deep sm:mt-0 sm:w-auto"
      >
        {t("cookie.ok")}
      </button>
    </div>
  );
}
