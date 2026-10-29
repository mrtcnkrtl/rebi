import { Link } from "react-router-dom";
import { useTranslation } from "react-i18next";
import { ArrowLeft, LifeBuoy, Mail, Trash2 } from "lucide-react";

/** Destek e-postası: App Store / Google Play "destek URL'si" bu sayfayı gösterir. */
export const SUPPORT_EMAIL = "mertkartal48.mck@gmail.com";

export default function Support() {
  const { t } = useTranslation();

  return (
    <div className="min-h-screen bg-gradient-to-b from-teal-50 to-white px-4 py-10">
      <article className="max-w-2xl mx-auto">
        <Link
          to="/"
          className="inline-flex items-center gap-1.5 text-sm text-teal-700 hover:text-teal-800 font-medium mb-6"
        >
          <ArrowLeft className="w-4 h-4" />
          {t("support.back")}
        </Link>
        <div className="flex items-start gap-3 mb-6">
          <div className="w-11 h-11 rounded-2xl bg-teal-600 text-white flex items-center justify-center shrink-0">
            <LifeBuoy className="w-5 h-5" />
          </div>
          <div>
            <h1 className="text-2xl font-bold text-gray-900">{t("support.title")}</h1>
            <p className="text-sm text-gray-500 mt-1">{t("support.subtitle")}</p>
          </div>
        </div>

        <div className="card space-y-6 text-sm text-gray-700 leading-relaxed">
          <section>
            <h2 className="font-bold text-gray-900 mb-1.5 flex items-center gap-2">
              <Mail className="w-4 h-4 text-teal-600" />
              {t("support.contactTitle")}
            </h2>
            <p>{t("support.contactBody")}</p>
            <a
              href={`mailto:${SUPPORT_EMAIL}?subject=Rebi`}
              className="inline-block mt-3 font-semibold text-teal-700 hover:text-teal-800 underline underline-offset-2 break-all"
            >
              {SUPPORT_EMAIL}
            </a>
          </section>

          <section>
            <h2 className="font-bold text-gray-900 mb-1.5 flex items-center gap-2">
              <Trash2 className="w-4 h-4 text-teal-600" />
              {t("support.deleteTitle")}
            </h2>
            <p>{t("support.deleteInApp")}</p>
            <p className="mt-2">{t("support.deleteByEmail")}</p>
          </section>

          <section>
            <h2 className="font-bold text-gray-900 mb-1.5">{t("support.medicalTitle")}</h2>
            <p>{t("support.medicalBody")}</p>
          </section>
        </div>

        <p className="text-center text-xs text-gray-400 mt-8">
          <Link to="/kvkk" className="hover:text-teal-700 underline underline-offset-2">
            {t("legal.kvkkTitle")}
          </Link>
          {" · "}
          <Link to="/riza" className="hover:text-teal-700 underline underline-offset-2">
            {t("legal.rizaTitle")}
          </Link>
        </p>
      </article>
    </div>
  );
}
