import { Link } from "react-router-dom";
import { useTranslation } from "react-i18next";

export default function LegalConsentFields({ kvkk, riza, onKvkk, onRiza }) {
  const { t } = useTranslation();
  const kvkkBefore = (t("auth.kvkkBefore") || "").trim();
  const rizaBefore = (t("auth.rizaBefore") || "").trim();

  return (
    <div className="space-y-3 rounded-2xl border border-teal-100 bg-teal-50/40 p-3.5">
      <label className="flex items-start gap-2.5 cursor-pointer text-sm text-gray-700 leading-relaxed">
        <input
          type="checkbox"
          className="mt-1 w-4 h-4 shrink-0 rounded border-gray-300 text-teal-600 focus:ring-teal-500"
          checked={kvkk}
          onChange={(e) => onKvkk(e.target.checked)}
          required
        />
        <span>
          {kvkkBefore ? `${kvkkBefore} ` : null}
          <Link
            to="/kvkk"
            target="_blank"
            rel="noopener noreferrer"
            className="text-teal-700 font-semibold underline underline-offset-2 hover:text-teal-800"
          >{t("auth.kvkkLink")}</Link>{t("auth.kvkkAfter")}
        </span>
      </label>
      <label className="flex items-start gap-2.5 cursor-pointer text-sm text-gray-700 leading-relaxed">
        <input
          type="checkbox"
          className="mt-1 w-4 h-4 shrink-0 rounded border-gray-300 text-teal-600 focus:ring-teal-500"
          checked={riza}
          onChange={(e) => onRiza(e.target.checked)}
          required
        />
        <span>
          {rizaBefore ? `${rizaBefore} ` : null}
          <Link
            to="/riza"
            target="_blank"
            rel="noopener noreferrer"
            className="text-teal-700 font-semibold underline underline-offset-2 hover:text-teal-800"
          >{t("auth.rizaLink")}</Link>{t("auth.rizaAfter")}
        </span>
      </label>
    </div>
  );
}
