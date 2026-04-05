import { Link } from "react-router-dom";
import { useAuth } from "../context/AuthContext";
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
} from "lucide-react";

const features = [
  {
    icon: Camera,
    title: "Kamera ile Takip",
    desc: "Cildini fotoğrafla, yapay zeka değişimleri izlesin.",
    color: "from-pink-500 to-rose-500",
    bg: "bg-pink-50",
  },
  {
    icon: Brain,
    title: "Bütüncül Analiz",
    desc: "Uyku, stres ve su tüketimini cilt sağlığınla birlikte değerlendirir.",
    color: "from-purple-500 to-indigo-500",
    bg: "bg-purple-50",
  },
  {
    icon: CloudSun,
    title: "Hava Durumuna Göre Koruma",
    desc: "UV ve nem verilerine göre günlük koruma önerileri.",
    color: "from-blue-500 to-cyan-500",
    bg: "bg-blue-50",
  },
];

const steps = [
  { num: "01", title: "Bilgilerini Gir", desc: "Cilt tipin, yaşam tarzın ve konumun." },
  { num: "02", title: "AI Analiz Etsin", desc: "Bilimsel literatür + hava durumu + yaşam tarzın." },
  { num: "03", title: "Rutinini Al", desc: "Sana özel sabah ve akşam rutini." },
];

const plusHighlights = [
  {
    icon: MessageCircle,
    title: "Sınırsız Rebi AI",
    desc: "Cilt bakımı, içerikler ve ürün sorularında kesintisiz sohbet.",
    gradient: "from-violet-500 to-fuchsia-500",
    glow: "shadow-fuchsia-500/20",
  },
  {
    icon: Palette,
    title: "Premium temalar",
    desc: "Gün batımı, okyanus ve gece şehir gibi özel görünümler.",
    gradient: "from-cyan-500 to-blue-600",
    glow: "shadow-cyan-500/20",
  },
  {
    icon: ClipboardCheck,
    title: "Derin takip",
    desc: "Günlük check-in ile rutinin cildinin cevabına göre uyarlanır.",
    gradient: "from-amber-500 to-orange-600",
    glow: "shadow-amber-500/25",
  },
];

export default function Landing() {
  const { user } = useAuth();

  return (
    <div className="min-h-screen bg-gradient-to-b from-warm-50 via-white to-teal-50/30">
      {/* Hero */}
      <section className="relative overflow-hidden">
        <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_top,_var(--tw-gradient-stops))] from-teal-100/40 via-transparent to-transparent" />
        <div className="absolute top-20 right-10 w-72 h-72 bg-teal-200/20 rounded-full blur-3xl" />
        <div className="absolute bottom-10 left-10 w-96 h-96 bg-purple-200/10 rounded-full blur-3xl" />

        <div className="relative max-w-6xl mx-auto px-4 pt-20 pb-24 md:pt-32 md:pb-36">
          <div className="text-center max-w-3xl mx-auto">
            <div className="inline-flex items-center gap-2 bg-teal-50 text-teal-700 px-4 py-2 rounded-full text-sm font-medium mb-8 border border-teal-100">
              <Sparkles className="w-4 h-4" />
              Yapay Zeka Destekli Cilt Bakımı
            </div>

            <h1 className="text-4xl md:text-6xl font-bold text-gray-900 leading-tight mb-6 tracking-tight">
              Cildinin ve Ruhunun{" "}
              <span className="bg-gradient-to-r from-teal-600 to-teal-500 bg-clip-text text-transparent">
                İhtiyacı Olan
              </span>{" "}
              Bilimsel Rutin.
            </h1>

            <p className="text-lg md:text-xl text-gray-500 mb-6 max-w-2xl mx-auto leading-relaxed">
              Rebi, cildin ile birlikte uykunu, stresini ve çevreni analiz eder.
              Bilimsel kaynaklara dayalı, sana özel bütüncül bir bakım rutini oluşturur.
            </p>
            <p className="text-base text-gray-600 mb-10 max-w-2xl mx-auto leading-relaxed">
              Analiz sonunda sabah ve akşam adımların, yaşam tarzı önerilerin ve hava durumuna göre koruma
              notların tek yerde toplanır. İstersen cilt fotoğrafını güvenli depoda saklayıp ilerlemeni
              karşılaştırabilirsin; günlük check-in ile rutin zaman içinde sana göre esner.
            </p>

            <div className="flex flex-col sm:flex-row gap-4 justify-center">
              <Link
                to={user ? "/dashboard/analyze" : "/auth"}
                className="btn-primary !px-8 !py-4 !text-lg !rounded-2xl group"
              >
                Ücretsiz Analiz Başlat
                <ArrowRight className="w-5 h-5 group-hover:translate-x-1 transition-transform" />
              </Link>
              <a
                href="#features"
                className="btn-secondary !px-8 !py-4 !text-lg !rounded-2xl"
              >
                Nasıl Çalışır?
              </a>
            </div>

            <div className="mt-10 flex items-center justify-center gap-6 text-sm text-gray-400">
              <div className="flex items-center gap-1.5">
                <Shield className="w-4 h-4 text-teal-500" />
                Ücretsiz
              </div>
              <div className="flex items-center gap-1.5">
                <Heart className="w-4 h-4 text-rose-400" />
                Bilimsel
              </div>
              <div className="flex items-center gap-1.5">
                <Star className="w-4 h-4 text-amber-400" />
                Kişisel
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
              Rebi Plus
            </div>
            <h2 className="text-3xl md:text-4xl font-bold text-white mb-4 tracking-tight">
              Ücretsiz analizle başla; istersen derinleş
            </h2>
            <p className="text-violet-200/90 text-lg max-w-2xl mx-auto leading-relaxed">
              Temel analiz ve rutin herkese açık. Plus ile yapay zeka sohbetinde sınır kalkar, özel temalar
              açılır ve günlük check-in akışın tam güçle çalışır.
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
                <h3 className="text-xl font-bold text-white mb-2">{item.title}</h3>
                <p className="text-sm text-violet-100/85 leading-relaxed">{item.desc}</p>
                <div className="mt-4 flex items-center gap-1.5 text-xs font-semibold text-amber-200/90">
                  <Lock className="w-3.5 h-3.5" />
                  Uygulama içi Plus ile açılır
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
              Plus&apos;ı keşfet
              <ArrowRight className="w-5 h-5" />
            </Link>
          </div>
        </div>
      </section>

      {/* Features */}
      <section id="features" className="py-20 md:py-28">
        <div className="max-w-6xl mx-auto px-4">
          <div className="text-center mb-16">
            <h2 className="text-3xl md:text-4xl font-bold text-gray-900 mb-4">
              Cilt Bakımında Yeni Nesil
            </h2>
            <p className="text-gray-500 text-lg max-w-xl mx-auto">
              Sadece krem önermekle kalmaz, uyku, stres, su ve beslenme gibi yaşam tarzı sinyallerini de
              rutinine bağlar.
            </p>
            <p className="text-gray-600 text-sm max-w-2xl mx-auto mt-4 leading-relaxed">
              Rebi tıbbi teşhis veya reçete yerine geçmez; güçlü aktiflerde dikkatli sıklık ve bariyer
              önceliği gibi güvenlik katmanlarıyla yönlendirir. Şüpheli durumda her zaman bir sağlık
              uzmanına danışmalısın.
            </p>
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
                <h3 className="text-xl font-bold text-gray-900 mb-2">
                  {f.title}
                </h3>
                <p className="text-gray-500 leading-relaxed">{f.desc}</p>
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
              3 Adımda Kişisel Rutinin
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
                    {s.title}
                  </h3>
                  <p className="text-gray-500">{s.desc}</p>
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
              Hemen Başla
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
            &copy; 2026 Rebi. Bütüncül cilt bakımı platformu.
          </p>
        </div>
      </footer>
    </div>
  );
}
