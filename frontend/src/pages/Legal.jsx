import { useLocation, useNavigate } from "react-router-dom";
import { useTranslation } from "react-i18next";
import { ArrowLeft, Shield } from "lucide-react";
import { LEGAL_UPDATED, legalSections } from "../lib/legalTexts";
import LegalLinks from "../components/LegalLinks";
import { LEGAL_PAGES } from "../lib/legalPages";

/** Kayıt akışının parçası olan iki metin; geri düğmesi girişe döner. Diğerleri ana sayfaya. */
const AUTH_DOCS = new Set(["kvkk", "riza"]);

export default function Legal() {
  const { t, i18n } = useTranslation();
  const location = useLocation();
  const navigate = useNavigate();
  // Eski adresler (/privacy-policy, /terms, /mesafeli...) listede yoksa KVKK metni gösterilir.
  const page =
    LEGAL_PAGES.find((p) => location.pathname.startsWith(p.path)) ||
    (location.pathname.startsWith("/terms") ? LEGAL_PAGES.find((p) => p.kind === "kosullar") : null) ||
    LEGAL_PAGES[0];
  const lang = (i18n.resolvedLanguage || i18n.language || "tr").split("-")[0];
  const sections = legalSections(page.kind, lang);
  const toAuth = AUTH_DOCS.has(page.kind);

  return (
    <div className="min-h-screen bg-gradient-to-b from-teal-50 to-white px-4 py-10">
      <article className="max-w-2xl mx-auto">
        <button
          type="button"
          onClick={() => {
            const idx = window.history.state?.idx;
            if (typeof idx === "number" && idx > 0) {
              navigate(-1);
              return;
            }
            navigate(toAuth ? "/auth" : "/");
          }}
          className="inline-flex items-center gap-1.5 text-sm text-teal-700 hover:text-teal-800 font-medium mb-6"
        >
          <ArrowLeft className="w-4 h-4" />
          {toAuth ? t("legal.backToAuth") : t("legal.back")}
        </button>
        <div className="flex items-start gap-3 mb-6">
          <div className="w-11 h-11 rounded-2xl bg-teal-600 text-white flex items-center justify-center shrink-0">
            <Shield className="w-5 h-5" />
          </div>
          <div>
            <h1 className="text-2xl font-bold text-gray-900">{t(page.titleKey)}</h1>
            <p className="text-xs text-gray-500 mt-1">{t("legal.updated", { date: LEGAL_UPDATED })}</p>
          </div>
        </div>
        <div className="card space-y-6 text-sm text-gray-700 leading-relaxed">
          {sections.map((s) => (
            <section key={s.title}>
              <h2 className="font-bold text-gray-900 mb-1.5">{s.title}</h2>
              <p className="break-words">{s.body}</p>
            </section>
          ))}
        </div>
        <LegalLinks className="mt-8 text-xs text-gray-500" />
      </article>
    </div>
  );
}
