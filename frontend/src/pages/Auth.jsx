import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { useAuth } from "../context/AuthContext";
import { Leaf, Mail, Lock, User, Eye, EyeOff, ArrowRight, AlertCircle, Info } from "lucide-react";

export default function Auth() {
  const [mode, setMode] = useState("login");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [fullName, setFullName] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [infoMessage, setInfoMessage] = useState("");
  const { signIn, signUp } = useAuth();
  const navigate = useNavigate();

  const handleSubmit = async (e) => {
    e.preventDefault();
    setError("");
    setInfoMessage("");
    setLoading(true);

    try {
      if (mode === "login") {
        const { error } = await signIn(email, password);
        if (error) throw error;
        navigate("/dashboard");
      } else {
        const { error, needsEmailConfirmation } = await signUp(email, password, fullName);
        if (error) throw error;
        if (needsEmailConfirmation) {
          setError("");
          setMode("login");
          setInfoMessage(
            "Kayıt alındı. E-postandaki onay linkine tıkladıktan sonra giriş yapabilirsin. Posta gelmediyse spam klasörüne bak."
          );
          return;
        }
        navigate("/dashboard");
      }
    } catch (err) {
      const raw = err?.message || String(err);
      const isNetwork =
        raw === "Failed to fetch" ||
        raw.includes("NetworkError") ||
        err?.name === "TypeError";
      if (isNetwork) {
        setError(
          "Sunucuya bağlanılamadı (Failed to fetch). Kontrol et: internet / VPN; " +
            "Supabase Dashboard → Project Settings → API ile .env içindeki VITE_SUPABASE_URL ve VITE_SUPABASE_ANON_KEY aynı mı; " +
            ".env değiştirdiysen `npm run dev` sunucusunu durdurup yeniden başlat. " +
            "Ayrıntı için tarayıcıda F12 → Ağ (Network) sekmesi."
        );
      } else {
        setError(raw || "Bir hata oluştu");
      }
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen bg-gradient-to-b from-teal-50 to-white flex items-center justify-center px-4 py-12">
      <div className="w-full max-w-md">
        {/* Logo */}
        <div className="text-center mb-8">
          <div className="w-16 h-16 bg-gradient-to-br from-teal-500 to-teal-600 rounded-2xl flex items-center justify-center mx-auto mb-4 shadow-xl shadow-teal-500/20">
            <Leaf className="w-8 h-8 text-white" />
          </div>
          <h1 className="text-2xl font-bold text-gray-900">
            {mode === "login" ? "Hoş Geldin" : "Hesap Oluştur"}
          </h1>
          <p className="text-gray-500 mt-1">
            {mode === "login"
              ? "Rebi hesabına giriş yap"
              : "Ücretsiz hesabını oluştur"}
          </p>
        </div>

        {/* Card */}
        <div className="card">
          {infoMessage && (
            <div className="flex items-start gap-2 bg-teal-50 text-teal-900 p-3 rounded-xl mb-4 text-sm border border-teal-100">
              <Info className="w-4 h-4 shrink-0 mt-0.5" />
              <span>{infoMessage}</span>
            </div>
          )}
          {error && (
            <div className="flex items-center gap-2 bg-red-50 text-red-600 p-3 rounded-xl mb-4 text-sm">
              <AlertCircle className="w-4 h-4 shrink-0" />
              {error}
            </div>
          )}

          <form onSubmit={handleSubmit} className="space-y-4">
            {mode === "signup" && (
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1.5">
                  Ad Soyad
                </label>
                <div className="relative">
                  <User className="absolute left-3.5 top-1/2 -translate-y-1/2 w-5 h-5 text-gray-400" />
                  <input
                    type="text"
                    value={fullName}
                    onChange={(e) => setFullName(e.target.value)}
                    className="input-field !pl-11"
                    placeholder="Adın Soyadın"
                    required
                  />
                </div>
              </div>
            )}

            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1.5">
                E-posta
              </label>
              <div className="relative">
                <Mail className="absolute left-3.5 top-1/2 -translate-y-1/2 w-5 h-5 text-gray-400" />
                <input
                  type="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  className="input-field !pl-11"
                  placeholder="ornek@email.com"
                  required
                />
              </div>
            </div>

            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1.5">
                Şifre
              </label>
              <div className="relative">
                <Lock className="absolute left-3.5 top-1/2 -translate-y-1/2 w-5 h-5 text-gray-400" />
                <input
                  type={showPassword ? "text" : "password"}
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  className="input-field !pl-11 !pr-11"
                  placeholder="••••••••"
                  required
                  minLength={6}
                />
                <button
                  type="button"
                  onClick={() => setShowPassword(!showPassword)}
                  className="absolute right-3.5 top-1/2 -translate-y-1/2 text-gray-400 hover:text-gray-600"
                >
                  {showPassword ? (
                    <EyeOff className="w-5 h-5" />
                  ) : (
                    <Eye className="w-5 h-5" />
                  )}
                </button>
              </div>
            </div>

            <button
              type="submit"
              disabled={loading}
              className="btn-primary w-full !mt-6"
            >
              {loading ? (
                <div className="w-5 h-5 border-2 border-white/30 border-t-white rounded-full animate-spin" />
              ) : (
                <>
                  {mode === "login" ? "Giriş Yap" : "Kayıt Ol"}
                  <ArrowRight className="w-5 h-5" />
                </>
              )}
            </button>
          </form>

          <p className="text-center text-sm text-gray-500 mt-6">
            {mode === "login" ? (
              <>
                Hesabın yok mu?{" "}
                <button
                  onClick={() => { setMode("signup"); setError(""); setInfoMessage(""); }}
                  className="text-teal-600 font-semibold hover:underline"
                >
                  Kayıt Ol
                </button>
              </>
            ) : (
              <>
                Zaten hesabın var mı?{" "}
                <button
                  onClick={() => { setMode("login"); setError(""); setInfoMessage(""); }}
                  className="text-teal-600 font-semibold hover:underline"
                >
                  Giriş Yap
                </button>
              </>
            )}
          </p>
        </div>
      </div>
    </div>
  );
}
