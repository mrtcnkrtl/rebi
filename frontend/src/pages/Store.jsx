import { useEffect, useMemo, useRef, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { useTranslation } from "react-i18next";
import {
  ArrowLeft,
  Droplets,
  FlaskConical,
  Loader2,
  Minus,
  Plus,
  ShoppingBag,
  Sparkles,
  Sun,
  Trash2,
  X,
} from "lucide-react";
import LegalLinks from "../components/LegalLinks";
import TiltStage from "../components/landing/TiltStage";
import { Symbol3D } from "../components/landing/Slab";
import { ConcernBadge, ConcernDetailList, ConcernFilterButton } from "../components/store/ConcernChip";
import { useAuth } from "../context/AuthContext";
import { getRoutineSnapshot } from "../lib/routineTracking";
import {
  addToCart,
  cartCount,
  clearCart,
  getCartLines,
  removeFromCart,
  setCartQuantity,
} from "../lib/storeCart";
import { activeInfoText } from "../lib/storeActiveInfo";
import { flyProductToCart } from "../lib/storeFlyToCart";
import {
  buildStrengthIndex,
  imageFilter,
  strengthFor,
  tintFor,
} from "../lib/storeVisual";
import {
  TYPE_I18N,
  fetchStoreProduct,
  fetchStoreProducts,
  formatPrice,
  productImage,
  productLabel,
} from "../lib/storeApi";

const CONCERN_IDS = ["acne", "pigmentation", "dryness", "aging", "sensitivity", "undereye", "oiliness", "pores"];

const STEP_BANDS = [
  { id: "cleanse", icon: Droplets, tone: "water" },
  { id: "treat", icon: FlaskConical, tone: "forest" },
  { id: "moisturize", icon: Sparkles, tone: "blush" },
  { id: "spf", icon: Sun, tone: "honey" },
];

function ComingSoonBadge({ t }) {
  return (
    <span className="inline-flex rounded-full bg-honey-tint px-2.5 py-0.5 text-[11px] font-bold text-honey">
      {t("store.comingSoon")}
    </span>
  );
}

function inStepBand(step, band) {
  if (!Number.isInteger(step)) return false;
  if (band === "cleanse") return step <= 15;
  if (band === "treat") return step >= 16 && step <= 28;
  if (band === "moisturize") return step >= 29 && step <= 35;
  if (band === "spf") return step >= 36;
  return true;
}

function normText(value) {
  return String(value || "")
    .toLocaleLowerCase("tr")
    .replace(/\s+/g, " ")
    .trim();
}

function matchMine(products, routine) {
  if (!Array.isArray(routine) || !routine.length || !products.length) return [];
  const lifestyle = new Set(["Zihin", "Yaşam", "Beslenme"]);
  const hits = new Map();

  for (const step of routine) {
    if (lifestyle.has(step?.category)) continue;
    const name = normText(`${step?.action || ""} ${step?.detail || ""}`);
    if (!name || name.startsWith("günlük denge:")) continue;
    const stepOrder = Number.isInteger(step?.step_order) ? step.step_order : null;
    let best = null;
    let bestScore = 0;

    for (const p of products) {
      const label = normText(p.size_label);
      const nameTr = normText(p.name_tr);
      const nameEn = normText(p.name_en);
      const base = nameTr.includes("·") ? nameTr.split("·")[0].trim() : nameTr;
      let score = 0;
      if (label && name.includes(label)) score += 3;
      if (base && (name.includes(base) || base.split(" ").some((tok) => tok.length > 3 && name.includes(tok)))) score += 2;
      if (nameEn && name.includes(nameEn.split("·")[0].trim())) score += 1;
      if (stepOrder != null && p.step_order === stepOrder) score += 1;
      if (score > bestScore) {
        bestScore = score;
        best = p;
      }
    }
    if (best && bestScore >= 3) hits.set(best.slug, best);
  }
  return [...hits.values()];
}

function useStoreCart() {
  const [lines, setLines] = useState(() => getCartLines());
  const refresh = () => setLines(getCartLines());
  return {
    lines,
    count: cartCount(lines),
    refresh,
    add: (slug, qty = 1) => {
      setLines(addToCart(slug, qty));
    },
    setQty: (slug, qty) => setLines(setCartQuantity(slug, qty)),
    remove: (slug) => setLines(removeFromCart(slug)),
    clear: () => setLines(clearCart()),
  };
}

function ProductThumb({ product, lang, strength, size = "md", thumbRef }) {
  const img = productImage(product, lang);
  const tint = tintFor(product, strength);
  const dims = size === "lg" ? { w: 220, h: 280, depth: 18, r: 28 } : { w: 148, h: 176, depth: 14, r: 22 };

  return (
    <span
      ref={thumbRef}
      className="store-product-thumb relative block"
      style={{ width: dims.w, height: dims.h, transformStyle: "preserve-3d" }}
    >
      {Array.from({ length: Math.max(1, Math.round(dims.depth / 2)) }, (_, i) => (
        <span
          key={i}
          className="absolute inset-0 block"
          style={{
            borderRadius: dims.r,
            background: tint.edge,
            transform: `translateZ(${-(Math.round(dims.depth / 2) - i) * 2}px)`,
            boxShadow: i === 0 ? "0 22px 30px -12px rgba(6, 43, 39, 0.45)" : undefined,
          }}
        />
      ))}
      <span
        className="absolute inset-0 overflow-hidden"
        style={{ borderRadius: dims.r, background: tint.face, transform: "translateZ(0)" }}
      >
        {img?.url ? (
          <img
            src={img.url}
            alt={img.alt || ""}
            className="h-full w-full object-cover"
            style={{ filter: imageFilter(strength) }}
            draggable={false}
          />
        ) : (
          <span className="flex h-full w-full items-center justify-center">
            <FlaskConical className="h-10 w-10 opacity-70" style={{ color: tint.text }} />
          </span>
        )}
        <span className="pointer-events-none absolute inset-0" style={{ background: tint.wash }} />
      </span>
    </span>
  );
}

function PriceBlock({ product, lang, t, className = "" }) {
  const price = formatPrice(product, lang);
  return (
    <div className={className}>
      {price ? (
        <p className="font-display text-2xl font-medium text-ink">{price}</p>
      ) : (
        <p className="font-display text-2xl font-medium text-ink-soft">{t("store.priceSoon")}</p>
      )}
      <p className="text-[11px] font-semibold uppercase tracking-wide text-ink-soft">{t("store.priceLabel")}</p>
    </div>
  );
}

function isPublicCopy(text) {
  const value = String(text || "").trim();
  if (!value) return false;
  // Eski katalog şablonları / iç sistem cümleleri vitrine çıkmaz.
  return !/(konsantrasyon bandı|concentration band|dermokozmetik ürün; satış|dermocosmetic product; price|rebi[’']nin önerdiği|sistemin önerdiği|rebi recommends|rebi’s recommended|rebi's recommended)/i.test(
    value,
  );
}

function MetaGrid({ product, t }) {
  return (
    <dl className="grid grid-cols-1 gap-3 text-sm sm:grid-cols-3">
      <div className="rounded-2xl bg-paper px-3 py-2">
        <dt className="text-[11px] font-semibold uppercase tracking-wide text-ink-soft">{t("store.metaConcentration")}</dt>
        <dd className="mt-0.5 font-semibold text-ink">{product.size_label || "—"}</dd>
      </div>
      <div className="rounded-2xl bg-paper px-3 py-2">
        <dt className="text-[11px] font-semibold uppercase tracking-wide text-ink-soft">{t("store.metaType")}</dt>
        <dd className="mt-0.5 font-semibold text-ink">{t(TYPE_I18N[product.product_type] || TYPE_I18N.other)}</dd>
      </div>
      <div className="rounded-2xl bg-paper px-3 py-2">
        <dt className="text-[11px] font-semibold uppercase tracking-wide text-ink-soft">{t("store.metaStatus")}</dt>
        <dd className="mt-0.5 font-semibold text-ink">{product.purchasable ? t("store.inStock") : t("store.comingSoon")}</dd>
      </div>
    </dl>
  );
}

function CartButton({ count, onOpen, bump, cartRef }) {
  const { t } = useTranslation();
  return (
    <button
      ref={cartRef}
      type="button"
      onClick={onOpen}
      data-store-cart-target="1"
      className={`relative inline-flex h-12 items-center gap-2 rounded-2xl bg-ink px-4 text-sm font-bold text-paper shadow-[0_6px_0_#062b27] transition ${
        bump ? "scale-110" : ""
      }`}
      aria-label={t("store.cartOpen", { count })}
    >
      <ShoppingBag className="h-5 w-5" />
      <span className="hidden sm:inline">{t("store.cart")}</span>
      {count > 0 ? (
        <span className="absolute -right-1.5 -top-1.5 flex h-5 min-w-5 items-center justify-center rounded-full bg-honey px-1 text-[11px] font-bold text-ink">
          {count > 99 ? "99+" : count}
        </span>
      ) : null}
    </button>
  );
}

function CartDrawer({ open, onClose, cart, catalog, lang, t }) {
  const bySlug = useMemo(() => new Map((catalog || []).map((p) => [p.slug, p])), [catalog]);
  const rows = cart.lines
    .map((line) => ({ ...line, product: bySlug.get(line.slug) }))
    .filter((row) => row.product);

  const priced = rows.every((r) => formatPrice(r.product, lang));
  let totalMinor = 0;
  if (priced) {
    for (const r of rows) totalMinor += (r.product.price_minor || 0) * r.quantity;
  }

  if (!open) return null;

  return (
    <div className="fixed inset-0 z-50">
      <button type="button" className="absolute inset-0 bg-ink/35" aria-label={t("store.cartClose")} onClick={onClose} />
      <aside className="absolute inset-y-0 right-0 flex w-full max-w-md flex-col border-l border-rule bg-paper shadow-[-24px_0_48px_-28px_rgba(6,43,39,0.45)]">
        <div className="flex items-center justify-between border-b border-rule px-5 py-4">
          <div>
            <p className="text-xs font-bold uppercase tracking-[0.16em] text-teal-700">{t("store.cart")}</p>
            <h2 className="font-display text-2xl font-medium text-ink">{t("store.cartTitle", { count: cart.count })}</h2>
          </div>
          <button type="button" onClick={onClose} className="rounded-xl border border-rule bg-white p-2 text-ink-soft hover:text-ink" aria-label={t("store.cartClose")}>
            <X className="h-5 w-5" />
          </button>
        </div>

        <div className="flex-1 overflow-y-auto px-5 py-4">
          {rows.length === 0 ? (
            <p className="text-sm text-ink-soft">{t("store.cartEmpty")}</p>
          ) : (
            <ul className="space-y-3">
              {rows.map((row) => {
                const price = formatPrice(row.product, lang);
                const img = productImage(row.product, lang);
                return (
                  <li key={row.slug} className="flex gap-3 rounded-2xl border border-rule bg-white p-3">
                    <div className="h-16 w-14 shrink-0 overflow-hidden rounded-xl bg-paper">
                      {img?.url ? <img src={img.url} alt="" className="h-full w-full object-cover" /> : null}
                    </div>
                    <div className="min-w-0 flex-1">
                      <p className="truncate text-sm font-semibold text-ink">{productLabel(row.product, lang)}</p>
                      <p className="text-xs text-ink-soft">{row.product.size_label}</p>
                      <p className="mt-1 text-sm font-bold text-teal-800">{price || t("store.priceSoon")}</p>
                      <div className="mt-2 flex items-center gap-2">
                        <button
                          type="button"
                          className="rounded-lg border border-rule p-1"
                          onClick={() => cart.setQty(row.slug, row.quantity - 1)}
                          aria-label={t("store.qtyDecrease")}
                        >
                          <Minus className="h-3.5 w-3.5" />
                        </button>
                        <span className="min-w-6 text-center text-sm font-semibold">{row.quantity}</span>
                        <button
                          type="button"
                          className="rounded-lg border border-rule p-1"
                          onClick={() => cart.setQty(row.slug, row.quantity + 1)}
                          aria-label={t("store.qtyIncrease")}
                        >
                          <Plus className="h-3.5 w-3.5" />
                        </button>
                        <button type="button" className="ml-auto rounded-lg p-1 text-ink-soft hover:text-red-700" onClick={() => cart.remove(row.slug)} aria-label={t("store.removeLine")}>
                          <Trash2 className="h-4 w-4" />
                        </button>
                      </div>
                    </div>
                  </li>
                );
              })}
            </ul>
          )}
        </div>

        <div className="border-t border-rule px-5 py-4">
          <div className="mb-3 flex items-end justify-between">
            <span className="text-sm text-ink-soft">{t("store.cartTotal")}</span>
            <span className="font-display text-xl font-medium text-ink">
              {priced && totalMinor > 0
                ? formatPrice({ price_minor: totalMinor, currency: rows[0]?.product?.currency || "TRY" }, lang)
                : t("store.priceSoon")}
            </span>
          </div>
          <button type="button" disabled className="inline-flex min-h-[48px] w-full items-center justify-center rounded-2xl bg-gray-200 text-sm font-bold text-gray-500">
            {t("store.checkoutDisabled")}
          </button>
          <p className="mt-2 text-center text-xs text-ink-soft">{t("store.salesClosed")}</p>
          {rows.length > 0 ? (
            <button type="button" onClick={() => cart.clear()} className="mt-3 w-full text-center text-xs font-semibold text-ink-soft underline underline-offset-2">
              {t("store.clearCart")}
            </button>
          ) : null}
        </div>
      </aside>
    </div>
  );
}

function ProductCard({ product, lang, t, strength, onAdd, cartRef }) {
  const thumbRef = useRef(null);
  const [busy, setBusy] = useState(false);
  const img = productImage(product, lang);
  const price = formatPrice(product, lang);
  const tint = tintFor(product, strength);

  const handleAdd = async (e) => {
    e.preventDefault();
    e.stopPropagation();
    if (busy) return;
    setBusy(true);
    try {
      await flyProductToCart({
        fromEl: thumbRef.current,
        toEl: cartRef?.current || document.querySelector("[data-store-cart-target]"),
        imageUrl: img?.url,
      });
      onAdd(product.slug);
    } finally {
      setBusy(false);
    }
  };

  return (
    <article
      className="group flex flex-col overflow-hidden rounded-[1.75rem] border bg-white/95 shadow-[0_18px_40px_-28px_rgba(6,43,39,0.55)] transition hover:-translate-y-1"
      style={{ borderColor: tint.border }}
    >
      <div className="h-1.5 w-full" style={{ background: tint.bar }} aria-hidden="true" />
      <Link to={`/magaza/${product.slug}`} className="relative flex items-center justify-center px-4 pb-3 pt-6" style={{ background: tint.cardBg }}>
        <span className="absolute right-3 top-3">
          <ComingSoonBadge t={t} />
        </span>
        <span className="scene-3d block">
          <span className="scene-3d__tilt">
            <span
              className="pose-3d block transition duration-300 group-hover:[transform:rotateY(-8deg)_rotateX(6deg)_translateZ(8px)]"
              style={{ transform: "rotateY(-18deg) rotateX(10deg)" }}
            >
              <ProductThumb product={product} lang={lang} strength={strength} thumbRef={thumbRef} />
            </span>
          </span>
        </span>
      </Link>
      <div className="flex flex-1 flex-col p-5" style={{ background: `linear-gradient(180deg, transparent, ${tint.solid}0d)` }}>
        <Link to={`/magaza/${product.slug}`}>
          <h2 className="font-display text-xl font-medium leading-snug text-ink">{productLabel(product, lang)}</h2>
        </Link>
        <div className="mt-3 flex items-start justify-between gap-3">
          <PriceBlock product={product} lang={lang} t={t} />
          <p className="rounded-full px-2.5 py-1 text-[11px] font-bold" style={{ background: tint.wash, color: tint.solid }}>
            {product.size_label || "—"}
          </p>
        </div>
        <div className="mt-3 flex flex-wrap gap-1.5">
          {(product.concerns || []).slice(0, 2).map((c) => (
            <ConcernBadge key={c} id={c} t={t} />
          ))}
          <span className="rounded-full border border-rule bg-paper px-2.5 py-0.5 text-[11px] font-semibold text-ink-soft">
            {t(TYPE_I18N[product.product_type] || TYPE_I18N.other)}
          </span>
        </div>
        <div className="mt-4 flex gap-2">
          <Link
            to={`/magaza/${product.slug}`}
            className="inline-flex min-h-[44px] flex-1 items-center justify-center rounded-2xl border border-rule bg-white text-sm font-semibold text-ink-soft hover:border-teal-200 hover:text-teal-800"
          >
            {t("store.view")}
          </Link>
          <button
            type="button"
            onClick={handleAdd}
            disabled={busy}
            className="inline-flex min-h-[44px] flex-1 items-center justify-center gap-1.5 rounded-2xl bg-ink px-3 text-sm font-bold text-paper shadow-[0_4px_0_#062b27] disabled:opacity-60"
          >
            <ShoppingBag className="h-4 w-4" />
            {t("store.addToCart")}
          </button>
        </div>
        {!price ? <p className="mt-2 text-[11px] text-ink-soft">{t("store.cartPreviewNote")}</p> : null}
      </div>
    </article>
  );
}

function TabButton({ active, onClick, children }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={`rounded-2xl px-4 py-2.5 text-sm font-semibold transition ${
        active ? "bg-ink text-paper shadow-[0_6px_0_#062b27]" : "border border-rule bg-white text-ink-soft hover:border-teal-200"
      }`}
    >
      {children}
    </button>
  );
}

function Chip({ active, onClick, children }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={`rounded-full px-3.5 py-2 text-sm font-semibold transition ${
        active ? "bg-teal-700 text-white" : "border border-rule bg-white text-ink-soft hover:border-teal-200"
      }`}
    >
      {children}
    </button>
  );
}

function StoreShell({ children, cart, catalog, lang, t, cartOpen, setCartOpen, cartRef, bump }) {
  return (
    <>
      <div className="pointer-events-none fixed right-4 top-20 z-40 sm:right-6">
        <div className="pointer-events-auto">
          <CartButton count={cart.count} onOpen={() => setCartOpen(true)} bump={bump} cartRef={cartRef} />
        </div>
      </div>
      {children}
      <CartDrawer open={cartOpen} onClose={() => setCartOpen(false)} cart={cart} catalog={catalog} lang={lang} t={t} />
    </>
  );
}

function StoreList() {
  const { t, i18n } = useTranslation();
  const lang = i18n.resolvedLanguage || i18n.language || "tr";
  const { user } = useAuth();
  const cart = useStoreCart();
  const cartRef = useRef(null);
  const [cartOpen, setCartOpen] = useState(false);
  const [bump, setBump] = useState(false);
  const [products, setProducts] = useState([]);
  const [q, setQ] = useState("");
  const [tab, setTab] = useState("all");
  const [concern, setConcern] = useState("");
  const [stepBand, setStepBand] = useState("");
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);

  useEffect(() => {
    let cancelled = false;
    fetchStoreProducts()
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
  }, []);

  const userId = user ? user.id : null;
  const routine = useMemo(() => {
    if (!userId) return [];
    const snap = getRoutineSnapshot(userId);
    return Array.isArray(snap?.routine) ? snap.routine : [];
  }, [userId]);

  const mine = useMemo(() => matchMine(products, routine), [products, routine]);
  const strengthIndex = useMemo(() => buildStrengthIndex(products), [products]);

  const availableConcerns = useMemo(() => {
    const present = new Set();
    for (const p of products) {
      for (const c of p.concerns || []) present.add(c);
    }
    return CONCERN_IDS.filter((id) => present.has(id));
  }, [products]);

  const filtered = useMemo(() => {
    let list = products;
    if (tab === "concern" && concern) {
      list = list.filter((p) => (p.concerns || []).map(String).includes(concern));
    }
    if (tab === "step" && stepBand) {
      list = list.filter((p) => inStepBand(p.step_order, stepBand));
    }
    if (tab === "mine") list = mine;
    const needle = q.trim().toLocaleLowerCase("tr");
    if (needle) {
      list = list.filter((p) => {
        const hay = [p.name_tr, p.name_en, p.summary_tr, p.summary_en, p.size_label, p.slug, p.dose_key]
          .map((x) => String(x || "").toLocaleLowerCase("tr"))
          .join(" ");
        return hay.includes(needle);
      });
    }
    return list;
  }, [products, tab, concern, stepBand, mine, q]);

  const onAdd = (slug) => {
    cart.add(slug);
    setBump(true);
    window.setTimeout(() => setBump(false), 280);
  };

  return (
    <TiltStage className="relative min-h-screen overflow-hidden bg-paper text-ink">
      <StoreShell cart={cart} catalog={products} lang={lang} t={t} cartOpen={cartOpen} setCartOpen={setCartOpen} cartRef={cartRef} bump={bump}>
        <div className="pointer-events-none absolute inset-x-0 top-0 h-[28rem] bg-[radial-gradient(ellipse_at_20%_0%,rgba(45,212,191,0.18),transparent_55%),radial-gradient(ellipse_at_90%_10%,rgba(232,180,78,0.16),transparent_50%)]" />
        <div className="relative mx-auto max-w-6xl px-4 py-10 sm:px-6">
          <Link to="/" className="inline-flex items-center gap-1.5 text-sm font-medium text-teal-700 hover:text-teal-800">
            <ArrowLeft className="h-4 w-4" />
            {t("store.back")}
          </Link>

          <div className="mt-6 flex flex-col gap-6 md:flex-row md:items-end md:justify-between">
            <div className="max-w-2xl">
              <p className="text-xs font-bold uppercase tracking-[0.18em] text-teal-700">{t("store.eyebrow")}</p>
              <h1 className="mt-2 font-display text-4xl font-medium tracking-tight sm:text-5xl">{t("store.title")}</h1>
              <p className="mt-3 text-base leading-relaxed text-ink-soft">{t("store.subtitle")}</p>
            </div>
            <span className="scene-3d block shrink-0 self-start md:self-auto">
              <span className="scene-3d__tilt">
                <span className="sway-3d">
                  <Symbol3D icon={ShoppingBag} tone="ink" size={88} />
                </span>
              </span>
            </span>
          </div>

          <div className="mt-8 flex flex-wrap gap-2">
            <TabButton
              active={tab === "all"}
              onClick={() => {
                setTab("all");
                setConcern("");
                setStepBand("");
              }}
            >
              {t("store.tabAll")}
            </TabButton>
            <TabButton
              active={tab === "concern"}
              onClick={() => {
                setTab("concern");
                setStepBand("");
              }}
            >
              {t("store.tabConcern")}
            </TabButton>
            <TabButton
              active={tab === "step"}
              onClick={() => {
                setTab("step");
                setConcern("");
              }}
            >
              {t("store.tabStep")}
            </TabButton>
            <TabButton
              active={tab === "mine"}
              onClick={() => {
                setTab("mine");
                setConcern("");
                setStepBand("");
              }}
            >
              {t("store.tabMine")}
            </TabButton>
          </div>

          {tab === "concern" ? (
            <div className="mt-4 space-y-3">
              <Chip active={!concern} onClick={() => setConcern("")}>
                {t("store.filterAll")}
              </Chip>
              <div className="flex flex-wrap gap-3">
                {availableConcerns.map((id) => (
                  <ConcernFilterButton
                    key={id}
                    id={id}
                    active={concern === id}
                    onClick={() => setConcern(id)}
                    t={t}
                    withSymbol
                  />
                ))}
              </div>
            </div>
          ) : null}

          {tab === "step" ? (
            <div className="mt-4 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
              {STEP_BANDS.map((band) => {
                const Icon = band.icon;
                const active = stepBand === band.id;
                return (
                  <button
                    key={band.id}
                    type="button"
                    onClick={() => setStepBand(active ? "" : band.id)}
                    className={`flex items-center gap-3 rounded-2xl border px-3 py-3 text-left transition ${
                      active ? "border-teal-600 bg-teal-50" : "border-rule bg-white hover:border-teal-200"
                    }`}
                  >
                    <span className="scene-3d shrink-0">
                      <span className="scene-3d__tilt">
                        <Symbol3D icon={Icon} tone={band.tone} size={48} rotate="rotateY(-16deg) rotateX(10deg)" />
                      </span>
                    </span>
                    <span className="text-sm font-semibold text-ink">{t(`store.band.${band.id}`)}</span>
                  </button>
                );
              })}
            </div>
          ) : null}

          {tab === "mine" && !user ? (
            <p className="mt-4 rounded-2xl border border-rule bg-white px-4 py-3 text-sm text-ink-soft">{t("store.mineNeedLogin")}</p>
          ) : null}
          {tab === "mine" && user && routine.length === 0 ? (
            <p className="mt-4 rounded-2xl border border-rule bg-white px-4 py-3 text-sm text-ink-soft">{t("store.mineEmptyRoutine")}</p>
          ) : null}

          <div className="mt-6">
            <input
              value={q}
              onChange={(e) => setQ(e.target.value)}
              placeholder={t("store.searchPlaceholder")}
              className="input-field max-w-md"
              aria-label={t("store.searchPlaceholder")}
            />
          </div>

          {loading ? (
            <div className="mt-16 flex justify-center text-ink-soft">
              <Loader2 className="h-8 w-8 animate-spin" />
            </div>
          ) : error ? (
            <p className="mt-12 text-center text-sm text-red-700">{t("store.error")}</p>
          ) : filtered.length === 0 ? (
            <p className="mt-12 text-center text-sm text-ink-soft">{t("store.empty")}</p>
          ) : (
            <div className="mt-10 grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
              {filtered.map((p) => (
                <ProductCard
                  key={p.slug}
                  product={p}
                  lang={lang}
                  t={t}
                  strength={strengthFor(p, strengthIndex)}
                  onAdd={onAdd}
                  cartRef={cartRef}
                />
              ))}
            </div>
          )}

          <p className="mt-12 text-center text-xs text-ink-soft">{t("store.salesClosed")}</p>
          <LegalLinks className="mt-8 text-xs text-ink-soft" />
        </div>
      </StoreShell>
    </TiltStage>
  );
}

function StoreDetail() {
  const { slug } = useParams();
  const { t, i18n } = useTranslation();
  const lang = i18n.resolvedLanguage || i18n.language || "tr";
  const en = String(lang).startsWith("en");
  const cart = useStoreCart();
  const cartRef = useRef(null);
  const thumbRef = useRef(null);
  const [cartOpen, setCartOpen] = useState(false);
  const [bump, setBump] = useState(false);
  const [busy, setBusy] = useState(false);
  const [product, setProduct] = useState(null);
  const [catalog, setCatalog] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);

  useEffect(() => {
    let cancelled = false;
    Promise.all([fetchStoreProduct(slug), fetchStoreProducts().catch(() => ({ products: [] }))])
      .then(([detail, list]) => {
        if (cancelled) return;
        setProduct(detail.product || null);
        setCatalog(Array.isArray(list.products) ? list.products : []);
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

  const strengthIndex = useMemo(() => buildStrengthIndex(catalog.length ? catalog : product ? [product] : []), [catalog, product]);

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

  const descriptionRaw = en ? product.description_en || product.description_tr : product.description_tr;
  const description = isPublicCopy(descriptionRaw) ? descriptionRaw : null;
  const activeBlurb = activeInfoText(t, product.dose_key);
  const aboutText = activeBlurb || description;
  const usageRaw = en ? product.usage_en || product.usage_tr : product.usage_tr;
  const usage = isPublicCopy(usageRaw) ? usageRaw : null;
  const img = productImage(product, lang);
  const strength = strengthFor(product, strengthIndex);
  const tint = tintFor(product, strength);
  const related = catalog
    .filter((p) => p.dose_key && p.dose_key === product.dose_key && p.slug !== product.slug)
    .sort((a, b) => strengthFor(a, strengthIndex) - strengthFor(b, strengthIndex));

  const handleAdd = async () => {
    if (busy) return;
    setBusy(true);
    try {
      await flyProductToCart({
        fromEl: thumbRef.current,
        toEl: cartRef.current || document.querySelector("[data-store-cart-target]"),
        imageUrl: img?.url,
      });
      cart.add(product.slug);
      setBump(true);
      window.setTimeout(() => setBump(false), 280);
    } finally {
      setBusy(false);
    }
  };

  return (
    <TiltStage className="relative min-h-screen overflow-hidden bg-paper text-ink">
      <StoreShell cart={cart} catalog={catalog} lang={lang} t={t} cartOpen={cartOpen} setCartOpen={setCartOpen} cartRef={cartRef} bump={bump}>
        <div className="pointer-events-none absolute inset-x-0 top-0 h-[28rem]" style={{ background: `radial-gradient(ellipse at 18% 0%, ${tint.solid}33, transparent 55%), radial-gradient(ellipse at 88% 8%, rgba(232,180,78,0.14), transparent 48%)` }} />
        <div className="relative mx-auto max-w-6xl px-4 py-10 sm:px-6">
          <Link to="/magaza" className="inline-flex items-center gap-1.5 text-sm font-medium text-teal-700 hover:text-teal-800">
            <ArrowLeft className="h-4 w-4" />
            {t("store.backToStore")}
          </Link>

          <div className="mt-6 flex flex-wrap items-center gap-2">
            <ComingSoonBadge t={t} />
            {(product.concerns || []).map((c) => (
              <ConcernBadge key={c} id={c} t={t} />
            ))}
          </div>
          <h1 className="mt-3 max-w-3xl font-display text-4xl font-medium tracking-tight sm:text-5xl">{productLabel(product, lang)}</h1>

          <div className="mt-8 grid gap-8 lg:grid-cols-[minmax(0,1fr)_minmax(0,1.05fr)] lg:items-start">
            <div className="flex justify-center rounded-[2rem] border px-6 py-10" style={{ background: tint.cardBg, borderColor: tint.border }}>
              <span className="scene-3d block">
                <span className="scene-3d__tilt">
                  <span className="sway-3d">
                    <span className="pose-3d block" style={{ transform: "rotateY(-20deg) rotateX(12deg)" }}>
                      <ProductThumb product={product} lang={lang} strength={strength} size="lg" thumbRef={thumbRef} />
                    </span>
                  </span>
                </span>
              </span>
            </div>

            <div className="rounded-[2rem] border bg-white/95 p-6 sm:p-8" style={{ borderColor: tint.border }}>
              <div className="h-1.5 w-full rounded-full" style={{ background: tint.bar }} aria-hidden="true" />
              <div className="mt-5 flex flex-wrap items-end justify-between gap-4">
                <PriceBlock product={product} lang={lang} t={t} />
                <p className="rounded-full px-3 py-1.5 text-sm font-bold" style={{ background: tint.wash, color: tint.solid }}>
                  {product.size_label || "—"}
                </p>
              </div>
              <div className="mt-6">
                <MetaGrid product={product} t={t} />
              </div>

              {(product.concerns || []).length ? (
                <div className="mt-8">
                  <h2 className="font-display text-xl font-medium text-ink">{t("store.detailConcerns")}</h2>
                  <p className="mt-1 text-sm text-ink-soft">{t("store.detailConcernsIntro")}</p>
                  <div className="mt-4">
                    <ConcernDetailList ids={product.concerns} t={t} />
                  </div>
                </div>
              ) : null}

              {aboutText ? (
                <div className="mt-8">
                  <h2 className="font-display text-xl font-medium text-ink">{t("store.detailAbout")}</h2>
                  <p className="mt-2 text-sm leading-relaxed text-ink">{aboutText}</p>
                </div>
              ) : null}
              {usage ? (
                <div className="mt-6 rounded-2xl bg-paper px-4 py-3 text-sm text-ink-soft">
                  <div className="font-semibold text-ink">{t("store.usage")}</div>
                  <p className="mt-1 leading-relaxed">{usage}</p>
                </div>
              ) : null}
              {product.inci ? (
                <div className="mt-6">
                  <h2 className="text-sm font-semibold text-ink">{t("store.inci")}</h2>
                  <p className="mt-1 text-xs leading-relaxed text-ink-soft">{product.inci}</p>
                </div>
              ) : null}

              <button
                type="button"
                onClick={handleAdd}
                disabled={busy}
                className="mt-8 inline-flex min-h-[48px] w-full items-center justify-center gap-2 rounded-2xl bg-ink px-5 text-sm font-bold text-paper shadow-[0_6px_0_#062b27] disabled:opacity-60 sm:w-auto"
              >
                <ShoppingBag className="h-5 w-5" />
                {t("store.addToCart")}
              </button>
            </div>
          </div>

          {related.length ? (
            <section className="mt-12">
              <h2 className="font-display text-2xl font-medium text-ink">{t("store.relatedTitle")}</h2>
              <p className="mt-1 text-sm text-ink-soft">{t("store.relatedBlurb")}</p>
              <div className="mt-5 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
                {related.map((p) => {
                  const s = strengthFor(p, strengthIndex);
                  const pt = tintFor(p, s);
                  return (
                    <Link
                      key={p.slug}
                      to={`/magaza/${p.slug}`}
                      className="flex items-center gap-3 rounded-2xl border bg-white p-3 transition hover:-translate-y-0.5"
                      style={{ borderColor: pt.border }}
                    >
                      <span className="relative h-16 w-14 overflow-hidden rounded-xl" style={{ background: pt.face }}>
                        {productImage(p, lang)?.url ? (
                          <img src={productImage(p, lang).url} alt="" className="h-full w-full object-cover" style={{ filter: imageFilter(s) }} />
                        ) : null}
                        <span className="absolute inset-0" style={{ background: pt.wash }} />
                      </span>
                      <span className="min-w-0 flex-1">
                        <span className="block truncate text-sm font-semibold text-ink">{productLabel(p, lang)}</span>
                        <span className="mt-0.5 block text-xs font-bold" style={{ color: pt.solid }}>
                          {p.size_label}
                        </span>
                      </span>
                    </Link>
                  );
                })}
              </div>
            </section>
          ) : null}

          <div className="mt-10 flex flex-wrap gap-4 text-sm">
            <Link to="/mesafeli-satis" className="font-medium text-teal-700 underline underline-offset-4">
              {t("legal.distanceTitle")}
            </Link>
            <Link to="/iade" className="font-medium text-teal-700 underline underline-offset-4">
              {t("legal.refundTitle")}
            </Link>
          </div>
          <LegalLinks className="mt-8 text-xs text-ink-soft" />
        </div>
      </StoreShell>
    </TiltStage>
  );
}

export default function Store() {
  const { slug } = useParams();
  return slug ? <StoreDetail /> : <StoreList />;
}
