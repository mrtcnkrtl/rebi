import { Link } from "react-router-dom";
import { useTranslation } from "react-i18next";

export default function LegalConsentFields({
  kvkk,
  riza,
  ai,
  location,
  photo,
  onKvkk,
  onRiza,
  onAi,
  onLocation,
  onPhoto,
}) {
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
      <label className="flex items-start gap-2.5 cursor-pointer text-sm text-gray-700 leading-relaxed">
        <input
          type="checkbox"
          className="mt-1 w-4 h-4 shrink-0 rounded border-gray-300 text-teal-600 focus:ring-teal-500"
          checked={ai}
          onChange={(e) => onAi(e.target.checked)}
          required
        />
        <span>{t("auth.aiConsent")}</span>
      </label>
      <div className="border-t border-teal-100 pt-2">
        <p className="text-xs font-semibold text-gray-600 mb-2">{t("auth.optionalPermissions")}</p>
        <div className="space-y-2">
          <label className="flex items-start gap-2.5 cursor-pointer text-sm text-gray-700 leading-relaxed">
            <input
              type="checkbox"
              className="mt-1 w-4 h-4 shrink-0 rounded border-gray-300 text-teal-600 focus:ring-teal-500"
              checked={location}
              onChange={(e) => onLocation(e.target.checked)}
            />
            <span>{t("auth.locationConsent")}</span>
          </label>
          <label className="flex items-start gap-2.5 cursor-pointer text-sm text-gray-700 leading-relaxed">
            <input
              type="checkbox"
              className="mt-1 w-4 h-4 shrink-0 rounded border-gray-300 text-teal-600 focus:ring-teal-500"
              checked={photo}
              onChange={(e) => onPhoto(e.target.checked)}
            />
            <span>{t("auth.photoConsent")}</span>
          </label>
        </div>
      </div>
    </div>
  );
}
