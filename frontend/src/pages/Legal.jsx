import { Link, useLocation } from "react-router-dom";
import { useTranslation } from "react-i18next";
import { ArrowLeft, Shield } from "lucide-react";
import { LEGAL_UPDATED, legalSections } from "../lib/legalTexts";

export default function Legal() {
  const { t, i18n } = useTranslation();
  const location = useLocation();
  const kind = location.pathname.startsWith("/riza") ? "riza" : "kvkk";
  const lang = (i18n.resolvedLanguage || i18n.language || "tr").split("-")[0];
  const sections = legalSections(kind, lang);
  const title = kind === "riza" ? t("legal.rizaTitle") : t("legal.kvkkTitle");

  return (
    <div className="min-h-screen bg-gradient-to-b from-teal-50 to-white px-4 py-10">
      <article className="max-w-2xl mx-auto">
        <Link
          to="/auth"
          className="inline-flex items-center gap-1.5 text-sm text-teal-700 hover:text-teal-800 font-medium mb-6"
        >
          <ArrowLeft className="w-4 h-4" />
          {t("legal.backToAuth")}
        </Link>
        <div className="flex items-start gap-3 mb-6">
          <div className="w-11 h-11 rounded-2xl bg-teal-600 text-white flex items-center justify-center shrink-0">
            <Shield className="w-5 h-5" />
          </div>
          <div>
            <h1 className="text-2xl font-bold text-gray-900">{title}</h1>
            <p className="text-xs text-gray-500 mt-1">{t("legal.updated", { date: LEGAL_UPDATED })}</p>
          </div>
        </div>
        <div className="card space-y-6 text-sm text-gray-700 leading-relaxed">
          {sections.map((s) => (
            <section key={s.title}>
              <h2 className="font-bold text-gray-900 mb-1.5">{s.title}</h2>
              <p>{s.body}</p>
            </section>
          ))}
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
