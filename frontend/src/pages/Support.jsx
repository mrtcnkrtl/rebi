import { Link } from "react-router-dom";
import { useTranslation } from "react-i18next";
import { ArrowLeft, Building2, LifeBuoy, Mail, Trash2 } from "lucide-react";
import { COMPANY, companyRows } from "../lib/company";
import LegalLinks from "../components/LegalLinks";

/** Destek sayfası: App Store / Google Play "destek URL'si" burayı gösterir. E-posta ve künye `lib/company.js`'ten gelir. */
export default function Support() {
  const { t, i18n } = useTranslation();
  const en = (i18n.resolvedLanguage || i18n.language || "tr").startsWith("en");
  const rows = companyRows(en);

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
              href={`mailto:${COMPANY.email}?subject=Rebi`}
              className="inline-block mt-3 text-base font-semibold text-teal-700 hover:text-teal-800 underline underline-offset-2 break-all"
            >
              {COMPANY.email}
            </a>
          </section>

          <section>
            <h2 className="font-bold text-gray-900 mb-1.5 flex items-center gap-2">
              <Building2 className="w-4 h-4 text-teal-600" />
              {t("support.companyTitle")}
            </h2>
            <p>{t("support.companyBody", { name: COMPANY.legalName })}</p>
            <dl className="mt-3 divide-y divide-gray-100 rounded-2xl border border-gray-100">
              {rows.map(([label, value]) => (
                <div key={label} className="flex flex-col gap-0.5 px-3.5 py-2.5 sm:flex-row sm:gap-4">
                  <dt className="shrink-0 text-gray-500 sm:w-40">{label}</dt>
                  <dd className="font-medium text-gray-900 break-words">{value}</dd>
                </div>
              ))}
            </dl>
          </section>

          <section id="veri-silme" className="scroll-mt-24">
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

        <LegalLinks className="mt-8 text-xs text-gray-500" />
      </article>
    </div>
  );
}
