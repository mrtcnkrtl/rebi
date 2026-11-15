import { Link } from "react-router-dom";
import { useTranslation } from "react-i18next";
import { LEGAL_PAGES } from "../lib/legalPages";

/** Tüm yasal sayfalara ve desteğe giden bağlantı satırı. `linkClassName` zemine göre renk verir. */
export default function LegalLinks({ className = "", linkClassName = "hover:text-teal-700" }) {
  const { t } = useTranslation();
  return (
    <p className={`flex flex-wrap items-center justify-center gap-x-4 gap-y-1.5 ${className}`}>
      {LEGAL_PAGES.map((p) => (
        <Link key={p.path} to={p.path} className={`underline underline-offset-4 ${linkClassName}`}>
          {t(p.titleKey)}
        </Link>
      ))}
      <Link to="/destek" className={`underline underline-offset-4 ${linkClassName}`}>
        {t("support.link")}
      </Link>
    </p>
  );
}
