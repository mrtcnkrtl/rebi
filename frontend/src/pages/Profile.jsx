import { useState, useEffect, useCallback } from "react";
import { Link, useNavigate } from "react-router-dom";
import { useAuth } from "../context/AuthContext";
import { useTheme } from "../context/ThemeContext";
import { supabase } from "../lib/supabase";
import { apiAuthHeaders } from "../lib/apiAuth";
import { DEMO_USER_ID } from "../lib/demoUser";
import {
  User,
  Mail,
  Calendar,
  Camera,
  Lock,
  Shield,
  Info,
  Loader2,
  CheckCircle,
  AlertCircle,
  ImageIcon,
  Trash2,
} from "lucide-react";

const API = import.meta.env.VITE_API_URL || "http://localhost:8000";
const ACCOUNT_DELETE_PHRASE = "HESABIMI_SIL";

function formatJoined(iso) {
  if (!iso) return "—";
  try {
    return new Date(iso).toLocaleDateString("tr-TR", {
      year: "numeric",
      month: "long",
      day: "numeric",
    });
  } catch {
    return "—";
  }
}

export default function Profile() {
  const { user, refreshUser, signOut } = useAuth();
  const { theme } = useTheme();
  const navigate = useNavigate();

  const [displayName, setDisplayName] = useState("");
  const [profileMsg, setProfileMsg] = useState({ type: "", text: "" });
  const [profileSaving, setProfileSaving] = useState(false);

  const [newPassword, setNewPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [pwdMsg, setPwdMsg] = useState({ type: "", text: "" });
  const [pwdSaving, setPwdSaving] = useState(false);

  const [photos, setPhotos] = useState([]);
  const [photosLoading, setPhotosLoading] = useState(true);
  const [photosError, setPhotosError] = useState("");

  const [deletePhrase, setDeletePhrase] = useState("");
  const [deleteBusy, setDeleteBusy] = useState(false);
  const [deleteMsg, setDeleteMsg] = useState({ type: "", text: "" });

  const uid = user?.id;
  const email = user?.email || "—";
  const plus =
    user?.user_metadata?.rebi_plus === true ||
    ["plus", "pro", "premium"].includes(
      String(user?.user_metadata?.subscription_tier || "").toLowerCase()
    );

  useEffect(() => {
    setDisplayName(user?.user_metadata?.full_name || "");
  }, [user?.user_metadata?.full_name]);

  const loadPhotos = useCallback(async () => {
    if (!supabase || !uid) {
      setPhotos([]);
      setPhotosLoading(false);
      return;
    }
    setPhotosLoading(true);
    setPhotosError("");
    try {
      let list = await supabase.storage.from("skin-photos").list(uid, {
        limit: 100,
        offset: 0,
        sortBy: { column: "created_at", order: "desc" },
      });
      if (list.error) {
        list = await supabase.storage.from("skin-photos").list(uid, { limit: 100, offset: 0 });
      }
      const { data, error } = list;
      if (error) throw error;
      const files = (data || []).filter(
        (f) =>
          f.name &&
          !f.name.startsWith(".") &&
          /\.(jpe?g|png|webp|gif|heic|avif)$/i.test(f.name)
      );
      const withUrls = files.map((f) => {
        const path = `${uid}/${f.name}`;
        const { data: pub } = supabase.storage.from("skin-photos").getPublicUrl(path);
        return {
          name: f.name,
          path,
          url: pub?.publicUrl || "",
          created_at: f.created_at || null,
        };
      });
      withUrls.sort((a, b) => {
        const ta = a.created_at ? new Date(a.created_at).getTime() : 0;
        const tb = b.created_at ? new Date(b.created_at).getTime() : 0;
        if (tb !== ta) return tb - ta;
        return b.name.localeCompare(a.name);
      });
      setPhotos(withUrls);
    } catch (e) {
      setPhotosError(e?.message || "Fotoğraflar yüklenemedi.");
      setPhotos([]);
    } finally {
      setPhotosLoading(false);
    }
  }, [uid]);

  useEffect(() => {
    loadPhotos();
  }, [loadPhotos]);

  const saveProfile = async (e) => {
    e.preventDefault();
    if (!supabase) return;
    setProfileMsg({ type: "", text: "" });
    setProfileSaving(true);
    try {
      const trimmed = displayName.trim();
      const { error } = await supabase.auth.updateUser({
        data: { full_name: trimmed || null },
      });
      if (error) throw error;
      await refreshUser();
      setProfileMsg({ type: "ok", text: "Bilgilerin güncellendi." });
    } catch (err) {
      setProfileMsg({ type: "err", text: err?.message || "Kaydedilemedi." });
    } finally {
      setProfileSaving(false);
    }
  };

  const changePassword = async (e) => {
    e.preventDefault();
    setPwdMsg({ type: "", text: "" });
    if (newPassword.length < 6) {
      setPwdMsg({ type: "err", text: "Şifre en az 6 karakter olmalı." });
      return;
    }
    if (newPassword !== confirmPassword) {
      setPwdMsg({ type: "err", text: "Şifreler eşleşmiyor." });
      return;
    }
    if (!supabase) return;
    setPwdSaving(true);
    try {
      const { error } = await supabase.auth.updateUser({ password: newPassword });
      if (error) throw error;
      setNewPassword("");
      setConfirmPassword("");
      setPwdMsg({ type: "ok", text: "Şifren güncellendi." });
    } catch (err) {
      setPwdMsg({ type: "err", text: err?.message || "Şifre değiştirilemedi." });
    } finally {
      setPwdSaving(false);
    }
  };

  const deleteAccount = async (e) => {
    e.preventDefault();
    setDeleteMsg({ type: "", text: "" });
    if (!uid) return;
    if (deletePhrase.trim() !== ACCOUNT_DELETE_PHRASE) {
      setDeleteMsg({
        type: "err",
        text: `Kalıcı silmek için kutuya tam olarak ${ACCOUNT_DELETE_PHRASE} yazmalısın.`,
      });
      return;
    }
    setDeleteBusy(true);
    try {
      const headers = {
        "Content-Type": "application/json",
        ...(await apiAuthHeaders()),
      };
      const res = await fetch(`${API}/account/delete`, {
        method: "POST",
        headers,
        body: JSON.stringify({
          user_id: uid,
          confirm_text: ACCOUNT_DELETE_PHRASE,
        }),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) {
        throw new Error(data?.detail || res.statusText || "İstek başarısız");
      }
      setDeletePhrase("");
      await signOut();
      navigate("/", { replace: true });
    } catch (err) {
      setDeleteMsg({
        type: "err",
        text: err?.message || "Hesap silinemedi.",
      });
    } finally {
      setDeleteBusy(false);
    }
  };

  if (!supabase) {
    return (
      <div className={`min-h-screen ${theme.bg} pb-28 flex items-center justify-center px-4`}>
        <p className="text-sm text-gray-600 text-center">
          Supabase yapılandırılmamış; profil ve fotoğraflar kullanılamıyor.
        </p>
      </div>
    );
  }

  return (
    <div className={`min-h-screen ${theme.bg} pb-28`}>
      <div className="max-w-lg mx-auto px-4 py-8 space-y-6">
        <div className="flex items-center gap-3">
          <div
            className="w-14 h-14 rounded-2xl flex items-center justify-center text-white shadow-lg"
            style={{ background: `linear-gradient(135deg, ${theme.accent}, ${theme.primary})` }}
          >
            <User className="w-7 h-7" />
          </div>
          <div>
            <h1 className="text-xl font-bold text-gray-900">Profil</h1>
            <p className="text-sm text-gray-500">Hesap, güvenlik ve cilt fotoğrafların</p>
          </div>
        </div>

        {/* Bilgilendirme */}
        <div
          className="card !p-4 border-sky-100 bg-sky-50/60"
          style={{ borderColor: theme.primaryLight }}
        >
          <div className="flex gap-3">
            <Info className="w-5 h-5 shrink-0 text-sky-700 mt-0.5" />
            <div className="text-sm text-sky-950/90 space-y-2 leading-relaxed">
              <p>
                <strong className="text-sky-950">Rebi</strong> verilerini güvenle saklar. Analiz
                sırasında yüklediğin cilt fotoğrafları aşağıda kronolojik olarak listelenir; yeni
                fotoğraf için{" "}
                <Link to="/dashboard/analyze" className="font-semibold underline underline-offset-2">
                  analiz
                </Link>{" "}
                adımlarına gidebilirsin.
              </p>
              <p className="text-xs text-sky-900/80">
                Şifre değişikliği e-posta ile giriş yaptığın hesaplar içindir. Sosyal giriş
                kullanıyorsan şifre bu ekrandan değişmez.
              </p>
            </div>
          </div>
        </div>

        {/* Hesap özeti */}
        <div className="card !p-4 space-y-3">
          <h2 className="text-sm font-bold text-gray-800 flex items-center gap-2">
            <Shield className="w-4 h-4" style={{ color: theme.primary }} />
            Hesap özeti
          </h2>
          <div className="space-y-2 text-sm">
            <div className="flex items-start gap-2 text-gray-700">
              <Mail className="w-4 h-4 shrink-0 mt-0.5 text-gray-400" />
              <span className="break-all">{email}</span>
            </div>
            <div className="flex items-center gap-2 text-gray-700">
              <Calendar className="w-4 h-4 shrink-0 text-gray-400" />
              <span>Üyelik: {formatJoined(user?.created_at)}</span>
            </div>
            {plus && (
              <p className="text-xs font-semibold text-amber-800 bg-amber-50 border border-amber-200 rounded-lg px-2 py-1.5 w-fit">
                Rebi Plus aktif
              </p>
            )}
          </div>
        </div>

        {/* Ad güncelle */}
        <form onSubmit={saveProfile} className="card !p-4 space-y-3">
          <h2 className="text-sm font-bold text-gray-800 flex items-center gap-2">
            <User className="w-4 h-4" style={{ color: theme.primary }} />
            Görünen ad
          </h2>
          <input
            type="text"
            value={displayName}
            onChange={(e) => setDisplayName(e.target.value)}
            className="input-field"
            placeholder="Adın soyadın"
            maxLength={120}
          />
          {profileMsg.text && (
            <p
              className={`text-xs flex items-center gap-1 ${
                profileMsg.type === "ok" ? "text-emerald-700" : "text-red-600"
              }`}
            >
              {profileMsg.type === "ok" ? (
                <CheckCircle className="w-3.5 h-3.5" />
              ) : (
                <AlertCircle className="w-3.5 h-3.5" />
              )}
              {profileMsg.text}
            </p>
          )}
          <button
            type="submit"
            disabled={profileSaving}
            className="btn-primary w-full justify-center !py-2.5 text-sm"
            style={{ backgroundColor: theme.primary }}
          >
            {profileSaving ? <Loader2 className="w-4 h-4 animate-spin" /> : "Bilgileri kaydet"}
          </button>
        </form>

        {/* Şifre */}
        <form onSubmit={changePassword} className="card !p-4 space-y-3">
          <h2 className="text-sm font-bold text-gray-800 flex items-center gap-2">
            <Lock className="w-4 h-4" style={{ color: theme.primary }} />
            Şifre değiştir
          </h2>
          <input
            type="password"
            value={newPassword}
            onChange={(e) => setNewPassword(e.target.value)}
            className="input-field"
            placeholder="Yeni şifre (en az 6 karakter)"
            autoComplete="new-password"
          />
          <input
            type="password"
            value={confirmPassword}
            onChange={(e) => setConfirmPassword(e.target.value)}
            className="input-field"
            placeholder="Yeni şifre tekrar"
            autoComplete="new-password"
          />
          {pwdMsg.text && (
            <p
              className={`text-xs flex items-center gap-1 ${
                pwdMsg.type === "ok" ? "text-emerald-700" : "text-red-600"
              }`}
            >
              {pwdMsg.type === "ok" ? (
                <CheckCircle className="w-3.5 h-3.5" />
              ) : (
                <AlertCircle className="w-3.5 h-3.5" />
              )}
              {pwdMsg.text}
            </p>
          )}
          <button
            type="submit"
            disabled={pwdSaving || !newPassword}
            className="btn-secondary w-full justify-center !py-2.5 text-sm"
            style={{ borderColor: theme.primaryLight, color: theme.primary }}
          >
            {pwdSaving ? <Loader2 className="w-4 h-4 animate-spin" /> : "Şifreyi güncelle"}
          </button>
        </form>

        {uid && uid !== DEMO_USER_ID && (
          <form onSubmit={deleteAccount} className="card !p-4 space-y-3 border-red-200 bg-red-50/40">
            <h2 className="text-sm font-bold text-red-900 flex items-center gap-2">
              <Trash2 className="w-4 h-4" />
              Hesabı kalıcı olarak sil
            </h2>
            <p className="text-xs text-red-900/85 leading-relaxed">
              Profil, rutinler, günlük kayıtlar ve analiz verilerin veritabanından silinir. Cilt
              fotoğrafların depodan kaldırılır. Bu işlem geri alınamaz; Rebi Plus veya başka üyelik
              bilgisi ayrıca faturalandırma sisteminde kalıyorsa oradan da iptal etmen gerekebilir.
            </p>
            <div>
              <label className="block text-xs font-semibold text-red-950/90 mb-1">
                Onay için tam yaz:{" "}
                <span className="font-mono bg-white/80 px-1 rounded">{ACCOUNT_DELETE_PHRASE}</span>
              </label>
              <input
                type="text"
                value={deletePhrase}
                onChange={(e) => setDeletePhrase(e.target.value)}
                className="input-field font-mono text-sm"
                placeholder={ACCOUNT_DELETE_PHRASE}
                autoComplete="off"
                spellCheck={false}
              />
            </div>
            {deleteMsg.text && (
              <p
                className={`text-xs flex items-center gap-1 ${
                  deleteMsg.type === "ok" ? "text-emerald-700" : "text-red-700"
                }`}
              >
                <AlertCircle className="w-3.5 h-3.5 shrink-0" />
                {deleteMsg.text}
              </p>
            )}
            <button
              type="submit"
              disabled={deleteBusy || deletePhrase.trim() !== ACCOUNT_DELETE_PHRASE}
              className="w-full justify-center !py-2.5 text-sm font-semibold rounded-xl border-2 border-red-600 text-red-700 bg-white hover:bg-red-50 disabled:opacity-50 disabled:cursor-not-allowed"
            >
              {deleteBusy ? <Loader2 className="w-4 h-4 animate-spin mx-auto" /> : "Hesabımı kalıcı sil"}
            </button>
          </form>
        )}

        {/* Fotoğraf zaman çizelgesi */}
        <div className="card !p-4 space-y-3">
          <div className="flex items-center justify-between gap-2">
            <h2 className="text-sm font-bold text-gray-800 flex items-center gap-2">
              <Camera className="w-4 h-4" style={{ color: theme.primary }} />
              Cilt fotoğrafları
            </h2>
            <button
              type="button"
              onClick={() => loadPhotos()}
              className="text-xs font-semibold underline-offset-2 hover:underline"
              style={{ color: theme.primary }}
            >
              Yenile
            </button>
          </div>
          <p className="text-xs text-gray-500">
            Analizde yüklediğin görseller burada tarih sırasıyla listelenir (sunucudaki dosya
            tarihine göre).
          </p>
          {photosLoading ? (
            <div className="flex justify-center py-8">
              <Loader2 className="w-8 h-8 animate-spin text-gray-300" style={{ color: theme.primary }} />
            </div>
          ) : photosError ? (
            <p className="text-sm text-red-600 flex items-center gap-2">
              <AlertCircle className="w-4 h-4 shrink-0" />
              {photosError}
            </p>
          ) : photos.length === 0 ? (
            <div className="text-center py-8 rounded-2xl border border-dashed border-gray-200 bg-white/50">
              <ImageIcon className="w-10 h-10 mx-auto text-gray-300 mb-2" />
              <p className="text-sm text-gray-600 mb-3">Henüz kayıtlı fotoğraf yok.</p>
              <Link
                to="/dashboard/analyze"
                className="text-sm font-semibold underline-offset-2 hover:underline"
                style={{ color: theme.primary }}
              >
                Analizde fotoğraf yükle
              </Link>
            </div>
          ) : (
            <ul className="space-y-4">
              {photos.map((p) => (
                <li
                  key={p.path}
                  className="rounded-2xl border border-gray-100 overflow-hidden bg-white shadow-sm"
                >
                  {p.url ? (
                    <img src={p.url} alt="" className="w-full h-48 object-cover bg-gray-100" />
                  ) : (
                    <div className="h-32 flex items-center justify-center text-gray-400 text-sm">
                      Önizleme yok
                    </div>
                  )}
                  <div className="px-3 py-2 flex items-center justify-between text-xs text-gray-500 border-t border-gray-50">
                    <span className="font-mono truncate max-w-[60%]" title={p.name}>
                      {p.name}
                    </span>
                    <span>
                      {p.created_at
                        ? new Date(p.created_at).toLocaleString("tr-TR")
                        : "—"}
                    </span>
                  </div>
                </li>
              ))}
            </ul>
          )}
        </div>

        <div className="flex flex-wrap gap-3 justify-center text-xs pb-4">
          <Link
            to="/dashboard/subscribe"
            className="font-semibold underline-offset-2 hover:underline"
            style={{ color: theme.primary }}
          >
            Rebi Plus
          </Link>
          <span className="text-gray-300">·</span>
          <Link to="/dashboard/themes" className="text-gray-600 underline-offset-2 hover:underline">
            Temalar
          </Link>
        </div>
      </div>
    </div>
  );
}
