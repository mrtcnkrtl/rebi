import { useEffect, useMemo, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { useTranslation } from "react-i18next";
import { ArrowLeft, FlaskConical, Loader2, ShoppingBag } from "lucide-react";
import LegalLinks from "../components/LegalLinks";
import { fetchStoreProduct, fetchStoreProducts, productLabel, productSummary } from "../lib/storeApi";

const TYPE_KEYS = {
  cleanser: "store.typeCleanser",
  toner: "store.typeToner",
  serum: "store.typeSerum",
  moisturizer: "store.typeMoisturizer",
  sunscreen: "store.typeSunscreen",
  mask: "store.typeMask",
  other: "store.typeOther",
};

function TypeBadge({ type, t }) {
  return (
    <span className="inline-flex rounded-full border border-rule bg-paper px-2.5 py-0.5 text-[11px] font-semibold text-ink-soft">
      {t(TYPE_KEYS[type] || TYPE_KEYS.other)}
    </span>
  );
}

function ComingSoonBadge({ t }) {
  return (
    <span className="inline-flex rounded-full bg-honey-tint px-2.5 py-0.5 text-[11px] font-bold text-honey">
      {t("store.comingSoon")}
    </span>
  );
}

function ProductCard({ product, lang, t }) {
  return (
    <Link
      to={`/magaza/${product.slug}`}
      className="group flex flex-col rounded-3xl border border-rule bg-white p-5 shadow-[0_12px_30px_-24px_rgba(6,43,39,0.45)] transition hover:-translate-y-0.5 hover:border-teal-200"
    >
      <div className="flex items-start justify-between gap-3">
        <div className="flex h-12 w-12 items-center justify-center rounded-2xl bg-gradient-to-br from-teal-500 to-teal-700 text-white shadow-lg shadow-teal-600/20">
          <FlaskConical className="h-5 w-5" />
        </div>
        <ComingSoonBadge t={t} />
      </div>
      <h2 className="mt-4 font-display text-xl font-medium leading-snug text-ink">{productLabel(product, lang)}</h2>
      {product.size_label ? (
        <p className="mt-1 text-sm font-semibold text-teal-700">{product.size_label}</p>
      ) : null}
      <p className="mt-2 flex-1 text-sm leading-relaxed text-ink-soft">{productSummary(product, lang)}</p>
      <div className="mt-4 flex items-center justify-between gap-2">
        <TypeBadge type={product.product_type} t={t} />
        <span className="text-xs font-semibold text-ink-soft group-hover:text-teal-700">{t("store.view")}</span>
      </div>
    </Link>
  );
}

function StoreList() {
  const { t, i18n } = useTranslation();
  const lang = i18n.resolvedLanguage || i18n.language || "tr";
  const [products, setProducts] = useState([]);
  const [q, setQ] = useState("");
  const [type, setType] = useState("");
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);

  useEffect(() => {
    let cancelled = false;
    fetchStoreProducts({ q: q || undefined, product_type: type || undefined })
      .then((data) => {
        if (cancelled) return;
        setProducts(Array.isArray(data.products) ? data.products : []);
        setError(false);
        setLoading(false);
      })
      .catch(() => {
        if (cancelled) return;
        setError(true);
        setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [q, type]);

  const types = useMemo(
    () => [
      { id: "", label: t("store.filterAll") },
      { id: "serum", label: t("store.typeSerum") },
      { id: "moisturizer", label: t("store.typeMoisturizer") },
      { id: "sunscreen", label: t("store.typeSunscreen") },
      { id: "other", label: t("store.typeOther") },
    ],
    [t],
  );

  return (
    <div className="min-h-screen bg-paper text-ink">
      <div className="mx-auto max-w-6xl px-4 py-10 sm:px-6">
        <Link to="/" className="inline-flex items-center gap-1.5 text-sm font-medium text-teal-700 hover:text-teal-800">
          <ArrowLeft className="h-4 w-4" />
          {t("store.back")}
        </Link>
        <div className="mt-6 flex flex-col gap-4 md:flex-row md:items-end md:justify-between">
          <div>
            <p className="text-xs font-bold uppercase tracking-[0.18em] text-teal-700">{t("store.eyebrow")}</p>
            <h1 className="mt-2 font-display text-4xl font-medium tracking-tight sm:text-5xl">{t("store.title")}</h1>
            <p className="mt-3 max-w-2xl text-base leading-relaxed text-ink-soft">{t("store.subtitle")}</p>
          </div>
          <div className="flex h-14 w-14 items-center justify-center rounded-2xl bg-ink text-paper">
            <ShoppingBag className="h-6 w-6" />
          </div>
        </div>

        <div className="mt-8 flex flex-col gap-3 sm:flex-row sm:items-center">
          <input
            value={q}
            onChange={(e) => setQ(e.target.value)}
            placeholder={t("store.searchPlaceholder")}
            className="input-field max-w-md flex-1"
            aria-label={t("store.searchPlaceholder")}
          />
          <div className="flex flex-wrap gap-2">
            {types.map((opt) => (
              <button
                key={opt.id || "all"}
                type="button"
                onClick={() => setType(opt.id)}
                className={`rounded-full px-3.5 py-2 text-sm font-semibold transition ${
                  type === opt.id ? "bg-ink text-paper" : "border border-rule bg-white text-ink-soft hover:border-teal-200"
                }`}
              >
                {opt.label}
              </button>
            ))}
          </div>
        </div>

        {loading ? (
          <div className="mt-16 flex justify-center text-ink-soft">
            <Loader2 className="h-8 w-8 animate-spin" />
          </div>
        ) : error ? (
          <p className="mt-12 text-center text-sm text-red-700">{t("store.error")}</p>
        ) : products.length === 0 ? (
          <p className="mt-12 text-center text-sm text-ink-soft">{t("store.empty")}</p>
        ) : (
          <div className="mt-10 grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
            {products.map((p) => (
              <ProductCard key={p.slug} product={p} lang={lang} t={t} />
            ))}
          </div>
        )}

        <p className="mt-12 text-center text-xs text-ink-soft">{t("store.salesClosed")}</p>
        <LegalLinks className="mt-8 text-xs text-ink-soft" />
      </div>
    </div>
  );
}

function StoreDetail() {
  const { slug } = useParams();
  const { t, i18n } = useTranslation();
  const lang = i18n.resolvedLanguage || i18n.language || "tr";
  const en = String(lang).startsWith("en");
  const [product, setProduct] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);

  useEffect(() => {
    let cancelled = false;
    fetchStoreProduct(slug)
      .then((data) => {
        if (cancelled) return;
        setProduct(data.product || null);
        setError(false);
        setLoading(false);
      })
      .catch(() => {
        if (cancelled) return;
        setError(true);
        setProduct(null);
        setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [slug]);

  if (loading) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-paper text-ink-soft">
        <Loader2 className="h-8 w-8 animate-spin" />
      </div>
    );
  }
  if (error || !product) {
    return (
      <div className="min-h-screen bg-paper px-4 py-10 text-ink">
        <div className="mx-auto max-w-2xl">
          <Link to="/magaza" className="inline-flex items-center gap-1.5 text-sm font-medium text-teal-700">
            <ArrowLeft className="h-4 w-4" />
            {t("store.backToStore")}
          </Link>
          <p className="mt-8 text-sm text-red-700">{t("store.notFound")}</p>
        </div>
      </div>
    );
  }

  const description = en ? product.description_en || product.description_tr : product.description_tr;
  const usage = en ? product.usage_en || product.usage_tr : product.usage_tr;

  return (
    <div className="min-h-screen bg-paper text-ink">
      <div className="mx-auto max-w-3xl px-4 py-10 sm:px-6">
        <Link to="/magaza" className="inline-flex items-center gap-1.5 text-sm font-medium text-teal-700 hover:text-teal-800">
          <ArrowLeft className="h-4 w-4" />
          {t("store.backToStore")}
        </Link>

        <div className="mt-8 rounded-[2rem] border border-rule bg-white p-6 sm:p-8">
          <div className="flex flex-wrap items-center gap-2">
            <ComingSoonBadge t={t} />
            <TypeBadge type={product.product_type} t={t} />
          </div>
          <h1 className="mt-4 font-display text-3xl font-medium tracking-tight sm:text-4xl">{productLabel(product, lang)}</h1>
          {product.size_label ? <p className="mt-2 text-lg font-semibold text-teal-700">{product.size_label}</p> : null}
          <p className="mt-4 text-base leading-relaxed text-ink-soft">{productSummary(product, lang)}</p>
          {description ? <p className="mt-6 text-sm leading-relaxed text-ink">{description}</p> : null}
          {usage ? (
            <div className="mt-6 rounded-2xl bg-paper px-4 py-3 text-sm text-ink-soft">
              <div className="font-semibold text-ink">{t("store.usage")}</div>
              <p className="mt-1 leading-relaxed">{usage}</p>
            </div>
          ) : null}
          {product.step_order != null ? (
            <p className="mt-4 text-xs text-ink-soft">{t("store.stepOrder", { n: product.step_order })}</p>
          ) : null}

          <button
            type="button"
            disabled
            className="mt-8 inline-flex min-h-[48px] w-full items-center justify-center gap-2 rounded-2xl bg-gray-200 px-5 text-sm font-bold text-gray-500 sm:w-auto"
          >
            {t("store.addToCartDisabled")}
          </button>
          <p className="mt-3 text-xs text-ink-soft">{t("store.salesClosed")}</p>
        </div>

        <div className="mt-8 flex flex-wrap gap-4 text-sm">
          <Link to="/mesafeli-satis" className="font-medium text-teal-700 underline underline-offset-4">
            {t("legal.distanceTitle")}
          </Link>
          <Link to="/iade" className="font-medium text-teal-700 underline underline-offset-4">
            {t("legal.refundTitle")}
          </Link>
        </div>
        <LegalLinks className="mt-8 text-xs text-ink-soft" />
      </div>
    </div>
  );
}

export default function Store() {
  const { slug } = useParams();
  return slug ? <StoreDetail /> : <StoreList />;
}
