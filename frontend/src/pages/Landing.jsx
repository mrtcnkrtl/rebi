import { useEffect, useMemo } from "react";
import { Link } from "react-router-dom";
import { useTranslation } from "react-i18next";
import {
  AlertTriangle,
  ArrowRight,
  Brain,
  Camera,
  Check,
  ClipboardCheck,
  Crown,
  Droplets,
  Globe,
  Leaf,
  Lock,
  MessageCircle,
  Moon,
  Package,
  Palette,
  Shield,
  Smartphone,
  Sparkles,
  Sun,
  UserRound,
} from "lucide-react";
import { useAuth } from "../context/AuthContext";
import AiDisclaimer from "../components/AiDisclaimer";
import TiltStage from "../components/landing/TiltStage";
import PhoneScene from "../components/landing/PhoneScene";
import StoreButton from "../components/landing/StoreButton";
import { Slab, Symbol3D } from "../components/landing/Slab";
import { BrandMark } from "../components/landing/StoreGlyphs";
import { detectPlatform, orderedStores } from "../lib/storeLinks";
import { COMPANY } from "../lib/company";
import LegalLinks from "../components/LegalLinks";

/** Uygulamanın bir günü; renkler mobildeki anlamlarıyla (bal = güneş, su mavisi, lavanta = akşam, pudra = raf). */
const DAY = [
  { icon: Sun, tone: "honey", titleKey: "landing.dayMorning", descKey: "landing.dayMorningDesc" },
  { icon: Droplets, tone: "water", titleKey: "landing.dayNoon", descKey: "landing.dayNoonDesc" },
  { icon: Moon, tone: "lilac", titleKey: "landing.dayEvening", descKey: "landing.dayEveningDesc" },
  { icon: Package, tone: "blush", titleKey: "landing.dayShelf", descKey: "landing.dayShelfDesc" },
];

const DAY_EXTRAS = ["landing.dayExtra1", "landing.dayExtra2", "landing.dayExtra3", "landing.dayExtra4"];

const APP_FEATURES = ["landing.ecoAppF1", "landing.ecoAppF2", "landing.ecoAppF3", "landing.ecoAppF4"];

const PLUS = [
  { icon: MessageCircle, titleKey: "landing.plus.unlimitedAiTitle", descKey: "landing.plus.unlimitedAiDesc" },
  { icon: Palette, titleKey: "landing.plus.premiumThemesTitle", descKey: "landing.plus.premiumThemesDesc" },
  { icon: ClipboardCheck, titleKey: "landing.plus.deepTrackingTitle", descKey: "landing.plus.deepTrackingDesc" },
];

const OTHERS = [
  { icon: Camera, key: "landing.differenceSchemaOthersS1" },
  { icon: AlertTriangle, key: "landing.differenceSchemaOthersS2" },
  { icon: Shield, key: "landing.differenceSchemaOthersS3" },
];

const OURS = [
  { icon: Brain, key: "landing.differenceSchemaUsS1" },
  { icon: ClipboardCheck, key: "landing.differenceSchemaUsS2" },
  { icon: Sparkles, key: "landing.differenceSchemaUsS3" },
];

/** Tarayıcıdaki iki giriş için giriş bölümündeki düğme. */
const WEB_BTN =
  "group inline-flex min-h-[58px] items-center gap-3 rounded-2xl border-2 border-ink bg-white px-5 text-[17px] font-semibold text-ink transition-colors hover:bg-ink hover:text-paper sm:min-w-[214px]";

const EYEBROW = "text-[12px] font-semibold uppercase tracking-[0.12em] sm:text-[13px] sm:tracking-[0.16em]";
const H2 = "font-display text-[2.1rem] font-medium leading-[1.08] tracking-[-0.015em] text-balance sm:text-5xl";

/** Mağazadaki uygulama ikonu, kalınlığı olan bir levha olarak. Üst öğede `.scene-3d` bulunmalı. */
function AppIcon3D({ size = 96, rotate = "rotateY(-22deg) rotateX(14deg)" }) {
  return (
    <span className="pose-3d" style={{ width: size, height: size, transform: rotate }} aria-hidden="true">
      <Slab
        tone="app"
        depth={Math.round(size / 6)}
        radius={Math.round(size * 0.24)}
        lift={Math.round(size / 8)}
        style={{ width: size, height: size }}
      >
        <BrandMark style={{ width: size * 0.74, height: size * 0.74 }} />
      </Slab>
    </span>
  );
}

function SchemaCard({ title, steps, ours }) {
  const { t } = useTranslation();
  return (
    <div
      className={`rounded-[1.75rem] p-5 md:p-7 ${
        ours ? "border-2 border-teal-700 bg-white" : "border border-rule bg-paper-deep"
      }`}
    >
      <div className={`mb-4 text-sm font-bold ${ours ? "text-teal-700" : "text-ink-soft"}`}>{title}</div>
      <ol className="space-y-2">
        {steps.map((s, i) => (
          <li key={s.key}>
            <div
              className={`flex items-center gap-3 rounded-2xl px-4 py-3.5 text-[15px] ${
                ours ? "bg-teal-50 font-medium text-ink" : "bg-white text-ink-soft"
              }`}
            >
              <s.icon className={`h-5 w-5 shrink-0 ${ours ? "text-teal-700" : "text-ink-soft"}`} />
              {t(s.key)}
            </div>
            {i < steps.length - 1 ? (
              <div className={`pt-2 text-center text-lg leading-none ${ours ? "text-teal-700" : "text-ink-soft/50"}`} aria-hidden="true">
                ↓
              </div>
            ) : null}
          </li>
        ))}
      </ol>
    </div>
  );
}

export default function Landing() {
  const { user } = useAuth();
  const { t } = useTranslation();
  const isAuthed = Boolean(user);
  const nextAnalyze = "/dashboard/analyze";
  const rebiHref = isAuthed ? "/dashboard/chat" : "/rebi";
  const routineHref = isAuthed ? nextAnalyze : `/auth?next=${encodeURIComponent(nextAnalyze)}`;
  const platform = useMemo(() => detectPlatform(), []);
  // İki mağaza her ekranda birlikte durur; telefonda ziyaretçinin kendi mağazası üstte.
  const stores = useMemo(() => orderedStores(platform), [platform]);
  // Telefonda /indir ziyaretçiyi kendi mağazasına gönderir; masaüstünde sayfanın sonundaki indirme bölümüne iner.
  const getAppHref = platform === "desktop" ? "#indir" : "/indir";

  // /indir masaüstünde buraya "#indir" ile döner; sayfa ilk kurulduğunda doğrudan o bölümde açılır.
  // (Sayfa içindeki "#indir" bağlantılarını tarayıcı kendisi kaydırır; burası yalnız ilk açılış içindir.)
  useEffect(() => {
    const hash = window.location.hash;
    if (!hash) return undefined;
    const id = window.setTimeout(() => {
      document.getElementById(hash.slice(1))?.scrollIntoView({ block: "start", behavior: "instant" });
    }, 60);
    return () => window.clearTimeout(id);
  }, []);

  return (
    <div className="min-h-screen bg-paper text-ink">
      {/* Giriş: uygulama + mağaza düğmeleri */}
      <section className="overflow-x-clip">
        <TiltStage className="mx-auto grid w-full max-w-7xl items-center gap-12 px-4 pb-16 pt-10 sm:px-6 lg:grid-cols-[minmax(0,1.05fr)_minmax(0,0.95fr)] lg:gap-6 lg:pb-20 lg:pt-14">
          <div className="text-center lg:text-left">
            <p className={`${EYEBROW} text-teal-700`}>{t("landing.eyebrow")}</p>
            <h1 className="mt-4 font-display text-[2.7rem] font-medium leading-[1.04] tracking-[-0.02em] text-balance sm:text-6xl lg:text-[4.3rem]">
              {t("landing.heroTitle")}
            </h1>
            <p className="mx-auto mt-5 max-w-xl text-lg leading-relaxed text-ink-soft lg:mx-0">{t("landing.heroSub")}</p>

            <div className="mt-9 flex flex-col items-stretch justify-center gap-4 sm:flex-row sm:items-center sm:gap-5 lg:justify-start">
              {stores.map((s) => (
                <StoreButton key={s.id} store={s} className="sm:min-w-[272px]" />
              ))}
            </div>
            <p className="mt-6 text-sm font-medium text-ink-soft">{t("landing.storeNote")}</p>

            <div className="mt-9">
              <p className="text-[15px] font-medium text-ink-soft">{t("landing.webEntry")}</p>
              <div className="mt-3 flex flex-col gap-3 sm:flex-row sm:justify-center lg:justify-start">
                <Link to={rebiHref} className={WEB_BTN}>
                  <MessageCircle className="h-5 w-5 shrink-0 text-teal-700 group-hover:text-paper" />
                  {t("landing.webChat")}
                  <ArrowRight className="ml-auto h-4 w-4 shrink-0 transition-transform group-hover:translate-x-0.5" />
                </Link>
                <Link to={routineHref} className={WEB_BTN}>
                  <Sparkles className="h-5 w-5 shrink-0 text-teal-700 group-hover:text-paper" />
                  {t("landing.webRoutine")}
                  <ArrowRight className="ml-auto h-4 w-4 shrink-0 transition-transform group-hover:translate-x-0.5" />
                </Link>
              </div>
            </div>

            <AiDisclaimer className="mx-auto mt-6 max-w-xl lg:mx-0" />
          </div>

          <div className="relative mx-auto h-[410px] w-[304px] -translate-x-2 sm:h-[540px] sm:w-[400px] sm:translate-x-0 lg:h-[620px] lg:w-[460px]">
            {/* Günün ışığı: uygulamanın açılışındaki güneş diski. Fareyle çok az kayar; sayfanın tek arka plan süsü. */}
            <span className="pointer-events-none absolute left-1/2 top-[47%] block aspect-square w-[150%] -translate-x-1/2 -translate-y-1/2" aria-hidden="true">
              <span className="hero-light hero-light--far absolute inset-0 rounded-full border border-ink/[0.07]" />
              <span className="hero-light hero-light--far absolute inset-[12%] rounded-full border border-ink/[0.09]" />
              <span className="hero-light hero-sun absolute inset-[24%] rounded-full" />
            </span>
            <PhoneScene className="h-[620px] w-[460px] origin-top-left scale-[0.66] sm:scale-[0.87] lg:scale-100" />
          </div>
        </TiltStage>
      </section>

      {/* Ekosistem: üç giriş, tek hesap */}
      <section id="ekosistem" className="scroll-mt-20 px-4 pb-16 sm:px-6 md:pb-24">
        <div className="mx-auto max-w-6xl">
          <header className="max-w-2xl">
            <p className={`${EYEBROW} text-teal-700`}>{t("landing.ecoEyebrow")}</p>
            <h2 className={`${H2} mt-3`}>{t("landing.ecoTitle")}</h2>
            <p className="mt-4 text-lg leading-relaxed text-ink-soft">{t("landing.ecoSub")}</p>
          </header>

          <TiltStage className="mt-10">
            <div className="grid gap-5 md:grid-cols-2">
              {[
                {
                  to: rebiHref,
                  icon: MessageCircle,
                  tone: "cream",
                  bg: "bg-teal-700",
                  title: t("landing.ecoChatTitle"),
                  desc: t("landing.choiceRebiDesc"),
                  cta: t("landing.ecoChatCta"),
                },
                {
                  to: routineHref,
                  icon: Sparkles,
                  tone: "honey",
                  bg: "bg-ink",
                  title: t("landing.ecoRoutineTitle"),
                  desc: t("landing.choiceRoutineDesc"),
                  cta: t("landing.ecoRoutineCta"),
                },
              ].map((d) => (
                <Link
                  key={d.title}
                  to={d.to}
                  className={`group relative flex flex-col overflow-hidden rounded-[2rem] p-7 text-paper shadow-[0_28px_50px_-30px_rgba(6,43,39,0.7)] transition-transform hover:-translate-y-1 md:p-10 ${d.bg}`}
                >
                  <d.icon
                    className="pointer-events-none absolute -bottom-12 -right-10 h-64 w-64 text-paper opacity-[0.07]"
                    strokeWidth={1.1}
                    aria-hidden="true"
                  />
                  <span className="scene-3d relative block w-fit">
                    <span className="scene-3d__tilt">
                      <Symbol3D icon={d.icon} tone={d.tone} size={84} />
                    </span>
                  </span>
                  <span className={`${EYEBROW} relative mt-9 text-paper/70`}>{t("landing.ecoWebTag")}</span>
                  <span className="relative mt-2 font-display text-4xl font-medium leading-tight md:text-[2.75rem]">
                    {d.title}
                  </span>
                  <span className="relative mb-8 mt-3 max-w-md text-lg leading-relaxed text-paper/85">{d.desc}</span>
                  <span className="relative mt-auto inline-flex min-h-[56px] w-fit items-center gap-2.5 rounded-2xl bg-paper px-6 text-[17px] font-semibold text-ink">
                    {d.cta}
                    <ArrowRight className="h-5 w-5 transition-transform group-hover:translate-x-1" />
                  </span>
                </Link>
              ))}
            </div>

            <div className="mt-5 flex flex-col gap-6 rounded-[2rem] border border-rule bg-white p-6 md:p-8 lg:flex-row lg:items-center lg:gap-10">
              <div className="flex shrink-0 items-center gap-5 lg:w-[310px]">
                <span className="scene-3d block shrink-0">
                  <span className="scene-3d__tilt">
                    <AppIcon3D size={76} />
                  </span>
                </span>
                <div>
                  <p className={`${EYEBROW} text-teal-700`}>{t("landing.ecoAppTag")}</p>
                  <h3 className="mt-1 font-display text-2xl font-medium leading-tight">{t("landing.ecoAppTitle")}</h3>
                  <p className="mt-1 text-sm text-ink-soft">{t("landing.ecoAppDesc")}</p>
                </div>
              </div>
              <ul className="grid flex-1 gap-x-6 gap-y-2.5 sm:grid-cols-2">
                {APP_FEATURES.map((k) => (
                  <li key={k} className="flex items-start gap-2.5 text-sm leading-snug text-ink-soft">
                    <span className="mt-0.5 flex h-[18px] w-[18px] shrink-0 items-center justify-center rounded-full bg-teal-50 text-teal-700">
                      <Check className="h-3 w-3" strokeWidth={3} />
                    </span>
                    {t(k)}
                  </li>
                ))}
              </ul>
              <a
                href={getAppHref}
                className="inline-flex min-h-[52px] shrink-0 items-center justify-center gap-2 rounded-2xl bg-ink px-6 font-semibold text-paper transition-colors hover:bg-ink-deep"
              >
                <Smartphone className="h-5 w-5" />
                {t("nav.getApp")}
              </a>
            </div>
          </TiltStage>

          <div className="mt-6 flex flex-col items-start gap-4 px-2 sm:flex-row sm:items-center">
            <div className="flex shrink-0 items-center gap-2 text-teal-700" aria-hidden="true">
              <Globe className="h-5 w-5" />
              <span className="h-px w-5 bg-teal-700/40" />
              <span className="flex h-9 w-9 items-center justify-center rounded-full bg-teal-700 text-paper">
                <UserRound className="h-[18px] w-[18px]" />
              </span>
              <span className="h-px w-5 bg-teal-700/40" />
              <Smartphone className="h-5 w-5" />
            </div>
            <p className="text-[15px] leading-relaxed text-ink-soft">
              <span className="font-semibold text-ink">{t("landing.ecoAccountTitle")}.</span> {t("landing.ecoAccountDesc")}
            </p>
          </div>
        </div>
      </section>

      {/* Yükselen panel: uygulamayla bir gün, fark, Plus */}
      <div className="rounded-t-[2.5rem] border-t border-rule bg-white">
        <section className="px-4 py-16 sm:px-6 md:py-24">
          <div className="mx-auto max-w-6xl">
            <header className="max-w-3xl">
              <p className={`${EYEBROW} text-teal-700`}>{t("landing.dayEyebrow")}</p>
              <h2 className={`${H2} mt-3`}>{t("landing.dayTitle")}</h2>
            </header>

            <TiltStage className="relative mt-12 grid gap-x-8 gap-y-10 sm:grid-cols-2 lg:grid-cols-4">
              <span className="absolute left-0 right-0 top-8 hidden h-px bg-rule lg:block" aria-hidden="true" />
              {DAY.map((d) => (
                <div key={d.titleKey} className="relative">
                  <span className="scene-3d block w-fit">
                    <span className="scene-3d__tilt">
                      <Symbol3D icon={d.icon} tone={d.tone} size={64} />
                    </span>
                  </span>
                  <h3 className="mt-6 font-display text-2xl font-medium">{t(d.titleKey)}</h3>
                  <p className="mt-2 text-[15px] leading-relaxed text-ink-soft">{t(d.descKey)}</p>
                </div>
              ))}
            </TiltStage>

            <div className="mt-12 flex flex-wrap items-center gap-2.5 border-t border-rule pt-6">
              <span className="mr-1 text-sm font-semibold">{t("landing.dayExtras")}</span>
              {DAY_EXTRAS.map((k) => (
                <span key={k} className="rounded-full border border-rule bg-paper px-3.5 py-1.5 text-sm text-ink-soft">
                  {t(k)}
                </span>
              ))}
            </div>
          </div>
        </section>

        <section className="border-t border-rule px-4 py-16 sm:px-6 md:py-20">
          <div className="mx-auto max-w-6xl">
            <header className="max-w-2xl">
              <h2 className={H2}>{t("landing.differenceTitle")}</h2>
              <p className="mt-4 text-lg leading-relaxed text-ink-soft">{t("landing.differenceSubtitle")}</p>
            </header>
            <div className="mt-10 grid gap-5 md:grid-cols-2">
              <SchemaCard title={t("landing.differenceSchemaOthers")} steps={OTHERS} />
              <SchemaCard title={t("landing.differenceSchemaUs")} steps={OURS} ours />
            </div>
            <p className="mt-8 max-w-3xl text-sm leading-relaxed text-ink-soft">{t("landing.disclaimer")}</p>
          </div>
        </section>

        <section className="border-t border-rule px-4 py-16 sm:px-6 md:py-20">
          <div className="mx-auto grid max-w-6xl gap-10 rounded-[2rem] border border-rule bg-paper p-7 md:p-10 lg:grid-cols-[minmax(0,0.9fr)_minmax(0,1.1fr)] lg:gap-14">
            <div>
              <div className="inline-flex items-center gap-2 rounded-full bg-honey-tint px-3.5 py-1.5 text-sm font-semibold text-honey">
                <Crown className="h-4 w-4" />
                {t("landing.plusBadge")}
              </div>
              <h2 className="mt-5 font-display text-3xl font-medium leading-tight text-balance md:text-4xl">
                {t("landing.plusTitle")}
              </h2>
              <p className="mt-4 leading-relaxed text-ink-soft">{t("landing.plusDesc")}</p>
              <Link
                to={user ? "/dashboard/subscribe" : "/auth"}
                className="group mt-7 inline-flex min-h-[48px] items-center gap-2 rounded-2xl bg-ink px-6 py-3 font-semibold text-paper transition-colors hover:bg-ink-deep"
              >
                {t("landing.plusCta")}
                <ArrowRight className="h-5 w-5 transition-transform group-hover:translate-x-1" />
              </Link>
            </div>
            <div>
              <ul className="divide-y divide-rule">
                {PLUS.map((p) => (
                  <li key={p.titleKey} className="flex items-start gap-4 py-4 first:pt-0">
                    <span className="flex h-11 w-11 shrink-0 items-center justify-center rounded-full bg-honey-tint text-honey">
                      <p.icon className="h-5 w-5" />
                    </span>
                    <div>
                      <h3 className="text-lg font-semibold">{t(p.titleKey)}</h3>
                      <p className="mt-0.5 text-[15px] leading-relaxed text-ink-soft">{t(p.descKey)}</p>
                    </div>
                  </li>
                ))}
              </ul>
              <p className="mt-4 flex items-center gap-1.5 text-xs font-semibold text-honey">
                <Lock className="h-3.5 w-3.5" />
                {t("landing.plusUnlockHint")}
              </p>
            </div>
          </div>
        </section>

        {/* İndirme sahnesi */}
        <section id="indir" className="relative scroll-mt-16 overflow-hidden rounded-t-[2.5rem] bg-ink text-paper">
          <BrandMark className="pointer-events-none absolute -right-24 -top-24 h-[520px] w-[520px] text-paper opacity-[0.05]" />
          <TiltStage className="relative mx-auto grid max-w-6xl items-center gap-10 px-4 py-16 sm:px-6 md:py-24 lg:grid-cols-[auto_minmax(0,1fr)_auto] lg:gap-14">
            <span className="scene-3d mx-auto block lg:mx-0">
              <span className="scene-3d__tilt">
                <span className="sway-3d">
                  <AppIcon3D size={148} rotate="rotateY(-20deg) rotateX(12deg) rotateZ(-3deg)" />
                </span>
              </span>
            </span>

            <div className="text-center lg:text-left">
              <p className={`${EYEBROW} text-teal-300`}>{t("landing.dlEyebrow")}</p>
              <h2 className="mt-3 font-display text-[2.4rem] font-medium leading-[1.05] tracking-[-0.02em] text-balance sm:text-6xl">
                {t("landing.dlTitle")}
              </h2>
              <p className="mx-auto mt-4 max-w-xl text-lg leading-relaxed text-paper/75 lg:mx-0">{t("landing.dlSub")}</p>
              <div className="mt-9 flex flex-col items-stretch justify-center gap-5 pb-2 sm:flex-row sm:items-center lg:justify-start">
                {stores.map((s) => (
                  <StoreButton key={s.id} store={s} tone="cream" className="sm:min-w-[272px]" />
                ))}
              </div>
            </div>

            <div className="hidden w-[212px] rounded-[1.75rem] bg-paper p-5 text-center text-ink lg:block">
              <img src="/qr-indir.svg" alt={t("landing.dlQrAlt")} width="172" height="172" className="mx-auto h-[172px] w-[172px]" />
              <p className="mt-3 text-sm font-semibold leading-snug">{t("landing.dlQrTitle")}</p>
              <p className="mt-1 text-xs leading-snug text-ink-soft">{t("landing.dlQrDesc")}</p>
            </div>
          </TiltStage>
        </section>
      </div>

      <footer className="bg-ink-deep px-4 py-10 text-paper/70 sm:px-6">
        <div className="mx-auto max-w-6xl">
          <div className="flex flex-col items-center gap-7 text-center md:flex-row md:items-start md:justify-between md:text-left">
            <div className="shrink-0">
              <div className="flex items-center justify-center gap-2.5 text-paper md:justify-start">
                <span className="flex h-8 w-8 items-center justify-center rounded-lg bg-gradient-to-br from-teal-500 to-teal-600 text-white">
                  <Leaf className="h-4 w-4" />
                </span>
                <span className="font-display text-lg font-medium">Rebi</span>
              </div>
              <p className="mt-3 text-sm text-paper/85">{COMPANY.legalName}</p>
              {COMPANY.address ? <p className="mt-1 max-w-xs text-xs leading-relaxed">{COMPANY.address}</p> : null}
              <a href={`mailto:${COMPANY.email}`} className="mt-1 inline-block text-sm underline underline-offset-4 hover:text-paper">
                {COMPANY.email}
              </a>
            </div>
            <LegalLinks className="max-w-2xl text-sm md:justify-end" linkClassName="hover:text-paper" />
          </div>
          <p className="mt-8 border-t border-paper/10 pt-5 text-center text-xs text-paper/55 md:text-left">{t("landing.footer")}</p>
        </div>
      </footer>
    </div>
  );
}
