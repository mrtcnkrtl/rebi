import { Link } from "react-router-dom";
import { useAuth } from "../context/AuthContext";
import { useTranslation } from "react-i18next";
import HeroBackgroundVideo from "../components/HeroBackgroundVideo";
import { useEffect, useMemo, useRef, useState } from "react";
import {
  Leaf,
  Camera,
  Brain,
  CloudSun,
  ArrowRight,
  Shield,
  Heart,
  Sparkles,
  Star,
  ChevronRight,
  Crown,
  MessageCircle,
  Palette,
  ClipboardCheck,
  Lock,
  AlertTriangle,
} from "lucide-react";

const features = [
  {
    icon: Camera,
    titleKey: "landing.features.cameraTitle",
    descKey: "landing.features.cameraDesc",
    color: "from-pink-500 to-rose-500",
    bg: "bg-pink-50",
  },
  {
    icon: Brain,
    titleKey: "landing.features.holisticTitle",
    descKey: "landing.features.holisticDesc",
    color: "from-purple-500 to-indigo-500",
    bg: "bg-purple-50",
  },
  {
    icon: CloudSun,
    titleKey: "landing.features.weatherTitle",
    descKey: "landing.features.weatherDesc",
    color: "from-blue-500 to-cyan-500",
    bg: "bg-blue-50",
  },
];

const steps = [
  { num: "01", titleKey: "landing.steps.s1Title", descKey: "landing.steps.s1Desc" },
  { num: "02", titleKey: "landing.steps.s2Title", descKey: "landing.steps.s2Desc" },
  { num: "03", titleKey: "landing.steps.s3Title", descKey: "landing.steps.s3Desc" },
];

const plusHighlights = [
  {
    icon: MessageCircle,
    titleKey: "landing.plus.unlimitedAiTitle",
    descKey: "landing.plus.unlimitedAiDesc",
    gradient: "from-violet-500 to-fuchsia-500",
    glow: "shadow-fuchsia-500/20",
  },
  {
    icon: Palette,
    titleKey: "landing.plus.premiumThemesTitle",
    descKey: "landing.plus.premiumThemesDesc",
    gradient: "from-cyan-500 to-blue-600",
    glow: "shadow-cyan-500/20",
  },
  {
    icon: ClipboardCheck,
    titleKey: "landing.plus.deepTrackingTitle",
    descKey: "landing.plus.deepTrackingDesc",
    gradient: "from-amber-500 to-orange-600",
    glow: "shadow-amber-500/25",
  },
];

export default function Landing() {
  const { user } = useAuth();
  const { t } = useTranslation();
  const [choice, setChoice] = useState(null); // "rebi" | "routine" | null
  const [phase, setPhase] = useState("choice"); // "choice" | "reveal"
  const [rebiInfoOpen, setRebiInfoOpen] = useState(false);
  const revealRef = useRef(null);
  const isAuthed = Boolean(user);
  const nextAnalyze = "/dashboard/analyze";
  const rebiHref = isAuthed ? "/dashboard/chat" : "/rebi";

  const cta = useMemo(() => {
    if (choice === "routine") {
      return {
        href: isAuthed ? nextAnalyze : `/auth?next=${encodeURIComponent(nextAnalyze)}`,
        label: t("landing.ctaBuildRoutine"),
        sub: t("nav.newAnalyze"),
        icon: Sparkles,
      };
    }
    return {
      href: rebiHref,
      label: t("landing.ctaChat"),
      sub: t("nav.chat"),
      icon: MessageCircle,
    };
  }, [choice, isAuthed, nextAnalyze, rebiHref, t]);

  useEffect(() => {
    if (phase !== "reveal") return;
    const id = window.setTimeout(() => {
      revealRef.current?.scrollIntoView({ behavior: "smooth", block: "start" });
    }, 450);
    return () => window.clearTimeout(id);
  }, [phase]);

  const pick = (next) => {
    setChoice(next);
    if (next === "rebi") {
      setRebiInfoOpen(true);
      setPhase("choice");
      return;
    }
    setPhase("reveal");
  };

  return (
    <div className="min-h-screen bg-gradient-to-b from-warm-50 via-white to-teal-50/30">
      {/* Hero */}
      <section className="relative min-h-[calc(100dvh-72px)] overflow-hidden flex items-center">
        <HeroBackgroundVideo />
        <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_top,_var(--tw-gradient-stops))] from-teal-100/35 via-transparent to-transparent" />
        <div className="absolute top-10 right-[-5%] w-[min(90vw,520px)] h-[min(90vw,520px)] bg-teal-200/25 rounded-full blur-3xl" />
        <div className="absolute bottom-[-10%] left-[-8%] w-[min(95vw,640px)] h-[min(95vw,640px)] bg-purple-200/15 rounded-full blur-3xl" />
        <div className="absolute -top-16 left-8 w-40 h-40 rounded-[2.5rem] bg-gradient-to-br from-fuchsia-300/25 via-purple-300/10 to-transparent rotate-12 blur-xl" />
        <div className="absolute top-28 left-[55%] w-28 h-28 rounded-full bg-gradient-to-br from-amber-300/18 via-orange-300/10 to-transparent blur-xl" />
        <div className="absolute bottom-20 right-10 w-44 h-44 rounded-[3rem] bg-gradient-to-br from-sky-300/20 via-cyan-300/10 to-transparent -rotate-12 blur-xl" />
        <div
          className="absolute inset-0 opacity-[0.35] mix-blend-soft-light"
          style={{
            backgroundImage:
              "linear-gradient(135deg, rgba(255,255,255,0.65) 0%, transparent 35%, rgba(255,255,255,0.15) 65%, transparent 100%)",
          }}
        />

        <div className="relative w-full max-w-7xl mx-auto px-4 sm:px-6 py-10 md:py-12">
          <div className="text-center max-w-6xl mx-auto w-full">
            <div
              className={`transition-all duration-700 ${
                phase === "choice" ? "opacity-100 translate-y-0" : "opacity-0 -translate-y-3 pointer-events-none select-none"
              }`}
            >
              <div className="inline-flex items-center gap-2 bg-teal-50 text-teal-700 px-4 py-2 rounded-full text-sm font-medium mb-6 border border-teal-100">
                <Sparkles className="w-4 h-4" />
                {t("landing.heroBadge")}
              </div>

              <h1 className="text-4xl sm:text-5xl md:text-7xl font-bold text-gray-900 leading-[1.05] mb-5 tracking-tight drop-shadow-sm">
                {t("landing.choiceTitle")}
              </h1>
              <p className="text-lg md:text-xl text-gray-700 mb-7 md:mb-8 max-w-2xl mx-auto">
                {t("landing.choiceSubtitle")}
              </p>

              <div className="grid md:grid-cols-2 gap-5 md:gap-8 text-left">
                <button
                  type="button"
                  onClick={() => pick("rebi")}
                  className="group relative min-h-[190px] md:min-h-[220px] rounded-[2rem] border-2 border-teal-200/90 bg-white/75 backdrop-blur-md hover:bg-white/90 px-7 md:px-8 py-7 md:py-8 shadow-md hover:shadow-2xl hover:shadow-teal-500/10 transition-all"
                >
                  <div className="absolute -top-16 -right-16 w-56 h-56 bg-teal-300/30 rounded-full blur-3xl" />
                  <div className="relative flex items-start justify-between gap-5">
                    <div className="flex items-start gap-4">
                      <div className="w-14 h-14 md:w-16 md:h-16 rounded-2xl bg-teal-600 flex items-center justify-center shadow-xl shadow-teal-600/25 shrink-0">
                        <MessageCircle className="w-7 h-7 md:w-8 md:h-8 text-white" />
                      </div>
                      <div>
                        <div className="text-xl md:text-2xl font-black text-gray-900">{t("appName")}</div>
                        <div className="text-base md:text-lg text-gray-600 mt-2 leading-relaxed">
                          {t("landing.choiceRebiDesc")}
                        </div>
                      </div>
                    </div>
                    <ArrowRight className="w-7 h-7 text-teal-700 shrink-0 group-hover:translate-x-1 transition-transform mt-1" />
                  </div>
                </button>

                <button
                  type="button"
                  onClick={() => pick("routine")}
                  className="group relative min-h-[190px] md:min-h-[220px] rounded-[2rem] border-2 border-gray-200 bg-white/90 hover:bg-white px-7 md:px-8 py-7 md:py-8 shadow-md hover:shadow-2xl transition-all"
                >
                  <div className="absolute -bottom-16 -left-16 w-56 h-56 bg-purple-300/20 rounded-full blur-3xl" />
                  <div className="relative flex items-start justify-between gap-5">
                    <div className="flex items-start gap-4">
                      <div className="w-14 h-14 md:w-16 md:h-16 rounded-2xl bg-gradient-to-br from-teal-500 to-emerald-500 flex items-center justify-center shadow-xl shadow-emerald-600/20 shrink-0">
                        <Sparkles className="w-7 h-7 md:w-8 md:h-8 text-white" />
                      </div>
                      <div>
                        <div className="text-xl md:text-2xl font-black text-gray-900">
                          {t("landing.choiceRoutineName")}
                        </div>
                        <div className="text-base md:text-lg text-gray-600 mt-2 leading-relaxed">
                          {t("landing.choiceRoutineDesc")}
                        </div>
                      </div>
                    </div>
                    <ArrowRight className="w-7 h-7 text-gray-700 shrink-0 group-hover:translate-x-1 transition-transform mt-1" />
                  </div>
                </button>
              </div>

              {/* subtle wave footer */}
              <div className="mt-8 md:mt-10 opacity-80">
                <svg viewBox="0 0 1440 120" className="w-full h-14 md:h-18">
                  <path
                    fill="rgba(20,184,166,0.12)"
                    d="M0,64L80,58.7C160,53,320,43,480,48C640,53,800,75,960,80C1120,85,1280,75,1360,69.3L1440,64L1440,120L1360,120C1280,120,1120,120,960,120C800,120,640,120,480,120C320,120,160,120,80,120L0,120Z"
                  >
                    <animate
                      attributeName="d"
                      dur="6s"
                      repeatCount="indefinite"
                      values="
                        M0,64L80,58.7C160,53,320,43,480,48C640,53,800,75,960,80C1120,85,1280,75,1360,69.3L1440,64L1440,120L0,120Z;
                        M0,70L80,80C160,90,320,110,480,96C640,82,800,34,960,26C1120,18,1280,50,1360,66L1440,82L1440,120L0,120Z;
                        M0,64L80,58.7C160,53,320,43,480,48C640,53,800,75,960,80C1120,85,1280,75,1360,69.3L1440,64L1440,120L0,120Z
                      "
                    />
                  </path>
                </svg>
              </div>
            </div>

            <div
              ref={revealRef}
              className={`transition-all duration-700 ${
                phase === "reveal" ? "opacity-100 translate-y-0" : "opacity-0 translate-y-3 pointer-events-none select-none"
              }`}
            >
              <div className="inline-flex items-center gap-2 bg-white/70 backdrop-blur px-4 py-2 rounded-full text-sm font-bold mb-6 border border-gray-200">
                <Leaf className="w-4 h-4 text-teal-600" />
                {t("landing.choicePicked")}{" "}
                <span className="text-teal-700">
                  {choice === "routine" ? t("landing.choiceRoutineName") : t("appName")}
                </span>
              </div>

              <div className="rounded-[2rem] border border-gray-200/90 bg-white/85 backdrop-blur-xl shadow-lg p-6 md:p-10 lg:p-12 text-left">
                <div className="flex items-start gap-4">
                  <div className="w-12 h-12 rounded-2xl bg-teal-50 border border-teal-100 flex items-center justify-center shrink-0">
                    <Leaf className="w-6 h-6 text-teal-600" />
                  </div>
                  <div className="min-w-0">
                    <h3 className="text-xl md:text-2xl font-bold text-gray-900">{t("landing.differenceTitle")}</h3>
                    <p className="text-base text-gray-600 mt-2 leading-relaxed">{t("landing.differenceSubtitle")}</p>
                  </div>
                </div>

                {/* Schema: Others vs Rebi */}
                <div className="mt-8 grid lg:grid-cols-2 gap-5 md:gap-6">
                  <div className="rounded-3xl border border-gray-200 bg-white/95 p-5 md:p-7 shadow-sm">
                    <div className="text-sm font-bold text-gray-700 mb-4">{t("landing.differenceSchemaOthers")}</div>
                    <div className="space-y-3">
                      <div className="flex items-center gap-3 rounded-2xl border border-gray-100 bg-gray-50 px-4 py-3.5 text-base text-gray-800">
                        <Camera className="w-5 h-5 text-gray-600 shrink-0" />
                        {t("landing.differenceSchemaOthersS1")}
                      </div>
                      <div className="flex justify-center text-gray-300 text-lg">↓</div>
                      <div className="flex items-center gap-3 rounded-2xl border border-gray-100 bg-gray-50 px-4 py-3.5 text-base text-gray-800">
                        <AlertTriangle className="w-5 h-5 text-amber-600 shrink-0" />
                        {t("landing.differenceSchemaOthersS2")}
                      </div>
                      <div className="flex justify-center text-gray-300 text-lg">↓</div>
                      <div className="flex items-center gap-3 rounded-2xl border border-gray-100 bg-gray-50 px-4 py-3.5 text-base text-gray-800">
                        <Shield className="w-5 h-5 text-gray-600 shrink-0" />
                        {t("landing.differenceSchemaOthersS3")}
                      </div>
                    </div>
                  </div>

                  <div className="relative rounded-3xl border-2 border-teal-300 bg-gradient-to-br from-teal-50 via-emerald-50/70 to-cyan-50 p-5 md:p-7 overflow-hidden shadow-md">
                    <div className="absolute -top-10 -right-10 w-40 h-40 bg-teal-300/25 rounded-full blur-3xl" />
                    <div className="absolute -bottom-12 -left-12 w-48 h-48 bg-emerald-300/20 rounded-full blur-3xl" />
                    <div className="absolute inset-0 opacity-50">
                      <svg viewBox="0 0 600 220" className="w-full h-full">
                        <defs>
                          <linearGradient id="revealWave" x1="0" x2="1" y1="0" y2="1">
                            <stop offset="0" stopColor="rgba(20,184,166,0.25)" />
                            <stop offset="1" stopColor="rgba(16,185,129,0.18)" />
                          </linearGradient>
                        </defs>
                        <path
                          fill="url(#revealWave)"
                          d="M0,160 C120,120 240,200 360,160 C480,120 540,120 600,140 L600,220 L0,220 Z"
                        >
                          <animate
                            attributeName="d"
                            dur="5s"
                            repeatCount="indefinite"
                            values="
                              M0,160 C120,120 240,200 360,160 C480,120 540,120 600,140 L600,220 L0,220 Z;
                              M0,150 C130,190 240,110 360,150 C480,190 540,170 600,150 L600,220 L0,220 Z;
                              M0,160 C120,120 240,200 360,160 C480,120 540,120 600,140 L600,220 L0,220 Z
                            "
                          />
                        </path>
                      </svg>
                    </div>
                    <div className="relative">
                      <div className="text-sm font-bold text-teal-900 mb-4">{t("landing.differenceSchemaUs")}</div>
                      <div className="space-y-3">
                        <div className="flex items-center gap-3 rounded-2xl border border-teal-200/70 bg-white/90 backdrop-blur px-4 py-3.5 text-base text-gray-900 shadow-sm">
                          <Brain className="w-5 h-5 text-teal-700 shrink-0" />
                          {t("landing.differenceSchemaUsS1")}
                        </div>
                        <div className="flex justify-center text-teal-500/70 font-bold text-lg">↓</div>
                        <div className="flex items-center gap-3 rounded-2xl border border-teal-200/70 bg-white/90 backdrop-blur px-4 py-3.5 text-base text-gray-900 shadow-sm">
                          <ClipboardCheck className="w-5 h-5 text-teal-700 shrink-0" />
                          {t("landing.differenceSchemaUsS2")}
                        </div>
                        <div className="flex justify-center text-teal-500/70 font-bold text-lg">↓</div>
                        <div className="flex items-center gap-3 rounded-2xl border border-teal-200/70 bg-white/90 backdrop-blur px-4 py-3.5 text-base text-gray-900 shadow-sm">
                          <Sparkles className="w-5 h-5 text-teal-700 shrink-0" />
                          {t("landing.differenceSchemaUsS3")}
                        </div>
                      </div>
                    </div>
                  </div>
                </div>

                <div className="grid sm:grid-cols-2 gap-4 mt-8">
                  <Link
                    to={choice === "rebi" ? rebiHref : cta.href}
                    className="group rounded-[1.25rem] border-2 border-teal-200 bg-teal-50/70 hover:bg-teal-50 px-6 py-5 md:py-6 flex items-center justify-between transition-colors min-h-[88px]"
                  >
                    <div className="flex items-center gap-4">
                      <div className="w-12 h-12 rounded-2xl bg-white border border-teal-100 flex items-center justify-center shrink-0">
                        <cta.icon className="w-6 h-6 text-teal-700" />
                      </div>
                      <div className="text-left">
                        <div className="text-base font-bold text-gray-900">
                          {choice === "rebi" ? t("landing.rebiOk") : cta.label}
                        </div>
                        <div className="text-sm text-gray-600">
                          {choice === "rebi" ? t("landing.rebiOkSub") : cta.sub}
                        </div>
                      </div>
                    </div>
                    <ChevronRight className="w-6 h-6 text-teal-700 group-hover:translate-x-0.5 transition-transform shrink-0" />
                  </Link>

                  <button
                    type="button"
                    onClick={() => {
                      setPhase("choice");
                      setChoice(null);
                      window.scrollTo({ top: 0, behavior: "smooth" });
                    }}
                    className="group rounded-[1.25rem] border-2 border-gray-200 bg-white hover:bg-gray-50 px-6 py-5 md:py-6 flex items-center justify-between transition-colors min-h-[88px]"
                  >
                    <div className="flex items-center gap-4">
                      <div className="w-12 h-12 rounded-2xl bg-gray-900 flex items-center justify-center shadow-sm shrink-0">
                        <ChevronRight className="w-6 h-6 text-white rotate-180" />
                      </div>
                      <div className="text-left">
                        <div className="text-base font-bold text-gray-900">{t("landing.changeChoice")}</div>
                        <div className="text-sm text-gray-600">{t("landing.changeChoiceSub")}</div>
                      </div>
                    </div>
                    <ArrowRight className="w-6 h-6 text-gray-700 group-hover:translate-x-0.5 transition-transform shrink-0" />
                  </button>
                </div>
              </div>

              <div className="mt-10 flex items-center justify-center gap-6 text-sm text-gray-400">
                <div className="flex items-center gap-1.5">
                  <Shield className="w-4 h-4 text-teal-500" />
                  {t("landing.badgeFree")}
                </div>
                <div className="flex items-center gap-1.5">
                  <Heart className="w-4 h-4 text-rose-400" />
                  {t("landing.badgeScientific")}
                </div>
                <div className="flex items-center gap-1.5">
                  <Star className="w-4 h-4 text-amber-400" />
                  {t("landing.badgePersonal")}
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* Rebi info overlay (front) */}
      {rebiInfoOpen && (
        <div className="fixed inset-0 z-[60] px-4 py-6 flex items-center justify-center">
          <div
            className="absolute inset-0 bg-slate-950/55 backdrop-blur-sm"
            onClick={() => setRebiInfoOpen(false)}
            aria-hidden="true"
          />
          <div className="relative w-full max-w-4xl">
            <div className="absolute -inset-4 bg-gradient-to-br from-teal-200/20 via-fuchsia-200/15 to-cyan-200/15 blur-2xl rounded-[3rem]" />
            <div className="relative rounded-[2.25rem] border border-white/15 bg-white/80 backdrop-blur-xl shadow-2xl p-5 md:p-8">
              <div className="text-left mb-4 md:mb-6">
                <div className="inline-flex items-center gap-2 bg-teal-50 text-teal-700 px-3.5 py-1.5 rounded-full text-xs font-bold border border-teal-100">
                  <MessageCircle className="w-4 h-4" />
                  {t("landing.rebiInfoPill")}
                </div>
                <h3 className="text-xl md:text-2xl font-black text-gray-900 mt-3">
                  {t("landing.rebiInfoTitle")}
                </h3>
                <p className="text-sm md:text-base text-gray-600 mt-2 leading-relaxed">
                  {t("landing.rebiInfoDesc")}
                </p>
              </div>

              {/* Differences only */}
              <div className="rounded-[2rem] border border-gray-200/90 bg-white/85 backdrop-blur-xl shadow-lg p-5 md:p-7 text-left">
                <div className="flex items-start gap-4">
                  <div className="w-12 h-12 rounded-2xl bg-teal-50 border border-teal-100 flex items-center justify-center shrink-0">
                    <Leaf className="w-6 h-6 text-teal-600" />
                  </div>
                  <div className="min-w-0">
                    <h4 className="text-lg md:text-xl font-bold text-gray-900">{t("landing.differenceTitle")}</h4>
                    <p className="text-sm md:text-base text-gray-600 mt-1.5 leading-relaxed">
                      {t("landing.differenceSubtitle")}
                    </p>
                  </div>
                </div>

                <div className="mt-6 grid lg:grid-cols-2 gap-4 md:gap-5">
                  <div className="rounded-3xl border border-gray-200 bg-white/95 p-5 md:p-6 shadow-sm">
                    <div className="text-sm font-bold text-gray-700 mb-4">{t("landing.differenceSchemaOthers")}</div>
                    <div className="space-y-3">
                      <div className="flex items-center gap-3 rounded-2xl border border-gray-100 bg-gray-50 px-4 py-3.5 text-base text-gray-800">
                        <Camera className="w-5 h-5 text-gray-600 shrink-0" />
                        {t("landing.differenceSchemaOthersS1")}
                      </div>
                      <div className="flex justify-center text-gray-300 text-lg">↓</div>
                      <div className="flex items-center gap-3 rounded-2xl border border-gray-100 bg-gray-50 px-4 py-3.5 text-base text-gray-800">
                        <AlertTriangle className="w-5 h-5 text-amber-600 shrink-0" />
                        {t("landing.differenceSchemaOthersS2")}
                      </div>
                      <div className="flex justify-center text-gray-300 text-lg">↓</div>
                      <div className="flex items-center gap-3 rounded-2xl border border-gray-100 bg-gray-50 px-4 py-3.5 text-base text-gray-800">
                        <Shield className="w-5 h-5 text-gray-600 shrink-0" />
                        {t("landing.differenceSchemaOthersS3")}
                      </div>
                    </div>
                  </div>

                  <div className="relative rounded-3xl border-2 border-teal-300 bg-gradient-to-br from-teal-50 via-emerald-50/70 to-cyan-50 p-5 md:p-6 overflow-hidden shadow-md">
                    <div className="absolute -top-10 -right-10 w-40 h-40 bg-teal-300/25 rounded-full blur-3xl" />
                    <div className="absolute -bottom-12 -left-12 w-48 h-48 bg-emerald-300/20 rounded-full blur-3xl" />
                    <div className="relative">
                      <div className="text-sm font-bold text-teal-900 mb-4">{t("landing.differenceSchemaUs")}</div>
                      <div className="space-y-3">
                        <div className="flex items-center gap-3 rounded-2xl border border-teal-200/70 bg-white/90 backdrop-blur px-4 py-3.5 text-base text-gray-900 shadow-sm">
                          <Brain className="w-5 h-5 text-teal-700 shrink-0" />
                          {t("landing.differenceSchemaUsS1")}
                        </div>
                        <div className="flex justify-center text-teal-500/70 font-bold text-lg">↓</div>
                        <div className="flex items-center gap-3 rounded-2xl border border-teal-200/70 bg-white/90 backdrop-blur px-4 py-3.5 text-base text-gray-900 shadow-sm">
                          <ClipboardCheck className="w-5 h-5 text-teal-700 shrink-0" />
                          {t("landing.differenceSchemaUsS2")}
                        </div>
                        <div className="flex justify-center text-teal-500/70 font-bold text-lg">↓</div>
                        <div className="flex items-center gap-3 rounded-2xl border border-teal-200/70 bg-white/90 backdrop-blur px-4 py-3.5 text-base text-gray-900 shadow-sm">
                          <Sparkles className="w-5 h-5 text-teal-700 shrink-0" />
                          {t("landing.differenceSchemaUsS3")}
                        </div>
                      </div>
                    </div>
                  </div>
                </div>

                <div className="mt-6 flex flex-col sm:flex-row gap-3">
                  <Link
                    to={rebiHref}
                    onClick={() => setRebiInfoOpen(false)}
                    className="btn-primary w-full sm:w-auto inline-flex justify-center !px-8"
                  >
                    {t("landing.rebiOk")}
                    <ArrowRight className="w-5 h-5" />
                  </Link>
                  <button
                    type="button"
                    onClick={() => setRebiInfoOpen(false)}
                    className="btn-secondary w-full sm:w-auto inline-flex justify-center !px-8 !border-gray-200 !text-gray-800"
                  >
                    {t("common.close")}
                  </button>
                </div>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Differences (horizontal section) */}
      <section className="py-10 md:py-12">
        <div className="max-w-6xl mx-auto px-4">
          <div className="flex items-end justify-between gap-4 mb-5">
            <div>
              <h2 className="text-xl md:text-2xl font-black text-gray-900">{t("landing.differenceTitle")}</h2>
              <p className="text-sm text-gray-600 mt-1">{t("landing.differenceSubtitle")}</p>
            </div>
            <a
              href="#"
              onClick={(e) => { e.preventDefault(); window.scrollTo({ top: 0, behavior: "smooth" }); }}
              className="hidden md:inline-flex text-sm font-semibold text-teal-700 hover:text-teal-800 underline-offset-2 hover:underline"
            >
              {t("landing.entryHint")}
            </a>
          </div>

          <div className="overflow-x-auto pb-2 -mx-4 px-4">
            <div className="min-w-[900px] grid grid-cols-9 gap-3 items-stretch">
              <div className="col-span-4 rounded-3xl border border-gray-200 bg-white p-5 shadow-sm">
                <div className="text-sm font-bold text-gray-700 mb-4">{t("landing.differenceSchemaOthers")}</div>
                <div className="grid grid-cols-5 gap-2 items-center">
                  <div className="col-span-2 flex items-center gap-2 rounded-2xl border border-gray-100 bg-gray-50 px-3 py-3 text-sm text-gray-800">
                    <Camera className="w-4 h-4 text-gray-600 shrink-0" />
                    <span className="min-w-0">{t("landing.differenceSchemaOthersS1")}</span>
                  </div>
                  <div className="col-span-1 flex justify-center text-gray-300 font-black">→</div>
                  <div className="col-span-2 flex items-center gap-2 rounded-2xl border border-gray-100 bg-gray-50 px-3 py-3 text-sm text-gray-800">
                    <AlertTriangle className="w-4 h-4 text-amber-600 shrink-0" />
                    <span className="min-w-0">{t("landing.differenceSchemaOthersS2")}</span>
                  </div>
                  <div className="col-span-5 flex items-center gap-2 rounded-2xl border border-gray-100 bg-gray-50 px-3 py-3 text-sm text-gray-800">
                    <Shield className="w-4 h-4 text-gray-600 shrink-0" />
                    <span className="min-w-0">{t("landing.differenceSchemaOthersS3")}</span>
                  </div>
                </div>
              </div>

              <div className="col-span-1 flex items-center justify-center">
                <div className="w-12 h-12 rounded-2xl bg-gradient-to-br from-teal-600 to-emerald-500 text-white flex items-center justify-center shadow-lg shadow-teal-600/20">
                  <ArrowRight className="w-6 h-6" />
                </div>
              </div>

              <div className="col-span-4 relative rounded-3xl border-2 border-teal-300 bg-gradient-to-br from-teal-50 via-emerald-50/70 to-cyan-50 p-5 shadow-sm overflow-hidden">
                <div className="absolute -top-10 -right-10 w-44 h-44 bg-teal-300/25 rounded-full blur-3xl" />
                <div className="absolute -bottom-12 -left-12 w-56 h-56 bg-emerald-300/20 rounded-full blur-3xl" />
                <div className="relative">
                  <div className="text-sm font-bold text-teal-900 mb-4">{t("landing.differenceSchemaUs")}</div>
                  <div className="grid grid-cols-5 gap-2 items-center">
                    <div className="col-span-2 flex items-center gap-2 rounded-2xl border border-teal-200/70 bg-white/90 backdrop-blur px-3 py-3 text-sm text-gray-900 shadow-sm">
                      <Brain className="w-4 h-4 text-teal-700 shrink-0" />
                      <span className="min-w-0">{t("landing.differenceSchemaUsS1")}</span>
                    </div>
                    <div className="col-span-1 flex justify-center text-teal-500/70 font-black">→</div>
                    <div className="col-span-2 flex items-center gap-2 rounded-2xl border border-teal-200/70 bg-white/90 backdrop-blur px-3 py-3 text-sm text-gray-900 shadow-sm">
                      <ClipboardCheck className="w-4 h-4 text-teal-700 shrink-0" />
                      <span className="min-w-0">{t("landing.differenceSchemaUsS2")}</span>
                    </div>
                    <div className="col-span-5 flex items-center gap-2 rounded-2xl border border-teal-200/70 bg-white/90 backdrop-blur px-3 py-3 text-sm text-gray-900 shadow-sm">
                      <Sparkles className="w-4 h-4 text-teal-700 shrink-0" />
                      <span className="min-w-0">{t("landing.differenceSchemaUsS3")}</span>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <div className="mt-4 text-[11px] text-gray-500 md:hidden">
            Yatay kaydırarak tamamını görebilirsin.
          </div>
        </div>
      </section>

      {/* Rebi Plus — premium görsel blok */}
      <section className="py-12 md:py-14 relative overflow-hidden">
        <div className="absolute inset-0 bg-gradient-to-b from-slate-900 via-violet-950/95 to-slate-900" />
        <div
          className="absolute inset-0 opacity-40"
          style={{
            backgroundImage:
              "radial-gradient(circle at 20% 30%, rgba(167,139,250,0.35) 0%, transparent 45%), radial-gradient(circle at 80% 70%, rgba(244,114,182,0.25) 0%, transparent 40%)",
          }}
        />
        <div className="relative max-w-6xl mx-auto px-4">
          <div className="text-center mb-12 md:mb-14">
            <div className="inline-flex items-center gap-2 rounded-full bg-white/10 border border-white/15 px-4 py-2 text-sm font-medium text-amber-200 mb-6">
              <Crown className="w-4 h-4 text-amber-300" />
              {t("landing.plusBadge")}
            </div>
            <h2 className="text-3xl md:text-4xl font-bold text-white mb-4 tracking-tight">
              {t("landing.plusTitle")}
            </h2>
            <p className="text-violet-200/90 text-lg max-w-2xl mx-auto leading-relaxed">
              {t("landing.plusDesc")}
            </p>
          </div>
          <div className="grid md:grid-cols-3 gap-5 md:gap-6">
            {plusHighlights.map((item, i) => (
              <div
                key={i}
                className={`group relative rounded-3xl border border-white/10 bg-white/5 backdrop-blur-md p-6 md:p-7 shadow-xl ${item.glow} hover:bg-white/10 transition-all duration-300`}
              >
                <div
                  className={`w-14 h-14 rounded-2xl bg-gradient-to-br ${item.gradient} flex items-center justify-center mb-5 shadow-lg group-hover:scale-105 transition-transform`}
                >
                  <item.icon className="w-7 h-7 text-white" />
                </div>
                <h3 className="text-xl font-bold text-white mb-2">{t(item.titleKey)}</h3>
                <p className="text-sm text-violet-100/85 leading-relaxed">{t(item.descKey)}</p>
                <div className="mt-4 flex items-center gap-1.5 text-xs font-semibold text-amber-200/90">
                  <Lock className="w-3.5 h-3.5" />
                  {t("landing.plusUnlockHint")}
                </div>
              </div>
            ))}
          </div>
          <div className="text-center mt-10">
            <Link
              to={user ? "/dashboard/subscribe" : "/auth"}
              className="inline-flex items-center gap-2 rounded-2xl bg-white text-violet-950 font-bold px-8 py-4 text-base shadow-lg shadow-black/20 hover:bg-violet-50 transition-colors"
            >
              <Crown className="w-5 h-5 text-amber-600" />
              {t("landing.plusCta")}
              <ArrowRight className="w-5 h-5" />
            </Link>
          </div>
        </div>
      </section>

      {/* Features */}
      <section id="features" className="py-12 md:py-16">
        <div className="max-w-6xl mx-auto px-4">
          <div className="text-center mb-10 md:mb-12">
            <h2 className="text-3xl md:text-4xl font-bold text-gray-900 mb-4">{t("landing.featuresTitle")}</h2>
            <p className="text-gray-500 text-lg max-w-xl mx-auto">{t("landing.featuresSubtitle")}</p>
            <p className="text-gray-600 text-sm max-w-2xl mx-auto mt-4 leading-relaxed">{t("landing.disclaimer")}</p>
          </div>

          <div className="grid md:grid-cols-3 gap-6 md:gap-8">
            {features.map((f, i) => (
              <div
                key={i}
                className="card hover:shadow-xl hover:-translate-y-1 transition-all duration-300 group"
              >
                <div
                  className={`w-14 h-14 ${f.bg} rounded-2xl flex items-center justify-center mb-5 group-hover:scale-110 transition-transform`}
                >
                  <f.icon className={`w-7 h-7 bg-gradient-to-br ${f.color} bg-clip-text`} style={{color: f.color.includes('pink') ? '#ec4899' : f.color.includes('purple') ? '#8b5cf6' : '#3b82f6'}} />
                </div>
                <h3 className="text-xl font-bold text-gray-900 mb-2">{t(f.titleKey)}</h3>
                <p className="text-gray-500 leading-relaxed">{t(f.descKey)}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* How It Works */}
      <section className="py-12 md:py-16 bg-gradient-to-b from-white to-teal-50/50">
        <div className="max-w-4xl mx-auto px-4">
          <div className="text-center mb-10 md:mb-12">
            <h2 className="text-3xl md:text-4xl font-bold text-gray-900 mb-4">
              {t("landing.howItWorksTitle")}
            </h2>
          </div>

          <div className="space-y-6">
            {steps.map((s, i) => (
              <div
                key={i}
                className="flex items-start gap-6 p-6 rounded-3xl bg-white border border-gray-100 hover:shadow-lg transition-shadow group"
              >
                <div className="w-14 h-14 bg-gradient-to-br from-teal-500 to-teal-600 rounded-2xl flex items-center justify-center text-white font-bold text-lg shrink-0 group-hover:scale-110 transition-transform shadow-lg shadow-teal-500/20">
                  {s.num}
                </div>
                <div>
                  <h3 className="text-xl font-bold text-gray-900 mb-1">
                    {t(s.titleKey)}
                  </h3>
                  <p className="text-gray-500">{t(s.descKey)}</p>
                </div>
                <ChevronRight className="w-5 h-5 text-gray-300 shrink-0 mt-1 ml-auto" />
              </div>
            ))}
          </div>

          <div className="text-center mt-10">
            <Link
              to={user ? "/dashboard/analyze" : "/auth"}
              className="btn-primary !px-8 !py-4 !text-lg inline-flex group"
            >
              {t("landing.ctaStartNow")}
              <ArrowRight className="w-5 h-5 group-hover:translate-x-1 transition-transform" />
            </Link>
          </div>
        </div>
      </section>

      {/* Footer */}
      <footer className="py-10 border-t border-gray-100">
        <div className="max-w-6xl mx-auto px-4 flex flex-col md:flex-row items-center justify-between gap-4">
          <div className="flex items-center gap-2">
            <div className="w-8 h-8 bg-gradient-to-br from-teal-500 to-teal-600 rounded-lg flex items-center justify-center">
              <Leaf className="w-4 h-4 text-white" />
            </div>
            <span className="font-bold text-gray-900">Rebi</span>
          </div>
          <p className="text-sm text-gray-400">
            {t("landing.footer")}
          </p>
        </div>
      </footer>
    </div>
  );
}
