import { Link } from "react-router-dom";
import { useTheme } from "../context/ThemeContext";
import { useAuth } from "../context/AuthContext";
import { Sparkles, Crown, MessageCircle, Palette, ExternalLink, Check, Shield } from "lucide-react";
import ThemePatternOverlay from "../components/ThemePatternOverlay";
import { useTranslation } from "react-i18next";

const CHECKOUT_URL = import.meta.env.VITE_REBI_PLUS_CHECKOUT_URL || "";

export default function Subscribe() {
  const { theme } = useTheme();
  const { user } = useAuth();
  const { t } = useTranslation();
  const plus =
    user?.user_metadata?.rebi_plus === true ||
    ["plus", "pro", "premium"].includes(
      String(user?.user_metadata?.subscription_tier || "").toLowerCase()
    );

  return (
    <div className={`min-h-screen ${theme.bg} pb-28 relative overflow-hidden`}>
      <ThemePatternOverlay pattern={theme.pattern} />
      <div className="absolute inset-0">
        <div className="absolute inset-0 bg-gradient-to-b from-slate-950 via-violet-950/95 to-slate-900 opacity-90" />
        <div
          className="absolute inset-0 opacity-55"
          style={{
            backgroundImage:
              "radial-gradient(circle at 18% 25%, rgba(167,139,250,0.45) 0%, transparent 44%), radial-gradient(circle at 82% 70%, rgba(244,114,182,0.28) 0%, transparent 40%), radial-gradient(circle at 40% 110%, rgba(34,211,238,0.18) 0%, transparent 45%)",
          }}
        />
      </div>

      <div className="max-w-lg mx-auto px-4 py-10 relative z-[1]">
        <div className="text-center mb-7">
          <div
            className="w-16 h-16 rounded-3xl flex items-center justify-center text-white shadow-2xl shadow-fuchsia-500/15 mx-auto mb-4"
            style={{ background: `linear-gradient(135deg, ${theme.accent}, ${theme.primary})` }}
          >
            <Crown className="w-8 h-8" />
          </div>
          <div className="inline-flex items-center gap-2 rounded-full bg-white/10 border border-white/15 px-4 py-2 text-sm font-semibold text-amber-200 mb-4">
            <Sparkles className="w-4 h-4 text-amber-300" />
            Rebi Plus
          </div>
          <h1 className="text-3xl font-black text-white tracking-tight">{t("subscribe.title")}</h1>
          <p className="text-sm text-violet-100/80 mt-2 leading-relaxed">{t("subscribe.subtitle")}</p>
        </div>

        {plus && (
          <div
            className="mb-6 rounded-3xl border border-emerald-300/25 bg-emerald-500/10 backdrop-blur px-5 py-4 text-emerald-100 text-sm"
          >
            <div className="flex items-start gap-2">
              <Check className="w-4 h-4 mt-0.5 text-emerald-300 shrink-0" />
              <div className="min-w-0">
                <div className="font-bold text-emerald-100">Plus aktif</div>
                <div className="text-emerald-100/80 mt-0.5">Hesabında Rebi Plus görünüyor. Teşekkürler.</div>
              </div>
            </div>
          </div>
        )}

        <div className="rounded-[2rem] border border-white/10 bg-white/5 backdrop-blur-xl p-6 md:p-7 mb-6 shadow-2xl shadow-black/20">
          <h2 className="font-black text-white mb-5 tracking-tight text-xl">Neler dahil?</h2>

          <div className="grid gap-4">
            <div className="group relative rounded-3xl border border-white/10 bg-gradient-to-br from-white/10 to-white/5 p-5 overflow-hidden shadow-xl shadow-black/20 hover:bg-white/10 transition-colors">
              <div className="absolute -top-12 -right-12 w-44 h-44 bg-amber-400/15 rounded-full blur-3xl" />
              <div className="relative flex items-start gap-4">
                <div className="w-12 h-12 rounded-2xl bg-white/10 border border-white/10 flex items-center justify-center shrink-0">
                  <MessageCircle className="w-6 h-6 text-amber-200" />
                </div>
                <div className="min-w-0">
                  <div className="text-lg font-extrabold text-white">Sınırsız Rebi AI</div>
                  <div className="text-sm text-white/75 mt-1 leading-relaxed">
                    Günlük ücretsiz mesaj limiti kalkar; sohbet kesilmez.
                  </div>
                </div>
              </div>
            </div>

            <div className="group relative rounded-3xl border border-white/10 bg-gradient-to-br from-white/10 to-white/5 p-5 overflow-hidden shadow-xl shadow-black/20 hover:bg-white/10 transition-colors">
              <div className="absolute -bottom-12 -left-12 w-44 h-44 bg-cyan-400/15 rounded-full blur-3xl" />
              <div className="relative flex items-start gap-4">
                <div className="w-12 h-12 rounded-2xl bg-white/10 border border-white/10 flex items-center justify-center shrink-0">
                  <Palette className="w-6 h-6 text-cyan-200" />
                </div>
                <div className="min-w-0">
                  <div className="text-lg font-extrabold text-white">Premium temalar</div>
                  <div className="text-sm text-white/75 mt-1 leading-relaxed">
                    Ayırt edici renkler, desenler ve daha “premium” his.
                  </div>
                </div>
              </div>
            </div>

            <div className="group relative rounded-3xl border border-white/10 bg-gradient-to-br from-white/10 to-white/5 p-5 overflow-hidden shadow-xl shadow-black/20 hover:bg-white/10 transition-colors">
              <div className="absolute -top-12 -left-12 w-44 h-44 bg-fuchsia-400/15 rounded-full blur-3xl" />
              <div className="relative flex items-start gap-4">
                <div className="w-12 h-12 rounded-2xl bg-white/10 border border-white/10 flex items-center justify-center shrink-0">
                  <Sparkles className="w-6 h-6 text-fuchsia-200" />
                </div>
                <div className="min-w-0">
                  <div className="text-lg font-extrabold text-white">Öncelikli yenilikler</div>
                  <div className="text-sm text-white/75 mt-1 leading-relaxed">
                    Yeni özellikler önce Plus’a gelir; ilk sen denersin.
                  </div>
                </div>
              </div>
            </div>

            <div className="group relative rounded-3xl border border-white/10 bg-gradient-to-br from-white/10 to-white/5 p-5 overflow-hidden shadow-xl shadow-black/20 hover:bg-white/10 transition-colors">
              <div className="absolute -bottom-12 -right-12 w-44 h-44 bg-emerald-400/15 rounded-full blur-3xl" />
              <div className="relative flex items-start gap-4">
                <div className="w-12 h-12 rounded-2xl bg-white/10 border border-white/10 flex items-center justify-center shrink-0">
                  <Shield className="w-6 h-6 text-emerald-200" />
                </div>
                <div className="min-w-0">
                  <div className="text-lg font-extrabold text-white">Daha derin takip</div>
                  <div className="text-sm text-white/75 mt-1 leading-relaxed">
                    Check-in akışı daha güçlü çalışır; rutinin daha iyi uyarlanır.
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>

        <div className="rounded-[2rem] border border-white/10 bg-white/5 backdrop-blur-xl p-6 md:p-7 space-y-3 shadow-2xl shadow-black/20">
          <p className="text-xs text-white/70 leading-relaxed">
            Ödeme bağlantısı hazır olduğunda buraya yönlendirileceksin. Şimdilik ödeme altyapısı
            (Stripe, iyzico vb.) projeye eklendiğinde{" "}
            <code className="text-[11px] bg-white/10 px-1 rounded">VITE_REBI_PLUS_CHECKOUT_URL</code>{" "}
            ortam değişkeni ile ödeme sayfası açılır.
          </p>
          {CHECKOUT_URL ? (
            <a
              href={CHECKOUT_URL}
              target="_blank"
              rel="noopener noreferrer"
              className="w-full inline-flex items-center justify-center gap-2 rounded-2xl bg-white text-violet-950 font-extrabold px-6 py-4 shadow-xl shadow-black/25 hover:bg-violet-50 transition-colors"
            >
              Plus’ı aç <ExternalLink className="w-4 h-4" />
            </a>
          ) : (
            <div className="rounded-2xl border border-amber-300/20 bg-amber-500/10 px-4 py-3 text-xs text-amber-100/90">
              Ödeme URL’si tanımlı değil. Stripe/iyzico linkini alıp frontend ortamına ekleyin.
              <div className="mt-1 text-[11px] text-amber-100/70">
                (Dev: <code className="bg-white/10 px-1 rounded">VITE_REBI_PLUS_CHECKOUT_URL</code>)
              </div>
            </div>
          )}
        </div>

        <Link
          to="/dashboard/chat"
          className="mt-7 block text-center text-sm font-semibold underline-offset-2 hover:underline text-white/80 hover:text-white transition-colors"
        >
          Sohbete dön
        </Link>
      </div>
    </div>
  );
}
