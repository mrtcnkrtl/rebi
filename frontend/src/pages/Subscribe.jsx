import { Link } from "react-router-dom";
import { useTheme } from "../context/ThemeContext";
import { useAuth } from "../context/AuthContext";
import { Sparkles, Crown, MessageCircle, Palette, ExternalLink } from "lucide-react";

const CHECKOUT_URL = import.meta.env.VITE_REBI_PLUS_CHECKOUT_URL || "";

export default function Subscribe() {
  const { theme } = useTheme();
  const { user } = useAuth();
  const plus =
    user?.user_metadata?.rebi_plus === true ||
    ["plus", "pro", "premium"].includes(
      String(user?.user_metadata?.subscription_tier || "").toLowerCase()
    );

  return (
    <div className={`min-h-screen ${theme.bg} pb-28`}>
      <div className="max-w-lg mx-auto px-4 py-8">
        <div className="flex items-center gap-3 mb-2">
          <div
            className="w-12 h-12 rounded-2xl flex items-center justify-center text-white shadow-lg"
            style={{ background: `linear-gradient(135deg, ${theme.accent}, ${theme.primary})` }}
          >
            <Crown className="w-6 h-6" />
          </div>
          <div>
            <h1 className="text-2xl font-bold text-gray-900">Rebi Plus</h1>
            <p className="text-sm text-gray-500">Sınırsız AI sohbet ve premium temalar</p>
          </div>
        </div>

        {plus && (
          <div
            className="mb-6 card !p-4 border-emerald-200 bg-emerald-50/90 text-emerald-900 text-sm"
          >
            Hesabında Rebi Plus aktif görünüyor. Teşekkürler.
          </div>
        )}

        <div className="card space-y-4 !p-5 mb-6">
          <h2 className="font-bold text-gray-900 text-sm">Neler dahil?</h2>
          <ul className="space-y-3 text-sm text-gray-700">
            <li className="flex gap-3">
              <MessageCircle className="w-5 h-5 shrink-0" style={{ color: theme.primary }} />
              <span>
                <strong className="text-gray-900">Rebi AI</strong> — günlük ücretsiz mesaj limiti olmadan
                cilt bakımı sohbeti (kotayı sunucu tarafında Plus ile kaldırırsın).
              </span>
            </li>
            <li className="flex gap-3">
              <Palette className="w-5 h-5 shrink-0" style={{ color: theme.primary }} />
              <span>
                <strong className="text-gray-900">Premium temalar</strong> — ayırt edici renkler ve desenler.
              </span>
            </li>
            <li className="flex gap-3">
              <Sparkles className="w-5 h-5 shrink-0" style={{ color: theme.primary }} />
              <span>Yeni özellikler önce Plus üyelerinde.</span>
            </li>
          </ul>
        </div>

        <div className="card !p-5 space-y-3 bg-gray-50/80 border-gray-200">
          <p className="text-xs text-gray-600 leading-relaxed">
            Ödeme bağlantısı hazır olduğunda buraya yönlendirileceksin. Şimdilik ödeme altyapısı
            (Stripe, iyzico vb.) projeye eklendiğinde <code className="text-[11px] bg-white px-1 rounded">VITE_REBI_PLUS_CHECKOUT_URL</code>{" "}
            ortam değişkeni ile ödeme sayfası açılır.
          </p>
          {CHECKOUT_URL ? (
            <a
              href={CHECKOUT_URL}
              target="_blank"
              rel="noopener noreferrer"
              className="btn-primary w-full inline-flex items-center justify-center gap-2 !py-3"
              style={{ backgroundColor: theme.primary }}
            >
              Ödemeye git <ExternalLink className="w-4 h-4" />
            </a>
          ) : (
            <p className="text-xs text-amber-800 bg-amber-50 border border-amber-200 rounded-xl px-3 py-2">
              Ödeme URL’si tanımlı değil. Hostinger / Stripe panelinden linki alıp frontend ortamına ekleyin.
            </p>
          )}
        </div>

        <Link
          to="/dashboard/chat"
          className="mt-6 block text-center text-sm font-medium underline-offset-2 hover:underline"
          style={{ color: theme.primary }}
        >
          Sohbete dön
        </Link>
      </div>
    </div>
  );
}
