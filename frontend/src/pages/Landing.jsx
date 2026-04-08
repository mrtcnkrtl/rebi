import { Link, useNavigate } from "react-router-dom";
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
  const navigate = useNavigate();
  const [choice, setChoice] = useState(null); // "rebi" | "routine" | null
  const [phase, setPhase] = useState("choice"); // "choice" | "reveal"
  const revealRef = useRef(null);
  const isAuthed = Boolean(user);
  const nextAnalyze = "/dashboard/analyze";
  const nextSubscribe = "/dashboard/subscribe";

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
      href: isAuthed ? "/dashboard/chat" : "/rebi",
      label: t("landing.ctaChat"),
      sub: t("nav.chat"),
      icon: MessageCircle,
    };
  }, [choice, isAuthed, t]);

  useEffect(() => {
    if (phase !== "reveal") return;
    const id = window.setTimeout(() => {
      revealRef.current?.scrollIntoView({ behavior: "smooth", block: "start" });
    }, 450);
    return () => window.clearTimeout(id);
  }, [phase]);

  const pick = (next) => {
    setChoice(next);
    setPhase("reveal");
  };

  return (
    <div className="min-h-screen bg-gradient-to-b from-warm-50 via-white to-teal-50/30">
      {/* Hero */}
      <section className="relative overflow-hidden">
        <HeroBackgroundVideo />
        <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_top,_var(--tw-gradient-stops))] from-teal-100/40 via-transparent to-transparent" />
        <div className="absolute top-20 right-10 w-72 h-72 bg-teal-200/20 rounded-full blur-3xl" />
        <div className="absolute bottom-10 left-10 w-96 h-96 bg-purple-200/10 rounded-full blur-3xl" />

        <div className="relative max-w-6xl mx-auto px-4 pt-20 pb-24 md:pt-32 md:pb-36">
          <div className="text-center max-w-3xl mx-auto">
            <div
              className={`transition-all duration-700 ${
                phase === "choice" ? "opacity-100 translate-y-0" : "opacity-0 -translate-y-3 pointer-events-none select-none"
              }`}
            >
              <div className="inline-flex items-center gap-2 bg-teal-50 text-teal-700 px-4 py-2 rounded-full text-sm font-medium mb-6 border border-teal-100">
                <Sparkles className="w-4 h-4" />
                {t("landing.heroBadge")}
              </div>

              <h1 className="text-4xl md:text-6xl font-bold text-gray-900 leading-tight mb-4 tracking-tight">
                Bugün hangisi?
              </h1>
              <p className="text-base md:text-lg text-gray-600 mb-8">
                <span className="font-semibold text-gray-900">Rebi</span> ile sohbet mi, yoksa{" "}
                <span className="font-semibold text-gray-900">Rutin</span> mi?
              </p>

              <div className="grid sm:grid-cols-2 gap-4 text-left">
                <button
                  type="button"
                  onClick={() => pick("rebi")}
                  className="group relative rounded-3xl border-2 border-teal-200 bg-white/70 backdrop-blur hover:bg-white px-6 py-6 shadow-sm hover:shadow-xl transition-all"
                >
                  <div className="absolute -top-10 -right-10 w-44 h-44 bg-teal-300/25 rounded-full blur-3xl" />
                  <div className="relative flex items-start justify-between gap-4">
                    <div className="flex items-start gap-3">
                      <div className="w-12 h-12 rounded-2xl bg-teal-600 flex items-center justify-center shadow-lg shadow-teal-600/20">
                        <MessageCircle className="w-6 h-6 text-white" />
                      </div>
                      <div>
                        <div className="text-lg font-black text-gray-900">Rebi</div>
                        <div className="text-sm text-gray-600 mt-1 leading-relaxed">
                          Sor, fotoğrafla, takip et. Dalgalar gibi akarak yönlendirsin.
                        </div>
                        <div className="mt-3 text-xs font-semibold text-teal-800/90">
                          Demo ile başla → sınırda giriş + Plus
                        </div>
                      </div>
                    </div>
                    <ChevronRight className="w-6 h-6 text-teal-700 group-hover:translate-x-1 transition-transform" />
                  </div>
                </button>

                <button
                  type="button"
                  onClick={() => pick("routine")}
                  className="group relative rounded-3xl border-2 border-gray-200 bg-white hover:bg-gray-50 px-6 py-6 shadow-sm hover:shadow-xl transition-all"
                >
                  <div className="absolute -bottom-10 -left-10 w-44 h-44 bg-purple-300/15 rounded-full blur-3xl" />
                  <div className="relative flex items-start justify-between gap-4">
                    <div className="flex items-start gap-3">
                      <div className="w-12 h-12 rounded-2xl bg-gradient-to-br from-teal-500 to-emerald-500 flex items-center justify-center shadow-lg shadow-emerald-600/15">
                        <Sparkles className="w-6 h-6 text-white" />
                      </div>
                      <div>
                        <div className="text-lg font-black text-gray-900">Rutin</div>
                        <div className="text-sm text-gray-600 mt-1 leading-relaxed">
                          Profilini çıkar, rutini kur, günlük check-in ile güncelle.
                        </div>
                        <div className="mt-3 text-xs font-semibold text-gray-700">
                          Başlamadan önce kayıt/giriş gerekli
                        </div>
                      </div>
                    </div>
                    <ArrowRight className="w-6 h-6 text-gray-700 group-hover:translate-x-1 transition-transform" />
                  </div>
                </button>
              </div>

              {/* subtle wave footer */}
              <div className="mt-10 opacity-70">
                <svg viewBox="0 0 1440 120" className="w-full h-16">
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
                Seçim:{" "}
                <span className="text-teal-700">{choice === "routine" ? "Rutin" : "Rebi"}</span>
              </div>

              <div className="rounded-3xl border border-gray-200 bg-white/80 backdrop-blur-md shadow-sm p-5 md:p-6 text-left">
                <div className="flex items-start gap-3">
                  <div className="w-10 h-10 rounded-2xl bg-teal-50 border border-teal-100 flex items-center justify-center shrink-0">
                    <Leaf className="w-5 h-5 text-teal-600" />
                  </div>
                  <div className="min-w-0">
                    <h3 className="text-base md:text-lg font-bold text-gray-900">{t("landing.differenceTitle")}</h3>
                    <p className="text-sm text-gray-600 mt-1 leading-relaxed">{t("landing.differenceSubtitle")}</p>
                  </div>
                </div>

                {/* Schema: Others vs Rebi */}
                <div className="mt-5 grid md:grid-cols-2 gap-3">
                  <div className="rounded-2xl border border-gray-200 bg-white p-4">
                    <div className="text-xs font-bold text-gray-700 mb-3">{t("landing.differenceSchemaOthers")}</div>
                    <div className="space-y-2">
                      <div className="flex items-center gap-2 rounded-xl border border-gray-100 bg-gray-50 px-3 py-2 text-sm text-gray-800">
                        <Camera className="w-4 h-4 text-gray-600" />
                        {t("landing.differenceSchemaOthersS1")}
                      </div>
                      <div className="flex justify-center text-gray-300">↓</div>
                      <div className="flex items-center gap-2 rounded-xl border border-gray-100 bg-gray-50 px-3 py-2 text-sm text-gray-800">
                        <AlertTriangle className="w-4 h-4 text-amber-600" />
                        {t("landing.differenceSchemaOthersS2")}
                      </div>
                      <div className="flex justify-center text-gray-300">↓</div>
                      <div className="flex items-center gap-2 rounded-xl border border-gray-100 bg-gray-50 px-3 py-2 text-sm text-gray-800">
                        <Shield className="w-4 h-4 text-gray-600" />
                        {t("landing.differenceSchemaOthersS3")}
                      </div>
                    </div>
                  </div>

                  <div className="relative rounded-2xl border-2 border-teal-300 bg-gradient-to-br from-teal-50 via-emerald-50/70 to-cyan-50 p-4 overflow-hidden">
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
                      <div className="text-xs font-bold text-teal-900 mb-3">{t("landing.differenceSchemaUs")}</div>
                      <div className="space-y-2">
                        <div className="flex items-center gap-2 rounded-xl border border-teal-200/70 bg-white/85 backdrop-blur px-3 py-2 text-sm text-gray-900 shadow-sm">
                          <Brain className="w-4 h-4 text-teal-700" />
                          {t("landing.differenceSchemaUsS1")}
                        </div>
                        <div className="flex justify-center text-teal-500/70 font-bold">↓</div>
                        <div className="flex items-center gap-2 rounded-xl border border-teal-200/70 bg-white/85 backdrop-blur px-3 py-2 text-sm text-gray-900 shadow-sm">
                          <ClipboardCheck className="w-4 h-4 text-teal-700" />
                          {t("landing.differenceSchemaUsS2")}
                        </div>
                        <div className="flex justify-center text-teal-500/70 font-bold">↓</div>
                        <div className="flex items-center gap-2 rounded-xl border border-teal-200/70 bg-white/85 backdrop-blur px-3 py-2 text-sm text-gray-900 shadow-sm">
                          <Sparkles className="w-4 h-4 text-teal-700" />
                          {t("landing.differenceSchemaUsS3")}
                        </div>
                      </div>
                    </div>
                  </div>
                </div>

                <div className="mt-5 text-xs font-semibold text-gray-500">
                  {choice === "routine"
                    ? "Rutin için kayıt/giriş zorunlu. (Devam edince yönlendireceğim.)"
                    : "Rebi demo ile başlar; sınırı geçince giriş + Rebi Plus önerilir."}
                </div>

                <div className="grid sm:grid-cols-2 gap-3 mt-3">
                  <Link
                    to={cta.href}
                    className="group rounded-2xl border-2 border-teal-200 bg-teal-50/60 hover:bg-teal-50 px-5 py-4 flex items-center justify-between transition-colors"
                  >
                    <div className="flex items-center gap-3">
                      <div className="w-10 h-10 rounded-2xl bg-white border border-teal-100 flex items-center justify-center">
                        <cta.icon className="w-5 h-5 text-teal-700" />
                      </div>
                      <div className="text-left">
                        <div className="text-sm font-bold text-gray-900">{cta.label}</div>
                        <div className="text-xs text-gray-600">{cta.sub}</div>
                      </div>
                    </div>
                    <ChevronRight className="w-5 h-5 text-teal-700 group-hover:translate-x-0.5 transition-transform" />
                  </Link>

                  <button
                    type="button"
                    onClick={() => {
                      setPhase("choice");
                      setChoice(null);
                      window.scrollTo({ top: 0, behavior: "smooth" });
                    }}
                    className="group rounded-2xl border-2 border-gray-200 bg-white hover:bg-gray-50 px-5 py-4 flex items-center justify-between transition-colors"
                  >
                    <div className="flex items-center gap-3">
                      <div className="w-10 h-10 rounded-2xl bg-gray-900 flex items-center justify-center shadow-sm">
                        <ChevronRight className="w-5 h-5 text-white rotate-180" />
                      </div>
                      <div className="text-left">
                        <div className="text-sm font-bold text-gray-900">Değiştir</div>
                        <div className="text-xs text-gray-600">Başa dön</div>
                      </div>
                    </div>
                    <ArrowRight className="w-5 h-5 text-gray-700 group-hover:translate-x-0.5 transition-transform" />
                  </button>
                </div>

                {!isAuthed && choice === "rebi" && (
                  <div className="mt-4 rounded-2xl border border-amber-200 bg-amber-50 px-4 py-3 text-xs text-amber-900 flex items-start gap-2">
                    <Lock className="w-4 h-4 mt-0.5 shrink-0" />
                    <div className="min-w-0">
                      <div className="font-bold">Sınırda ne olacak?</div>
                      <div className="mt-0.5">
                        Demo sohbetten sonra <span className="font-semibold">giriş</span> ve{" "}
                        <span className="font-semibold">Rebi Plus</span> isteyeceğiz.
                        <button
                          type="button"
                          onClick={() => navigate(`/auth?next=${encodeURIComponent(nextSubscribe)}`)}
                          className="ml-2 underline underline-offset-2 font-semibold"
                        >
                          Şimdiden Plus’a geç
                        </button>
                      </div>
                    </div>
                  </div>
                )}
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

      {/* Rebi Plus — premium görsel blok */}
      <section className="py-16 md:py-20 relative overflow-hidden">
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
      <section id="features" className="py-20 md:py-28">
        <div className="max-w-6xl mx-auto px-4">
          <div className="text-center mb-16">
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
      <section className="py-20 bg-gradient-to-b from-white to-teal-50/50">
        <div className="max-w-4xl mx-auto px-4">
          <div className="text-center mb-16">
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

          <div className="text-center mt-12">
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
